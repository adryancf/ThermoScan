#include <unity.h>
#include <ArduinoJson.h>
#include <regex>
#include <string>
#include <vector>
#include <cmath>

#include "hal/i_cloud_client.h"
#include "hal_esp32/http_cloud_client.h"

using namespace hal_esp32;

namespace {

bool isValidUUID(const std::string& str) {
    static const std::regex uuid_regex(
        "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
    );
    return std::regex_match(str, uuid_regex);
}

bool isValidRFC3339(const std::string& str) {
    static const std::regex rfc3339_regex(
        "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
    );
    return std::regex_match(str, rfc3339_regex);
}

} // namespace

void test_telemetry_batch_json_contract() {
    IngestTelemetryBatchInput input;
    input.inspection_source_event_id = "10000000-0000-0000-0000-000000000001";
    input.started_at_epoch = 1730721600; // 2024-11-04T12:00:00Z
    input.scheduled_for_epoch = 1730721600;
    input.inspection_type = "scheduled";

    // Measurement 1: full valid telemetry with some null/invalid thermal pixels
    float v1 = 18.5f;
    float a1 = 4.2f;
    float p1 = 77.7f;
    std::vector<float> frame1(768, 35.0f);
    // Introduce boundary and invalid pixels
    frame1[0] = NAN;              // Dead pixel -> null
    frame1[10] = INFINITY;        // Inf -> null
    frame1[20] = -50.0f;          // Below -40.0 C -> null
    frame1[30] = 350.0f;          // Above 300.0 C -> null
    frame1[100] = 55.5f;          // Valid hotspot pixel

    TelemetryMeasurementItem item1;
    item1.source_event_id = "20000000-0000-0000-0000-000000000001";
    item1.measured_at_epoch = 1730721605;
    item1.x_position_cm = 10.0f;
    item1.max_temperature_c = 55.5f;
    item1.voltage_v = &v1;
    item1.current_a = &a1;
    item1.power_w = &p1;
    item1.thermal_frame = frame1.data();
    item1.thermal_frame_size = 768;

    // Measurement 2: nullable electricals (sensor failure -> nullptr serializes as null, NO fake zeros!)
    std::vector<float> frame2(768, 34.0f);
    TelemetryMeasurementItem item2;
    item2.source_event_id = "20000000-0000-0000-0000-000000000002";
    item2.measured_at_epoch = 1730721610;
    item2.x_position_cm = 12.0f;
    item2.max_temperature_c = 34.0f;
    item2.voltage_v = nullptr; // MUST serialize as null
    item2.current_a = nullptr; // MUST serialize as null
    item2.power_w = nullptr;   // MUST serialize as null
    item2.thermal_frame = frame2.data();
    item2.thermal_frame_size = 768;

    input.batch.push_back(item1);
    input.batch.push_back(item2);

    // Act: build real JSON
    std::string json_str = HttpCloudClient::buildTelemetryBatchJson(input);
    TEST_ASSERT_TRUE(!json_str.empty());

    // Assert: deserialize and strictly validate schema
    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, json_str);
    TEST_ASSERT_EQUAL(DeserializationError::Ok, err.code());

    // Top-level fields
    TEST_ASSERT_TRUE(doc["inspection_source_event_id"].is<const char*>());
    std::string insp_id = doc["inspection_source_event_id"].as<std::string>();
    TEST_ASSERT_TRUE(isValidUUID(insp_id));
    TEST_ASSERT_EQUAL_STRING("10000000-0000-0000-0000-000000000001", insp_id.c_str());

    TEST_ASSERT_TRUE(doc["inspection_type"].is<const char*>());
    TEST_ASSERT_EQUAL_STRING("scheduled", doc["inspection_type"].as<const char*>());

    TEST_ASSERT_TRUE(doc["started_at"].is<const char*>());
    TEST_ASSERT_TRUE(isValidRFC3339(doc["started_at"].as<std::string>()));

    TEST_ASSERT_TRUE(doc["scheduled_for"].is<const char*>());
    TEST_ASSERT_TRUE(isValidRFC3339(doc["scheduled_for"].as<std::string>()));

    // Absence of prohibited fields at root
    TEST_ASSERT_TRUE(doc["hotspot_detected"].isNull());
    TEST_ASSERT_TRUE(doc["baseline_temperature_c"].isNull());
    TEST_ASSERT_TRUE(doc["hotspot_confirmed"].isNull());

    // Batch items
    TEST_ASSERT_TRUE(doc["batch"].is<JsonArray>());
    JsonArray batchArr = doc["batch"].as<JsonArray>();
    TEST_ASSERT_EQUAL(2, batchArr.size());

    // Item 1 validation
    JsonObject b1 = batchArr[0];
    TEST_ASSERT_TRUE(b1["source_event_id"].is<const char*>());
    TEST_ASSERT_TRUE(isValidUUID(b1["source_event_id"].as<std::string>()));
    TEST_ASSERT_TRUE(isValidRFC3339(b1["measured_at"].as<std::string>()));
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 10.0f, b1["x_position_cm"].as<float>());
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 55.5f, b1["max_temperature_c"].as<float>());

    TEST_ASSERT_FALSE(b1["voltage_v"].isNull());
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 18.5f, b1["voltage_v"].as<float>());
    TEST_ASSERT_FALSE(b1["current_a"].isNull());
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 4.2f, b1["current_a"].as<float>());
    TEST_ASSERT_FALSE(b1["power_w"].isNull());
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 77.7f, b1["power_w"].as<float>());

    // Thermal frame validation: exactly 768 elements
    TEST_ASSERT_TRUE(b1["thermal_frame"].is<JsonArray>());
    JsonArray f1 = b1["thermal_frame"].as<JsonArray>();
    TEST_ASSERT_EQUAL(768, f1.size());
    // Pixel 0 (NAN) -> null
    TEST_ASSERT_TRUE(f1[0].isNull());
    // Pixel 10 (INF) -> null
    TEST_ASSERT_TRUE(f1[10].isNull());
    // Pixel 20 (-50C) -> null
    TEST_ASSERT_TRUE(f1[20].isNull());
    // Pixel 30 (350C) -> null
    TEST_ASSERT_TRUE(f1[30].isNull());
    // Pixel 100 (55.5C) -> valid float
    TEST_ASSERT_FALSE(f1[100].isNull());
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 55.5f, f1[100].as<float>());

    // Item 2 validation: nullable electricals must be JSON null (no fake zeros!)
    JsonObject b2 = batchArr[1];
    TEST_ASSERT_TRUE(isValidUUID(b2["source_event_id"].as<std::string>()));
    TEST_ASSERT_TRUE(b2["voltage_v"].isNull());
    TEST_ASSERT_TRUE(b2["current_a"].isNull());
    TEST_ASSERT_TRUE(b2["power_w"].isNull());
    TEST_ASSERT_EQUAL(768, b2["thermal_frame"].as<JsonArray>().size());

    // Absence of prohibited fields per measurement item
    TEST_ASSERT_TRUE(b1["hotspot_detected"].isNull());
    TEST_ASSERT_TRUE(b1["baseline_temperature_c"].isNull());
    TEST_ASSERT_TRUE(b1["hotspot_confirmed"].isNull());
    TEST_ASSERT_TRUE(b2["hotspot_detected"].isNull());
    TEST_ASSERT_TRUE(b2["baseline_temperature_c"].isNull());
    TEST_ASSERT_TRUE(b2["hotspot_confirmed"].isNull());
}

