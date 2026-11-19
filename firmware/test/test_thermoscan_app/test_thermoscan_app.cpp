#include <unity.h>
#include "app/thermoscan_app.h"
#include "hal/i_thermal_camera.h"
#include "hal/i_power_meter.h"
#include "hal/i_motion_controller.h"
#include "hal/i_spray_actuator.h"
#include "hal/i_water_sensor.h"
#include "hal/i_storage.h"
#include "hal/i_backup_storage.h"
#include "hal/i_cloud_client.h"
#include "hal/i_time_provider.h"
#include <map>

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
    bool homed{true};
    MockThermalCamera* camera{nullptr};
    std::vector<float> visited_x;

    bool init() override { return true; }
    bool home() override {
        if (!home_success) {
            homed = false;
            return false;
        }
        homed = true;
        x_pos = 0.0f;
        if (camera) camera->current_x = 0.0f;
        return true;
    }
    bool isHomed() const override { return homed; }
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
    float lat{-23.5505f};
    float lon{-46.6333f};
    float azim{0.0f};
    float tilt_deg{20.0f};
    float hs_delta{8.0f};
    bool has_location_saved{false};
    bool has_hs_delta_saved{false};

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
    bool getMinSolarAngle(float& out) override { out = min_solar; return true; }
    bool saveIntervalDays(int32_t d) override { interval_d = d; return true; }
    bool getIntervalDays(int32_t& out) override { out = interval_d; return true; }
    bool savePingIntervalSeconds(int32_t s) override { ping_s = s; return true; }
    bool getPingIntervalSeconds(int32_t& out) override { out = ping_s; return true; }
    bool saveLocationAndOrientation(float latitude, float longitude, float azimuth, float tilt) override {
        lat = latitude; lon = longitude; azim = azimuth; tilt_deg = tilt;
        has_location_saved = true;
        return true;
    }
    bool getLocationAndOrientation(float& latitude, float& longitude, float& azimuth, float& tilt) override {
        if (!has_location_saved) return false;
        latitude = lat; longitude = lon; azimuth = azim; tilt = tilt_deg;
        return true;
    }
    bool saveHotspotThresholdDeltaC(float delta_c) override {
        hs_delta = delta_c;
        has_hs_delta_saved = true;
        return true;
    }
    bool getHotspotThresholdDeltaC(float& out) override {
        if (!has_hs_delta_saved) return false;
        out = hs_delta;
        return true;
    }
    bool saveInspectionProgress(const std::string& source_event_id, uint8_t last_completed_panel, uint8_t crash_retries) override {
        state.inspection_source_event_id = source_event_id;
        state.last_completed_panel = last_completed_panel;
        state.inspection_crash_retries = crash_retries;
        return true;
    }
    bool getInspectionProgress(std::string& source_event_id, uint8_t& last_completed_panel, uint8_t& crash_retries) override {
        source_event_id = state.inspection_source_event_id;
        last_completed_panel = state.last_completed_panel;
        crash_retries = state.inspection_crash_retries;
        return !source_event_id.empty();
    }
    bool clearInspectionProgress() override {
        state.inspection_source_event_id.clear();
        state.last_completed_panel = 0;
        state.inspection_crash_retries = 0;
        return true;
    }
    bool savePendingAbort(const std::string& insp_id, const std::string& reason) override {
        pending_abort_id = insp_id;
        pending_abort_reason = reason;
        return true;
    }
    bool getPendingAbort(std::string& insp_id, std::string& reason) override {
        if (pending_abort_id.empty()) return false;
        insp_id = pending_abort_id;
        reason = pending_abort_reason;
        return true;
    }
    bool clearPendingAbort() override {
        pending_abort_id.clear();
        pending_abort_reason.clear();
        return true;
    }
    bool saveAll(const StorageState& s) override { state = s; return true; }
    bool loadAll(StorageState& s) override { s = state; return true; }
    bool clear() override {
        state = StorageState{};
        saved_queue.clear();
        pending_abort_id.clear();
        pending_abort_reason.clear();
        return true;
    }

    std::vector<QueuedHotspot> saved_queue;
    std::string pending_abort_id;
    std::string pending_abort_reason;
};

class MockCloudClient : public ICloudClient {
public:
    int pings_sent{0};
    int telemetries_ingested{0};
    int cleanings_ingested{0};
    int batches_ingested{0};
    int panel_results_submitted{0};
    int inspections_finalized{0};
    int inspections_aborted{0};
    std::string last_abort_inspection_id;
    std::string last_abort_reason;
    int cleaning_reports_ingested{0};
    uint32_t last_acked_config_version{0};
    CleaningReportInput last_cleaning_report{};
    std::vector<CleaningReportInput> all_cleaning_reports;
    std::vector<PanelThermalResultInput> submitted_panel_results;
    bool submit_panel_result_success{true};
    bool ingest_batch_success{true};
    bool abort_inspection_success{true};

    bool config_pending{false};
    bool manual_cleaning_pending{false};
    float manual_cleaning_target_x_cm{0.0f};
    bool manual_cleaning_ack_pending{false};
    int manual_cleaning_acks_sent{0};
    bool reset_pending{false};
    bool reset_ack_pending{false};
    int reset_acks_sent{0};
    int trigger_reset_on_ping_call{0};
    bool get_config_success{true};
    std::string config_json_payload{
        "{\"config_version\":2,\"geometry\":{\"panel_length_cm\":120.0,\"panel_width_cm\":60.0,\"panel_count\":2,\"panel_spacing_cm\":3.0},\"min_solar_angle\":35.0,\"interval_days\":14,\"ping_interval_seconds\":120,\"latitude\":-23.5,\"longitude\":-46.6}"
    };

