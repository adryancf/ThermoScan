#if defined(ARDUINO) || defined(ESP32)

#include "nvs_storage.h"
#include <ArduinoJson.h>

namespace hal_esp32 {

NvsStorage::NvsStorage() = default;

NvsStorage::~NvsStorage() {
    if (initialized_) {
        preferences_.end();
    }
}

bool NvsStorage::init() {
    initialized_ = preferences_.begin(NVS_NAMESPACE, false);
    return initialized_;
}

bool NvsStorage::saveModuleId(const std::string& moduleId) {
    if (!initialized_ && !init()) return false;
    return preferences_.putString(KEY_MODULE_ID, moduleId.c_str()) > 0;
}

bool NvsStorage::getModuleId(std::string& out) {
    if (!initialized_ && !init()) return false;
    if (!preferences_.isKey(KEY_MODULE_ID)) {
        out.clear();
        return false;
    }
    String val = preferences_.getString(KEY_MODULE_ID, "");
    out = val.c_str();
    return true;
}

bool NvsStorage::saveConfigVersion(uint32_t version) {
    if (!initialized_ && !init()) return false;
    return preferences_.putUInt(KEY_CONFIG_VER, version) > 0;
}

bool NvsStorage::getConfigVersion(uint32_t& out) {
    if (!initialized_ && !init()) return false;
    if (!preferences_.isKey(KEY_CONFIG_VER)) {
        out = 0;
        return false;
    }
    out = preferences_.getUInt(KEY_CONFIG_VER, 0);
    return true;
}

bool NvsStorage::saveAnomalyEventId(const std::string& eventId) {
    if (!initialized_ && !init()) return false;
    return preferences_.putString(KEY_ANOMALY_ID, eventId.c_str()) > 0;
}

bool NvsStorage::getAnomalyEventId(std::string& out) {
    if (!initialized_ && !init()) return false;
    if (!preferences_.isKey(KEY_ANOMALY_ID)) {
        out.clear();
        return false;
    }
    String val = preferences_.getString(KEY_ANOMALY_ID, "");
    out = val.c_str();
    return true;
}

bool NvsStorage::saveEffectiveAttempts(uint8_t attempts) {
    if (!initialized_ && !init()) return false;
    return preferences_.putUChar(KEY_EFF_ATTEMPTS, attempts) > 0;
}

bool NvsStorage::getEffectiveAttempts(uint8_t& out) {
    if (!initialized_ && !init()) return false;
    if (!preferences_.isKey(KEY_EFF_ATTEMPTS)) {
        out = 0;
        return false;
    }
    out = preferences_.getUChar(KEY_EFF_ATTEMPTS, 0);
    return true;
}

bool NvsStorage::saveOperationStatus(const std::string& status) {
    if (!initialized_ && !init()) return false;
    return preferences_.putString(KEY_OP_STATUS, status.c_str()) > 0;
}

bool NvsStorage::getOperationStatus(std::string& out) {
    if (!initialized_ && !init()) return false;
    if (!preferences_.isKey(KEY_OP_STATUS)) {
        out = "idle";
        return false;
    }
    String val = preferences_.getString(KEY_OP_STATUS, "idle");
    out = val.c_str();
    return true;
}

bool NvsStorage::saveSprayEndedTimestamp(uint32_t timestamp) {
    if (!initialized_ && !init()) return false;
    return preferences_.putUInt(KEY_SPRAY_END, timestamp) > 0;
}

bool NvsStorage::getSprayEndedTimestamp(uint32_t& out) {
    if (!initialized_ && !init()) return false;
    if (!preferences_.isKey(KEY_SPRAY_END)) {
        out = 0;
        return false;
    }
    out = preferences_.getUInt(KEY_SPRAY_END, 0);
    return true;
}

bool NvsStorage::savePendingVerification(bool pending) {
    if (!initialized_ && !init()) return false;
    return preferences_.putBool(KEY_PENDING_VER, pending) > 0;
}

bool NvsStorage::getPendingVerification(bool& out) {
    if (!initialized_ && !init()) return false;
    if (!preferences_.isKey(KEY_PENDING_VER)) {
        out = false;
        return false;
    }
    out = preferences_.getBool(KEY_PENDING_VER, false);
    return true;
}

bool NvsStorage::saveNextInspectionTimestamp(uint32_t timestamp) {
    if (!initialized_ && !init()) return false;
    return preferences_.putUInt(KEY_NEXT_INSP, timestamp) > 0;
}

bool NvsStorage::getNextInspectionTimestamp(uint32_t& out) {
    if (!initialized_ && !init()) return false;
    if (!preferences_.isKey(KEY_NEXT_INSP)) {
        out = 0;
        return false;
    }
    out = preferences_.getUInt(KEY_NEXT_INSP, 0);
    return true;
}

bool NvsStorage::saveCleaningQueue(const std::vector<QueuedHotspot>& queue) {
    if (!initialized_ && !init()) return false;
    JsonDocument doc;
    JsonArray arr = doc.to<JsonArray>();
    for (const auto& item : queue) {
        JsonObject obj = arr.add<JsonObject>();
        obj["p"] = item.panel_index;
        obj["x"] = item.target_x_cm;
        obj["aid"] = item.anomaly_event_id;
        obj["cid"] = item.cleaning_operation_id;
        obj["att"] = item.attempts;
        obj["st"] = item.verification_status;
        obj["b"] = item.baseline_temp_c;
        obj["int"] = item.spray_interrupted;
    }
    String output;
    serializeJson(doc, output);
    return preferences_.putString(KEY_CLEAN_QUEUE, output) > 0;
}

bool NvsStorage::getCleaningQueue(std::vector<QueuedHotspot>& out) {
    out.clear();
    if (!initialized_ && !init()) return false;
    if (!preferences_.isKey(KEY_CLEAN_QUEUE)) return false;
    String raw = preferences_.getString(KEY_CLEAN_QUEUE, "");
    if (raw.isEmpty()) return false;
    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, raw);
    if (err) return false;
    JsonArray arr = doc.as<JsonArray>();
    for (JsonObject obj : arr) {
        QueuedHotspot item;
        item.panel_index = obj["p"] | 1;
        item.target_x_cm = obj["x"] | 0.0f;
        item.anomaly_event_id = obj["aid"] | "";
        item.cleaning_operation_id = obj["cid"] | "";
        item.attempts = obj["att"] | 0;
        item.verification_status = obj["st"] | "pending";
        item.baseline_temp_c = obj["b"] | 25.0f;
        item.spray_interrupted = obj["int"] | false;
        out.push_back(item);
    }
    return true;
}

