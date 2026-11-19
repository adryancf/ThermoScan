#include "http_cloud_client.h"

#if defined(ARDUINO) || defined(ESP32)
#include <Arduino.h>
#include <sys/time.h>
#include "diagnostics/web_diagnostics.h"
#define Serial diagnostics::getGlobalDualSerial()
#endif

#include <cstdio>
#include <cstring>
#include <ctime>
#include <cmath>

namespace hal_esp32 {

#if defined(ARDUINO) || defined(ESP32)
static bool parseHttpDateToEpoch(const char* date_str, uint32_t& out_epoch) {
    if (date_str == nullptr || date_str[0] == '\0') return false;
    int day = 0, year = 0, hour = 0, min = 0, sec = 0;
    char mon_str[4] = {0};
    if (std::sscanf(date_str, "%*3[^,], %d %3s %d %d:%d:%d",
                    &day, mon_str, &year, &hour, &min, &sec) != 6) {
        return false;
    }
    static const char* kMonths[12] = {
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    };
    int month = 0;
    for (int i = 0; i < 12; ++i) {
        if (std::strncmp(mon_str, kMonths[i], 3) == 0) {
            month = i + 1;
            break;
        }
    }
    if (month == 0 || year < 2024 || day < 1 || day > 31) return false;

    // Howard Hinnant's civil-from-days algorithm (UTC, zero timezone/locale issues)
    int y = year - (month <= 2 ? 1 : 0);
    int era = (y >= 0 ? y : y - 399) / 400;
    int yoe = y - era * 400;
    int doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
    int doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    int64_t days = static_cast<int64_t>(era) * 146097LL + static_cast<int64_t>(doe) - 719468LL;
    int64_t epoch = days * 86400LL + hour * 3600LL + min * 60LL + sec;
    if (epoch <= 1700000000LL) return false;
    out_epoch = static_cast<uint32_t>(epoch);
    return true;
}

static void syncClockFromHttpDateIfNeeded(HTTPClient& http) {
    time_t now = 0;
    time(&now);
    if (now > 1700000000) return;
    if (!http.hasHeader("Date")) return;
    String date_val = http.header("Date");
    uint32_t epoch = 0;
    if (parseHttpDateToEpoch(date_val.c_str(), epoch)) {
        struct timeval tv{};
        tv.tv_sec = static_cast<time_t>(epoch);
        tv.tv_usec = 0;
        settimeofday(&tv, nullptr);
        Serial.printf("[CLOCK] Synced UTC clock from backend HTTP Date header: %u\n", epoch);
    }
}
#endif

static void configureHttpTimeouts(HTTPClient& http, uint16_t timeout_ms = 6000) {
#if defined(ARDUINO) || defined(ESP32)
    http.setConnectTimeout(4000);
    http.setTimeout(timeout_ms);
#else
    (void)http;
    (void)timeout_ms;
#endif
}

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

void HttpCloudClient::setFirmwareState(const char* state, const char* detail) {
    current_firmware_state_ = state;
    current_firmware_state_detail_ = detail;
}

void HttpCloudClient::recordStateTransition(const char* state, const char* detail, uint32_t occurred_at) {
    if (state == nullptr || state[0] == '\0') {
        return;
    }
    const size_t write_idx = (state_ring_head_ + state_ring_count_) % STATE_RING_CAPACITY;
    state_ring_[write_idx].state = state;
    state_ring_[write_idx].detail = detail;
    state_ring_[write_idx].occurred_at = occurred_at;
    if (state_ring_count_ < STATE_RING_CAPACITY) {
        state_ring_count_++;
    } else {
        // Buffer is full: overwrite oldest entry and advance head
        state_ring_head_ = (state_ring_head_ + 1) % STATE_RING_CAPACITY;
    }
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
    configureHttpTimeouts(http, 6000);
    http.addHeader("Content-Type", "application/json");
#if defined(ARDUINO) || defined(ESP32)
    const char* date_hdr[] = {"Date"};
    http.collectHeaders(date_hdr, 1);
#endif

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

#if defined(ARDUINO) || defined(ESP32)
    syncClockFromHttpDateIfNeeded(http);
#endif
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
        auth_error_ = false;
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
    Serial.printf("[PING] Sending ping to %s (water=%d, limits=%d, thermal=%d, cleaning_ack=%d)...\n",
                  url.c_str(), water_ok, limits_ok, thermal_ok, manual_cleaning_ack_pending_);

    HTTPClient http;
    http.begin(url.c_str());
    configureHttpTimeouts(http, 6000);
    appendAuthHeader(http);
#if defined(ARDUINO) || defined(ESP32)
    const char* date_hdr[] = {"Date"};
    http.collectHeaders(date_hdr, 1);
#endif

    std::string next_insp_str;
    if (storage_ != nullptr) {
        uint32_t next_insp = 0;
        if (storage_->getNextInspectionTimestamp(next_insp) && next_insp > 0) {
            next_insp_str = formatEpochToRFC3339(next_insp);
        }
    }

    std::string requestBody = buildPingPayload(
        water_ok, limits_ok, thermal_ok, next_insp_str, manual_cleaning_ack_pending_, reset_ack_pending_);

    int httpCode = http.POST(String(requestBody.c_str()));

    if (httpCode == 401) {
        Serial.println(F("[PING] FAILED HTTP 401: Invalid or revoked device token!"));
        auth_error_ = true;
        http.end();
        return false;
    }

    if (httpCode == HTTP_CODE_OK) {
#if defined(ARDUINO) || defined(ESP32)
        syncClockFromHttpDateIfNeeded(http);
#endif
        String response = http.getString();
        http.end();

        manual_cleaning_ack_pending_ = false;
        reset_ack_pending_ = false;
        state_ring_head_ = 0;
        state_ring_count_ = 0;
        parsePingResponse(response.c_str());

        Serial.printf("[PING] Success HTTP 200 | config_pending=%d | manual_insp=%d | manual_clean=%d (x=%.1f)\n",
                      config_pending_, manual_inspection_pending_,
                      manual_cleaning_pending_, manual_cleaning_target_x_cm_);
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
    configureHttpTimeouts(http, 6000);
    appendAuthHeader(http);

    int httpCode = http.GET();
    if (httpCode != HTTP_CODE_OK) {
        if (httpCode == 401) {
            Serial.println(F("[CONFIG] FAILED HTTP 401: Invalid or revoked device token!"));
            auth_error_ = true;
        }
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
    configureHttpTimeouts(http, 6000);
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
    configureHttpTimeouts(http, 10000);
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
    configureHttpTimeouts(http, 6000);
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
    configureHttpTimeouts(http, 6000);
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

bool HttpCloudClient::abortInspection(const std::string& inspection_source_event_id,
                                      const std::string& failure_reason) {
    if (!isConnected() || module_id_.empty() || device_token_.empty()) {
        Serial.println(F("[INSPECTION] Abort skipped: No Wi-Fi or credentials!"));
        return false;
    }
    if (inspection_source_event_id.empty()) {
        return false;
    }

    std::string url = base_url_ + "/api/v1/devices/" + module_id_ + "/inspections/" +
                      inspection_source_event_id + "/abort";
    Serial.printf("[INSPECTION] Aborting inspection %s (Reason: %s)...\n",
                  inspection_source_event_id.c_str(), failure_reason.c_str());

    HTTPClient http;
    http.begin(url.c_str());
    configureHttpTimeouts(http, 6000);
    appendAuthHeader(http);

    std::string requestBody = buildAbortInspectionJson(failure_reason);

    int httpCode = http.POST(String(requestBody.c_str()));
    http.end();

    if (httpCode == 401) {
        Serial.println(F("[INSPECTION] Abort FAILED HTTP 401: Invalid token!"));
        auth_error_ = true;
        return false;
    }

    if (httpCode == HTTP_CODE_OK || httpCode == HTTP_CODE_NO_CONTENT || httpCode == HTTP_CODE_CREATED) {
        Serial.printf("[INSPECTION] Inspection %s aborted successfully! HTTP %d\n",
                      inspection_source_event_id.c_str(), httpCode);
        return true;
    }

    Serial.printf("[INSPECTION] Failed to abort inspection! HTTP code: %d\n", httpCode);
    return false;
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
    configureHttpTimeouts(http, 6000);
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