    bool init() override { return true; }
    bool claimDevice(const std::string&) override { return true; }
    bool sendPing() override {
        pings_sent++;
        if (manual_cleaning_ack_pending) {
            manual_cleaning_acks_sent++;
            manual_cleaning_ack_pending = false;
        }
        if (reset_ack_pending) {
            reset_acks_sent++;
            reset_ack_pending = false;
        }
        if (trigger_reset_on_ping_call > 0 && pings_sent == trigger_reset_on_ping_call) {
            reset_pending = true;
        }
        return true;
    }
    bool isConfigurationPending() const override { return config_pending; }
    void clearConfigurationPending() override { config_pending = false; }
    bool isManualCleaningPending() const override { return manual_cleaning_pending; }
    float getManualCleaningTargetXCm() const override { return manual_cleaning_target_x_cm; }
    void clearManualCleaningPending() override { manual_cleaning_pending = false; }
    void setManualCleaningAckPending(bool pending) override { manual_cleaning_ack_pending = pending; }
    bool isResetPending() const override { return reset_pending; }
    void clearResetPending() override { reset_pending = false; }
    void setResetAckPending(bool pending) override { reset_ack_pending = pending; }
    bool getConfiguration(std::string& out) override {
        if (!get_config_success) return false;
        out = config_json_payload;
        return true;
    }
    bool ackConfiguration(uint32_t v) override { last_acked_config_version = v; return true; }
    bool ingestTelemetryBatch(const IngestTelemetryBatchInput&) override {
        batches_ingested++;
        return ingest_batch_success;
    }
    bool submitPanelThermalResult(const std::string&, const PanelThermalResultInput& input) override {
        panel_results_submitted++;
        if (!submit_panel_result_success) return false;
        submitted_panel_results.push_back(input);
        return true;
    }
    bool finalizeInspection(const std::string&, const FinalizeInspectionInput&) override { inspections_finalized++; return true; }
    bool abortInspection(const std::string& inspection_source_event_id, const std::string& failure_reason) override {
        if (!abort_inspection_success) return false;
        inspections_aborted++;
        last_abort_inspection_id = inspection_source_event_id;
        last_abort_reason = failure_reason;
        return true;
    }
    bool ingestCleaningReport(const CleaningReportInput& cr, std::string& out_id) override {
        cleaning_reports_ingested++;
        last_cleaning_report = cr;
        all_cleaning_reports.push_back(cr);
        out_id = "clean-test-uuid-" + std::to_string(cleaning_reports_ingested);
        return true;
    }
    bool ingestTelemetry(const TelemetryPayload&) override { telemetries_ingested++; return true; }
    bool ingestCleaning(const CleaningPayload&) override { cleanings_ingested++; return true; }
    bool connected{true};
    bool isConnected() const override { return connected; }

    struct RecordedState {
        std::string state;
        std::string detail;
        uint32_t occurred_at{0};
    };
    std::string last_firmware_state;
    std::string last_firmware_detail;
    std::vector<RecordedState> state_transitions;

    void setFirmwareState(const char* state, const char* detail = nullptr) override {
        last_firmware_state = state ? state : "";
        last_firmware_detail = detail ? detail : "";
    }
    void recordStateTransition(const char* state, const char* detail, uint32_t occurred_at) override {
        state_transitions.push_back(RecordedState{
            state ? state : "",
            detail ? detail : "",
            occurred_at
        });
    }
};

class MockTimeProvider : public ITimeProvider {
public:
    uint32_t epoch{1730000000};
    bool sync{true};
    uint32_t uptime_ms{0};

    uint32_t getEpochSeconds() const override { return epoch; }
    bool isTimeSynchronized() const override { return sync; }
    uint32_t getUptimeMs() const override { return (uptime_ms > 0) ? uptime_ms : (sync ? epoch * 1000U : 0U); }
};

class MockBackupStorage : public IBackupStorage {
public:
    bool init_success{true};
    bool available{true};
    int init_calls{0};
    int purge_calls{0};
    std::string active_tmp_id;
    std::vector<float> tmp_frame_x_positions;
    std::map<std::string, size_t> committed_bins;
    std::vector<std::string> removed_bins;

    bool init() override {
        init_calls++;
        available = init_success;
        return init_success;
    }

    bool isAvailable() const override { return available; }

    bool beginScanBackup(const std::string& inspection_id) override {
        if (!available || inspection_id.empty()) return false;
        active_tmp_id = inspection_id;
        tmp_frame_x_positions.clear();
        return true;
    }

    bool appendRawFrame(float scan_x_cm, const float* temps_768) override {
        if (!available || active_tmp_id.empty() || temps_768 == nullptr) return false;
        tmp_frame_x_positions.push_back(scan_x_cm);
        return true;
    }

    bool commitScanBackup(const std::string& inspection_id) override {
        if (!available || active_tmp_id != inspection_id) return false;
        committed_bins[inspection_id] = tmp_frame_x_positions.size();
        active_tmp_id.clear();
        return true;
    }

    bool hasScanBackup(const std::string& inspection_id) override {
        if (!available || inspection_id.empty()) return false;
        return committed_bins.count(inspection_id) > 0;
    }

    bool removeScanBackup(const std::string& inspection_id) override {
        if (!available || inspection_id.empty()) return false;
        committed_bins.erase(inspection_id);
        removed_bins.push_back(inspection_id);
        return true;
    }

    bool purgeTempFiles() override {
        if (!available) return false;
        purge_calls++;
        active_tmp_id.clear();
        tmp_frame_x_positions.clear();
        return true;
    }
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

