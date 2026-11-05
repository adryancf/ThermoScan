#include <unity.h>
#include "app/thermoscan_app.h"
#include "hal/i_thermal_camera.h"
#include "hal/i_power_meter.h"
#include "hal/i_motion_controller.h"
#include "hal/i_spray_actuator.h"
#include "hal/i_water_sensor.h"
#include "hal/i_storage.h"
#include "hal/i_cloud_client.h"
#include "hal/i_time_provider.h"

namespace {

class MockThermalCamera : public IThermalCamera {
public:
    bool healthy{true};
    bool capture_valid{true};
    float pixel_fill{25.0f};
    float current_x{0.0f};
    std::vector<std::pair<float, int>> hotspots; // (target_x_cm, row)

    bool init() override { return true; }
    bool captureFrame(ThermalFrame& out) override {
        out.valid = capture_valid;
        for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
            out.pixels[i] = pixel_fill;
        }
        const float fov = 5.0f;
        for (const auto& hs : hotspots) {
            float tx = hs.first;
            int row = hs.second;
            if (tx >= current_x && tx < (current_x + fov)) {
                int col = static_cast<int>(std::round(((tx - current_x) / fov) * 32.0f));
                if (col < 0) col = 0;
                if (col >= 32) col = 31;
                out.pixels[row * 32 + col] = pixel_fill + 20.0f;
            }
        }
        return capture_valid;
    }
    bool isHealthy() override { return healthy; }
};

class MockPowerMeter : public IPowerMeter {
public:
    bool init() override { return true; }
    bool readSnapshot(PowerSnapshot& out) override {
        out.voltage_v = 18.5f;
        out.current_a = 5.2f;
        out.power_w = 96.2f;
        out.valid = true;
        return true;
    }
};

class MockMotionController : public IMotionController {
public:
    float x_pos{0.0f};
    bool limit_healthy{true};
    bool home_success{true};
    MockThermalCamera* camera{nullptr};
    std::vector<float> visited_x;

    bool init() override { return true; }
    bool home() override {
        if (!home_success) return false;
        x_pos = 0.0f;
        if (camera) camera->current_x = 0.0f;
        return true;
    }
    bool moveToXCm(float target_x_cm) override {
        x_pos = target_x_cm;
        visited_x.push_back(target_x_cm);
        if (camera) camera->current_x = target_x_cm;
        return true;
    }
    float getXPositionCm() const override { return x_pos; }
    bool checkLimitsIntegrity() override { return limit_healthy; }
    void disableMotor() override {}
    void emergencyStop() override {}
};

class MockSprayActuator : public ISprayActuator {
public:
    bool pump_active{false};
    float angle{90.0f};

    bool init() override {
        pump_active = false; // Safe boot
        return true;
    }
    bool setNozzleAngle(float angle_deg) override {
        angle = angle_deg;
        return true;
    }
    bool startPump() override {
        pump_active = true;
        return true;
    }
    void stopPump() override {
        pump_active = false;
    }
    bool isPumpActive() const override {
        return pump_active;
    }
};

class MockWaterSensor : public IWaterSensor {
public:
    bool available{true};

    WaterStatus readStatus() override {
        return available ? WaterStatus::AVAILABLE : WaterStatus::DEPLETED;
    }
    bool isWaterAvailable() override {
        return available;
    }
};

class MockStorage : public IStorage {
public:
    StorageState state{};
    uint32_t config_version{1};
    float panel_len{100.0f};
    float panel_wid{50.0f};
    int32_t panel_cnt{1};
    float panel_spc{2.0f};
    float min_solar{30.0f};
    int32_t interval_d{7};
    int32_t ping_s{300};

