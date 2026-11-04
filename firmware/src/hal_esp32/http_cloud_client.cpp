#if defined(ARDUINO) || defined(ESP32)

#include "http_cloud_client.h"

#include <ctime>

namespace hal_esp32 {

static String formatEpochToRFC3339(uint32_t epoch) {
    if (epoch == 0) return "";
    time_t raw = static_cast<time_t>(epoch);
    struct tm ts;
    gmtime_r(&raw, &ts);
    char buf[25];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &ts);
    return String(buf);
}

HttpCloudClient::HttpCloudClient(const std::string& base_url,
                                 NvsStorage* storage,
                                 IWaterSensor* water_sensor,
                                 IMotionController* motion,
                                 IThermalCamera* camera)
    : base_url_(base_url),
      storage_(storage),
      water_sensor_(water_sensor),
      motion_(motion),
      camera_(camera) {}

bool HttpCloudClient::init() {
    if (storage_ != nullptr) {
        storage_->getModuleId(module_id_);
        storage_->getDeviceToken(device_token_);
    }
    initialized_ = true;
    return true;
}

void HttpCloudClient::setBaseUrl(const std::string& base_url) {
    base_url_ = base_url;
}

void HttpCloudClient::setCredentials(const std::string& module_id, const std::string& device_token) {
    module_id_ = module_id;
    device_token_ = device_token;
    if (storage_ != nullptr) {
        storage_->saveModuleId(module_id_);
        storage_->saveDeviceToken(device_token_);
    }
}

bool HttpCloudClient::isConnected() const {
    return WiFi.status() == WL_CONNECTED;
}

void HttpCloudClient::appendAuthHeader(HTTPClient& http) {
    if (!device_token_.empty()) {
        std::string auth = "Bearer " + device_token_;
        http.addHeader("Authorization", auth.c_str());
    }
    http.addHeader("Content-Type", "application/json");
}

bool HttpCloudClient::claimDevice(const std::string& /*claim_token*/) {
    bool water_ok = (water_sensor_ != nullptr) ? water_sensor_->isWaterAvailable() : true;
    bool limits_ok = (motion_ != nullptr) ? motion_->checkLimitsIntegrity() : true;
    bool thermal_ok = (camera_ != nullptr) ? camera_->isHealthy() : true;
    return claimWithDiagnostics(water_ok, limits_ok, thermal_ok);
}