    motion.camera = &cam;
    storage.panel_len = 20.0f;
    cam.hotspots.push_back({10.0f, 5});

    // Deplete water reservoir
    water.available = false;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();

    // 1. Automatic cleaning refusal after confirmed scan hotspot still reports refused to backend
    app.triggerManualInspection();
    app.tick(); // IDLE -> SCANNING
    app.tick(); // SCANNING -> ANALYZING
    app.tick(); // ANALYZING -> CLEANING
    TEST_ASSERT_EQUAL(AppState::CLEANING, app.getState());
    app.tick(); // CLEANING evaluates pre-spray: water missing -> REFUSED -> SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());

    // Verify: pump was NEVER actuated and refusal was reported
    TEST_ASSERT_FALSE(spray.isPumpActive());
    TEST_ASSERT_EQUAL(1, cloud.cleaning_reports_ingested);
    TEST_ASSERT_FALSE(cloud.last_cleaning_report.pump_actuated);
    TEST_ASSERT_EQUAL(0, cloud.last_cleaning_report.attempt_number);
    TEST_ASSERT_EQUAL_STRING("refused", cloud.last_cleaning_report.status.c_str());

    // 2. Manual cleaning refusal also never actuates pump and returns safely to IDLE
    app.tick(); // SYNCING -> IDLE
    app.triggerManualCleaning(14.0f);
    app.tick(); // IDLE -> CLEANING
    app.tick(); // CLEANING refuses water-depleted manual wash -> IDLE
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_FALSE(spray.isPumpActive());
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
    const int pings_after_init = cloud.pings_sent;

    // In IDLE, if now == 0, ping must NOT be sent in tight loops!
    for (int i = 0; i < 10; ++i) {
        app.tick();
    }
    TEST_ASSERT_EQUAL(pings_after_init, cloud.pings_sent);
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
    const int pings_before_tick = cloud.pings_sent;

    app.tick(); // IDLE: sends ping -> detects pending -> transitions to SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());
    TEST_ASSERT_EQUAL(pings_before_tick + 2, cloud.pings_sent);

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

void test_inspection_crash_recovery_resumes_from_panel_2(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    motion.camera = &cam;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    // Multi-panel geometry: 2 panels, each 20 cm, spacing 2 cm
    // Panel 1: [0.0, 20.0], Panel 2: [22.0, 42.0]
    storage.panel_cnt = 2;
    storage.panel_len = 20.0f;
    storage.panel_spc = 2.0f;

    // Simulate crash after completing panel 1
    storage.state.inspection_source_event_id = "test-insp-uuid-crash-1";
    storage.state.last_completed_panel = 1;
    storage.state.inspection_crash_retries = 0;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_TRUE(app.init());

    // Bootinit detected crash recovery, incremented retries to 1, and set state to SCANNING
    TEST_ASSERT_EQUAL(AppState::SCANNING, app.getState());
    TEST_ASSERT_EQUAL_UINT8(1, app.getInspectionCrashRetries());
    TEST_ASSERT_EQUAL_UINT8(1, app.getLastCompletedPanel());
    TEST_ASSERT_EQUAL_STRING("test-insp-uuid-crash-1", app.getInspectionSourceEventId().c_str());

    // Verify storage has crash retry count updated
    TEST_ASSERT_EQUAL_UINT8(1, storage.state.inspection_crash_retries);

    // Tick SCANNING: should resume from Panel 2 (start X = 22.0 cm)
    app.tick(); // SCANNING executes for panel 2, then transitions to ANALYZING
    TEST_ASSERT_EQUAL(AppState::ANALYZING, app.getState());

    // Verify motion moved to Panel 2 start (22.0 cm) and not panel 1 (0.0 cm)
    TEST_ASSERT_FALSE(motion.visited_x.empty());
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 22.0f, motion.visited_x[0]);

    // Panel 2 submitted
    TEST_ASSERT_EQUAL(1, cloud.panel_results_submitted);
    TEST_ASSERT_EQUAL_UINT8(2, cloud.submitted_panel_results[0].panel_index);

    // Tick ANALYZING: finalizes inspection, clears inspection progress, transitions to SYNCING
    app.tick();
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());
    TEST_ASSERT_EQUAL(1, cloud.inspections_finalized);
    TEST_ASSERT_TRUE(app.getInspectionSourceEventId().empty());
    TEST_ASSERT_EQUAL_UINT8(0, app.getLastCompletedPanel());
    TEST_ASSERT_EQUAL_UINT8(0, app.getInspectionCrashRetries());
    TEST_ASSERT_TRUE(storage.state.inspection_source_event_id.empty());
    TEST_ASSERT_EQUAL_UINT8(0, storage.state.last_completed_panel);
    TEST_ASSERT_EQUAL_UINT8(0, storage.state.inspection_crash_retries);
}

void test_inspection_crash_retries_exhausted_aborts_inspection(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    // Simulate crash where retries already reached MAX_INSPECTION_CRASH_RETRIES (1)
    storage.state.inspection_source_event_id = "test-insp-uuid-exhausted";
    storage.state.last_completed_panel = 1;
    storage.state.inspection_crash_retries = 1;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_TRUE(app.init());

    // Bootinit detects retries exhausted, calls abortInspection, clears state, enters IDLE
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL(1, cloud.inspections_aborted);
    TEST_ASSERT_EQUAL_STRING("test-insp-uuid-exhausted", cloud.last_abort_inspection_id.c_str());
    TEST_ASSERT_EQUAL_STRING("crash_recovery_exhausted", cloud.last_abort_reason.c_str());

    // App state cleaned
    TEST_ASSERT_TRUE(app.getInspectionSourceEventId().empty());
    TEST_ASSERT_EQUAL_UINT8(0, app.getLastCompletedPanel());
    TEST_ASSERT_EQUAL_UINT8(0, app.getInspectionCrashRetries());

    // Storage progress cleared
    TEST_ASSERT_TRUE(storage.state.inspection_source_event_id.empty());
    TEST_ASSERT_EQUAL_UINT8(0, storage.state.last_completed_panel);
    TEST_ASSERT_EQUAL_UINT8(0, storage.state.inspection_crash_retries);
}

