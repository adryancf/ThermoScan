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
    std::string inspection_type{"scheduled"}; // "scheduled" ou "verification"
    std::string cleaning_operation_id{""};    // Obrigatório se verification
    std::vector<TelemetryMeasurementItem> batch; // Máximo 5 itens por lote!
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
    std::vector<std::string> confirming_event_ids; // Mínimo 2 IDs distintos da mesma inspeção
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

// Cleaning report input for POST /cleanings
// Sensor capacitivo é binário: estimated_water_volume_ml NÃO é transmitido
struct CleaningReportInput {
    std::string anomaly_event_id; // UUID autêntico da anomalia confirmada
    uint8_t panel_index{0};
    float target_x_position_cm{0.0f};
    bool pump_actuated{false};
    int attempt_number{0}; // 1..3 se pump_actuated, 0 se recusado (serializa null)
    float duration_seconds{0.0f};
    std::string status{"completed"}; // "completed", "failed", "refused"
    std::string failure_reason{""};
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
    virtual bool ingestCleaningReport(const CleaningReportInput& input, std::string& out_cleaning_id) = 0;
    virtual std::string getLastConfirmedAnomalyId() const { return ""; }
    virtual bool hadAuthError() const { return false; }
    virtual bool isConnected() const = 0;

    // Configuration sync query and reset
    virtual bool isConfigurationPending() const { return false; }
    virtual void clearConfigurationPending() {}

    // Legacy backward-compat methods
    virtual bool ingestTelemetry(const TelemetryPayload& telemetry) = 0;
    virtual bool ingestCleaning(const CleaningPayload& cleaning) = 0;
};

#endif // THERMOSCAN_HAL_I_CLOUD_CLIENT_H