bool NvsStorage::clearCleaningQueue() {
    if (!initialized_ && !init()) return false;
    return preferences_.remove(KEY_CLEAN_QUEUE);
}

bool NvsStorage::saveAll(const StorageState& state) {
    if (!initialized_ && !init()) return false;
    bool ok = true;
    ok &= saveModuleId(state.module_id);
    ok &= saveConfigVersion(state.config_version);
    ok &= saveAnomalyEventId(state.anomaly_event_id);
    ok &= saveEffectiveAttempts(state.effective_attempts);
    ok &= saveOperationStatus(state.operation_status);
    ok &= saveSprayEndedTimestamp(state.spray_ended_timestamp);
    ok &= savePendingVerification(state.pending_verification);
    ok &= saveNextInspectionTimestamp(state.next_inspection_timestamp);
    preferences_.putFloat("hotspot_x", state.active_hotspot_x_cm);
    preferences_.putFloat("base_temp", state.baseline_temp_c);
    preferences_.putString("clean_op_id", state.cleaning_operation_id.c_str());
    preferences_.putString("insp_src_id", state.inspection_source_event_id.c_str());
    preferences_.putUChar("act_p_idx", state.active_panel_index);
    return ok;
}

bool NvsStorage::loadAll(StorageState& state) {
    if (!initialized_ && !init()) return false;
    getModuleId(state.module_id);
    getConfigVersion(state.config_version);
    getAnomalyEventId(state.anomaly_event_id);
    getEffectiveAttempts(state.effective_attempts);
    getOperationStatus(state.operation_status);
    getSprayEndedTimestamp(state.spray_ended_timestamp);
    getPendingVerification(state.pending_verification);
    getNextInspectionTimestamp(state.next_inspection_timestamp);
    state.active_hotspot_x_cm = preferences_.getFloat("hotspot_x", 0.0f);
    state.baseline_temp_c = preferences_.getFloat("base_temp", 25.0f);
    state.cleaning_operation_id = preferences_.getString("clean_op_id", "").c_str();
    state.inspection_source_event_id = preferences_.getString("insp_src_id", "").c_str();
    state.active_panel_index = preferences_.getUChar("act_p_idx", 1);
    return true;
}

