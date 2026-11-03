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

    bool init() override { return true; }
    bool captureFrame(ThermalFrame& out) override {
        out.valid = capture_valid;
        for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
            out.pixels[i] = pixel_fill;
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

    bool init() override { return true; }
    bool home() override {
        if (!home_success) return false;
        x_pos = 0.0f;
        return true;
    }
    bool moveToXCm(float target_x_cm) override {
        x_pos = target_x_cm;
        return true;
    }
    float getXPositionCm() const override { return x_pos; }
    bool checkLimitsIntegrity() override { return limit_healthy; }
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

    bool init() override { return true; }
    bool saveModuleId(const std::string& moduleId) override { state.module_id = moduleId; return true; }
    bool getModuleId(std::string& out) override { out = state.module_id; return true; }
    bool saveConfigVersion(uint32_t version) override { state.config_version = version; return true; }
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
    bool saveAll(const StorageState& s) override { state = s; return true; }
    bool loadAll(StorageState& s) override { s = state; return true; }
    bool clear() override { state = StorageState{}; return true; }
};

class MockCloudClient : public ICloudClient {
public:
    int pings_sent{0};
    int telemetries_ingested{0};
    int cleanings_ingested{0};

    bool init() override { return true; }
    bool claimDevice(const std::string&) override { return true; }
    bool sendPing() override { pings_sent++; return true; }
    bool getConfiguration(std::string& out) override { out = "{}"; return true; }
    bool ackConfiguration(uint32_t) override { return true; }
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

int main(int argc, char **argv) {
    UNITY_BEGIN();
    RUN_TEST(test_safe_boot_forces_pump_off);
    RUN_TEST(test_conservative_nvs_recovery_with_pending_verification);
    RUN_TEST(test_motion_limit_failure_enters_emergency_stop);
    RUN_TEST(test_manual_inspection_trigger_and_idle_flow);
    return UNITY_END();
}
