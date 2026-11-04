#include <unity.h>
#include <string>
#include <vector>
#include <cmath>

#include "diagnostics/bench_diagnostics.h"

using namespace diagnostics;

namespace {

class FakeDiagStorage : public IStorage {
public:
    StorageState state{};
    std::string test_val;
    bool fail_save{false};
    bool fail_read{false};

    bool init() override { return true; }
    bool saveModuleId(const std::string& id) override { state.module_id = id; return true; }
    bool getModuleId(std::string& out) override { out = state.module_id; return !out.empty(); }
    bool saveConfigVersion(uint32_t v) override { state.config_version = v; return true; }
    bool getConfigVersion(uint32_t& out) override { out = state.config_version; return true; }
    bool saveAnomalyEventId(const std::string& id) override { state.anomaly_event_id = id; return true; }
    bool getAnomalyEventId(std::string& out) override { out = state.anomaly_event_id; return true; }
    bool saveEffectiveAttempts(uint8_t a) override { state.effective_attempts = a; return true; }
    bool getEffectiveAttempts(uint8_t& out) override { out = state.effective_attempts; return true; }
    bool saveOperationStatus(const std::string& s) override { state.operation_status = s; return true; }
    bool getOperationStatus(std::string& out) override { out = state.operation_status; return true; }
    bool saveSprayEndedTimestamp(uint32_t t) override { state.spray_ended_timestamp = t; return true; }
    bool getSprayEndedTimestamp(uint32_t& out) override { out = state.spray_ended_timestamp; return true; }
    bool savePendingVerification(bool p) override { state.pending_verification = p; return true; }
    bool getPendingVerification(bool& out) override { out = state.pending_verification; return true; }
    bool saveNextInspectionTimestamp(uint32_t t) override { state.next_inspection_timestamp = t; return true; }
    bool getNextInspectionTimestamp(uint32_t& out) override { out = state.next_inspection_timestamp; return true; }
    bool saveAll(const StorageState& s) override { state = s; return true; }
    bool loadAll(StorageState& s) override { s = state; return true; }
    bool clear() override { state = StorageState{}; return true; }

    bool saveTestKey(const std::string& /*key*/, const std::string& val) override {
        if (fail_save) return false;
        test_val = val;
        return true;
    }
    bool getTestKey(const std::string& /*key*/, std::string& out) override {
        if (fail_read) return false;
        out = test_val;
        return true;
    }
    bool removeTestKey(const std::string& /*key*/) override {
        test_val.clear();
        return true;
    }
};

class FakeDiagTimeProvider : public ITimeProvider {
public:
    uint32_t epoch{1730721600};
    bool synced{true};

    bool isTimeSynchronized() const override { return synced; }
    uint32_t getEpochSeconds() const override { return epoch; }
};

class FakeDiagCloudClient : public ICloudClient {
public:
    bool ping_result{true};
    bool auth_error{false};
    bool claim_result{true};

    bool init() override { return true; }
    bool claimDevice(const std::string& = "") override { return claim_result; }
    bool sendPing() override { return ping_result; }
    bool getConfiguration(std::string& out) override { out = "{}"; return true; }
    bool ackConfiguration(uint32_t) override { return true; }
    bool ingestTelemetryBatch(const IngestTelemetryBatchInput&) override { return true; }
    virtual bool finalizeInspection(const std::string&, const FinalizeInspectionInput&) override { return true; }
    bool ingestCleaningReport(const CleaningReportInput&, std::string&) override { return true; }
    bool isConnected() const override { return true; }
    bool hadAuthError() const override { return auth_error; }

    bool ingestTelemetry(const TelemetryPayload&) override { return true; }
    bool ingestCleaning(const CleaningPayload&) override { return true; }
};

class FakeDiagThermalCamera : public IThermalCamera {
public:
    bool init_ok{true};
    bool capture_ok{true};
    float pixel_temp{28.5f};
    bool inject_nan{false};

    bool init() override { return init_ok; }
    bool isHealthy() override { return true; }
    bool captureFrame(ThermalFrame& out) override {
        if (!capture_ok) return false;
        out.valid = true;
        for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
            out.pixels[i] = pixel_temp;
        }
        if (inject_nan) {
            for (size_t i = 0; i < 50; ++i) {
                out.pixels[i] = NAN;
            }
        }
        return true;
    }
};

