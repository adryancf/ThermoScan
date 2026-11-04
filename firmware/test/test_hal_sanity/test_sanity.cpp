#include <unity.h>
#include "pinout.h"
#include "hal/i_thermal_camera.h"
#include "hal/i_power_meter.h"
#include "hal/i_motion_controller.h"
#include "hal/i_spray_actuator.h"
#include "hal/i_water_sensor.h"
#include "hal/i_storage.h"
#include "hal/i_cloud_client.h"
#include "hal/i_time_provider.h"

// Mock implementations verifying pure virtual interface compatibility
class MockThermalCamera : public IThermalCamera {
public:
    bool init() override { return true; }
    bool captureFrame(ThermalFrame& out) override {
        out.valid = true;
        for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
            out.pixels[i] = 25.0f;
        }
        return true;
    }
    bool isHealthy() override { return true; }
};

class MockPowerMeter : public IPowerMeter {
public:
    bool init() override { return true; }
    bool readSnapshot(PowerSnapshot& out) override {
        out.voltage_v = 12.0f;
        out.current_a = 1.5f;
        out.power_w = 18.0f;
        out.valid = true;
        return true;
    }
};

class MockMotionController : public IMotionController {
    float pos_x{0.0f};
public:
    bool motor_enabled{false};

    bool init() override { return true; }
    bool home() override { pos_x = 0.0f; motor_enabled = true; return true; }
    bool moveToXCm(float target_x_cm) override { pos_x = target_x_cm; motor_enabled = true; return true; }
    float getXPositionCm() const override { return pos_x; }
    bool checkLimitsIntegrity() override { return true; }
    void disableMotor() override { motor_enabled = false; }
    void emergencyStop() override { motor_enabled = false; }
};

class MockSprayActuator : public ISprayActuator {
    bool pump_active{false};
    float angle{0.0f};
public:
    bool init() override { return true; }
    bool setNozzleAngle(float angle_deg) override { angle = angle_deg; return true; }
    bool startPump() override { pump_active = true; return true; }
    void stopPump() override { pump_active = false; }
    bool isPumpActive() const override { return pump_active; }
};

class MockWaterSensor : public IWaterSensor {
public:
    WaterStatus readStatus() override { return WaterStatus::AVAILABLE; }
    bool isWaterAvailable() override { return true; }
};

class MockStorage : public IStorage {
    StorageState state;
public:
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
    bool init() override { return true; }
    bool claimDevice(const std::string& /*claim_token*/) override { return true; }
    bool sendPing() override { return true; }
    bool getConfiguration(std::string& out) override { out = "{}"; return true; }
    bool ackConfiguration(uint32_t /*config_version*/) override { return true; }
    bool ingestTelemetryBatch(const IngestTelemetryBatchInput& /*input*/) override { return true; }
    bool finalizeInspection(const std::string& /*inspection_id*/, const FinalizeInspectionInput& /*input*/) override { return true; }
    bool ingestCleaningReport(const CleaningReportInput& /*input*/, std::string& out_id) override { out_id = "clean-mock"; return true; }
    bool ingestTelemetry(const TelemetryPayload& /*telemetry*/) override { return true; }
    bool ingestCleaning(const CleaningPayload& /*cleaning*/) override { return true; }
    bool isConnected() const override { return true; }
};

class MockTimeProvider : public ITimeProvider {
public:
    uint32_t getEpochSeconds() const override { return 1730000000; }
    bool isTimeSynchronized() const override { return true; }
};

void setUp(void) {}
void tearDown(void) {}

void test_pinout_constants(void) {
    TEST_ASSERT_EQUAL_FLOAT(2.0f, STEP_SIZE_CM);
    TEST_ASSERT_EQUAL_FLOAT(5.0f, FOV_OPTICAL_CM);
    TEST_ASSERT_EQUAL_FLOAT(60.0f, OVERLAP_PERCENT);
    TEST_ASSERT_EQUAL_FLOAT(60.0f, MAX_BASE_TEMP_C);
    TEST_ASSERT_EQUAL_FLOAT(10.0f, HOTSPOT_THRESHOLD_DELTA_C);
    TEST_ASSERT_EQUAL_UINT32(3, MAX_CLEANING_ATTEMPTS);
    TEST_ASSERT_EQUAL_UINT32(1800, POST_CLEANING_WAIT_SECONDS);
}

void test_hal_interfaces_instantiation(void) {
    MockThermalCamera cam;
    TEST_ASSERT_TRUE(cam.init());
    ThermalFrame frame;
    TEST_ASSERT_TRUE(cam.captureFrame(frame));
    TEST_ASSERT_TRUE(frame.valid);
    TEST_ASSERT_EQUAL_FLOAT(25.0f, frame.pixels[0]);

    MockPowerMeter pwr;
    TEST_ASSERT_TRUE(pwr.init());
    PowerSnapshot snap;
    TEST_ASSERT_TRUE(pwr.readSnapshot(snap));
    TEST_ASSERT_EQUAL_FLOAT(12.0f, snap.voltage_v);

    MockMotionController motion;
    TEST_ASSERT_TRUE(motion.init());
    TEST_ASSERT_TRUE(motion.moveToXCm(10.5f));
    TEST_ASSERT_EQUAL_FLOAT(10.5f, motion.getXPositionCm());

    MockSprayActuator spray;
    TEST_ASSERT_TRUE(spray.init());
    TEST_ASSERT_TRUE(spray.startPump());
    TEST_ASSERT_TRUE(spray.isPumpActive());
    spray.stopPump();
    TEST_ASSERT_FALSE(spray.isPumpActive());

    MockWaterSensor water;
    TEST_ASSERT_EQUAL(WaterStatus::AVAILABLE, water.readStatus());
    TEST_ASSERT_TRUE(water.isWaterAvailable());

    MockStorage storage;
    TEST_ASSERT_TRUE(storage.init());
    TEST_ASSERT_TRUE(storage.saveModuleId("MOD-001"));
    std::string mod;
    TEST_ASSERT_TRUE(storage.getModuleId(mod));
    TEST_ASSERT_EQUAL_STRING("MOD-001", mod.c_str());

    MockCloudClient cloud;
    TEST_ASSERT_TRUE(cloud.init());
    TEST_ASSERT_TRUE(cloud.isConnected());

    MockTimeProvider time;
    TEST_ASSERT_TRUE(time.isTimeSynchronized());
    TEST_ASSERT_EQUAL_UINT32(1730000000, time.getEpochSeconds());
}

int main(int argc, char **argv) {
    UNITY_BEGIN();
    RUN_TEST(test_pinout_constants);
    RUN_TEST(test_hal_interfaces_instantiation);
    return UNITY_END();
}
