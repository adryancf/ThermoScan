#ifndef THERMOSCAN_HAL_ESP32_HTTP_CLOUD_CLIENT_H
#define THERMOSCAN_HAL_ESP32_HTTP_CLOUD_CLIENT_H

#if defined(ARDUINO) || defined(ESP32)
#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#else
#include "hal/native_net_compat.h"
#endif

#include <ArduinoJson.h>
#include "hal/i_cloud_client.h"
#include "hal/i_water_sensor.h"
#include "hal/i_motion_controller.h"
#include "hal/i_thermal_camera.h"
#include "hal/i_storage.h"

namespace hal_esp32 {

/**
 * @brief HTTP/HTTPS REST client communicating with ThermoScan Go backend.
 * Authenticates via device_token ("dev_sec_...") using Bearer Authorization.
 */
class HttpCloudClient : public ICloudClient {
public:
    HttpCloudClient(const std::string& base_url = "http://192.168.1.100:8080",
                    IStorage* storage = nullptr,
                    IWaterSensor* water_sensor = nullptr,
                    IMotionController* motion = nullptr,
                    IThermalCamera* camera = nullptr);
    ~HttpCloudClient() override = default;

    bool init() override;
    bool claimDevice(const std::string& claim_token = "") override;
    bool sendPing() override;
    bool getConfiguration(std::string& out_config_json) override;
    bool ackConfiguration(uint32_t config_version) override;
    bool ingestTelemetryBatch(const IngestTelemetryBatchInput& input) override;
    bool submitPanelThermalResult(const std::string& inspection_source_event_id,
                                  const PanelThermalResultInput& input) override;
    bool finalizeInspection(const std::string& inspection_source_event_id,
                            const FinalizeInspectionInput& input) override;
    bool abortInspection(const std::string& inspection_source_event_id,
                         const std::string& failure_reason) override;
    bool ingestCleaningReport(const CleaningReportInput& input, std::string& out_cleaning_id) override;
    std::string getLastConfirmedAnomalyId() const override { return last_confirmed_anomaly_id_; }
    std::vector<ConfirmedAnomalyRecord> getLastConfirmedAnomalies() const override { return last_confirmed_anomalies_; }
    bool ingestTelemetry(const TelemetryPayload& /*telemetry*/) override { return false; }
    bool ingestCleaning(const CleaningPayload& /*cleaning*/) override { return false; }
    bool isConnected() const override;

    bool isConfigurationPending() const override { return config_pending_; }
    void clearConfigurationPending() override { config_pending_ = false; }
    bool isManualInspectionPending() const override { return manual_inspection_pending_; }
    void clearManualInspectionPending() override { manual_inspection_pending_ = false; }
    bool isManualCleaningPending() const override { return manual_cleaning_pending_; }
    float getManualCleaningTargetXCm() const override { return manual_cleaning_target_x_cm_; }
    void clearManualCleaningPending() override { manual_cleaning_pending_ = false; }
    void setManualCleaningAckPending(bool pending) override { manual_cleaning_ack_pending_ = pending; }
    bool isManualReadingPending() const override { return manual_reading_pending_; }
    float getManualReadingTargetXCm() const override { return manual_reading_target_x_cm_; }
    void clearManualReadingPending() override { manual_reading_pending_ = false; }
    void setManualReadingAckPending(bool pending) override { manual_reading_ack_pending_ = pending; }
    bool sendLocalizedReading(float x_position_cm,
                              uint8_t panel_index,
                              uint32_t measured_at_epoch,
                              float min_temp_c,
                              float max_temp_c,
                              float avg_temp_c,
                              const float* pixels_768) override;
    bool isResetPending() const override { return reset_pending_; }
    void clearResetPending() override { reset_pending_ = false; }
    void setResetAckPending(bool pending) override { reset_ack_pending_ = pending; }
    void setVerificationReadyAt(uint32_t epoch_sec) override { verification_ready_at_epoch_ = epoch_sec; }

