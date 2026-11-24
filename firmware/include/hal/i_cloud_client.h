#ifndef THERMOSCAN_HAL_I_CLOUD_CLIENT_H
#define THERMOSCAN_HAL_I_CLOUD_CLIENT_H

#include <cstdint>
#include <string>
#include <vector>

// Single measurement item in batch
struct TelemetryMeasurementItem {
    std::string source_event_id;
    uint8_t panel_index{0};                // 0 = omit / single-panel, >=1 = panel number
    uint32_t measured_at_epoch{0};
    float x_position_cm{0.0f};
    float max_temperature_c{0.0f};
    const float* voltage_v{nullptr};       // nullptr serializa como null (sem falsos zeros)
    const float* current_a{nullptr};       // nullptr serializa como null
    const float* power_w{nullptr};         // nullptr serializa como null
    const float* thermal_frame{nullptr};   // Exatamente 768 floats (nullptr/NaN serializa como null)
    size_t thermal_frame_size{768};
};

// Batch input for POST /telemetry (chunked batch uploads of max 5 items)
struct IngestTelemetryBatchInput {
    std::string inspection_source_event_id;
    uint32_t scheduled_for_epoch{0};       // 0 = omit (backend defaults to started_at)
    uint32_t started_at_epoch{0};
    std::string inspection_type{"scheduled"}; // "scheduled" or "verification"
    std::string cleaning_operation_id{""};    // Required if verification
    std::vector<TelemetryMeasurementItem> batch; // Maximum 5 items per batch
};

// Hotspot structure for inspection finalization and per-panel results
struct ConfirmedHotspotOutput {
    std::string source_event_id;
    uint8_t panel_index{0};
    float global_x_position_cm{0.0f};
    int row_index{0};
    float max_temperature_c{0.0f};
    uint32_t detected_at_epoch{0};
    std::string origin_measurement_event_id;
    std::vector<std::string> confirming_event_ids; // Minimum 2 distinct IDs from the same inspection
};

// Input for per-panel thermal result: POST /inspections/{inspectionSourceEventId}/panels/{panelIndex}/result
struct PanelThermalResultInput {
    uint8_t panel_index{1};
    float baseline_temperature_c{0.0f};
    bool truncated_by_memory{false};
    uint32_t finished_at_epoch{0};
    std::vector<ConfirmedHotspotOutput> confirmed_hotspots;
};

// Input for POST /inspections/{inspectionSourceEventId}/finalize
struct FinalizeInspectionInput {
    uint32_t finished_at_epoch{0};
    float baseline_temperature_c{0.0f};
    std::vector<ConfirmedHotspotOutput> confirmed_hotspots;
};

// Confirmed anomaly record returned by backend in submitPanelThermalResult and finalizeInspection
struct ConfirmedAnomalyRecord {
    std::string id{};
    uint8_t panel_index{1};
    float x_position_cm{0.0f};
    float local_x_position_cm{0.0f};
};

// Cleaning report input for POST /cleanings
// Capacitive water sensor is binary: estimated_water_volume_ml is omitted
struct CleaningReportInput {
    std::string source_event_id{""};
    std::string anomaly_event_id; // UUID of confirmed anomaly
    uint8_t panel_index{0};
    float target_x_position_cm{0.0f};
    bool pump_actuated{false};
    int attempt_number{0}; // 1..3 if pump_actuated, 0 if refused (serializes to null)
    float duration_seconds{0.0f};
    std::string status{"completed"}; // "completed", "failed", "refused"
    std::string failure_reason{""};
};

// Fixed-size state transition entry (~12 bytes on 32-bit ESP32, zero heap allocation)
struct StateTransitionEntry {
    const char* state{nullptr};
    const char* detail{nullptr};
    uint32_t occurred_at{0};
};

// Legacy structs for backward compatibility
struct TelemetryPayload {
    float ambient_temp_c{0.0f};
    float max_temp_c{0.0f};
    float min_temp_c{0.0f};
    float delta_temp_c{0.0f};
    float bus_voltage_v{0.0f};
    float current_a{0.0f};
    float power_w{0.0f};
    float x_position_cm{0.0f};
    uint32_t timestamp{0};
    std::string status;
};

