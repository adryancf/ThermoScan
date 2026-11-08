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

HttpCloudClient::HttpCloudClient(const std::string& base_url,
                                 IStorage* storage,
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
        Serial.println(F("[CLAIM] Aborted: No Wi-Fi connection!"));
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/claim";
    Serial.printf("[CLAIM] Sending claim request to %s (MAC: %s)...\n",
                  url.c_str(), WiFi.macAddress().c_str());

    HTTPClient http;
    http.begin(url.c_str());
    http.addHeader("Content-Type", "application/json");

    JsonDocument doc;
    doc["mac_address"] = WiFi.macAddress();
    doc["firmware_version"] = "v1.4.2";
    doc["water_available"] = water_ok;
    doc["limits_check_passed"] = limits_ok;
    doc["thermal_sensor_active"] = thermal_ok;

    std::string requestBody;
    serializeJson(doc, requestBody);

    int httpCode = http.POST(String(requestBody.c_str()));
    if (httpCode != HTTP_CODE_OK) {
        Serial.printf("[CLAIM] Claim failed! HTTP code: %d\n", httpCode);
        http.end();
        return false;
    }

    String response = http.getString();
    http.end();

    JsonDocument respDoc;
    DeserializationError error = deserializeJson(respDoc, response.c_str());
    if (error) {
        Serial.println(F("[CLAIM] Failed to deserialize claim JSON response!"));
        return false;
    }

    const char* mod_id = respDoc["module_id"] | "";
    const char* dev_tok = respDoc["device_token"] | "";
    int ping_int = respDoc["ping_interval_seconds"] | 30;
    int interval_d = respDoc["inspection_interval_days"] | 7;

    if (strlen(mod_id) > 0 && strlen(dev_tok) > 0) {
        module_id_ = mod_id;
        device_token_ = dev_tok;
        Serial.printf("[CLAIM] Success! Module ID: %s | Device Token saved | Ping: %d s\n", mod_id, ping_int);
        if (storage_ != nullptr) {
            storage_->saveModuleId(module_id_);
            storage_->saveDeviceToken(device_token_);
            storage_->savePingIntervalSeconds(ping_int);
            storage_->saveIntervalDays(interval_d);
        }
        // Immediately perform initial ping to register online presence and fetch config sync state
        sendPingWithDiagnostics(water_ok, limits_ok, thermal_ok);
        return true;
    }

    Serial.println(F("[CLAIM] Response missing valid module_id or device_token!"));
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
        Serial.printf("[PING] Aborted: wifi=%d, module_id=%s, token=%s\n",
                      isConnected(),
                      module_id_.empty() ? "EMPTY" : "OK",
                      device_token_.empty() ? "EMPTY" : "OK");
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/ping";
    Serial.printf("[PING] Sending ping to %s (water=%d, limits=%d, thermal=%d)...\n",
                  url.c_str(), water_ok, limits_ok, thermal_ok);

    HTTPClient http;
    http.begin(url.c_str());
    appendAuthHeader(http);

    JsonDocument doc;
    doc["water_available"] = water_ok;
    doc["limits_check_passed"] = limits_ok;
    doc["thermal_sensor_active"] = thermal_ok;

    if (storage_ != nullptr) {
        uint32_t next_insp = 0;
        if (storage_->getNextInspectionTimestamp(next_insp) && next_insp > 0) {
            std::string next_insp_str = formatEpochToRFC3339(next_insp);
            if (!next_insp_str.empty()) {
                doc["next_inspection_at"] = next_insp_str.c_str();
            }
        }
    }

    std::string requestBody;
    serializeJson(doc, requestBody);

    int httpCode = http.POST(String(requestBody.c_str()));

    if (httpCode == 401) {
        Serial.println(F("[PING] FAILED HTTP 401: Invalid or revoked device token!"));
        auth_error_ = true;
        http.end();
        return false;
    }

    if (httpCode == HTTP_CODE_OK) {
        String response = http.getString();
        http.end();

        JsonDocument respDoc;
        if (!deserializeJson(respDoc, response.c_str())) {
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
            if (respDoc["manual_inspection_pending"] == true || (!statusObj.isNull() && statusObj["manual_inspection_pending"] == true)) {
                manual_inspection_pending_ = true;
            } else {
                manual_inspection_pending_ = false;
            }
        }
        Serial.printf("[PING] Success HTTP 200 | config_pending=%d | manual_pending=%d\n",
                      config_pending_, manual_inspection_pending_);
        return true;
    }

    Serial.printf("[PING] FAILED HTTP code: %d\n", httpCode);
    http.end();
    return false;
}

