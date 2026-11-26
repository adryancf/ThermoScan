#include "http_cloud_client.h"

#if defined(ARDUINO) || defined(ESP32)
#include <Arduino.h>
#include "diagnostics/web_diagnostics.h"
#define Serial diagnostics::getGlobalDualSerial()
#endif

#include <cstdio>
#include <ctime>
#include <cmath>

namespace hal_esp32 {

static bool formatEpochToBuf(uint32_t epoch, char (&buf)[25]) {
    if (epoch == 0) {
        buf[0] = '\0';
        return false;
    }
    time_t raw = static_cast<time_t>(epoch);
    struct tm ts;
    gmtime_r(&raw, &ts);
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &ts);
    return true;
}

static std::string formatEpochToRFC3339(uint32_t epoch) {
    char buf[25];
    if (!formatEpochToBuf(epoch, buf)) return "";
    return std::string(buf);
}

std::string HttpCloudClient::buildPingJson(bool water_ok, bool limits_ok, bool thermal_ok,
                                         const std::string& next_inspection_at,
                                         bool manual_cleaning_ack,
                                         const char* firmware_state,
                                         const char* firmware_state_detail,
                                         const StateTransitionEntry* transitions,
                                         size_t transition_count,
                                         bool reset_ack,
                                         const std::string& verification_ready_at,
                                         bool manual_reading_ack,
                                         const PingPowerReading* power_readings,
                                         size_t power_reading_count) {
    JsonDocument doc;
    doc["water_available"] = water_ok;
    doc["limits_check_passed"] = limits_ok;
    doc["thermal_sensor_active"] = thermal_ok;

    if (!next_inspection_at.empty()) {
        doc["next_inspection_at"] = next_inspection_at.c_str();
    }
    if (!verification_ready_at.empty()) {
        doc["verification_ready_at"] = verification_ready_at.c_str();
    }
    if (manual_cleaning_ack) {
        doc["manual_cleaning_ack"] = true;
    }
    if (manual_reading_ack) {
        doc["manual_reading_ack"] = true;
    }
    if (reset_ack) {
        doc["reset_ack"] = true;
    }
    if (firmware_state != nullptr && firmware_state[0] != '\0') {
        doc["firmware_state"] = firmware_state;
    }
    if (firmware_state_detail != nullptr && firmware_state_detail[0] != '\0') {
        doc["firmware_state_detail"] = firmware_state_detail;
    }
    if (transitions != nullptr && transition_count > 0) {
        JsonArray arr = doc["state_transitions"].to<JsonArray>();
        for (size_t i = 0; i < transition_count; ++i) {
            const StateTransitionEntry& entry = transitions[i];
            if (entry.state == nullptr || entry.state[0] == '\0') {
                continue;
            }
            JsonObject item = arr.add<JsonObject>();
            item["state"] = entry.state;
            if (entry.detail != nullptr && entry.detail[0] != '\0') {
                item["detail"] = entry.detail;
            }
            char buf[25];
            if (formatEpochToBuf(entry.occurred_at, buf)) {
                item["occurred_at"] = buf;
            } else {
                item["occurred_at"] = 0;
            }
        }
    }
    if (power_readings != nullptr && power_reading_count > 0) {
        JsonArray parr = doc["power_readings"].to<JsonArray>();
        for (size_t i = 0; i < power_reading_count; ++i) {
            const PingPowerReading& pr = power_readings[i];
            if (pr.panel_index < 1) {
                continue;
            }
            JsonObject item = parr.add<JsonObject>();
            item["panel_index"] = pr.panel_index;
            if (pr.valid && !std::isnan(pr.voltage_v) && !std::isinf(pr.voltage_v)) {
                item["voltage_v"] = pr.voltage_v;
            } else {
                item["voltage_v"] = nullptr;
            }
            if (pr.valid && !std::isnan(pr.current_a) && !std::isinf(pr.current_a)) {
                item["current_a"] = pr.current_a;
            } else {
                item["current_a"] = nullptr;
            }
            if (pr.valid && !std::isnan(pr.power_w) && !std::isinf(pr.power_w)) {
                item["power_w"] = pr.power_w;
            } else {
                item["power_w"] = nullptr;
            }
            char buf[25];
            if (pr.measured_at > 1700000000UL && formatEpochToBuf(pr.measured_at, buf)) {
                item["measured_at"] = buf;
            }
        }
    }

    std::string requestBody;
    requestBody.reserve(512);
    serializeJson(doc, requestBody);
    return requestBody;
}