class FakeDiagMotionController : public IMotionController {
public:
    float x_pos{0.0f};
    bool limits_ok{true};
    bool home_ok{true};
    bool motor_enabled{true};
    int moves_count{0};

    bool init() override { return true; }
    bool home() override {
        if (!home_ok) return false;
        x_pos = 0.0f;
        return true;
    }
    bool moveToXCm(float x) override {
        moves_count++;
        x_pos = x;
        return true;
    }
    float getXPositionCm() const override { return x_pos; }
    bool checkLimitsIntegrity() override { return limits_ok; }
    void disableMotor() override { motor_enabled = false; }
    void emergencyStop() override { motor_enabled = false; }
};

class FakeDiagPowerMeter : public IPowerMeter {
public:
    bool read_ok{true};
    float voltage{19.2f};
    float current{4.5f};
    float power{86.4f};

    bool init() override { return true; }
    bool readSnapshot(PowerSnapshot& out) override {
        if (!read_ok) return false;
        out.valid = true;
        out.voltage_v = voltage;
        out.current_a = current;
        out.power_w = power;
        return true;
    }
};

class FakeDiagWaterSensor : public IWaterSensor {
public:
    bool available{true};
    bool oscillating{false};
    int call_count{0};

    WaterStatus readStatus() override {
        return isWaterAvailable() ? WaterStatus::AVAILABLE : WaterStatus::DEPLETED;
    }
    bool isWaterAvailable() override {
        call_count++;
        if (oscillating) {
            return (call_count % 2 == 0);
        }
        return available;
    }
};

class FakeDiagSprayActuator : public ISprayActuator {
public:
    bool pump_active{false};
    int activations{0};

    bool init() override { return true; }
    bool startPump() override {
        pump_active = true;
        activations++;
        return true;
    }
    void stopPump() override {
        pump_active = false;
    }
    bool isPumpActive() const override { return pump_active; }
    bool setNozzleAngle(float) override { return true; }
};

class MockConsole : public IConsole {
public:
    std::string output;
    std::vector<std::string> inputs;
    size_t input_idx{0};

    void print(const char* s) override { output += s; }
    void println(const char* s = "") override { output += s; output += "\n"; }
    void printf(const char* format, ...) override {
        char buf[512];
        va_list args;
        va_start(args, format);
        vsnprintf(buf, sizeof(buf), format, args);
        va_end(args);
        output += buf;
    }
    bool available() override { return input_idx < inputs.size(); }
    int read() override { return available() ? inputs[input_idx++][0] : -1; }
    std::string readLine(uint32_t = 0) override {
        if (input_idx < inputs.size()) {
            return inputs[input_idx++];
        }
        return "";
    }
    void clear() {
        output.clear();
        inputs.clear();
        input_idx = 0;
    }
};

} // namespace

void test_bench_diag_nvs() {
    FakeDiagStorage storage;
    FakeDiagTimeProvider time_p;
    FakeDiagCloudClient cloud;
    FakeDiagThermalCamera camera;
    FakeDiagMotionController motion;
    FakeDiagPowerMeter power;
    FakeDiagWaterSensor water;
    FakeDiagSprayActuator spray;
    app::ThermoscanApp app(&camera, &power, &motion, &spray, &water, &storage, &cloud, &time_p);
    MockConsole console;

    BenchDiagnostics diag(&storage, &time_p, &cloud, &camera, &motion, &power, &water, &spray, &app, &console);

    // 1. Success case
    TestResult r = diag.testNvs();
    TEST_ASSERT_EQUAL(TestStatus::PASS, r.status);
    TEST_ASSERT_TRUE(r.details.find("consistentes") != std::string::npos);

    // 2. Failure case
    storage.fail_read = true;
    TestResult r_fail = diag.testNvs();
    TEST_ASSERT_EQUAL(TestStatus::FAIL, r_fail.status);
    TEST_ASSERT_TRUE(!r_fail.failure_cause.empty());
}