bool HttpCloudClient::getConfiguration(std::string& out_config_json) {
    if (!isConnected() || module_id_.empty() || device_token_.empty()) {
        Serial.println(F("[CONFIG] Aborted: No Wi-Fi or credentials!"));
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/configuration";
    Serial.printf("[CONFIG] Fetching latest configuration from %s...\n", url.c_str());

    HTTPClient http;
    http.begin(url.c_str());
    appendAuthHeader(http);

    int httpCode = http.GET();
    if (httpCode != HTTP_CODE_OK) {
        Serial.printf("[CONFIG] Failed to get configuration! HTTP code: %d\n", httpCode);
        http.end();
        return false;
    }

    String response = http.getString();
    http.end();

    Serial.printf("[CONFIG] Configuration received successfully! (%u bytes)\n", response.length());
    out_config_json = response.c_str();
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
        Serial.println(F("[CONFIG_ACK] Aborted: No Wi-Fi or credentials!"));
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/configuration/ack";
    Serial.printf("[CONFIG_ACK] Sending config v%u confirmation (applied=%d, error=%s)...\n",
                  config_version, applied, error.c_str());

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

    if (storage_ != nullptr) {
        uint32_t next_insp = 0;
        if (storage_->getNextInspectionTimestamp(next_insp) && next_insp > 0) {
            std::string next_insp_str = formatEpochToRFC3339(next_insp);
            if (!next_insp_str.empty()) {
                doc["next_inspection_at"] = next_insp_str.c_str();
            }
        }
    }

    std::string requestBody;
    serializeJson(doc, requestBody);

    int httpCode = http.POST(String(requestBody.c_str()));
    http.end();

    if (httpCode == 401) {
        Serial.println(F("[CONFIG_ACK] FAILED HTTP 401: Unauthorized!"));
        auth_error_ = true;
        return false;
    }

    if (httpCode == HTTP_CODE_OK) {
        Serial.printf("[CONFIG_ACK] Success! Configuration v%u confirmed by backend (HTTP 200)\n", config_version);
        return true;
    }

    Serial.printf("[CONFIG_ACK] Config ACK failed! HTTP code: %d\n", httpCode);
    return false;
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

bool HttpCloudClient::ingestTelemetryBatch(const IngestTelemetryBatchInput& input) {
    if (!isConnected() || module_id_.empty() || device_token_.empty()) {
        Serial.println(F("[TELEMETRY] Aborted: No connection or credentials!"));
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/telemetry";
    Serial.printf("[TELEMETRY] Sending batch with %u measurements (Inspection: %s, Type: %s)...\n",
                  input.batch.size(), input.inspection_source_event_id.c_str(), input.inspection_type.c_str());

    // Build the body first so the JsonDocument is freed before TLS buffers are allocated.
    std::string requestBody = buildTelemetryBatchJson(input);
#if defined(ARDUINO) || defined(ESP32)
    Serial.printf("[TELEMETRY] Body %u bytes | free heap %u | largest block %u\n",
                  static_cast<unsigned>(requestBody.size()),
                  static_cast<unsigned>(ESP.getFreeHeap()),
                  static_cast<unsigned>(ESP.getMaxAllocHeap()));
#endif

    HTTPClient http;
    http.begin(url.c_str());
    appendAuthHeader(http);

#if defined(ARDUINO) || defined(ESP32)
    // Send the buffer directly: no extra Arduino String copy of the whole body.
    int httpCode = http.POST(reinterpret_cast<uint8_t*>(&requestBody[0]), requestBody.size());
#else
    int httpCode = http.POST(requestBody);
#endif
    http.end();

    if (httpCode == 401) {
        Serial.println(F("[TELEMETRY] FAILED HTTP 401: Invalid token!"));
        auth_error_ = true;
        return false;
    }
    if (httpCode == 409) {
        Serial.println(F("[TELEMETRY] Conflict HTTP 409 (duplicate measurement)."));
        conflict_error_ = true;
        return false;
    }

    if (httpCode == HTTP_CODE_CREATED || httpCode == HTTP_CODE_OK) {
        Serial.printf("[TELEMETRY] Batch of %u measurements recorded successfully! (HTTP %d)\n",
                      input.batch.size(), httpCode);
        return true;
    }

    Serial.printf("[TELEMETRY] Failed to ingest telemetry batch! HTTP %d\n", httpCode);
    return false;
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

bool HttpCloudClient::submitPanelThermalResult(const std::string& inspection_source_event_id,
                                               const PanelThermalResultInput& input) {
    if (!isConnected() || module_id_.empty() || device_token_.empty()) {
        Serial.println(F("[PANEL_RESULT] Aborted: No Wi-Fi or credentials!"));
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/inspections/" +
                      inspection_source_event_id + "/panels/" + std::to_string(input.panel_index) + "/result";
    Serial.printf("[PANEL_RESULT] Sending Panel %d result (Baseline: %.1f C, Hotspots: %u)...\n",
                  input.panel_index, input.baseline_temperature_c, input.confirmed_hotspots.size());

    HTTPClient http;
    http.begin(url.c_str());
    appendAuthHeader(http);

    std::string requestBody = buildPanelThermalResultJson(input);

    int httpCode = http.POST(String(requestBody.c_str()));
    if (httpCode == 401) {
        Serial.println(F("[PANEL_RESULT] FAILED HTTP 401: Invalid token!"));
        auth_error_ = true;
        http.end();
        return false;
    }

    if (httpCode == HTTP_CODE_OK || httpCode == HTTP_CODE_CREATED) {
        String response = http.getString();
        http.end();

        last_confirmed_anomalies_.clear();
        JsonDocument resDoc;
        if (!deserializeJson(resDoc, response.c_str())) {
            JsonArray arr;
            if (resDoc["confirmed_anomalies"].is<JsonArray>()) {
                arr = resDoc["confirmed_anomalies"].as<JsonArray>();
            } else if (resDoc["latest_inspection"]["confirmed_anomalies"].is<JsonArray>()) {
                arr = resDoc["latest_inspection"]["confirmed_anomalies"].as<JsonArray>();
            }
            for (JsonObject obj : arr) {
                ConfirmedAnomalyRecord rec;
                rec.id = obj["id"] | "";
                rec.panel_index = obj["panel_index"] | input.panel_index;
                rec.x_position_cm = obj["x_position_cm"] | 0.0f;
                rec.local_x_position_cm = obj["local_x_position_cm"] | 0.0f;
                if (!rec.id.empty()) {
                    last_confirmed_anomalies_.push_back(rec);
                }
            }
            if (!last_confirmed_anomalies_.empty()) {
                last_confirmed_anomaly_id_ = last_confirmed_anomalies_[0].id;
            }
        }
        Serial.printf("[PANEL_RESULT] Success HTTP %d: Panel %d recorded! (Confirmed anomalies: %u)\n",
                      httpCode, input.panel_index, last_confirmed_anomalies_.size());
        return true;
    }

    Serial.printf("[PANEL_RESULT] Panel %d result failed! HTTP code: %d\n", input.panel_index, httpCode);
    http.end();
    return false;
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

bool HttpCloudClient::finalizeInspection(const std::string& inspection_source_event_id,
                                        const FinalizeInspectionInput& input) {
    if (!isConnected() || module_id_.empty() || device_token_.empty()) {
        Serial.println(F("[INSPECTION] Aborted: No Wi-Fi or credentials!"));
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/inspections/" +
                      inspection_source_event_id + "/finalize";
    Serial.printf("[INSPECTION] Finalizing inspection %s (Consolidated baseline: %.1f C, Total hotspots: %u)...\n",
                  inspection_source_event_id.c_str(), input.baseline_temperature_c, input.confirmed_hotspots.size());

    HTTPClient http;
    http.begin(url.c_str());
    appendAuthHeader(http);

    std::string requestBody = buildFinalizeJson(input);

    int httpCode = http.POST(String(requestBody.c_str()));
    if (httpCode == 401) {
        Serial.println(F("[INSPECTION] FAILED HTTP 401: Invalid token!"));
        auth_error_ = true;
        http.end();
        return false;
    }

    if (httpCode == HTTP_CODE_OK || httpCode == HTTP_CODE_CREATED) {
        String response = http.getString();
        http.end();

        last_confirmed_anomalies_.clear();
        JsonDocument resDoc;
        if (!deserializeJson(resDoc, response.c_str())) {
            JsonArray arr;
            if (resDoc["confirmed_anomalies"].is<JsonArray>()) {
                arr = resDoc["confirmed_anomalies"].as<JsonArray>();
            } else if (resDoc["latest_inspection"]["confirmed_anomalies"].is<JsonArray>()) {
                arr = resDoc["latest_inspection"]["confirmed_anomalies"].as<JsonArray>();
            }
            for (JsonObject obj : arr) {
                ConfirmedAnomalyRecord rec;
                rec.id = obj["id"] | "";
                rec.panel_index = obj["panel_index"] | 1;
                rec.x_position_cm = obj["x_position_cm"] | 0.0f;
                rec.local_x_position_cm = obj["local_x_position_cm"] | 0.0f;
                if (!rec.id.empty()) {
                    last_confirmed_anomalies_.push_back(rec);
                }
            }
            if (!last_confirmed_anomalies_.empty()) {
                last_confirmed_anomaly_id_ = last_confirmed_anomalies_[0].id;
            }
        }
        Serial.printf("[INSPECTION] Inspection %s finalized successfully! HTTP %d (Final anomalies: %u)\n",
                      inspection_source_event_id.c_str(), httpCode, last_confirmed_anomalies_.size());
        return true;
    }

    Serial.printf("[INSPECTION] Failed to finalize inspection! HTTP code: %d\n", httpCode);
    http.end();
    return false;
}

std::string HttpCloudClient::buildCleaningReportJson(const CleaningReportInput& input) {
    JsonDocument doc;
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

bool HttpCloudClient::ingestCleaningReport(const CleaningReportInput& input, std::string& out_cleaning_id) {
    if (!isConnected() || module_id_.empty() || device_token_.empty()) {
        Serial.println(F("[CLEANING] Aborted: No Wi-Fi or credentials!"));
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/cleanings";
    Serial.printf("[CLEANING] Sending cleaning report (Panel %d, X=%.1f cm, Pump=%s, Status=%s)...\n",
                  input.panel_index, input.target_x_position_cm,
                  input.pump_actuated ? "ACTIVE" : "INACTIVE", input.status.c_str());

    HTTPClient http;
    http.begin(url.c_str());
    appendAuthHeader(http);

    std::string requestBody = buildCleaningReportJson(input);

    int httpCode = http.POST(String(requestBody.c_str()));
    if (httpCode == HTTP_CODE_CREATED || httpCode == HTTP_CODE_OK) {
        String response = http.getString();
        http.end();

        JsonDocument resDoc;
        if (!deserializeJson(resDoc, response.c_str())) {
            if (resDoc["cleaning"]["id"].is<const char*>()) {
                out_cleaning_id = resDoc["cleaning"]["id"].as<std::string>();
            }
        }
        Serial.printf("[CLEANING] Cleaning report recorded! HTTP %d (Cleaning ID: %s)\n",
                      httpCode, out_cleaning_id.c_str());
        return true;
    }

    if (httpCode == 401) {
        Serial.println(F("[CLEANING] FAILED HTTP 401: Invalid token!"));
        auth_error_ = true;
    } else {
        Serial.printf("[CLEANING] Failed to submit cleaning report! HTTP code: %d\n", httpCode);
    }
    http.end();
    return false;
}

} // namespace hal_esp32
