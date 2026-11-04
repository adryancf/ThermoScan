#ifndef THERMOSCAN_HAL_I_STORAGE_H
#define THERMOSCAN_HAL_I_STORAGE_H

#include <cstdint>
#include <string>

// Comprehensive NVS state representation
struct StorageState {
    std::string module_id;
    uint32_t config_version{0};
    std::string anomaly_event_id;
    uint8_t effective_attempts{0};
    std::string operation_status;
    uint32_t spray_ended_timestamp{0};
    bool pending_verification{false};
    uint32_t next_inspection_timestamp{0};
    float active_hotspot_x_cm{0.0f};
    float baseline_temp_c{0.0f};
    std::string cleaning_operation_id;
    std::string inspection_source_event_id;
};

class IStorage {
public:
    virtual ~IStorage() = default;

    virtual bool init() = 0;

    // Field-level persistence methods
    virtual bool saveModuleId(const std::string& moduleId) = 0;
    virtual bool getModuleId(std::string& out) = 0;

    virtual bool saveConfigVersion(uint32_t version) = 0;
    virtual bool getConfigVersion(uint32_t& out) = 0;

    virtual bool saveAnomalyEventId(const std::string& eventId) = 0;
    virtual bool getAnomalyEventId(std::string& out) = 0;

    virtual bool saveEffectiveAttempts(uint8_t attempts) = 0;
    virtual bool getEffectiveAttempts(uint8_t& out) = 0;

    virtual bool saveOperationStatus(const std::string& status) = 0;
    virtual bool getOperationStatus(std::string& out) = 0;

    virtual bool saveSprayEndedTimestamp(uint32_t timestamp) = 0;
    virtual bool getSprayEndedTimestamp(uint32_t& out) = 0;

    virtual bool savePendingVerification(bool pending) = 0;
    virtual bool getPendingVerification(bool& out) = 0;

    virtual bool saveNextInspectionTimestamp(uint32_t timestamp) = 0;
    virtual bool getNextInspectionTimestamp(uint32_t& out) = 0;

    // Aggregate state persistence methods
    virtual bool saveAll(const StorageState& state) = 0;
    virtual bool loadAll(StorageState& state) = 0;
    virtual bool clear() = 0;

    // Optional configuration & authentication helpers
    virtual bool saveDeviceToken(const std::string& /*token*/) { return true; }
    virtual bool getDeviceToken(std::string& /*out*/) { return true; }
    virtual bool saveGeometry(float /*length_cm*/, float /*width_cm*/, int32_t /*panel_count*/, float /*spacing_cm*/) { return true; }
    virtual bool getGeometry(float& /*length_cm*/, float& /*width_cm*/, int32_t& /*panel_count*/, float& /*spacing_cm*/) { return true; }
    virtual bool saveMinSolarAngle(float /*angle_deg*/) { return true; }
    virtual bool getMinSolarAngle(float& /*out*/) { return true; }
    virtual bool saveIntervalDays(int32_t /*days*/) { return true; }
    virtual bool getIntervalDays(int32_t& /*out*/) { return true; }
    virtual bool savePingIntervalSeconds(int32_t /*seconds*/) { return true; }
    virtual bool getPingIntervalSeconds(int32_t& /*out*/) { return true; }

    // Bench diagnostics helper
    virtual bool saveTestKey(const std::string& /*key*/, const std::string& /*val*/) { return true; }
    virtual bool getTestKey(const std::string& /*key*/, std::string& out) { out = "test_ok"; return true; }
    virtual bool removeTestKey(const std::string& /*key*/) { return true; }
};

#endif // THERMOSCAN_HAL_I_STORAGE_H