    bool init() override { return true; }
    bool saveModuleId(const std::string& moduleId) override { state.module_id = moduleId; return true; }
    bool getModuleId(std::string& out) override { out = state.module_id; return true; }
    bool saveConfigVersion(uint32_t version) override { state.config_version = version; config_version = version; return true; }
    bool getConfigVersion(uint32_t& out) override { out = state.config_version; return true; }
    bool saveAnomalyEventId(const std::string& eventId) override { state.anomaly_event_id = eventId; return true; }
    bool getAnomalyEventId(std::string& out) override { out = state.anomaly_event_id; return true; }
    bool saveEffectiveAttempts(uint8_t attempts) override { state.effective_attempts = attempts; return true; }
    bool getEffectiveAttempts(uint8_t& out) override { out = state.effective_attempts; return true; }
    bool saveOperationStatus(const std::string& status) override { state.operation_status = status; return true; }
    bool getOperationStatus(std::string& out) override { out = state.operation_status; return true; }
    bool saveSprayEndedTimestamp(uint32_t timestamp) override { state.spray_ended_timestamp = timestamp; return true; }
    bool getSprayEndedTimestamp(uint32_t& out) override { out = state.spray_ended_timestamp; return true; }
    bool savePendingVerification(bool pending) override { state.pending_verification = pending; return true; }
    bool getPendingVerification(bool& out) override { out = state.pending_verification; return true; }
    bool saveNextInspectionTimestamp(uint32_t timestamp) override { state.next_inspection_timestamp = timestamp; return true; }
    bool getNextInspectionTimestamp(uint32_t& out) override { out = state.next_inspection_timestamp; return true; }
    bool saveGeometry(float l, float w, int32_t c, float sp) override {
        panel_len = l; panel_wid = w; panel_cnt = c; panel_spc = sp;
        return true;
    }
    bool getGeometry(float& l, float& w, int32_t& c, float& sp) override {
        l = panel_len; w = panel_wid; c = panel_cnt; sp = panel_spc;
        return true;
    }
    bool saveCleaningQueue(const std::vector<QueuedHotspot>& q) override { saved_queue = q; return true; }
    bool getCleaningQueue(std::vector<QueuedHotspot>& out) override { out = saved_queue; return !out.empty(); }
    bool clearCleaningQueue() override { saved_queue.clear(); return true; }
    bool saveMinSolarAngle(float ang) override { min_solar = ang; return true; }
    bool saveIntervalDays(int32_t d) override { interval_d = d; return true; }
    bool savePingIntervalSeconds(int32_t s) override { ping_s = s; return true; }
    bool saveAll(const StorageState& s) override { state = s; return true; }
    bool loadAll(StorageState& s) override { s = state; return true; }
    bool clear() override { state = StorageState{}; saved_queue.clear(); return true; }

    std::vector<QueuedHotspot> saved_queue;
};

class MockCloudClient : public ICloudClient {
public:
    int pings_sent{0};
    int telemetries_ingested{0};
    int cleanings_ingested{0};
    int batches_ingested{0};
    int panel_results_submitted{0};
    int inspections_finalized{0};
    int cleaning_reports_ingested{0};
    uint32_t last_acked_config_version{0};
    CleaningReportInput last_cleaning_report{};
    std::vector<CleaningReportInput> all_cleaning_reports;
    std::vector<PanelThermalResultInput> submitted_panel_results;
    bool submit_panel_result_success{true};

    bool config_pending{false};
    bool get_config_success{true};
    std::string config_json_payload{
        "{\"config_version\":2,\"geometry\":{\"panel_length_cm\":120.0,\"panel_width_cm\":60.0,\"panel_count\":2,\"panel_spacing_cm\":3.0},\"min_solar_angle\":35.0,\"interval_days\":14,\"ping_interval_seconds\":120,\"latitude\":-23.5,\"longitude\":-46.6}"
    };

    bool init() override { return true; }
    bool claimDevice(const std::string&) override { return true; }
    bool sendPing() override { pings_sent++; return true; }
    bool isConfigurationPending() const override { return config_pending; }
    void clearConfigurationPending() override { config_pending = false; }
    bool getConfiguration(std::string& out) override {
        if (!get_config_success) return false;
        out = config_json_payload;
        return true;
    }
    bool ackConfiguration(uint32_t v) override { last_acked_config_version = v; return true; }
    bool ingestTelemetryBatch(const IngestTelemetryBatchInput&) override { batches_ingested++; return true; }
    bool submitPanelThermalResult(const std::string&, const PanelThermalResultInput& input) override {
        panel_results_submitted++;
        if (!submit_panel_result_success) return false;
        submitted_panel_results.push_back(input);
        return true;
    }
    bool finalizeInspection(const std::string&, const FinalizeInspectionInput&) override { inspections_finalized++; return true; }
    bool ingestCleaningReport(const CleaningReportInput& cr, std::string& out_id) override {
        cleaning_reports_ingested++;
        last_cleaning_report = cr;
        all_cleaning_reports.push_back(cr);
        out_id = "clean-test-uuid-" + std::to_string(cleaning_reports_ingested);
        return true;
    }
    bool ingestTelemetry(const TelemetryPayload&) override { telemetries_ingested++; return true; }
    bool ingestCleaning(const CleaningPayload&) override { cleanings_ingested++; return true; }
    bool isConnected() const override { return true; }
};