void test_inspection_abort_on_panel_result_rejected(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    storage.panel_cnt = 1;
    storage.panel_len = 20.0f;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    app.init();
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());

    // Configure cloud to reject panel thermal result
    cloud.submit_panel_result_success = false;

    app.triggerManualInspection();
    app.tick(); // IDLE -> SCANNING
    TEST_ASSERT_EQUAL(AppState::SCANNING, app.getState());

    app.tick(); // SCANNING completes, panel result rejected after retries -> ANALYZING
    TEST_ASSERT_EQUAL(AppState::ANALYZING, app.getState());
    TEST_ASSERT_FALSE(app.areAllPanelsAccepted());

    std::string active_insp_id = app.getInspectionSourceEventId();
    TEST_ASSERT_FALSE(active_insp_id.empty());

    // Tick ANALYZING: detects !all_panels_accepted_, calls abortInspection, resets to 0 cm, transitions to SYNCING
    app.tick();
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());
    TEST_ASSERT_EQUAL(1, cloud.inspections_aborted);
    TEST_ASSERT_EQUAL_STRING(active_insp_id.c_str(), cloud.last_abort_inspection_id.c_str());
    TEST_ASSERT_EQUAL_STRING("panel_result_rejected", cloud.last_abort_reason.c_str());
    TEST_ASSERT_EQUAL(0, cloud.inspections_finalized);

    // Carriage returned to 0 cm
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 0.0f, motion.x_pos);

    // Inspection state cleared
    TEST_ASSERT_TRUE(app.getInspectionSourceEventId().empty());
    TEST_ASSERT_EQUAL_UINT8(0, app.getLastCompletedPanel());
    TEST_ASSERT_EQUAL_UINT8(0, app.getInspectionCrashRetries());
    TEST_ASSERT_TRUE(storage.state.inspection_source_event_id.empty());
}

void test_manual_cleaning_from_device_status_and_ack(void) {
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

    // Simulate backend returning manual_cleaning_pending = true with target X = 42.5 cm
    cloud.manual_cleaning_pending = true;
    cloud.manual_cleaning_target_x_cm = 42.5f;

    app.tick(); // IDLE detects pending manual cleaning -> CLEANING
    TEST_ASSERT_EQUAL(AppState::CLEANING, app.getState());
    TEST_ASSERT_FALSE(cloud.isManualCleaningPending());

    app.tick(); // CLEANING moves to 42.5 cm, sprays, returns home, sends ping with ack -> IDLE (simplified manual demo mode)
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());

    // Verify carriage visited 42.5 cm and then returned to 0.0 cm
    TEST_ASSERT_EQUAL(2, motion.visited_x.size());
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 42.5f, motion.visited_x[0]);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 0.0f, motion.visited_x[1]);

    // Simplified manual cleaning does NOT post a fake anomaly to /cleanings or enter 30-min verification
    TEST_ASSERT_EQUAL(0, cloud.cleaning_reports_ingested);

    // Verify manual_cleaning_ack was sent via ping
    TEST_ASSERT_EQUAL(1, cloud.manual_cleaning_acks_sent);
}

void test_sd_backup_normal_scan_commit_and_sync_cleanup(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;
    MockBackupStorage backup;

    storage.panel_cnt = 1;
    storage.panel_len = 10.0f;
    cloud.config_json_payload =
        "{\"config_version\":2,\"geometry\":{\"panel_length_cm\":10.0,\"panel_width_cm\":50.0,"
        "\"panel_count\":1,\"panel_spacing_cm\":2.0},\"min_solar_angle\":30.0,"
        "\"interval_days\":7,\"ping_interval_seconds\":5}";

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time, &backup);
    TEST_ASSERT_TRUE(app.init());
    TEST_ASSERT_EQUAL(1, backup.init_calls);
    TEST_ASSERT_EQUAL(1, backup.purge_calls);
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());

    app.triggerManualInspection();
    app.tick(); // IDLE -> SCANNING
    TEST_ASSERT_EQUAL(AppState::SCANNING, app.getState());

    app.tick(); // SCANNING -> ANALYZING (appends frames to .tmp, commits .bin)
    TEST_ASSERT_EQUAL(AppState::ANALYZING, app.getState());
    std::string insp_id = app.getInspectionSourceEventId();
    TEST_ASSERT_FALSE(insp_id.empty());
    TEST_ASSERT_TRUE(backup.active_tmp_id.empty());
    TEST_ASSERT_TRUE(backup.hasScanBackup(insp_id));
    TEST_ASSERT_GREATER_THAN(0, static_cast<int>(backup.committed_bins[insp_id]));

    // Trigger config sync on SYNCING so HTTP 200 ackConfiguration runs before cleanup
    app.setConfigUpdatePending(true);
    app.tick(); // ANALYZING -> SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());
    TEST_ASSERT_TRUE(backup.hasScanBackup(insp_id));

    app.tick(); // SYNCING -> IDLE (HTTP 200 ack -> removes .bin)
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_FALSE(backup.hasScanBackup(insp_id));
    TEST_ASSERT_EQUAL(1, static_cast<int>(backup.removed_bins.size()));
    TEST_ASSERT_EQUAL_STRING(insp_id.c_str(), backup.removed_bins[0].c_str());
}