void test_finalize_inspection_json_contract() {
    FinalizeInspectionInput input;
    input.finished_at_epoch = 1730722200; // 2024-11-04T12:10:00Z
    input.baseline_temperature_c = 32.5f;

    ConfirmedHotspotOutput h1;
    h1.source_event_id = "30000000-0000-0000-0000-000000000001";
    h1.global_x_position_cm = 16.0f;
    h1.row_index = 8;
    h1.max_temperature_c = 48.2f;
    h1.detected_at_epoch = 1730721610;
    h1.origin_measurement_event_id = "20000000-0000-0000-0000-000000000001";
    h1.confirming_event_ids = {
        "20000000-0000-0000-0000-000000000001",
        "20000000-0000-0000-0000-000000000002"
    };
    input.confirmed_hotspots.push_back(h1);

    // Act
    std::string json_str = HttpCloudClient::buildFinalizeJson(input);
    TEST_ASSERT_TRUE(!json_str.empty());

    // Assert
    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, json_str);
    TEST_ASSERT_EQUAL(DeserializationError::Ok, err.code());

    TEST_ASSERT_TRUE(doc["finished_at"].is<const char*>());
    TEST_ASSERT_TRUE(isValidRFC3339(doc["finished_at"].as<std::string>()));
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 32.5f, doc["baseline_temperature_c"].as<float>());

    TEST_ASSERT_TRUE(doc["confirmed_hotspots"].is<JsonArray>());
    JsonArray arr = doc["confirmed_hotspots"].as<JsonArray>();
    TEST_ASSERT_EQUAL(1, arr.size());

    JsonObject obj = arr[0];
    TEST_ASSERT_TRUE(isValidUUID(obj["source_event_id"].as<std::string>()));
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 16.0f, obj["global_x_position_cm"].as<float>());
    TEST_ASSERT_EQUAL(8, obj["row_index"].as<int>());
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 48.2f, obj["max_temperature_c"].as<float>());
    TEST_ASSERT_TRUE(isValidRFC3339(obj["detected_at"].as<std::string>()));

    std::string origin_id = obj["origin_measurement_event_id"].as<std::string>();
    TEST_ASSERT_TRUE(isValidUUID(origin_id));
    TEST_ASSERT_EQUAL_STRING("20000000-0000-0000-0000-000000000001", origin_id.c_str());

    JsonArray cids = obj["confirming_event_ids"].as<JsonArray>();
    TEST_ASSERT_TRUE(cids.size() >= 2);
    bool found_origin = false;
    for (size_t i = 0; i < cids.size(); ++i) {
        std::string cid = cids[i].as<std::string>();
        TEST_ASSERT_TRUE(isValidUUID(cid));
        if (cid == origin_id) {
            found_origin = true;
        }
    }
    TEST_ASSERT_TRUE(found_origin);
}

