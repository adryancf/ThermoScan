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
};

#endif // THERMOSCAN_HAL_I_STORAGE_H