void test_sd_backup_fallback_when_unavailable(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;
    MockBackupStorage backup;

    backup.init_success = false;
    storage.panel_cnt = 1;
    storage.panel_len = 10.0f;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time, &backup);
    TEST_ASSERT_TRUE(app.init());
    TEST_ASSERT_FALSE(backup.isAvailable());
    TEST_ASSERT_EQUAL(0, backup.purge_calls);
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());

    app.triggerManualInspection();
    app.tick(); // IDLE -> SCANNING
    app.tick(); // SCANNING -> ANALYZING
    app.tick(); // ANALYZING -> SYNCING
    app.tick(); // SYNCING -> IDLE

    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL(1, cloud.inspections_finalized);
    TEST_ASSERT_TRUE(backup.committed_bins.empty());
    TEST_ASSERT_TRUE(backup.removed_bins.empty());
}

void test_sd_backup_boot_recovery_analyzing_and_syncing(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;
    MockBackupStorage backup;

    // Case 1: Pending ANALYZING with .bin present and retries=0 -> resumes SCANNING to rebuild hotspots
    storage.state.operation_status = "ANALYZING";
    storage.state.inspection_source_event_id = "insp-recover-analyzing";
    storage.state.inspection_crash_retries = 0;
    backup.committed_bins["insp-recover-analyzing"] = 4;

    ThermoscanApp app1(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time, &backup);
    TEST_ASSERT_TRUE(app1.init());
    TEST_ASSERT_EQUAL(1, backup.purge_calls);
    TEST_ASSERT_EQUAL(AppState::SCANNING, app1.getState());
    TEST_ASSERT_EQUAL_UINT8(1, app1.getInspectionCrashRetries());

    app1.tick(); // SCANNING -> ANALYZING
    TEST_ASSERT_EQUAL(AppState::ANALYZING, app1.getState());
    app1.tick(); // ANALYZING -> SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app1.getState());
    app1.tick(); // SYNCING -> IDLE (cleans up .bin)
    TEST_ASSERT_EQUAL(AppState::IDLE, app1.getState());
    TEST_ASSERT_FALSE(backup.hasScanBackup("insp-recover-analyzing"));

    // Case 2: Pending SYNCING with .bin present and retries=1 (< 2) -> recovers to SYNCING
    storage.state.operation_status = "SYNCING";
    storage.state.inspection_source_event_id = "insp-recover-syncing";
    storage.state.inspection_crash_retries = 1;
    backup.committed_bins["insp-recover-syncing"] = 4;

    ThermoscanApp app2(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time, &backup);
    TEST_ASSERT_TRUE(app2.init());
    TEST_ASSERT_EQUAL(AppState::SYNCING, app2.getState());
    TEST_ASSERT_EQUAL_UINT8(2, app2.getInspectionCrashRetries());

    // Case 3: Pending ANALYZING without .bin -> resets to IDLE
    storage.state.operation_status = "ANALYZING";
    storage.state.inspection_source_event_id = "insp-missing-bin";
    storage.state.inspection_crash_retries = 0;

    ThermoscanApp app3(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time, &backup);
    TEST_ASSERT_TRUE(app3.init());
    TEST_ASSERT_EQUAL(AppState::IDLE, app3.getState());
    TEST_ASSERT_TRUE(app3.getInspectionSourceEventId().empty());
}

void test_sd_backup_boot_recovery_crash_loop_guard(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;
    MockBackupStorage backup;

    storage.state.operation_status = "SYNCING";
    storage.state.inspection_source_event_id = "insp-crash-loop";
    storage.state.inspection_crash_retries = 2;
    backup.committed_bins["insp-crash-loop"] = 4;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time, &backup);
    TEST_ASSERT_TRUE(app.init());

    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL(1, cloud.inspections_aborted);
    TEST_ASSERT_EQUAL_STRING("insp-crash-loop", cloud.last_abort_inspection_id.c_str());
    TEST_ASSERT_EQUAL_STRING("crash_recovery_exhausted", cloud.last_abort_reason.c_str());
    TEST_ASSERT_FALSE(backup.hasScanBackup("insp-crash-loop"));
    TEST_ASSERT_TRUE(app.getInspectionSourceEventId().empty());
    TEST_ASSERT_EQUAL_UINT8(0, app.getInspectionCrashRetries());
}

void test_state_transition_records_detail_and_skips_ping_when_offline(void) {
    // 1. Offline boot: transitions are recorded without triggering sendPing()
    {
        MockThermalCamera cam;
        MockPowerMeter power;
        MockMotionController motion;
        MockSprayActuator spray;
        MockWaterSensor water;
        MockStorage storage;
        MockCloudClient cloud;
        MockTimeProvider time;
        cloud.connected = false;

        ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
        TEST_ASSERT_TRUE(app.init());
        TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
        TEST_ASSERT_EQUAL(0, cloud.pings_sent);
        TEST_ASSERT_EQUAL(2, static_cast<int>(cloud.state_transitions.size()));
        TEST_ASSERT_EQUAL_STRING("BOOT_INIT", cloud.state_transitions[0].state.c_str());
        TEST_ASSERT_EQUAL_STRING("IDLE", cloud.state_transitions[1].state.c_str());
    }

    // 2. Limits check failure -> ERROR_HALT with "limits_check_failed"
    {
        MockThermalCamera cam;
        MockPowerMeter power;
        MockMotionController motion;
        MockSprayActuator spray;
        MockWaterSensor water;
        MockStorage storage;
        MockCloudClient cloud;
        MockTimeProvider time;
        motion.limit_healthy = false;

        ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
        TEST_ASSERT_FALSE(app.init());
        TEST_ASSERT_EQUAL(AppState::ERROR_HALT, app.getState());
        TEST_ASSERT_EQUAL_STRING("ERROR_HALT", cloud.last_firmware_state.c_str());
        TEST_ASSERT_EQUAL_STRING("limits_check_failed", cloud.last_firmware_detail.c_str());
        TEST_ASSERT_EQUAL(2, cloud.pings_sent); // BOOT_INIT + ERROR_HALT
    }

    // 3. Homing failure -> ERROR_HALT with "homing_failed"
    {
        MockThermalCamera cam;
        MockPowerMeter power;
        MockMotionController motion;
        MockSprayActuator spray;
        MockWaterSensor water;
        MockStorage storage;
        MockCloudClient cloud;
        MockTimeProvider time;
        motion.home_success = false;

        ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
        TEST_ASSERT_FALSE(app.init());
        TEST_ASSERT_EQUAL(AppState::ERROR_HALT, app.getState());
        TEST_ASSERT_EQUAL_STRING("ERROR_HALT", cloud.last_firmware_state.c_str());
        TEST_ASSERT_EQUAL_STRING("homing_failed", cloud.last_firmware_detail.c_str());
    }
}