void test_cleaning_report_refused_contract() {
    CleaningReportInput input;
    input.anomaly_event_id = "40000000-0000-0000-0000-000000000001";
    input.target_x_position_cm = 16.0f;
    input.pump_actuated = false;
    input.attempt_number = 0;
    input.duration_seconds = 0.0f;
    input.status = "refused";
    input.failure_reason = "Water reservoir depleted";

    // Act
    std::string json_str = HttpCloudClient::buildCleaningReportJson(input);
    TEST_ASSERT_TRUE(!json_str.empty());

    // Assert
    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, json_str);
    TEST_ASSERT_EQUAL(DeserializationError::Ok, err.code());

    TEST_ASSERT_TRUE(isValidUUID(doc["anomaly_event_id"].as<std::string>()));
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 16.0f, doc["target_x_position_cm"].as<float>());
    TEST_ASSERT_FALSE(doc["pump_actuated"].as<bool>());
    TEST_ASSERT_TRUE(doc["attempt_number"].isNull());
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 0.0f, doc["duration_seconds"].as<float>());
    TEST_ASSERT_EQUAL_STRING("refused", doc["status"].as<const char*>());
    TEST_ASSERT_EQUAL_STRING("Water reservoir depleted", doc["failure_reason"].as<const char*>());
    TEST_ASSERT_EQUAL_STRING("pending", doc["post_cleaning_result"].as<const char*>());

    // Crucial requirement: Sensor capacitivo é binário -> estimated_water_volume_ml NÃO é transmitido!
    TEST_ASSERT_TRUE(doc["estimated_water_volume_ml"].isNull());
}

