#include "http_cloud_client.h"

#if defined(ARDUINO) || defined(ESP32)
#include <Arduino.h>
#include "diagnostics/web_diagnostics.h"
#define Serial diagnostics::getGlobalDualSerial()
#endif

#include <ctime>
#include <cmath>

namespace hal_esp32 {

static std::string formatEpochToRFC3339(uint32_t epoch) {
    if (epoch == 0) return "";
    time_t raw = static_cast<time_t>(epoch);
    struct tm ts;
    gmtime_r(&raw, &ts);
    char buf[25];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &ts);
    return std::string(buf);
}

std::string HttpCloudClient::buildPingJson(bool water_ok, bool limits_ok, bool thermal_ok,
                                         const std::string& next_inspection_at,
                                         bool manual_cleaning_ack) {
    JsonDocument doc;
    doc["water_available"] = water_ok;
    doc["limits_check_passed"] = limits_ok;
    doc["thermal_sensor_active"] = thermal_ok;

    if (!next_inspection_at.empty()) {
        doc["next_inspection_at"] = next_inspection_at.c_str();
    }
    if (manual_cleaning_ack) {
        doc["manual_cleaning_ack"] = true;
    }

    std::string requestBody;
    serializeJson(doc, requestBody);
    return requestBody;
}

bool HttpCloudClient::parsePingResponse(const std::string& response_json) {
    JsonDocument respDoc;
    if (deserializeJson(respDoc, response_json.c_str())) {
        return false;
    }

    JsonObject statusObj = respDoc["device_status"].as<JsonObject>();
    JsonObject sync = statusObj.isNull()
                          ? respDoc["configuration_sync"].as<JsonObject>()
                          : statusObj["configuration_sync"].as<JsonObject>();

    if (!sync.isNull()) {
        const char* state = sync["state"] | "";
        uint32_t latest_ver = sync["config_version"] | sync["latest_version"] | 0;
        uint32_t applied_ver = sync["config_applied_version"] | sync["applied_version"] | 0;
        bool is_sync = (strcmp(state, "synced") == 0) || (sync["is_synchronized"] | false);

        if (!is_sync || (latest_ver > applied_ver)) {
            config_pending_ = true;
        } else {
            config_pending_ = false;
        }
    }

    if (respDoc["manual_inspection_pending"] == true ||
        (!statusObj.isNull() && statusObj["manual_inspection_pending"] == true)) {
        manual_inspection_pending_ = true;
    } else {
        manual_inspection_pending_ = false;
    }

    if (respDoc["manual_cleaning_pending"] == true ||
        (!statusObj.isNull() && statusObj["manual_cleaning_pending"] == true)) {
        manual_cleaning_pending_ = true;
        if (respDoc["manual_cleaning_target_x_cm"].is<float>()) {
            manual_cleaning_target_x_cm_ = respDoc["manual_cleaning_target_x_cm"].as<float>();
        } else if (!statusObj.isNull() && statusObj["manual_cleaning_target_x_cm"].is<float>()) {
            manual_cleaning_target_x_cm_ = statusObj["manual_cleaning_target_x_cm"].as<float>();
        } else {
            manual_cleaning_target_x_cm_ = 0.0f;
        }
    } else {
        manual_cleaning_pending_ = false;
        manual_cleaning_target_x_cm_ = 0.0f;
    }

    return true;
}


std::string HttpCloudClient::buildTelemetryBatchJson(const IngestTelemetryBatchInput& input) {
    JsonDocument doc;
    doc["inspection_source_event_id"] = input.inspection_source_event_id.c_str();
    doc["inspection_type"] = input.inspection_type.c_str();
    // thermal_frame pixels are integers in tenths of a degree Celsius (275 == 27.5 °C).
    doc["thermal_frame_unit"] = "decicelsius";

    if (!input.cleaning_operation_id.empty()) {
        doc["cleaning_operation_id"] = input.cleaning_operation_id.c_str();
    }
    if (input.started_at_epoch > 0) {
        doc["started_at"] = formatEpochToRFC3339(input.started_at_epoch);
    }
    if (input.scheduled_for_epoch > 0) {
        doc["scheduled_for"] = formatEpochToRFC3339(input.scheduled_for_epoch);
    }

    JsonArray batchArr = doc["batch"].to<JsonArray>();
    for (const auto& m : input.batch) {
        JsonObject item = batchArr.add<JsonObject>();
        item["source_event_id"] = m.source_event_id.c_str();
        if (m.panel_index > 0) {
            item["panel_index"] = m.panel_index;
        }
        if (m.measured_at_epoch > 0) {
            item["measured_at"] = formatEpochToRFC3339(m.measured_at_epoch);
        }
        item["x_position_cm"] = m.x_position_cm;
        item["max_temperature_c"] = m.max_temperature_c;

        if (m.voltage_v != nullptr) {
            item["voltage_v"] = *m.voltage_v;
        } else {
            item["voltage_v"] = nullptr;
        }

        if (m.current_a != nullptr) {
            item["current_a"] = *m.current_a;
        } else {
            item["current_a"] = nullptr;
        }

        if (m.power_w != nullptr) {
            item["power_w"] = *m.power_w;
        } else {
            item["power_w"] = nullptr;
        }

        JsonArray frameArr = item["thermal_frame"].to<JsonArray>();
        if (m.thermal_frame != nullptr) {
            for (size_t i = 0; i < m.thermal_frame_size; ++i) {
                float t = m.thermal_frame[i];
                if (std::isnan(t) || std::isinf(t) || t < -40.0f || t > 300.0f) {
                    frameArr.add(nullptr);
                } else {
                    // -400..3000 fits int16; integers serialize ~40% shorter than floats
                    frameArr.add(static_cast<int16_t>(std::lround(t * 10.0f)));
                }
            }
        } else {
            for (size_t i = 0; i < 768; ++i) {
                frameArr.add(nullptr);
            }
        }
    }

    // Allocate the body once at its exact size. Letting std::string grow by doubling kept
    // old+new buffers alive at once and aborted the ESP32 with bad_alloc on the first batch.
    std::string requestBody;
    requestBody.reserve(measureJson(doc) + 1);
    serializeJson(doc, requestBody);
    return requestBody;  // doc is released here, before the HTTP/TLS connection opens
}