    static constexpr size_t STATE_RING_CAPACITY = 16;
    void setFirmwareState(const char* state, const char* detail = nullptr) override;
    void recordStateTransition(const char* state, const char* detail, uint32_t occurred_at) override;
    size_t getPendingStateTransitionCount() const { return state_ring_count_; }
    const char* getFirmwareState() const { return current_firmware_state_; }
    const char* getFirmwareStateDetail() const { return current_firmware_state_detail_; }

    bool hadAuthError() const override { return auth_error_; }
    void clearAuthError() override { auth_error_ = false; }
    bool hadConflictError() const { return conflict_error_; }
    void clearConflictError() { conflict_error_ = false; }

    // JSON payload builders (directly testable)
    static std::string buildTelemetryBatchJson(const IngestTelemetryBatchInput& input);
    static std::string buildPanelThermalResultJson(const PanelThermalResultInput& input);
    static std::string buildFinalizeJson(const FinalizeInspectionInput& input);
    static std::string buildAbortInspectionJson(const std::string& failure_reason);
    static std::string buildCleaningReportJson(const CleaningReportInput& input);
    static std::string buildLocalizedReadingJson(float x_position_cm,
                                                 uint8_t panel_index,
                                                 uint32_t measured_at_epoch,
                                                 float min_temp_c,
                                                 float max_temp_c,
                                                 float avg_temp_c,
                                                 const float* pixels_768);
    static std::string buildPingJson(bool water_ok, bool limits_ok, bool thermal_ok,
                                     const std::string& next_inspection_at = "",
                                     bool manual_cleaning_ack = false,
                                     const char* firmware_state = nullptr,
                                     const char* firmware_state_detail = nullptr,
                                     const StateTransitionEntry* transitions = nullptr,
                                     size_t transition_count = 0,
                                     bool reset_ack = false,
                                     const std::string& verification_ready_at = "",
                                     bool manual_reading_ack = false);
    std::string buildPingPayload(bool water_ok, bool limits_ok, bool thermal_ok,
                                 const std::string& next_inspection_at = "",
                                 bool manual_cleaning_ack = false,
                                 bool reset_ack = false,
                                 bool manual_reading_ack = false) const;
    bool parsePingResponse(const std::string& response_json);

    // Advanced & Diagnostic helpers
    bool claimWithDiagnostics(bool water_ok, bool limits_ok, bool thermal_ok);
    bool sendPingWithDiagnostics(bool water_ok, bool limits_ok, bool thermal_ok);
    bool ackConfigurationAdvanced(uint32_t config_version, bool applied, const std::string& checksum, const std::string& error = "");

    void setBaseUrl(const std::string& base_url);
    void setCredentials(const std::string& module_id, const std::string& device_token);
    const std::string& getModuleId() const { return module_id_; }
    const std::string& getDeviceToken() const { return device_token_; }

private:
    std::string base_url_;
    std::string module_id_;
    std::string device_token_;
    std::string last_confirmed_anomaly_id_;
    std::vector<ConfirmedAnomalyRecord> last_confirmed_anomalies_;

    IStorage* storage_{nullptr};
    IWaterSensor* water_sensor_{nullptr};
    IMotionController* motion_{nullptr};
    IThermalCamera* camera_{nullptr};

    bool initialized_{false};
    bool auth_error_{false};
    bool conflict_error_{false};
    bool config_pending_{false};
    bool manual_inspection_pending_{false};
    bool manual_cleaning_pending_{false};
    float manual_cleaning_target_x_cm_{0.0f};
    bool manual_cleaning_ack_pending_{false};
    bool manual_reading_pending_{false};
    float manual_reading_target_x_cm_{0.0f};
    bool manual_reading_ack_pending_{false};
    bool reset_pending_{false};
    bool reset_ack_pending_{false};
    uint32_t verification_ready_at_epoch_{0};

    const char* current_firmware_state_{nullptr};
    const char* current_firmware_state_detail_{nullptr};
    StateTransitionEntry state_ring_[STATE_RING_CAPACITY]{};
    size_t state_ring_head_{0};
    size_t state_ring_count_{0};

    void appendAuthHeader(HTTPClient& http);
};

} // namespace hal_esp32

#endif // THERMOSCAN_HAL_ESP32_HTTP_CLOUD_CLIENT_H