class MockTimeProvider : public ITimeProvider {
public:
    uint32_t epoch{1730000000};
    bool sync{true};

    uint32_t getEpochSeconds() const override { return epoch; }
    bool isTimeSynchronized() const override { return sync; }
};

} // namespace

void setUp(void) {}
void tearDown(void) {}

void test_safe_boot_forces_pump_off(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    spray.startPump();
    TEST_ASSERT_TRUE(spray.isPumpActive());

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_TRUE(app.init());

    // Boot guarantee: Pump MUST be turned off
    TEST_ASSERT_FALSE(spray.isPumpActive());
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_FLOAT(0.0f, motion.getXPositionCm());
}

void test_conservative_nvs_recovery_with_pending_verification(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    // Simulate pre-existing pending verification state stored in NVS before reboot
    storage.state.pending_verification = true;
    storage.state.spray_ended_timestamp = 1730000000;
    storage.state.effective_attempts = 1;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_TRUE(app.init());

    // Should transition to WAITING_VERIFICATION instead of re-spraying
    TEST_ASSERT_EQUAL(AppState::WAITING_VERIFICATION, app.getState());
    TEST_ASSERT_FALSE(spray.isPumpActive());
    TEST_ASSERT_EQUAL_UINT8(1, app.getCleaningStateMachine().getEffectiveAttempts());
    TEST_ASSERT_EQUAL_UINT32(1730000000, app.getCleaningStateMachine().getSprayEndedTimestamp());
}

void test_motion_limit_failure_enters_emergency_stop(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    motion.limit_healthy = false; // Simulate open-circuit/broken switch wiring

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_FALSE(app.init());
    TEST_ASSERT_EQUAL(AppState::ERROR_HALT, app.getState());
}

void test_manual_inspection_trigger_and_idle_flow(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_TRUE(app.init());
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());

    app.triggerManualInspection();
    app.tick(); // Transitions to SCANNING
    TEST_ASSERT_EQUAL(AppState::SCANNING, app.getState());
}

void test_batch_telemetry_and_finalize_flow(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();

    // Trigger scan: panel length 20 cm = 11 steps of 2 cm (steps 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20)
    // Batch size is 5 -> 3 batches sent!
    app.triggerManualInspection();
    app.tick(); // IDLE -> SCANNING
    app.tick(); // SCANNING completes and transitions to ANALYZING
    TEST_ASSERT_EQUAL(AppState::ANALYZING, app.getState());
    TEST_ASSERT_GREATER_THAN(0, cloud.batches_ingested);

    app.tick(); // ANALYZING calculates baseline, calls finalizeInspection, transitions to SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());
    TEST_ASSERT_EQUAL(1, cloud.inspections_finalized);
}

void test_scan_truncation_at_memory_limit(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();

    // Panel is 100 cm (which would be 51 steps of 2 cm), but SCAN_MAX_ACQUISITIONS is 35
    app.triggerManualInspection();
    app.tick(); // IDLE -> SCANNING
    app.tick(); // SCANNING loop should safely truncate at 35 acquisitions, not crash/hang!
    TEST_ASSERT_EQUAL(AppState::ANALYZING, app.getState());
    TEST_ASSERT_GREATER_THAN(0, cloud.batches_ingested);

    app.tick(); // ANALYZING -> SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());
    TEST_ASSERT_EQUAL(1, cloud.inspections_finalized);
}