void test_bench_diag_clock() {
    FakeDiagStorage storage;
    FakeDiagTimeProvider time_p;
    FakeDiagCloudClient cloud;
    FakeDiagThermalCamera camera;
    FakeDiagMotionController motion;
    FakeDiagPowerMeter power;
    FakeDiagWaterSensor water;
    FakeDiagSprayActuator spray;
    app::ThermoscanApp app(&camera, &power, &motion, &spray, &water, &storage, &cloud, &time_p);
    MockConsole console;

    BenchDiagnostics diag(&storage, &time_p, &cloud, &camera, &motion, &power, &water, &spray, &app, &console);

    // 1. Valid clock
    TestResult r = diag.testClock();
    TEST_ASSERT_EQUAL(TestStatus::PASS, r.status);

    // 2. Unsynchronized clock
    time_p.synced = false;
    TestResult r_unsync = diag.testClock();
    TEST_ASSERT_EQUAL(TestStatus::FAIL, r_unsync.status);

    // 3. Zero epoch
    time_p.synced = true;
    time_p.epoch = 0;
    TestResult r_zero = diag.testClock();
    TEST_ASSERT_EQUAL(TestStatus::FAIL, r_zero.status);
}

void test_bench_diag_backend_and_reclaim() {
    FakeDiagStorage storage;
    FakeDiagTimeProvider time_p;
    FakeDiagCloudClient cloud;
    FakeDiagThermalCamera camera;
    FakeDiagMotionController motion;
    FakeDiagPowerMeter power;
    FakeDiagWaterSensor water;
    FakeDiagSprayActuator spray;
    app::ThermoscanApp app(&camera, &power, &motion, &spray, &water, &storage, &cloud, &time_p);
    MockConsole console;

    BenchDiagnostics diag(&storage, &time_p, &cloud, &camera, &motion, &power, &water, &spray, &app, &console);

    // 1. Success ping
    cloud.ping_result = true;
    TestResult r = diag.testBackend();
    TEST_ASSERT_EQUAL(TestStatus::PASS, r.status);

    // 2. 401 Unauthorized triggers re-claim
    cloud.ping_result = false;
    cloud.auth_error = true;
    cloud.claim_result = true;
    TestResult r_reclaim = diag.testBackend();
    TEST_ASSERT_EQUAL(TestStatus::PASS, r_reclaim.status);
    TEST_ASSERT_TRUE(r_reclaim.details.find("re-claim") != std::string::npos);

    // 3. 401 Unauthorized where re-claim also fails
    cloud.claim_result = false;
    TestResult r_fail = diag.testBackend();
    TEST_ASSERT_EQUAL(TestStatus::FAIL, r_fail.status);
}

void test_bench_diag_mlx() {
    FakeDiagStorage storage;
    FakeDiagTimeProvider time_p;
    FakeDiagCloudClient cloud;
    FakeDiagThermalCamera camera;
    FakeDiagMotionController motion;
    FakeDiagPowerMeter power;
    FakeDiagWaterSensor water;
    FakeDiagSprayActuator spray;
    app::ThermoscanApp app(&camera, &power, &motion, &spray, &water, &storage, &cloud, &time_p);
    MockConsole console;

    BenchDiagnostics diag(&storage, &time_p, &cloud, &camera, &motion, &power, &water, &spray, &app, &console);

    // 1. Valid 768 pixels
    TestResult r = diag.testMlx(false);
    TEST_ASSERT_EQUAL(TestStatus::PASS, r.status);
    TEST_ASSERT_TRUE(r.details.find("768 pixels") != std::string::npos);

    // 2. Corrupt / excessive invalid pixels
    camera.inject_nan = true;
    TestResult r_nan = diag.testMlx(false);
    TEST_ASSERT_EQUAL(TestStatus::FAIL, r_nan.status);

    // 3. Init failure
    camera.inject_nan = false;
    camera.init_ok = false;
    TestResult r_init = diag.testMlx(false);
    TEST_ASSERT_EQUAL(TestStatus::FAIL, r_init.status);
}

void test_bench_diag_ina() {
    FakeDiagStorage storage;
    FakeDiagTimeProvider time_p;
    FakeDiagCloudClient cloud;
    FakeDiagThermalCamera camera;
    FakeDiagMotionController motion;
    FakeDiagPowerMeter power;
    FakeDiagWaterSensor water;
    FakeDiagSprayActuator spray;
    app::ThermoscanApp app(&camera, &power, &motion, &spray, &water, &storage, &cloud, &time_p);
    MockConsole console;

    BenchDiagnostics diag(&storage, &time_p, &cloud, &camera, &motion, &power, &water, &spray, &app, &console);

    // 1. Valid reading
    TestResult r = diag.testIna();
    TEST_ASSERT_EQUAL(TestStatus::PASS, r.status);
    TEST_ASSERT_TRUE(r.details.find("Tensao:") != std::string::npos);

    // 2. I2C Failure
    power.read_ok = false;
    TestResult r_fail = diag.testIna();
    TEST_ASSERT_EQUAL(TestStatus::FAIL, r_fail.status);

    // 3. NaN value
    power.read_ok = true;
    power.voltage = NAN;
    TestResult r_nan = diag.testIna();
    TEST_ASSERT_EQUAL(TestStatus::FAIL, r_nan.status);
}

