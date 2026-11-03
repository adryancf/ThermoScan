#ifndef THERMOSCAN_HAL_I_CLOUD_CLIENT_H
#define THERMOSCAN_HAL_I_CLOUD_CLIENT_H

#include <cstdint>
#include <string>

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
    virtual bool claimDevice(const std::string& claim_token) = 0;
    virtual bool sendPing() = 0;
    virtual bool getConfiguration(std::string& out_config_json) = 0;
    virtual bool ackConfiguration(uint32_t config_version) = 0;
    virtual bool ingestTelemetry(const TelemetryPayload& telemetry) = 0;
    virtual bool ingestCleaning(const CleaningPayload& cleaning) = 0;
    virtual bool isConnected() const = 0;
};

#endif // THERMOSCAN_HAL_I_CLOUD_CLIENT_H