void test_waiting_verification_detail_transitions_cooldown_to_solar_window_closed(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    // 1730000000 is ~2024-10-27 03:33:20 UTC (nighttime in Sao Paulo -46.6333 -> solar window closed)
    storage.state.pending_verification = true;
    storage.state.spray_ended_timestamp = 1730000000;
    storage.state.effective_attempts = 1;
    time.epoch = 1730000100; // Only 100s elapsed (< 1800s cooldown)

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_TRUE(app.init());
    TEST_ASSERT_EQUAL(AppState::WAITING_VERIFICATION, app.getState());
    TEST_ASSERT_EQUAL_STRING("cooldown_wait", cloud.last_firmware_detail.c_str());

    // Advance past 1800s cooldown while still in nighttime (solar window closed)
    time.epoch = 1730001900;
    app.tick();
    TEST_ASSERT_EQUAL(AppState::WAITING_VERIFICATION, app.getState());
    TEST_ASSERT_EQUAL_STRING("solar_window_closed", cloud.last_firmware_detail.c_str());
}

void test_execute_full_reset_from_scanning_preserves_nvs_credentials(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    storage.state.module_id = "mod-reset-1";
    storage.saveConfigVersion(42);
    time.epoch = 1730721600;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_TRUE(app.init());
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());

    // Trigger manual inspection -> IDLE -> SCANNING
    app.triggerManualInspection();
    app.tick();
    TEST_ASSERT_EQUAL(AppState::SCANNING, app.getState());

    // Trigger reset_pending on the ping right after the first batch is sent in SCANNING
    cloud.trigger_reset_on_ping_call = cloud.pings_sent + 1;
    app.tick();

    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_STRING("IDLE", cloud.last_firmware_state.c_str());
    TEST_ASSERT_EQUAL_STRING("user_reset", cloud.last_firmware_detail.c_str());
    TEST_ASSERT_FALSE(cloud.isResetPending());
    TEST_ASSERT_TRUE(cloud.reset_acks_sent >= 1);
    TEST_ASSERT_EQUAL_FLOAT(0.0f, motion.getXPositionCm());
    TEST_ASSERT_TRUE(app.getCleaningQueue().empty());
    TEST_ASSERT_TRUE(app.getAllConfirmedHotspots().empty());
    TEST_ASSERT_TRUE(app.getInspectionSourceEventId().empty());
    TEST_ASSERT_EQUAL_UINT8(0, app.getLastCompletedPanel());
    TEST_ASSERT_EQUAL_UINT8(0, app.getInspectionCrashRetries());

    // Operational NVS cleared, credentials & config_version preserved
    TEST_ASSERT_EQUAL_STRING("mod-reset-1", storage.state.module_id.c_str());
    TEST_ASSERT_EQUAL_UINT32(42, storage.state.config_version);
    TEST_ASSERT_EQUAL_STRING("IDLE", storage.state.operation_status.c_str());
    TEST_ASSERT_FALSE(storage.state.pending_verification);
    TEST_ASSERT_TRUE(storage.saved_queue.empty());
}

void test_execute_full_reset_from_cleaning_halts_pump_and_clears_queue(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    storage.state.module_id = "mod-reset-2";
    storage.saveConfigVersion(7);
    time.epoch = 1730721600;
    QueuedHotspot qh;
    qh.panel_index = 1;
    qh.target_x_cm = 35.0f;
    qh.anomaly_event_id = "anom-reset-1";
    qh.verification_status = "pending";
    storage.saved_queue.push_back(qh);

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_TRUE(app.init());
    TEST_ASSERT_EQUAL(AppState::CLEANING, app.getState());
    TEST_ASSERT_EQUAL_UINT(1, app.getCleaningQueue().size());

    // Next ping in handleCleaning() returns reset_pending=true before spraying
    cloud.trigger_reset_on_ping_call = cloud.pings_sent + 1;
    app.tick();

    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_STRING("user_reset", cloud.last_firmware_detail.c_str());
    TEST_ASSERT_FALSE(spray.isPumpActive());
    TEST_ASSERT_TRUE(app.getCleaningQueue().empty());
    TEST_ASSERT_TRUE(storage.saved_queue.empty());
    TEST_ASSERT_EQUAL_FLOAT(0.0f, motion.getXPositionCm());
    TEST_ASSERT_TRUE(cloud.reset_acks_sent >= 1);
    TEST_ASSERT_EQUAL_STRING("mod-reset-2", storage.state.module_id.c_str());
    TEST_ASSERT_EQUAL_UINT32(7, storage.state.config_version);
}

