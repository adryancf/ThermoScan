#ifndef THERMOSCAN_HAL_ESP32_NVS_STORAGE_H
#define THERMOSCAN_HAL_ESP32_NVS_STORAGE_H

#if defined(ARDUINO) || defined(ESP32)

#include <Preferences.h>
#include "hal/i_storage.h"
#include <string>

namespace hal_esp32 {

/**
 * @brief ESP32 NVS (Non-Volatile Storage) driver implementing IStorage via Preferences.h.
 * ZERO MicroSD policy: all state, identifiers, device tokens, and configurations
 * are strictly persisted in internal ESP32 Flash NVS under "thermoscan" namespace.
 */
class NvsStorage : public IStorage {
public:
    NvsStorage();
    ~NvsStorage() override;

    bool init() override;

    // Field-level persistence methods (IStorage interface)
    bool saveModuleId(const std::string& moduleId) override;
    bool getModuleId(std::string& out) override;

    bool saveConfigVersion(uint32_t version) override;
    bool getConfigVersion(uint32_t& out) override;

    bool saveAnomalyEventId(const std::string& eventId) override;
    bool getAnomalyEventId(std::string& out) override;

    bool saveEffectiveAttempts(uint8_t attempts) override;
    bool getEffectiveAttempts(uint8_t& out) override;

    bool saveOperationStatus(const std::string& status) override;
    bool getOperationStatus(std::string& out) override;

    bool saveSprayEndedTimestamp(uint32_t timestamp) override;
    bool getSprayEndedTimestamp(uint32_t& out) override;

    bool savePendingVerification(bool pending) override;
    bool getPendingVerification(bool& out) override;

    bool saveNextInspectionTimestamp(uint32_t timestamp) override;
    bool getNextInspectionTimestamp(uint32_t& out) override;

    // Cleaning queue persistence (IStorage interface)
    bool saveCleaningQueue(const std::vector<QueuedHotspot>& queue) override;
    bool getCleaningQueue(std::vector<QueuedHotspot>& out) override;
    bool clearCleaningQueue() override;

    // Aggregate state persistence methods (IStorage interface)
    bool saveAll(const StorageState& state) override;
    bool loadAll(StorageState& state) override;
    bool clear() override;

    // Additional configuration & authentication storage helpers
    bool saveDeviceToken(const std::string& token) override;
    bool getDeviceToken(std::string& out) override;

    bool saveGeometry(float length_cm, float width_cm, int32_t panel_count, float spacing_cm) override;
    bool getGeometry(float& length_cm, float& width_cm, int32_t& panel_count, float& spacing_cm) override;

    bool saveMinSolarAngle(float angle_deg) override;
    bool getMinSolarAngle(float& out) override;

    bool saveIntervalDays(int32_t days) override;
    bool getIntervalDays(int32_t& out) override;

    bool savePingIntervalSeconds(int32_t seconds) override;
    bool getPingIntervalSeconds(int32_t& out) override;

    bool saveTestKey(const std::string& key, const std::string& val) override;
    bool getTestKey(const std::string& key, std::string& out) override;
    bool removeTestKey(const std::string& key) override;

private:
    Preferences preferences_;
    bool initialized_{false};

    static constexpr const char* NVS_NAMESPACE = "thermoscan";
    // NVS keys limited to 15 characters
    static constexpr const char* KEY_MODULE_ID    = "mod_id";
    static constexpr const char* KEY_DEVICE_TOKEN = "dev_tok";
    static constexpr const char* KEY_CONFIG_VER   = "cfg_ver";
    static constexpr const char* KEY_ANOMALY_ID   = "anom_id";
    static constexpr const char* KEY_EFF_ATTEMPTS = "eff_att";
    static constexpr const char* KEY_OP_STATUS    = "op_stat";
    static constexpr const char* KEY_SPRAY_END    = "spray_end";
    static constexpr const char* KEY_PENDING_VER  = "pend_ver";
    static constexpr const char* KEY_NEXT_INSP    = "next_insp";
    static constexpr const char* KEY_CLEAN_QUEUE  = "clean_q";

    static constexpr const char* KEY_PANEL_LEN    = "p_len";
    static constexpr const char* KEY_PANEL_WIDTH  = "p_width";
    static constexpr const char* KEY_PANEL_COUNT  = "p_count";
    static constexpr const char* KEY_PANEL_SPACE  = "p_space";
    static constexpr const char* KEY_MIN_SOLAR    = "min_solar";
    static constexpr const char* KEY_INTERVAL_D   = "interval_d";
    static constexpr const char* KEY_PING_INT     = "ping_int";
};

} // namespace hal_esp32

#endif // ARDUINO || ESP32

#endif // THERMOSCAN_HAL_ESP32_NVS_STORAGE_H