std::string HttpCloudClient::buildPanelThermalResultJson(const PanelThermalResultInput& input) {
    JsonDocument doc;
    doc["baseline_temperature_c"] = input.baseline_temperature_c;
    doc["truncated_by_memory"] = input.truncated_by_memory;
    if (input.finished_at_epoch > 0) {
        doc["finished_at"] = formatEpochToRFC3339(input.finished_at_epoch);
    }

    JsonArray hotspotsArr = doc["confirmed_hotspots"].to<JsonArray>();
    for (const auto& ch : input.confirmed_hotspots) {
        JsonObject h = hotspotsArr.add<JsonObject>();
        h["source_event_id"] = ch.source_event_id.c_str();
        if (ch.panel_index > 0) {
            h["panel_index"] = ch.panel_index;
        }
        h["global_x_position_cm"] = ch.global_x_position_cm;
        h["row_index"] = ch.row_index;
        h["max_temperature_c"] = ch.max_temperature_c;
        if (ch.detected_at_epoch > 0) {
            h["detected_at"] = formatEpochToRFC3339(ch.detected_at_epoch);
        }
        h["origin_measurement_event_id"] = ch.origin_measurement_event_id.c_str();

        JsonArray cids = h["confirming_event_ids"].to<JsonArray>();
        for (const auto& cid : ch.confirming_event_ids) {
            cids.add(cid.c_str());
        }
    }

    std::string requestBody;
    serializeJson(doc, requestBody);
    return requestBody;
}


std::string HttpCloudClient::buildFinalizeJson(const FinalizeInspectionInput& input) {
    JsonDocument doc;
    if (input.finished_at_epoch > 0) {
        doc["finished_at"] = formatEpochToRFC3339(input.finished_at_epoch);
    }
    doc["baseline_temperature_c"] = input.baseline_temperature_c;

    JsonArray hotspotsArr = doc["confirmed_hotspots"].to<JsonArray>();
    for (const auto& ch : input.confirmed_hotspots) {
        JsonObject h = hotspotsArr.add<JsonObject>();
        h["source_event_id"] = ch.source_event_id.c_str();
        if (ch.panel_index > 0) {
            h["panel_index"] = ch.panel_index;
        }
        h["global_x_position_cm"] = ch.global_x_position_cm;
        h["row_index"] = ch.row_index;
        h["max_temperature_c"] = ch.max_temperature_c;
        if (ch.detected_at_epoch > 0) {
            h["detected_at"] = formatEpochToRFC3339(ch.detected_at_epoch);
        }
        h["origin_measurement_event_id"] = ch.origin_measurement_event_id.c_str();

        JsonArray cids = h["confirming_event_ids"].to<JsonArray>();
        for (const auto& cid : ch.confirming_event_ids) {
            cids.add(cid.c_str());
        }
    }

    std::string requestBody;
    serializeJson(doc, requestBody);
    return requestBody;
}


std::string HttpCloudClient::buildAbortInspectionJson(const std::string& failure_reason) {
    JsonDocument doc;
    doc["failure_reason"] = failure_reason;
    std::string requestBody;
    serializeJson(doc, requestBody);
    return requestBody;
}


std::string HttpCloudClient::buildCleaningReportJson(const CleaningReportInput& input) {
    JsonDocument doc;
    if (!input.source_event_id.empty()) {
        doc["source_event_id"] = input.source_event_id.c_str();
    }
    if (!input.anomaly_event_id.empty()) {
        doc["anomaly_event_id"] = input.anomaly_event_id.c_str();
    }
    if (input.panel_index > 0) {
        doc["panel_index"] = input.panel_index;
    }
    doc["target_x_position_cm"] = input.target_x_position_cm;
    doc["pump_actuated"] = input.pump_actuated;

    if (input.pump_actuated && input.attempt_number >= 1) {
        doc["attempt_number"] = input.attempt_number;
    } else {
        doc["attempt_number"] = nullptr;
    }

    doc["duration_seconds"] = input.duration_seconds;
    doc["status"] = input.status.c_str();
    if (!input.failure_reason.empty()) {
        doc["failure_reason"] = input.failure_reason.c_str();
    }
    doc["post_cleaning_result"] = "pending";

    std::string requestBody;
    serializeJson(doc, requestBody);
    return requestBody;
}



} // namespace hal_esp32