void test_cleaning_refusal_without_pump(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    // Deplete water reservoir
    water.available = false;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();

    // Trigger manual cleaning
    app.triggerManualCleaning(14.0f);
    app.tick(); // IDLE -> CLEANING
    app.tick(); // CLEANING evaluates pre-spray: water missing -> REFUSED!
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());

    // Verify: pump was NEVER actuated
    TEST_ASSERT_FALSE(spray.isPumpActive());
    TEST_ASSERT_EQUAL(1, cloud.cleaning_reports_ingested);
    TEST_ASSERT_FALSE(cloud.last_cleaning_report.pump_actuated);
    TEST_ASSERT_EQUAL(0, cloud.last_cleaning_report.attempt_number);
    TEST_ASSERT_EQUAL_STRING("refused", cloud.last_cleaning_report.status.c_str());
}

void test_unsynced_clock_prevents_ping_and_solar_window(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    // Simulate clock unsynchronized (now == 0)
    time.epoch = 0;
    time.sync = false;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();

    // In IDLE, if now == 0, ping must NOT be sent in tight loops!
    for (int i = 0; i < 10; ++i) {
        app.tick();
    }
    TEST_ASSERT_EQUAL(0, cloud.pings_sent);
}

void test_ack_configuration_called_in_syncing(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();

    // Mark pending configuration
    app.setConfigUpdatePending(true);

    // Force transition to SYNCING
    app.triggerManualInspection();
    app.tick(); // SCANNING
    app.tick(); // ANALYZING
    app.tick(); // SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());

    app.tick(); // Executes handleSyncing() -> fetches config & calls ackConfiguration!
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_UINT32(2, cloud.last_acked_config_version);
}

void test_ping_in_idle_with_pending_config_syncs_and_acks(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_UINT32(1, app.getConfig().config_version);

    // Backend informs via ping that configuration is pending
    cloud.config_pending = true;
    time.epoch = 1730000301; // Advance past ping interval (300s)

    app.tick(); // IDLE: sends ping -> detects pending -> transitions to SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());
    TEST_ASSERT_EQUAL(1, cloud.pings_sent);

    app.tick(); // SYNCING: fetches config -> validates -> applies RAM & NVS -> acks -> returns IDLE
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_UINT32(2, app.getConfig().config_version);
    TEST_ASSERT_EQUAL_FLOAT(120.0f, app.getConfig().panel_length_cm);
    TEST_ASSERT_EQUAL_INT32(14, app.getConfig().interval_days);
    TEST_ASSERT_EQUAL_UINT32(2, storage.config_version);
    TEST_ASSERT_EQUAL_INT32(14, storage.interval_d);
    TEST_ASSERT_EQUAL_UINT32(2, cloud.last_acked_config_version);
    TEST_ASSERT_FALSE(cloud.isConfigurationPending());
}

void test_interval_days_change_recalculates_next_inspection_time_without_immediate_scan(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();
    TEST_ASSERT_EQUAL_INT32(7, app.getConfig().interval_days);

    uint32_t prior_schedule = time.epoch + (7 * 86400);
    app.setNextInspectionTime(prior_schedule);

    // New configuration changes interval from 7 to 14 days
    cloud.config_pending = true;
    time.epoch = 1730000305;

    app.tick(); // IDLE -> SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());

    app.tick(); // SYNCING -> applies -> returns IDLE
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_INT32(14, app.getConfig().interval_days);

    // next_inspection_time_ must be recalculated as now + (14 * 86400)
    uint32_t expected_next = 1730000305 + (14 * 86400);
    TEST_ASSERT_EQUAL_UINT32(expected_next, app.getNextInspectionTime());

    // CRITICAL REQUIREMENT: No immediate scan must be triggered!
    app.tick();
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
}