void test_execute_full_reset_from_waiting_verification(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    storage.state.module_id = "mod-reset-3";
    storage.saveConfigVersion(9);
    storage.state.pending_verification = true;
    storage.state.spray_ended_timestamp = 1730000000;
    storage.state.effective_attempts = 1;
    QueuedHotspot qh;
    qh.panel_index = 1;
    qh.target_x_cm = 40.0f;
    qh.anomaly_event_id = "anom-123";
    qh.verification_status = "cleaned";
    storage.saved_queue.push_back(qh);

    time.epoch = 1730000100; // In cooldown wait

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_TRUE(app.init());
    TEST_ASSERT_EQUAL(AppState::WAITING_VERIFICATION, app.getState());

    // Advance past ping interval and return reset_pending=true
    time.epoch = 1730000200;
    cloud.trigger_reset_on_ping_call = cloud.pings_sent + 1;
    app.tick();

    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_STRING("user_reset", cloud.last_firmware_detail.c_str());
    TEST_ASSERT_TRUE(app.getCleaningQueue().empty());
    TEST_ASSERT_TRUE(storage.saved_queue.empty());
    TEST_ASSERT_FALSE(storage.state.pending_verification);
    TEST_ASSERT_EQUAL_UINT8(0, app.getCleaningStateMachine().getEffectiveAttempts());
    TEST_ASSERT_TRUE(cloud.reset_acks_sent >= 1);
    TEST_ASSERT_EQUAL_STRING("mod-reset-3", storage.state.module_id.c_str());
    TEST_ASSERT_EQUAL_UINT32(9, storage.state.config_version);
}

void test_execute_full_reset_from_error_halt_recovers_to_idle(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    storage.state.module_id = "mod-reset-4";
    storage.saveConfigVersion(11);
    motion.home_success = false;
    time.epoch = 1730721600;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_FALSE(app.init());
    TEST_ASSERT_EQUAL(AppState::ERROR_HALT, app.getState());
    TEST_ASSERT_FALSE(motion.isHomed());

    // Advance 5s in ERROR_HALT so handleErrorHalt() sends periodic ping and sees reset_pending=true
    time.epoch = 1730721606;
    cloud.trigger_reset_on_ping_call = cloud.pings_sent + 1;
    app.tick();

    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL_STRING("IDLE", cloud.last_firmware_state.c_str());
    TEST_ASSERT_EQUAL_STRING("user_reset", cloud.last_firmware_detail.c_str());
    TEST_ASSERT_TRUE(cloud.reset_acks_sent >= 1);
    TEST_ASSERT_EQUAL_STRING("mod-reset-4", storage.state.module_id.c_str());
    TEST_ASSERT_EQUAL_UINT32(11, storage.state.config_version);
}

void test_uptime_ping_works_without_ntp_sync(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    // Simulate local router without internet: NTP is not synced (epoch == 0), but uptime_ms advances
    time.epoch = 0;
    time.sync = false;
    time.uptime_ms = 1000;
    storage.ping_s = 5;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_TRUE(app.init());
    const int pings_after_init = cloud.pings_sent;

    // First tick with uptime_ms > 0 sends ping; tight ticks at same uptime_ms must not spam
    app.tick();
    TEST_ASSERT_EQUAL(pings_after_init + 1, cloud.pings_sent);
    for (int i = 0; i < 5; ++i) {
        app.tick();
    }
    TEST_ASSERT_EQUAL(pings_after_init + 1, cloud.pings_sent);

    // Advancing uptime by 5000 ms triggers next ping even without NTP
    time.uptime_ms += 5000;
    app.tick();
    TEST_ASSERT_EQUAL(pings_after_init + 2, cloud.pings_sent);
}

void test_nvs_restores_full_config_including_solar_interval_location_and_threshold(void) {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    cloud.config_json_payload =
        "{\"config_version\":9,\"geometry\":{\"panel_length_cm\":150.0,\"panel_width_cm\":80.0,\"panel_count\":3,\"panel_spacing_cm\":4.0},"
        "\"min_solar_angle\":22.5,\"interval_days\":10,\"ping_interval_seconds\":15,"
        "\"latitude\":-25.42,\"longitude\":-49.27,\"azimuth_deg\":15.0,\"tilt_deg\":24.0,\"hotspot_threshold_delta_c\":12.5}";

    {
        ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
        TEST_ASSERT_TRUE(app.init());
        app.setConfigUpdatePending(true);
        app.tick(); // IDLE -> SYNCING
        app.tick(); // SYNCING applies and persists to NVS
        TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    }

    // Simulate reboot with fresh ThermoscanApp instance reading from same MockStorage
    ThermoscanApp rebooted(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_TRUE(rebooted.init());
    TEST_ASSERT_EQUAL_UINT32(9, rebooted.getConfig().config_version);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 22.5f, rebooted.getConfig().min_solar_angle);
    TEST_ASSERT_EQUAL_INT32(10, rebooted.getConfig().interval_days);
    TEST_ASSERT_EQUAL_INT32(15, rebooted.getConfig().ping_interval_seconds);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, -25.42f, rebooted.getConfig().latitude);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, -49.27f, rebooted.getConfig().longitude);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 15.0f, rebooted.getConfig().azimuth);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 24.0f, rebooted.getConfig().tilt);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 12.5f, rebooted.getConfig().hotspot_threshold_delta_c);
}