bool HttpCloudClient::claimWithDiagnostics(bool water_ok, bool limits_ok, bool thermal_ok) {
    if (!isConnected()) {
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/claim";
    HTTPClient http;
    http.begin(url.c_str());
    http.addHeader("Content-Type", "application/json");

    JsonDocument doc;
    doc["mac_address"] = WiFi.macAddress();
    doc["firmware_version"] = "v1.4.2";
    doc["water_available"] = water_ok;
    doc["limits_check_passed"] = limits_ok;
    doc["thermal_sensor_active"] = thermal_ok;

    String requestBody;
    serializeJson(doc, requestBody);

    int httpCode = http.POST(requestBody);
    if (httpCode != HTTP_CODE_OK) {
        http.end();
        return false;
    }

    String response = http.getString();
    http.end();

    JsonDocument respDoc;
    DeserializationError error = deserializeJson(respDoc, response);
    if (error) {
        return false;
    }

    const char* mod_id = respDoc["module_id"] | "";
    const char* dev_tok = respDoc["device_token"] | "";
    int ping_int = respDoc["ping_interval_seconds"] | 300;
    int interval_d = respDoc["inspection_interval_days"] | 7;

    if (strlen(mod_id) > 0 && strlen(dev_tok) > 0) {
        module_id_ = mod_id;
        device_token_ = dev_tok;
        if (storage_ != nullptr) {
            storage_->saveModuleId(module_id_);
            storage_->saveDeviceToken(device_token_);
            storage_->savePingIntervalSeconds(ping_int);
            storage_->saveIntervalDays(interval_d);
        }
        return true;
    }

    return false;
}

bool HttpCloudClient::sendPing() {
    bool water_ok = (water_sensor_ != nullptr) ? water_sensor_->isWaterAvailable() : true;
    bool limits_ok = (motion_ != nullptr) ? motion_->checkLimitsIntegrity() : true;
    bool thermal_ok = (camera_ != nullptr) ? camera_->isHealthy() : true;
    return sendPingWithDiagnostics(water_ok, limits_ok, thermal_ok);
}

bool HttpCloudClient::sendPingWithDiagnostics(bool water_ok, bool limits_ok, bool thermal_ok) {
    if (!isConnected() || module_id_.empty() || device_token_.empty()) {
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/ping";
    HTTPClient http;
    http.begin(url.c_str());
    appendAuthHeader(http);

    JsonDocument doc;
    doc["water_available"] = water_ok;
    doc["limits_check_passed"] = limits_ok;
    doc["thermal_sensor_active"] = thermal_ok;

    String requestBody;
    serializeJson(doc, requestBody);

    int httpCode = http.POST(requestBody);
    http.end();

    if (httpCode == 401) {
        auth_error_ = true;
        return false;
    }

    return (httpCode == HTTP_CODE_OK);
}

bool HttpCloudClient::getConfiguration(std::string& out_config_json) {
    if (!isConnected() || module_id_.empty() || device_token_.empty()) {
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/configuration";
    HTTPClient http;
    http.begin(url.c_str());
    appendAuthHeader(http);

    int httpCode = http.GET();
    if (httpCode != HTTP_CODE_OK) {
        http.end();
        return false;
    }

    String response = http.getString();
    http.end();

    out_config_json = response.c_str();

    // Parse and cache in NVS if available
    if (storage_ != nullptr) {
        JsonDocument doc;
        if (!deserializeJson(doc, response)) {
            uint32_t ver = doc["config_version"] | 0;
            if (ver > 0) {
                storage_->saveConfigVersion(ver);
            }
            float min_solar = doc["min_solar_angle"] | 30.0f;
            storage_->saveMinSolarAngle(min_solar);
            int interval_d = doc["interval_days"] | 7;
            storage_->saveIntervalDays(interval_d);
            int ping_s = doc["ping_interval_seconds"] | 300;
            storage_->savePingIntervalSeconds(ping_s);

            if (doc["geometry"].is<JsonObject>()) {
                float len = doc["geometry"]["panel_length_cm"] | 100.0f;
                float width = doc["geometry"]["panel_width_cm"] | 50.0f;
                int count = doc["geometry"]["panel_count"] | 1;
                float space = doc["geometry"]["panel_spacing_cm"] | 2.0f;
                storage_->saveGeometry(len, width, count, space);
            }
        }
    }

    return true;
}

bool HttpCloudClient::ackConfiguration(uint32_t config_version) {
    return ackConfigurationAdvanced(config_version, true, "applied", "");
}

bool HttpCloudClient::ackConfigurationAdvanced(uint32_t config_version,
                                              bool applied,
                                              const std::string& checksum,
                                              const std::string& error) {
    if (!isConnected() || module_id_.empty() || device_token_.empty()) {
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/configuration/ack";
    HTTPClient http;
    http.begin(url.c_str());
    appendAuthHeader(http);

    JsonDocument doc;
    doc["config_version"] = config_version;
    doc["applied"] = applied;
    doc["checksum"] = checksum.c_str();
    if (!applied && !error.empty()) {
        doc["error"] = error.c_str();
    }

    String requestBody;
    serializeJson(doc, requestBody);

    int httpCode = http.POST(requestBody);
    http.end();

    if (httpCode == 401) {
        auth_error_ = true;
        return false;
    }

    return (httpCode == HTTP_CODE_OK);
}

bool HttpCloudClient::ingestTelemetryBatch(const IngestTelemetryBatchInput& input) {
    if (!isConnected() || module_id_.empty() || device_token_.empty()) {
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/telemetry";
    HTTPClient http;
    http.begin(url.c_str());
    appendAuthHeader(http);

    JsonDocument doc;
    doc["inspection_source_event_id"] = input.inspection_source_event_id.c_str();
    doc["inspection_type"] = input.inspection_type.c_str();

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
                    frameArr.add(t);
                }
            }
        } else {
            for (size_t i = 0; i < 768; ++i) {
                frameArr.add(nullptr);
            }
        }
    }

    String requestBody;
    serializeJson(doc, requestBody);

    int httpCode = http.POST(requestBody);
    http.end();

    if (httpCode == 401) {
        auth_error_ = true;
        return false;
    }
    if (httpCode == 409) {
        conflict_error_ = true;
        return false;
    }

    return (httpCode == HTTP_CODE_CREATED || httpCode == HTTP_CODE_OK);
}

bool HttpCloudClient::finalizeInspection(const std::string& inspection_source_event_id,
                                        const FinalizeInspectionInput& input) {
    if (!isConnected() || module_id_.empty() || device_token_.empty()) {
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/inspections/" +
                      inspection_source_event_id + "/finalize";
    HTTPClient http;
    http.begin(url.c_str());
    appendAuthHeader(http);

    JsonDocument doc;
    if (input.finished_at_epoch > 0) {
        doc["finished_at"] = formatEpochToRFC3339(input.finished_at_epoch);
    }
    doc["baseline_temperature_c"] = input.baseline_temperature_c;

    JsonArray hotspotsArr = doc["confirmed_hotspots"].to<JsonArray>();
    for (const auto& ch : input.confirmed_hotspots) {
        JsonObject h = hotspotsArr.add<JsonObject>();
        h["source_event_id"] = ch.source_event_id.c_str();
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

    String requestBody;
    serializeJson(doc, requestBody);

    int httpCode = http.POST(requestBody);
    http.end();

    if (httpCode == 401) {
        auth_error_ = true;
        return false;
    }

    return (httpCode == HTTP_CODE_OK || httpCode == HTTP_CODE_CREATED);
}

bool HttpCloudClient::ingestCleaningReport(const CleaningReportInput& input, std::string& out_cleaning_id) {
    if (!isConnected() || module_id_.empty() || device_token_.empty()) {
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/cleanings";
    HTTPClient http;
    http.begin(url.c_str());
    appendAuthHeader(http);

    JsonDocument doc;
    if (!input.anomaly_event_id.empty()) {
        doc["anomaly_event_id"] = input.anomaly_event_id.c_str();
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

    String requestBody;
    serializeJson(doc, requestBody);

    int httpCode = http.POST(requestBody);
    if (httpCode == HTTP_CODE_CREATED || httpCode == HTTP_CODE_OK) {
        String response = http.getString();
        http.end();

        JsonDocument resDoc;
        if (!deserializeJson(resDoc, response)) {
            if (resDoc["cleaning"]["id"].is<const char*>()) {
                out_cleaning_id = resDoc["cleaning"]["id"].as<std::string>();
            }
        }
        return true;
    }

    if (httpCode == 401) {
        auth_error_ = true;
    }
    http.end();
    return false;
}

bool HttpCloudClient::ingestTelemetry(const TelemetryPayload& telemetry) {
    return ingestTelemetryDetailed(telemetry.x_position_cm,
                                   telemetry.ambient_temp_c,
                                   telemetry.max_temp_c,
                                   (telemetry.delta_temp_c >= 10.0f),
                                   false,
                                   telemetry.bus_voltage_v,
                                   telemetry.current_a,
                                   telemetry.power_w,
                                   nullptr);
}

bool HttpCloudClient::ingestTelemetryDetailed(float x_pos_cm,
                                             float base_temp_c,
                                             float max_temp_c,
                                             bool hotspot_detected,
                                             bool hotspot_confirmed,
                                             float voltage_v,
                                             float current_a,
                                             float power_w,
                                             const float* /*thermal_frame*/) {
    if (!isConnected() || module_id_.empty() || device_token_.empty()) {
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/telemetry";
    HTTPClient http;
    http.begin(url.c_str());
    appendAuthHeader(http);

    JsonDocument doc;
    doc["x_position_cm"] = x_pos_cm;
    doc["baseline_temperature_c"] = base_temp_c;
    doc["max_temperature_c"] = max_temp_c;
    doc["hotspot_detected"] = hotspot_detected;
    doc["hotspot_confirmed"] = hotspot_confirmed;
    doc["voltage_v"] = voltage_v;
    doc["current_a"] = current_a;
    doc["power_w"] = power_w;

    String requestBody;
    serializeJson(doc, requestBody);

    int httpCode = http.POST(requestBody);
    http.end();

    return (httpCode == HTTP_CODE_CREATED || httpCode == HTTP_CODE_OK);
}

bool HttpCloudClient::ingestCleaning(const CleaningPayload& cleaning) {
    if (!isConnected() || module_id_.empty() || device_token_.empty()) {
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/cleanings";
    HTTPClient http;
    http.begin(url.c_str());
    appendAuthHeader(http);

    JsonDocument doc;
    if (!cleaning.anomaly_event_id.empty()) {
        doc["anomaly_event_id"] = cleaning.anomaly_event_id.c_str();
    }
    doc["target_x_position_cm"] = cleaning.x_position_cm;
    doc["pump_actuated"] = true;
    doc["attempt_number"] = cleaning.cleaning_attempts;
    doc["duration_seconds"] = (cleaning.ended_timestamp >= cleaning.started_timestamp)
                                  ? (cleaning.ended_timestamp - cleaning.started_timestamp)
                                  : 3.5;
    doc["estimated_water_volume_ml"] = 50.0;
    doc["status"] = cleaning.success ? "completed" : "failed";
    doc["post_cleaning_result"] = cleaning.success ? "resolved" : "unresolved";

    String requestBody;
    serializeJson(doc, requestBody);

    int httpCode = http.POST(requestBody);
    http.end();

    return (httpCode == HTTP_CODE_CREATED || httpCode == HTTP_CODE_OK);
}

} // namespace hal_esp32

#endif // ARDUINO || ESP32