void test_ping_in_waiting_verification_marks_pending_without_cooldown_interruption(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    // Simulate recovery of a pending verification (spray ended at t=1730000000)
    storage.state.pending_verification = true;
    storage.state.spray_ended_timestamp = 1730000000;
    storage.state.effective_attempts = 1;
    storage.state.active_hotspot_x_cm = 30.0f;
    storage.state.baseline_temp_c = 25.0f;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    time.epoch = 1730000050;
    app.init();
    TEST_ASSERT_EQUAL(AppState::WAITING_VERIFICATION, app.getState());

    // At t=1730000350 (only 350s into 1800s cooldown), a ping occurs with pending config
    time.epoch = 1730000350;
    cloud.config_pending = true;

    app.tick(); // handleWaitingVerification executes ping

    // Must remain strictly in WAITING_VERIFICATION!
    TEST_ASSERT_EQUAL(AppState::WAITING_VERIFICATION, app.getState());
    // Config pending flag must be set
    TEST_ASSERT_TRUE(app.isConfigUpdatePending());
    // RAM config must NOT be touched
    TEST_ASSERT_EQUAL_UINT32(1, app.getConfig().config_version);
    // Ack must NOT be sent
    TEST_ASSERT_EQUAL_UINT32(0, cloud.last_acked_config_version);

    // Cooldown must continue undisturbed
    time.epoch = 1730001000;
    app.tick();
    TEST_ASSERT_EQUAL(AppState::WAITING_VERIFICATION, app.getState());
}

void test_return_to_idle_after_verification_triggers_pending_sync(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    // SP solar noon equinox is ~1710946800. Spray finished at 1710945000 (14:30 UTC)
    const uint32_t spray_end = 1710945000;
    storage.state.pending_verification = true;
    storage.state.spray_ended_timestamp = spray_end;
    storage.state.effective_attempts = 1;
    storage.state.active_hotspot_x_cm = 30.0f;
    storage.state.baseline_temp_c = 25.0f;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    time.epoch = spray_end + 50;
    app.init();

    // Trigger pending config during cooldown (at +350s)
    time.epoch = spray_end + 350;
    cloud.config_pending = true;
    app.tick();
    TEST_ASSERT_EQUAL(AppState::WAITING_VERIFICATION, app.getState());
    TEST_ASSERT_TRUE(app.isConfigUpdatePending());

    // Advance past 1800s cooldown into valid solar window (~15:00 UTC in SP):
    time.epoch = spray_end + 1850; // 1710946850
    app.tick(); // WAITING_VERIFICATION -> VERIFYING
    TEST_ASSERT_EQUAL(AppState::VERIFYING, app.getState());

    // Complete verification scan (mock camera returns uniform 25.0C -> RESOLVED)
    app.tick(); // VERIFYING -> completes -> transitions to SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());

    // SYNCING executes: applies the pending configuration that was deferred during cooldown!
    app.tick();
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_UINT32(2, app.getConfig().config_version);
    TEST_ASSERT_EQUAL_UINT32(2, cloud.last_acked_config_version);
    TEST_ASSERT_FALSE(app.isConfigUpdatePending());
}

void test_invalid_config_retains_previous_and_does_not_ack(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();

    // Malformed/invalid configuration: panel length negative (-100) and solar angle 150 deg (> 90)
    cloud.config_json_payload = "{\"config_version\":3,\"geometry\":{\"panel_length_cm\":-100.0,\"panel_width_cm\":50.0,\"panel_count\":1,\"panel_spacing_cm\":2.0},\"min_solar_angle\":150.0,\"interval_days\":0,\"ping_interval_seconds\":2}";
    cloud.config_pending = true;
    time.epoch = 1730000305;

    app.tick(); // IDLE -> SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());

    app.tick(); // SYNCING: detects invalid params, refuses to apply, does NOT ack, returns to IDLE
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_UINT32(1, app.getConfig().config_version); // Retained original v1
    TEST_ASSERT_EQUAL_UINT32(0, cloud.last_acked_config_version); // No ack sent!
    TEST_ASSERT_FALSE(app.getLastConfigError().empty());
}

void test_network_failure_in_get_config_retains_pending_and_returns_idle(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();

    cloud.config_pending = true;
    cloud.get_config_success = false; // Simulate HTTP network failure or timeout
    time.epoch = 1730000305;

    app.tick(); // IDLE -> SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());

    app.tick(); // SYNCING: getConfiguration fails -> retains pending flag, no ack, returns IDLE
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_UINT32(1, app.getConfig().config_version);
    TEST_ASSERT_EQUAL_UINT32(0, cloud.last_acked_config_version);
    TEST_ASSERT_TRUE(app.isConfigUpdatePending()); // Pending retained for next ping!
}

