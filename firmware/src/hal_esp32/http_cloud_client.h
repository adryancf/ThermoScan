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
    bool finalizeInspection(const std::string& inspection_source_event_id,
                            const FinalizeInspectionInput& input) override;
    bool ingestCleaningReport(const CleaningReportInput& input, std::string& out_cleaning_id) override;
    std::string getLastConfirmedAnomalyId() const override { return last_confirmed_anomaly_id_; }
    bool ingestTelemetry(const TelemetryPayload& /*telemetry*/) override { return false; }
    bool ingestCleaning(const CleaningPayload& /*cleaning*/) override { return false; }
    bool isConnected() const override;

    bool isConfigurationPending() const override { return config_pending_; }
    void clearConfigurationPending() override { config_pending_ = false; }

    bool hadAuthError() const { return auth_error_; }
    void clearAuthError() { auth_error_ = false; }
    bool hadConflictError() const { return conflict_error_; }
    void clearConflictError() { conflict_error_ = false; }

    // JSON payload builders (directly testable)
    static std::string buildTelemetryBatchJson(const IngestTelemetryBatchInput& input);
    static std::string buildFinalizeJson(const FinalizeInspectionInput& input);
    static std::string buildCleaningReportJson(const CleaningReportInput& input);

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

    IStorage* storage_{nullptr};
    IWaterSensor* water_sensor_{nullptr};
    IMotionController* motion_{nullptr};
    IThermalCamera* camera_{nullptr};

    bool initialized_{false};
    bool auth_error_{false};
    bool conflict_error_{false};
    bool config_pending_{false};

    void appendAuthHeader(HTTPClient& http);
};

} // namespace hal_esp32

#endif // THERMOSCAN_HAL_ESP32_HTTP_CLOUD_CLIENT_H
