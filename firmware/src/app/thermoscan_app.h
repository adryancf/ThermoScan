#ifndef THERMOSCAN_APP_THERMOSCAN_APP_H
#define THERMOSCAN_APP_THERMOSCAN_APP_H

#include <cstdint>
#include <string>
#include <vector>

#include "pinout.h"
#include "hal/i_thermal_camera.h"
#include "hal/i_power_meter.h"
#include "hal/i_motion_controller.h"
#include "hal/i_spray_actuator.h"
#include "hal/i_water_sensor.h"
#include "hal/i_storage.h"
#include "hal/i_cloud_client.h"
#include "hal/i_time_provider.h"

#include "domain/cleaning_state_machine.h"
#include "domain/thermal_analyzer.h"
#include "domain/solar_geometry.h"
#include "domain/quantized_frame.h"
#include "domain/temperature_histogram.h"
#include "utils/heap_tracker.h"
#include "utils/uuid_generator.h"

namespace app {

enum class AppState {
    BOOT_INIT,
    IDLE,
    SCANNING,
    ANALYZING,
    CLEANING,
    WAITING_VERIFICATION,
    VERIFYING,
    SYNCING,
    ERROR_HALT
};

struct AppConfig {
    uint32_t config_version{1};
    float panel_length_cm{100.0f};
    float panel_width_cm{50.0f};
    int32_t panel_count{1};
    float panel_spacing_cm{2.0f};
    float min_solar_angle{30.0f};
    int32_t interval_days{7};
    int32_t ping_interval_seconds{300};

    // Geographic location (default São Paulo, Brazil)
    float latitude{-23.5505f};
    float longitude{-46.6333f};
    float azimuth{0.0f};   // North-facing in Southern hemisphere
    float tilt{20.0f};     // 20 degrees tilt
};

/**
 * @brief Central application orchestrator managing inspection scans, thermal analysis,
 * spray cleaning actuation with water interlocks, and post-wash verification cooldowns.
 */
class ThermoscanApp {
public:
    ThermoscanApp(IThermalCamera* camera,
                  IPowerMeter* power_meter,
                  IMotionController* motion,
                  ISprayActuator* spray,
                  IWaterSensor* water_sensor,
                  IStorage* storage,
                  ICloudClient* cloud,
                  ITimeProvider* time_provider);

    ~ThermoscanApp() = default;

    bool init();
    void tick();

    // State & Diagnosis getters
    AppState getState() const { return state_; }
    const char* getStateName() const;
    const domain::CleaningStateMachine& getCleaningStateMachine() const { return cleaning_sm_; }
    const AppConfig& getConfig() const { return config_; }

    // Manual triggers
    void triggerManualInspection();
    void triggerManualCleaning(float target_x_cm);

private:
    IThermalCamera* camera_{nullptr};
    IPowerMeter* power_meter_{nullptr};
    IMotionController* motion_{nullptr};
    ISprayActuator* spray_{nullptr};
    IWaterSensor* water_sensor_{nullptr};
    IStorage* storage_{nullptr};
    ICloudClient* cloud_{nullptr};
    ITimeProvider* time_provider_{nullptr};

    AppState state_{AppState::BOOT_INIT};
    AppConfig config_;

    domain::CleaningStateMachine cleaning_sm_;
    domain::ThermalAnalyzer thermal_analyzer_;

    std::vector<domain::QuantizedThermalFrame> quantized_frames_;
    domain::TemperatureHistogram histogram_;
    std::vector<TelemetryMeasurementItem> current_batch_;
    std::string inspection_source_event_id_{};
    uint32_t inspection_started_at_{0};
    uint32_t inspection_scheduled_for_{0};
    std::string current_cleaning_op_id_{};
    bool scan_truncated_by_memory_{false};

    domain::HotspotEvent active_hotspot_{};
    float baseline_temp_c_{25.0f};

    uint32_t last_ping_time_{0};
    uint32_t next_inspection_time_{0};
    bool manual_inspection_requested_{false};
    bool manual_cleaning_requested_{false};
    float manual_cleaning_target_x_{0.0f};

    // State handlers
    void handleBootInit();
    void handleIdle();
    void handleScanning();
    void handleAnalyzing();
    void handleCleaning();
    void handleWaitingVerification();
    void handleVerifying();
    void handleSyncing();

    // Helpers
    uint32_t getCurrentTime() const;
    bool checkSolarWindow() const;
    void executeEmergencyStop();
    void saveCurrentStateToNvs();
    void restoreStateFromNvs();
};

} // namespace app

using app::ThermoscanApp;
using app::AppState;
using app::AppConfig;

#endif // THERMOSCAN_APP_THERMOSCAN_APP_H