struct CleaningPayload {
    std::string anomaly_event_id;
    uint8_t cleaning_attempts{0};
    float nozzle_angle_deg{0.0f};
    float x_position_cm{0.0f};
    uint32_t started_timestamp{0};
    uint32_t ended_timestamp{0};
    bool water_available{false};
    bool success{false};
};

class ICloudClient {
public:
    virtual ~ICloudClient() = default;

    virtual bool init() = 0;
    virtual bool claimDevice(const std::string& claim_token = "") = 0;
    virtual bool sendPing() = 0;
    virtual bool getConfiguration(std::string& out_config_json) = 0;
    virtual bool ackConfiguration(uint32_t config_version) = 0;
    virtual bool ingestTelemetryBatch(const IngestTelemetryBatchInput& input) = 0;
    virtual bool submitPanelThermalResult(const std::string& inspection_source_event_id,
                                          const PanelThermalResultInput& input) {
        (void)inspection_source_event_id;
        (void)input;
        return true;
    }
    virtual bool finalizeInspection(const std::string& inspection_source_event_id,
                                    const FinalizeInspectionInput& input) = 0;
    virtual bool abortInspection(const std::string& inspection_source_event_id,
                                 const std::string& failure_reason) {
        (void)inspection_source_event_id;
        (void)failure_reason;
        return true;
    }
    virtual bool ingestCleaningReport(const CleaningReportInput& input, std::string& out_cleaning_id) = 0;
    virtual std::string getLastConfirmedAnomalyId() const { return ""; }
    virtual std::vector<ConfirmedAnomalyRecord> getLastConfirmedAnomalies() const { return {}; }
    virtual bool hadAuthError() const { return false; }
    virtual void clearAuthError() {}
    virtual bool isConnected() const = 0;

    // Configuration sync query and reset
    virtual bool isConfigurationPending() const { return false; }
    virtual void clearConfigurationPending() {}

    // Manual inspection pending query and reset
    virtual bool isManualInspectionPending() const { return false; }
    virtual void clearManualInspectionPending() {}

    // Manual cleaning pending query, target, reset, and ack
    virtual bool isManualCleaningPending() const { return false; }
    virtual float getManualCleaningTargetXCm() const { return 0.0f; }
    virtual void clearManualCleaningPending() {}
    virtual void setManualCleaningAckPending(bool pending) { (void)pending; }

    // Manual localized thermal reading pending query, target, reset, ack, and upload
    virtual bool isManualReadingPending() const { return false; }
    virtual float getManualReadingTargetXCm() const { return 0.0f; }
    virtual void clearManualReadingPending() {}
    virtual void setManualReadingAckPending(bool pending) { (void)pending; }
    virtual bool sendLocalizedReading(float x_position_cm,
                                      uint8_t panel_index,
                                      uint32_t measured_at_epoch,
                                      float min_temp_c,
                                      float max_temp_c,
                                      float avg_temp_c,
                                      const float* pixels_768) {
        (void)x_position_cm;
        (void)panel_index;
        (void)measured_at_epoch;
        (void)min_temp_c;
        (void)max_temp_c;
        (void)avg_temp_c;
        (void)pixels_768;
        return true;
    }

    // Reset routine pending query, reset, and ack
    virtual bool isResetPending() const { return false; }
    virtual void clearResetPending() {}
    virtual void setResetAckPending(bool pending) { (void)pending; }

    // Verification cooldown ready timestamp (0 = omit)
    virtual void setVerificationReadyAt(uint32_t epoch_sec) { (void)epoch_sec; }

    // Firmware state tracking (zero-heap-allocation ring buffer in concrete client)
    virtual void setFirmwareState(const char* state, const char* detail = nullptr) {
        (void)state;
        (void)detail;
    }
    virtual void recordStateTransition(const char* state, const char* detail, uint32_t occurred_at) {
        (void)state;
        (void)detail;
        (void)occurred_at;
    }

    // Legacy backward-compat methods
    virtual bool ingestTelemetry(const TelemetryPayload& telemetry) = 0;
    virtual bool ingestCleaning(const CleaningPayload& cleaning) = 0;
};

#endif // THERMOSCAN_HAL_I_CLOUD_CLIENT_H