std::string HttpCloudClient::buildPingPayload(bool water_ok, bool limits_ok, bool thermal_ok,
                                            const std::string& next_inspection_at,
                                            bool manual_cleaning_ack,
                                            bool reset_ack,
                                            bool manual_reading_ack,
                                            const PingPowerReading* power_readings,
                                            size_t power_reading_count) const {
    StateTransitionEntry ordered[STATE_RING_CAPACITY];
    const size_t count = (state_ring_count_ <= STATE_RING_CAPACITY) ? state_ring_count_ : STATE_RING_CAPACITY;
    for (size_t i = 0; i < count; ++i) {
        ordered[i] = state_ring_[(state_ring_head_ + i) % STATE_RING_CAPACITY];
    }
    const std::string verification_ready_at =
        (verification_ready_at_epoch_ > 1700000000UL) ? formatEpochToRFC3339(verification_ready_at_epoch_) : "";
    return buildPingJson(water_ok,
                         limits_ok,
                         thermal_ok,
                         next_inspection_at,
                         manual_cleaning_ack,
                         current_firmware_state_,
                         current_firmware_state_detail_,
                         ordered,
                         count,
                         reset_ack,
                         verification_ready_at,
                         manual_reading_ack,
                         power_readings,
                         power_reading_count);
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

    if (respDoc["manual_reading_pending"] == true ||
        (!statusObj.isNull() && statusObj["manual_reading_pending"] == true)) {
        manual_reading_pending_ = true;
        if (respDoc["manual_reading_target_x_cm"].is<float>()) {
            manual_reading_target_x_cm_ = respDoc["manual_reading_target_x_cm"].as<float>();
        } else if (!statusObj.isNull() && statusObj["manual_reading_target_x_cm"].is<float>()) {
            manual_reading_target_x_cm_ = statusObj["manual_reading_target_x_cm"].as<float>();
        } else {
            manual_reading_target_x_cm_ = 0.0f;
        }
    } else {
        manual_reading_pending_ = false;
        manual_reading_target_x_cm_ = 0.0f;
    }

    if (respDoc["reset_pending"] == true ||
        (!statusObj.isNull() && statusObj["reset_pending"] == true)) {
        reset_pending_ = true;
    } else {
        reset_pending_ = false;
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


std::string HttpCloudClient::buildLocalizedReadingJson(float x_position_cm,
                                                       uint8_t panel_index,
                                                       uint32_t measured_at_epoch,
                                                       float min_temp_c,
                                                       float max_temp_c,
                                                       float avg_temp_c,
                                                       const float* pixels_768) {
    auto sanitize = [](float v) -> float {
        return (std::isnan(v) || std::isinf(v)) ? 0.0f : v;
    };

    // Single pre-allocated buffer: avoids ArduinoJson overhead and heap fragmentation on ESP32.
    std::string payload;
    payload.reserve(6400);

    char buf[160];
    int n = std::snprintf(buf, sizeof(buf),
                          "{\"x_position_cm\":%.2f,\"panel_index\":%u,",
                          static_cast<double>(sanitize(x_position_cm)),
                          static_cast<unsigned>(panel_index));
    if (n > 0) {
        payload.append(buf, static_cast<size_t>(n));
    }

    if (measured_at_epoch > 1700000000UL) {
        const std::string ts = formatEpochToRFC3339(measured_at_epoch);
        if (!ts.empty()) {
            payload.append("\"measured_at\":\"");
            payload.append(ts);
            payload.append("\",");
        }
    }

    n = std::snprintf(buf, sizeof(buf),
                      "\"min_temperature_c\":%.2f,\"max_temperature_c\":%.2f,\"avg_temperature_c\":%.2f,\"thermal_matrix\":[",
                      static_cast<double>(sanitize(min_temp_c)),
                      static_cast<double>(sanitize(max_temp_c)),
                      static_cast<double>(sanitize(avg_temp_c)));
    if (n > 0) {
        payload.append(buf, static_cast<size_t>(n));
    }

    char pbuf[24];
    for (size_t i = 0; i < 768; ++i) {
        if (i > 0) {
            payload.push_back(',');
        }
        const float v = (pixels_768 != nullptr) ? sanitize(pixels_768[i]) : 0.0f;
        const int pn = std::snprintf(pbuf, sizeof(pbuf), "%.2f", static_cast<double>(v));
        if (pn > 0) {
            payload.append(pbuf, static_cast<size_t>(pn));
        }
    }

    payload.append("]}");
    return payload;
}



} // namespace hal_esp32