void test_first_provisioning_with_interval_days_7_schedules_inspection_without_immediate_scan(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();
    TEST_ASSERT_EQUAL_INT32(7, app.getConfig().interval_days);
    TEST_ASSERT_EQUAL_UINT32(0, app.getNextInspectionTime());

    // Provisioning with default interval_days = 7
    cloud.config_json_payload =
        "{\"config_version\":1,\"geometry\":{\"panel_length_cm\":100.0,\"panel_width_cm\":50.0,\"panel_count\":1,\"panel_spacing_cm\":2.0},\"min_solar_angle\":30.0,\"interval_days\":7,\"ping_interval_seconds\":300}";
    cloud.config_pending = true;
    time.epoch = 1730000100;

    app.tick(); // IDLE -> SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());

    app.tick(); // SYNCING -> applies -> returns IDLE
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_INT32(7, app.getConfig().interval_days);

    // Must schedule now + (7 * 86400) even though interval_days was already 7
    uint32_t expected_next = 1730000100 + (7 * 86400);
    TEST_ASSERT_EQUAL_UINT32(expected_next, app.getNextInspectionTime());
    TEST_ASSERT_EQUAL_UINT32(expected_next, storage.state.next_inspection_timestamp);

    // CRITICAL: No immediate scan must be triggered
    app.tick();
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
}

void test_interval_days_change_from_7_to_3_recalculates_schedule(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();
    app.setNextInspectionTime(1730000000 + (7 * 86400));

    // Change interval from 7 to 3 days
    cloud.config_json_payload =
        "{\"config_version\":2,\"geometry\":{\"panel_length_cm\":100.0,\"panel_width_cm\":50.0,\"panel_count\":1,\"panel_spacing_cm\":2.0},\"min_solar_angle\":30.0,\"interval_days\":3,\"ping_interval_seconds\":300}";
    cloud.config_pending = true;
    time.epoch = 1730000200;

    app.tick(); // IDLE -> SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());

    app.tick(); // SYNCING -> applies -> returns IDLE
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_INT32(3, app.getConfig().interval_days);

    uint32_t expected_next = 1730000200 + (3 * 86400);
    TEST_ASSERT_EQUAL_UINT32(expected_next, app.getNextInspectionTime());
    TEST_ASSERT_EQUAL_UINT32(expected_next, storage.state.next_inspection_timestamp);
}

void test_config_sync_with_same_interval_and_future_schedule_preserves_current_timestamp(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();

    // Established future schedule
    const uint32_t future_target = 1730000500 + (5 * 86400);
    app.setNextInspectionTime(future_target);
    storage.state.next_inspection_timestamp = future_target;

    // Config update with config_version 2, but SAME interval_days = 7
    cloud.config_json_payload =
        "{\"config_version\":2,\"geometry\":{\"panel_length_cm\":120.0,\"panel_width_cm\":60.0,\"panel_count\":1,\"panel_spacing_cm\":2.0},\"min_solar_angle\":35.0,\"interval_days\":7,\"ping_interval_seconds\":300}";
    cloud.config_pending = true;
    time.epoch = 1730000500;

    app.tick(); // IDLE -> SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());

    app.tick(); // SYNCING -> applies -> returns IDLE
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());

    // Schedule must be strictly preserved
    TEST_ASSERT_EQUAL_UINT32(future_target, app.getNextInspectionTime());
    TEST_ASSERT_EQUAL_UINT32(future_target, storage.state.next_inspection_timestamp);
}

void test_invalid_config_does_not_modify_next_inspection_time(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();

    const uint32_t existing_schedule = 1730000000 + (7 * 86400);
    app.setNextInspectionTime(existing_schedule);
    storage.state.next_inspection_timestamp = existing_schedule;

    // Invalid config (interval_days = 0, invalid angle = 150)
    cloud.config_json_payload =
        "{\"config_version\":3,\"geometry\":{\"panel_length_cm\":-100.0,\"panel_width_cm\":50.0,\"panel_count\":1,\"panel_spacing_cm\":2.0},\"min_solar_angle\":150.0,\"interval_days\":0,\"ping_interval_seconds\":2}";
    cloud.config_pending = true;
    time.epoch = 1730000305;

    app.tick(); // IDLE -> SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());

    app.tick(); // SYNCING: rejected -> returns IDLE
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());

    // Schedule must remain unchanged
    TEST_ASSERT_EQUAL_UINT32(existing_schedule, app.getNextInspectionTime());
    TEST_ASSERT_EQUAL_UINT32(existing_schedule, storage.state.next_inspection_timestamp);
}