bool NvsStorage::clear() {
    if (!initialized_ && !init()) return false;
    return preferences_.clear();
}

bool NvsStorage::saveDeviceToken(const std::string& token) {
    if (!initialized_ && !init()) return false;
    return preferences_.putString(KEY_DEVICE_TOKEN, token.c_str()) > 0;
}

bool NvsStorage::getDeviceToken(std::string& out) {
    if (!initialized_ && !init()) return false;
    if (!preferences_.isKey(KEY_DEVICE_TOKEN)) {
        out.clear();
        return false;
    }
    String val = preferences_.getString(KEY_DEVICE_TOKEN, "");
    out = val.c_str();
    return true;
}

bool NvsStorage::saveGeometry(float length_cm, float width_cm, int32_t panel_count, float spacing_cm) {
    if (!initialized_ && !init()) return false;
    bool ok = true;
    ok &= (preferences_.putFloat(KEY_PANEL_LEN, length_cm) > 0);
    ok &= (preferences_.putFloat(KEY_PANEL_WIDTH, width_cm) > 0);
    ok &= (preferences_.putInt(KEY_PANEL_COUNT, panel_count) > 0);
    ok &= (preferences_.putFloat(KEY_PANEL_SPACE, spacing_cm) > 0);
    return ok;
}

bool NvsStorage::getGeometry(float& length_cm, float& width_cm, int32_t& panel_count, float& spacing_cm) {
    if (!initialized_ && !init()) return false;
    length_cm = preferences_.getFloat(KEY_PANEL_LEN, 100.0f);
    width_cm = preferences_.getFloat(KEY_PANEL_WIDTH, 50.0f);
    panel_count = preferences_.getInt(KEY_PANEL_COUNT, 1);
    spacing_cm = preferences_.getFloat(KEY_PANEL_SPACE, 2.0f);
    return true;
}

bool NvsStorage::saveMinSolarAngle(float angle_deg) {
    if (!initialized_ && !init()) return false;
    return preferences_.putFloat(KEY_MIN_SOLAR, angle_deg) > 0;
}

bool NvsStorage::getMinSolarAngle(float& out) {
    if (!initialized_ && !init()) return false;
    out = preferences_.getFloat(KEY_MIN_SOLAR, 30.0f);
    return true;
}

bool NvsStorage::saveIntervalDays(int32_t days) {
    if (!initialized_ && !init()) return false;
    return preferences_.putInt(KEY_INTERVAL_D, days) > 0;
}

bool NvsStorage::getIntervalDays(int32_t& out) {
    if (!initialized_ && !init()) return false;
    out = preferences_.getInt(KEY_INTERVAL_D, 7);
    return true;
}

bool NvsStorage::savePingIntervalSeconds(int32_t seconds) {
    if (!initialized_ && !init()) return false;
    return preferences_.putInt(KEY_PING_INT, seconds) > 0;
}

bool NvsStorage::getPingIntervalSeconds(int32_t& out) {
    if (!initialized_ && !init()) return false;
    out = preferences_.getInt(KEY_PING_INT, 30);
    return true;
}

bool NvsStorage::saveTestKey(const std::string& key, const std::string& val) {
    if (!initialized_ && !init()) return false;
    return preferences_.putString(key.c_str(), val.c_str()) > 0;
}

bool NvsStorage::getTestKey(const std::string& key, std::string& out) {
    if (!initialized_ && !init()) return false;
    if (!preferences_.isKey(key.c_str())) return false;
    String v = preferences_.getString(key.c_str(), "");
    out = v.c_str();
    return true;
}

bool NvsStorage::removeTestKey(const std::string& key) {
    if (!initialized_ && !init()) return false;
    return preferences_.remove(key.c_str());
}

} // namespace hal_esp32

#endif // ARDUINO || ESP32