void test_scan_flushes_residual_batch_when_last_frame_fails(void) {
    class FailOnLastCamera : public MockThermalCamera {
    public:
        bool captureFrame(ThermalFrame& out) override {
            // Panel length 8 cm -> steps at 0, 2, 4, 6, 8 (batch chunk is 3).
            // Step x=8.0 fails all retries, leaving 1 residual frame (x=6.0) in current_batch_.
            if (current_x >= 7.9f) {
                out.valid = false;
                return false;
            }
            return MockThermalCamera::captureFrame(out);
        }
    };

    FailOnLastCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    motion.camera = &cam;
    storage.panel_cnt = 1;
    storage.panel_len = 8.0f;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_TRUE(app.init());

    app.triggerManualInspection();
    app.tick(); // IDLE -> SCANNING
    app.tick(); // SCANNING sends batch 1 (0,2,4) + residual batch 2 (6) even though x=8 failed
    TEST_ASSERT_EQUAL(AppState::ANALYZING, app.getState());
    TEST_ASSERT_EQUAL(2, cloud.batches_ingested);
}

void test_telemetry_failure_aborts_and_persists_pending_abort_until_reconnect() {
    MockThermalCamera cam;
    MockPowerMeter power;
    MockMotionController motion;
    MockSprayActuator spray;
    MockWaterSensor water;
    MockStorage storage;
    MockCloudClient cloud;
    MockTimeProvider time;

    motion.camera = &cam;
    storage.panel_cnt = 1;
    storage.panel_len = 8.0f;

    // Telemetry upload fails and abort call also fails initially (simulating offline drop mid-scan)
    cloud.ingest_batch_success = false;
    cloud.abort_inspection_success = false;
    cloud.connected = true;

    ThermoscanApp app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_TRUE(app.init());

    app.triggerManualInspection();
    app.tick(); // IDLE -> SCANNING
    app.tick(); // SCANNING -> ANALYZING (all_panels_accepted_ = false)
    TEST_ASSERT_EQUAL(AppState::ANALYZING, app.getState());

    cloud.state_transitions.clear();
    app.tick(); // ANALYZING sees all_panels_accepted_ == false, tries abortInspection -> fails -> persists to NVS -> SYNCING
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());
    app.tick(); // SYNCING -> IDLE
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
    TEST_ASSERT_EQUAL(0, cloud.inspections_aborted);
    TEST_ASSERT_EQUAL(0, cloud.inspections_finalized);
    TEST_ASSERT_FALSE(storage.pending_abort_id.empty());
    TEST_ASSERT_EQUAL_STRING("telemetry_upload_failed", storage.pending_abort_reason.c_str());

    bool found_scan_aborted = false;
    for (const auto& t : cloud.state_transitions) {
        if (t.state == "SCAN_ABORTED") {
            found_scan_aborted = true;
            TEST_ASSERT_EQUAL_STRING("telemetry_upload_failed", t.detail.c_str());
        }
    }
    TEST_ASSERT_TRUE(found_scan_aborted);

    // Simulate reboot restoring pending abort from NVS while still offline
    cloud.connected = false;
    ThermoscanApp rebooted_app(&cam, &power, &motion, &spray, &water, &storage, &cloud, &time);
    TEST_ASSERT_TRUE(rebooted_app.init());
    rebooted_app.tick(); // IDLE while offline: pending abort stays in NVS
    TEST_ASSERT_EQUAL(0, cloud.inspections_aborted);
    TEST_ASSERT_FALSE(storage.pending_abort_id.empty());

    // Network reconnects and abort succeeds
    cloud.connected = true;
    cloud.abort_inspection_success = true;
    cloud.state_transitions.clear();
    rebooted_app.tick(); // IDLE flushes pending abort
    TEST_ASSERT_EQUAL(1, cloud.inspections_aborted);
    TEST_ASSERT_EQUAL_STRING("telemetry_upload_failed", cloud.last_abort_reason.c_str());
    TEST_ASSERT_TRUE(storage.pending_abort_id.empty());

    bool found_abort_synced = false;
    for (const auto& t : cloud.state_transitions) {
        if (t.state == "ABORT_SYNCED") {
            found_abort_synced = true;
        }
    }
    TEST_ASSERT_TRUE(found_abort_synced);
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
    RUN_TEST(test_inspection_crash_recovery_resumes_from_panel_2);
    RUN_TEST(test_inspection_crash_retries_exhausted_aborts_inspection);
    RUN_TEST(test_inspection_abort_on_panel_result_rejected);
    RUN_TEST(test_manual_cleaning_from_device_status_and_ack);
    RUN_TEST(test_sd_backup_normal_scan_commit_and_sync_cleanup);
    RUN_TEST(test_sd_backup_fallback_when_unavailable);
    RUN_TEST(test_sd_backup_boot_recovery_analyzing_and_syncing);
    RUN_TEST(test_sd_backup_boot_recovery_crash_loop_guard);
    RUN_TEST(test_state_transition_records_detail_and_skips_ping_when_offline);
    RUN_TEST(test_waiting_verification_detail_transitions_cooldown_to_solar_window_closed);
    RUN_TEST(test_execute_full_reset_from_scanning_preserves_nvs_credentials);
    RUN_TEST(test_execute_full_reset_from_cleaning_halts_pump_and_clears_queue);
    RUN_TEST(test_execute_full_reset_from_waiting_verification);
    RUN_TEST(test_execute_full_reset_from_error_halt_recovers_to_idle);
    RUN_TEST(test_uptime_ping_works_without_ntp_sync);
    RUN_TEST(test_nvs_restores_full_config_including_solar_interval_location_and_threshold);
    RUN_TEST(test_scan_flushes_residual_batch_when_last_frame_fails);
    RUN_TEST(test_telemetry_failure_aborts_and_persists_pending_abort_until_reconnect);
    return UNITY_END();
}