void test_bench_diag_water() {
    FakeDiagStorage storage;
    FakeDiagTimeProvider time_p;
    FakeDiagCloudClient cloud;
    FakeDiagThermalCamera camera;
    FakeDiagMotionController motion;
    FakeDiagPowerMeter power;
    FakeDiagWaterSensor water;
    FakeDiagSprayActuator spray;
    app::ThermoscanApp app(&camera, &power, &motion, &spray, &water, &storage, &cloud, &time_p);
    MockConsole console;

    BenchDiagnostics diag(&storage, &time_p, &cloud, &camera, &motion, &power, &water, &spray, &app, &console);

    // 1. Stable reading -> MANUAL
    TestResult r = diag.testWater();
    TEST_ASSERT_EQUAL(TestStatus::MANUAL, r.status);
    TEST_ASSERT_TRUE(r.details.find("estaveis") != std::string::npos);

    // 2. Oscillating sensor -> FAIL
    water.oscillating = true;
    TestResult r_osc = diag.testWater();
    TEST_ASSERT_EQUAL(TestStatus::FAIL, r_osc.status);
}

void test_bench_diag_motor_confirmation() {
    FakeDiagStorage storage;
    FakeDiagTimeProvider time_p;
    FakeDiagCloudClient cloud;
    FakeDiagThermalCamera camera;
    FakeDiagMotionController motion;
    FakeDiagPowerMeter power;
    FakeDiagWaterSensor water;
    FakeDiagSprayActuator spray;
    app::ThermoscanApp app(&camera, &power, &motion, &spray, &water, &storage, &cloud, &time_p);
    MockConsole console;

    BenchDiagnostics diag(&storage, &time_p, &cloud, &camera, &motion, &power, &water, &spray, &app, &console);

    // 1. Operator rejects motor test ('n'): no movement, status MANUAL
    console.clear();
    console.inputs.push_back("n");
    TestResult r_rej = diag.testMotor(true);
    TEST_ASSERT_EQUAL(TestStatus::MANUAL, r_rej.status);
    TEST_ASSERT_EQUAL(0, motion.moves_count);

    // 2. Operator confirms motor test ('s'): moves forward + backward, motor disabled
    console.clear();
    console.inputs.push_back("s");
    TestResult r_conf = diag.testMotor(true);
    TEST_ASSERT_EQUAL(TestStatus::MANUAL, r_conf.status);
    TEST_ASSERT_EQUAL(2, motion.moves_count);
    TEST_ASSERT_FALSE(motion.motor_enabled);
}

void test_bench_diag_homing() {
    FakeDiagStorage storage;
    FakeDiagTimeProvider time_p;
    FakeDiagCloudClient cloud;
    FakeDiagThermalCamera camera;
    FakeDiagMotionController motion;
    FakeDiagPowerMeter power;
    FakeDiagWaterSensor water;
    FakeDiagSprayActuator spray;
    app::ThermoscanApp app(&camera, &power, &motion, &spray, &water, &storage, &cloud, &time_p);
    MockConsole console;

    BenchDiagnostics diag(&storage, &time_p, &cloud, &camera, &motion, &power, &water, &spray, &app, &console);

    // 1. Success homing
    TestResult r = diag.testHoming();
    TEST_ASSERT_EQUAL(TestStatus::PASS, r.status);
    TEST_ASSERT_EQUAL_FLOAT(0.0f, motion.getXPositionCm());

    // 2. Limit wire broken / open circuit before starting
    motion.limits_ok = false;
    TestResult r_broken = diag.testHoming();
    TEST_ASSERT_EQUAL(TestStatus::FAIL, r_broken.status);

    // 3. Homing fails during motion
    motion.limits_ok = true;
    motion.home_ok = false;
    TestResult r_fail = diag.testHoming();
    TEST_ASSERT_EQUAL(TestStatus::FAIL, r_fail.status);
}