void test_panel_thermal_result_and_multi_panel_index_contracts() {
    // 1. TelemetryBatch with panel_index = 2
    IngestTelemetryBatchInput b_in;
    b_in.inspection_source_event_id = "10000000-0000-0000-0000-000000000009";
    b_in.inspection_type = "scheduled";
    b_in.started_at_epoch = 1730721600;

    std::vector<float> frame(768, 30.0f);
    TelemetryMeasurementItem m_item;
    m_item.source_event_id = "20000000-0000-0000-0000-000000000009";
    m_item.panel_index = 2;
    m_item.measured_at_epoch = 1730721605;
    m_item.x_position_cm = 122.0f;
    m_item.max_temperature_c = 44.0f;
    m_item.thermal_frame = frame.data();
    m_item.thermal_frame_size = 768;
    b_in.batch.push_back(m_item);

    std::string b_json = HttpCloudClient::buildTelemetryBatchJson(b_in);
    JsonDocument b_doc;
    TEST_ASSERT_EQUAL(DeserializationError::Ok, deserializeJson(b_doc, b_json).code());
    TEST_ASSERT_EQUAL_UINT8(2, b_doc["batch"][0]["panel_index"].as<uint8_t>());

    // 2. PanelThermalResultInput contract
    PanelThermalResultInput p_in;
    p_in.panel_index = 2;
    p_in.baseline_temperature_c = 31.2f;
    p_in.truncated_by_memory = true;
    p_in.finished_at_epoch = 1730721800;

    ConfirmedHotspotOutput h;
    h.source_event_id = "30000000-0000-0000-0000-000000000009";
    h.panel_index = 2;
    h.global_x_position_cm = 126.0f;
    h.row_index = 12;
    h.max_temperature_c = 46.5f;
    h.detected_at_epoch = 1730721750;
    h.origin_measurement_event_id = "20000000-0000-0000-0000-000000000009";
    h.confirming_event_ids = {
        "20000000-0000-0000-0000-000000000009",
        "20000000-0000-0000-0000-000000000010"
    };
    p_in.confirmed_hotspots.push_back(h);

    std::string p_json = HttpCloudClient::buildPanelThermalResultJson(p_in);
    JsonDocument p_doc;
    TEST_ASSERT_EQUAL(DeserializationError::Ok, deserializeJson(p_doc, p_json).code());
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 31.2f, p_doc["baseline_temperature_c"].as<float>());
    TEST_ASSERT_TRUE(p_doc["truncated_by_memory"].as<bool>());
    TEST_ASSERT_TRUE(isValidRFC3339(p_doc["finished_at"].as<std::string>()));
    TEST_ASSERT_EQUAL(1, p_doc["confirmed_hotspots"].as<JsonArray>().size());
    TEST_ASSERT_EQUAL_UINT8(2, p_doc["confirmed_hotspots"][0]["panel_index"].as<uint8_t>());
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 126.0f, p_doc["confirmed_hotspots"][0]["global_x_position_cm"].as<float>());

    // 3. FinalizeInspectionInput with panel_index
    FinalizeInspectionInput f_in;
    f_in.finished_at_epoch = 1730721900;
    f_in.baseline_temperature_c = 0.0f;
    f_in.confirmed_hotspots.push_back(h);
    std::string f_json = HttpCloudClient::buildFinalizeJson(f_in);
    JsonDocument f_doc;
    TEST_ASSERT_EQUAL(DeserializationError::Ok, deserializeJson(f_doc, f_json).code());
    TEST_ASSERT_EQUAL_UINT8(2, f_doc["confirmed_hotspots"][0]["panel_index"].as<uint8_t>());

    // 4. CleaningReportInput with panel_index
    CleaningReportInput c_in;
    c_in.anomaly_event_id = "40000000-0000-0000-0000-000000000009";
    c_in.panel_index = 2;
    c_in.target_x_position_cm = 126.0f;
    c_in.pump_actuated = true;
    c_in.attempt_number = 1;
    c_in.duration_seconds = 3.5f;
    c_in.status = "completed";
    std::string c_json = HttpCloudClient::buildCleaningReportJson(c_in);
    JsonDocument c_doc;
    TEST_ASSERT_EQUAL(DeserializationError::Ok, deserializeJson(c_doc, c_json).code());
    TEST_ASSERT_EQUAL_UINT8(2, c_doc["panel_index"].as<uint8_t>());
    TEST_ASSERT_EQUAL(1, c_doc["attempt_number"].as<int>());
}

int main(int argc, char** argv) {
    UNITY_BEGIN();
    RUN_TEST(test_telemetry_batch_json_contract);
    RUN_TEST(test_finalize_inspection_json_contract);
    RUN_TEST(test_cleaning_report_refused_contract);
    RUN_TEST(test_panel_thermal_result_and_multi_panel_index_contracts);
    return UNITY_END();
}
