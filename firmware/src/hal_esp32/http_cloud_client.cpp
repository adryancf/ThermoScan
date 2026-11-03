#if defined(ARDUINO) || defined(ESP32)

#include "http_cloud_client.h"

namespace hal_esp32 {

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

    return (httpCode == HTTP_CODE_OK);
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