void test_bench_diag_pump_safety_interlock() {
    FakeDiagStorage storage;
    FakeDiagTimeProvider time_p;
    FakeDiagCloudClient cloud;
    FakeDiagThermalCamera camera;
    FakeDiagMotionController motion;
    FakeDiagPowerMeter power;
    FakeDiagWaterSensor water;
    FakeDiagSprayActuator spray;
    app::ThermoscanApp app(&camera, &power, &motion, &spray, &water, &storage, &cloud, &time_p);
    MockConsole console;

    BenchDiagnostics diag(&storage, &time_p, &cloud, &camera, &motion, &power, &water, &spray, &app, &console);

    // 1. NEVER actuate pump on refusal: pump activations MUST be 0!
    console.clear();
    console.inputs.push_back("n");
    TestResult r_rej = diag.testPump(true);
    TEST_ASSERT_EQUAL(TestStatus::MANUAL, r_rej.status);
    TEST_ASSERT_EQUAL(0, spray.activations);
    TEST_ASSERT_FALSE(spray.pump_active);

    // 2. Actuate only when explicitly confirmed ('s'): pulses and turns off
    console.clear();
    console.inputs.push_back("s");
    TestResult r_conf = diag.testPump(true);
    TEST_ASSERT_EQUAL(TestStatus::MANUAL, r_conf.status);
    TEST_ASSERT_EQUAL(1, spray.activations);
    TEST_ASSERT_FALSE(spray.pump_active);
}

void test_bench_diag_safety_emergency_stop() {
    FakeDiagStorage storage;
    FakeDiagTimeProvider time_p;
    FakeDiagCloudClient cloud;
    FakeDiagThermalCamera camera;
    FakeDiagMotionController motion;
    FakeDiagPowerMeter power;
    FakeDiagWaterSensor water;
    FakeDiagSprayActuator spray;
    app::ThermoscanApp app(&camera, &power, &motion, &spray, &water, &storage, &cloud, &time_p);
    MockConsole console;

    BenchDiagnostics diag(&storage, &time_p, &cloud, &camera, &motion, &power, &water, &spray, &app, &console);

    // Simulate pump and motor active
    spray.pump_active = true;
    motion.motor_enabled = true;

    TestResult r = diag.testSafety();
    TEST_ASSERT_EQUAL(TestStatus::PASS, r.status);
    TEST_ASSERT_FALSE(spray.pump_active);
    TEST_ASSERT_FALSE(motion.motor_enabled);
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
}

void test_bench_diag_command_dispatch_and_run_all() {
    FakeDiagStorage storage;
    FakeDiagTimeProvider time_p;
    FakeDiagCloudClient cloud;
    FakeDiagThermalCamera camera;
    FakeDiagMotionController motion;
    FakeDiagPowerMeter power;
    FakeDiagWaterSensor water;
    FakeDiagSprayActuator spray;
    app::ThermoscanApp app(&camera, &power, &motion, &spray, &water, &storage, &cloud, &time_p);
    MockConsole console;

    BenchDiagnostics diag(&storage, &time_p, &cloud, &camera, &motion, &power, &water, &spray, &app, &console);

    // 1. diag list command
    console.clear();
    bool handled_list = diag.handleCommand("diag list");
    TEST_ASSERT_TRUE(handled_list);
    TEST_ASSERT_TRUE(console.output.find("Catalogo de Testes de Bancada") != std::string::npos);

    // 2. diag all command (provide confirmations for motor and pump)
    console.clear();
    console.inputs.push_back("s"); // motor confirm
    console.inputs.push_back("s"); // pump confirm
    bool handled_all = diag.handleCommand("diag all");
    TEST_ASSERT_TRUE(handled_all);
    TEST_ASSERT_TRUE(console.output.find("RESUMO DO DIAGNOSTICO") != std::string::npos);
    TEST_ASSERT_TRUE(console.output.find("RECOMENDACAO:") != std::string::npos);
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());
}

int main(int argc, char** argv) {
    UNITY_BEGIN();
    RUN_TEST(test_bench_diag_nvs);
    RUN_TEST(test_bench_diag_clock);
    RUN_TEST(test_bench_diag_backend_and_reclaim);
    RUN_TEST(test_bench_diag_mlx);
    RUN_TEST(test_bench_diag_ina);
    RUN_TEST(test_bench_diag_water);
    RUN_TEST(test_bench_diag_motor_confirmation);
    RUN_TEST(test_bench_diag_homing);
    RUN_TEST(test_bench_diag_pump_safety_interlock);
    RUN_TEST(test_bench_diag_safety_emergency_stop);
    RUN_TEST(test_bench_diag_command_dispatch_and_run_all);
    return UNITY_END();
}