void test_network_failure_in_get_config_does_not_modify_next_inspection_time(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();

    const uint32_t existing_schedule = 1730000000 + (7 * 86400);
    app.setNextInspectionTime(existing_schedule);
    storage.state.next_inspection_timestamp = existing_schedule;

    cloud.config_pending = true;
    cloud.get_config_success = false; // Network failure
    time.epoch = 1730000305;

    app.tick(); // IDLE -> SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());

    app.tick(); // SYNCING: fails download -> returns IDLE
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());

    // Schedule must remain unchanged
    TEST_ASSERT_EQUAL_UINT32(existing_schedule, app.getNextInspectionTime());
    TEST_ASSERT_EQUAL_UINT32(existing_schedule, storage.state.next_inspection_timestamp);
}

void test_clock_not_synchronized_does_not_erase_existing_schedule(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();

    const uint32_t future_target = 1730000000 + (7 * 86400);
    app.setNextInspectionTime(future_target);
    storage.state.next_inspection_timestamp = future_target;

    // Interval changes from 7 to 3, but clock is NOT synchronized (now == 0)
    cloud.config_json_payload =
        "{\"config_version\":2,\"geometry\":{\"panel_length_cm\":100.0,\"panel_width_cm\":50.0,\"panel_count\":1,\"panel_spacing_cm\":2.0},\"min_solar_angle\":30.0,\"interval_days\":3,\"ping_interval_seconds\":300}";
    app.setConfigUpdatePending(true);
    time.sync = false;
    time.epoch = 0; // now == 0

    app.tick(); // IDLE -> SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());

    app.tick(); // SYNCING -> applies config to RAM/NVS -> returns IDLE
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_INT32(3, app.getConfig().interval_days);

    // next_inspection_time_ must NOT be erased or zeroed out
    TEST_ASSERT_EQUAL_UINT32(future_target, app.getNextInspectionTime());
    TEST_ASSERT_EQUAL_UINT32(future_target, storage.state.next_inspection_timestamp);
}

int main(int argc, char **argv) {
    UNITY_BEGIN();
    RUN_TEST(test_safe_boot_forces_pump_off);
    RUN_TEST(test_conservative_nvs_recovery_with_pending_verification);
    RUN_TEST(test_motion_limit_failure_enters_emergency_stop);
    RUN_TEST(test_manual_inspection_trigger_and_idle_flow);
    RUN_TEST(test_batch_telemetry_and_finalize_flow);
    RUN_TEST(test_scan_truncation_at_memory_limit);
    RUN_TEST(test_cleaning_refusal_without_pump);
    RUN_TEST(test_unsynced_clock_prevents_ping_and_solar_window);
    RUN_TEST(test_ack_configuration_called_in_syncing);
    RUN_TEST(test_ping_in_idle_with_pending_config_syncs_and_acks);
    RUN_TEST(test_interval_days_change_recalculates_next_inspection_time_without_immediate_scan);
    RUN_TEST(test_first_provisioning_with_interval_days_7_schedules_inspection_without_immediate_scan);
    RUN_TEST(test_interval_days_change_from_7_to_3_recalculates_schedule);
    RUN_TEST(test_config_sync_with_same_interval_and_future_schedule_preserves_current_timestamp);
    RUN_TEST(test_invalid_config_does_not_modify_next_inspection_time);
    RUN_TEST(test_network_failure_in_get_config_does_not_modify_next_inspection_time);
    RUN_TEST(test_clock_not_synchronized_does_not_erase_existing_schedule);
    RUN_TEST(test_ping_in_waiting_verification_marks_pending_without_cooldown_interruption);
    RUN_TEST(test_return_to_idle_after_verification_triggers_pending_sync);
    RUN_TEST(test_invalid_config_retains_previous_and_does_not_ack);
    RUN_TEST(test_network_failure_in_get_config_retains_pending_and_returns_idle);
    return UNITY_END();
}
