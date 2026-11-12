#include <unity.h>
#include <ArduinoJson.h>
#include <cstdlib>
#include <cstdio>
#include <string>
#include <vector>
#include <memory>
#include <iostream>
#include <sstream>
#include <cmath>

#include "app/thermoscan_app.h"
#include "hal/i_thermal_camera.h"
#include "hal/i_power_meter.h"
#include "hal/i_motion_controller.h"
#include "hal/i_spray_actuator.h"
#include "hal/i_water_sensor.h"
#include "hal/i_storage.h"
#include "hal/i_time_provider.h"
#include "hal_esp32/http_cloud_client.h"

using namespace app;
using namespace hal_esp32;

namespace {

std::string getBackendUrl() {
    const char* env_url = std::getenv("THERMOSCAN_BACKEND_URL");
    if (env_url != nullptr && env_url[0] != '\0') {
        return std::string(env_url);
    }
    return "http://localhost:8080";
}

std::string execCommand(const std::string& cmd) {
    char buffer[256];
    std::string result = "";
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) return "";
    while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        result += buffer;
    }
    pclose(pipe);
    // Trim trailing newlines
    while (!result.empty() && (result.back() == '\n' || result.back() == '\r')) {
        result.pop_back();
    }
    return result;
}

std::string queryDB(const std::string& sql) {
    std::string cmd = "docker exec thermoscan-db psql -U thermoscan -d thermoscan -t -A -c \"" + sql + "\"";
    return execCommand(cmd);
}

void cleanDatabaseTables() {
    queryDB("TRUNCATE cleaning_operations, anomaly_events, measurements, inspections CASCADE;");
}

void cleanAllTestData() {
    queryDB("TRUNCATE cleaning_operations, anomaly_events, measurements, inspections, "
            "interval_change_logs, reservoir_readings, notifications, "
            "module_clients, module_managers, module_technicians, technician_managers CASCADE; "
            "DELETE FROM modules WHERE id = '00000000-0000-0000-0000-000000000003' OR company_id = '00000000-0000-0000-0000-000000000001'; "
            "DELETE FROM users WHERE id = '00000000-0000-0000-0000-000000000002' OR company_id = '00000000-0000-0000-0000-000000000001'; "
            "DELETE FROM companies WHERE id = '00000000-0000-0000-0000-000000000001';");
}

void ensureTestSeedDataExists() {
    cleanAllTestData();
    queryDB("INSERT INTO companies (id, name, address, is_active) "
            "VALUES ('00000000-0000-0000-0000-000000000001', 'Solar Farm Alpha', 'Rua das Flores 123', true) "
            "ON CONFLICT (id) DO NOTHING; "
            "INSERT INTO users (id, company_id, name, email, password_hash, role, is_active, is_default_manager, must_change_password) "
            "VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Tech Operator', 'tech@solarfarm.local', '$2a$10$abcdefghijklmnopqrstuv', 'technician', true, false, false) "
            "ON CONFLICT (id) DO NOTHING; "
            "INSERT INTO modules ( "
            "    id, company_id, installer_technician_id, name, mac_address, "
            "    is_active, monitoring_status, panel_length_cm, panel_width_cm, "
            "    panel_count, panel_spacing_cm, latitude, longitude, "
            "    elevation_m, azimuth_deg, tilt_deg, azimuth_source, tilt_source, "
            "    minimum_solar_angle_deg, inspection_interval_days, "
            "    reservoir_nominal_capacity_ml, configured_at "
            ") VALUES ( "
            "    '00000000-0000-0000-0000-000000000003', "
            "    '00000000-0000-0000-0000-000000000001', "
            "    '00000000-0000-0000-0000-000000000002', "
            "    'ThermoScan Unit 01', "
            "    '02:00:00:00:00:01', "
            "    true, 'active', 68.0, 50.0, 1, 0.0, "
            "    -23.5505, -46.6333, 760.0, 180.0, 20.0, 'manual', 'manual', "
            "    30.0, 7, 1000.0, now() "
            ") ON CONFLICT (id) DO NOTHING;");
}

class FakeE2EStorage : public IStorage {
public:
    StorageState state{};

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

    bool saveDeviceToken(const std::string& t) override { device_token_ = t; return true; }
    bool getDeviceToken(std::string& out) override { out = device_token_; return !out.empty(); }

    bool saveAll(const StorageState& s) override { state = s; return true; }
    bool loadAll(StorageState& s) override { s = state; return true; }
    bool clear() override { state = StorageState{}; device_token_.clear(); return true; }

private:
    std::string device_token_;
};

class FakeE2EThermalCamera : public IThermalCamera {
public:
    float baseline_temp{30.0f};
    bool hotspot_active{true};
    float hotspot_temp{52.0f}; // baseline + 22.0 C (> baseline + 10.0 C)
    float current_x{0.0f};

    bool init() override { return true; }
    bool isHealthy() override { return true; }

    bool captureFrame(ThermalFrame& out) override {
        out.valid = true;
        for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
            out.pixels[i] = baseline_temp;
        }

        // Physical hotspot located at X = 12.0 cm on panel, row = 8
        // Visible when carriage X is in range [7.1 cm, 12.0 cm] (within 5 cm optical FOV)
        if (hotspot_active) {
            const float target_x_panel = 12.0f;
            const float fov = 5.0f;
            if (target_x_panel >= current_x && target_x_panel < (current_x + fov)) {
                int col = static_cast<int>(std::round(((target_x_panel - current_x) / fov) * 31.0f));
                if (col >= 0 && col < 32) {
                    out.pixels[8 * 32 + col] = hotspot_temp;
                }
            }
        }
        return true;
    }
};

class FakeE2EPowerMeter : public IPowerMeter {
public:
    bool init() override { return true; }
    bool readSnapshot(PowerSnapshot& out) override {
        out.valid = true;
        out.voltage_v = 18.5f;
        out.current_a = 4.2f;
        out.power_w = 77.7f;
        return true;
    }
};

class FakeE2EMotionController : public IMotionController {
public:
    float x_pos{0.0f};
    FakeE2EThermalCamera* camera{nullptr};

    bool init() override { return true; }
    bool home() override {
        x_pos = 0.0f;
        if (camera) camera->current_x = 0.0f;
        return true;
    }
    bool moveToXCm(float target_x_cm) override {
        x_pos = target_x_cm;
        if (camera) camera->current_x = target_x_cm;
        return true;
    }
    float getXPositionCm() const override { return x_pos; }
    bool checkLimitsIntegrity() override { return true; }
    void disableMotor() override {}
    void emergencyStop() override {}
};

class FakeE2ESprayActuator : public ISprayActuator {
public:
    bool pump_active{false};
    float current_angle{90.0f};
    int pump_activations{0};

    bool init() override { return true; }
    bool startPump() override {
        pump_active = true;
        pump_activations++;
        return true;
    }
    void stopPump() override {
        pump_active = false;
    }
    bool isPumpActive() const override {
        return pump_active;
    }
    bool setNozzleAngle(float angle_deg) override {
        current_angle = angle_deg;
        return true;
    }
};

class FakeE2EWaterSensor : public IWaterSensor {
public:
    bool water_available{true};
    int checks_remaining_before_depletion{-1};

    WaterStatus readStatus() override {
        return isWaterAvailable() ? WaterStatus::AVAILABLE : WaterStatus::DEPLETED;
    }
    bool isWaterAvailable() override {
        if (checks_remaining_before_depletion > 0) {
            checks_remaining_before_depletion--;
            return true;
        } else if (checks_remaining_before_depletion == 0) {
            water_available = false;
            return false;
        }
        return water_available;
    }
};

class FakeE2ETimeProvider : public ITimeProvider {
public:
    uint32_t current_epoch{1730721600}; // 2024-11-04 12:00:00 UTC
    bool isTimeSynchronized() const override { return true; }
    uint32_t getEpochSeconds() const override { return current_epoch; }
    void advance(uint32_t seconds) { current_epoch += seconds; }
};

} // namespace

void test_e2e_device_claim_and_configuration() {
    std::string backend_url = getBackendUrl();
    FakeE2EStorage storage;
    FakeE2EWaterSensor water;
    FakeE2EMotionController motion;
    FakeE2EThermalCamera camera;

    HttpCloudClient client(backend_url, &storage, &water, &motion, &camera);
    TEST_ASSERT_TRUE(client.init());

    // Claim device using pre-seeded MAC "02:00:00:00:00:01"
    bool claim_ok = client.claimDevice();
    TEST_ASSERT_TRUE_MESSAGE(claim_ok, "Device claim failed against local backend!");

    TEST_ASSERT_EQUAL_STRING("00000000-0000-0000-0000-000000000003", client.getModuleId().c_str());
    TEST_ASSERT_TRUE(!client.getDeviceToken().empty());
    TEST_ASSERT_TRUE(client.getDeviceToken().rfind("dev_sec_", 0) == 0);

    // Get configuration
    std::string config_json;
    bool cfg_ok = client.getConfiguration(config_json);
    TEST_ASSERT_TRUE_MESSAGE(cfg_ok, "Failed to get configuration from backend!");
    TEST_ASSERT_TRUE(config_json.find("panel_length_cm") != std::string::npos);

    // Acknowledge configuration version 0
    bool ack_ok = client.ackConfiguration(0);
    TEST_ASSERT_TRUE_MESSAGE(ack_ok, "Failed to ack configuration!");
}

void test_e2e_full_cycle_scan_finalize_cleaning_verification() {
    cleanDatabaseTables();

    std::string backend_url = getBackendUrl();
    FakeE2EStorage storage;
    FakeE2EWaterSensor water;
    FakeE2EThermalCamera camera;
    FakeE2EMotionController motion;
    motion.camera = &camera;
    FakeE2EPowerMeter power;
    FakeE2ESprayActuator spray;
    FakeE2ETimeProvider time_provider;

    HttpCloudClient client(backend_url, &storage, &water, &motion, &camera);
    TEST_ASSERT_TRUE(client.init());
    TEST_ASSERT_TRUE(client.claimDevice());

    ThermoscanApp app(&camera, &power, &motion, &spray, &water, &storage, &client, &time_provider);
    TEST_ASSERT_TRUE(app.init());

    // 1. Boot initialization -> Transitions to IDLE
    app.tick();
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());

    // 2. Trigger manual inspection scan
    app.triggerManualInspection();
    app.tick();
    TEST_ASSERT_EQUAL(AppState::SCANNING, app.getState());

    // 3. Complete scan across 35 acquisitions (0 to 68 cm in 2 cm steps)
    // ThermoscanApp::handleScanning runs the loop internally, streams 7 batches of 5 items,
    // and transitions to ANALYZING.
    app.tick();
    TEST_ASSERT_EQUAL(AppState::ANALYZING, app.getState());

    // 4. Analysis and Finalization
    // Analyzes quantized frames, confirms hotspot at X=12 cm,
    // calls POST /finalize, and transitions to CLEANING because hotspot was confirmed.
    app.tick();
    TEST_ASSERT_EQUAL(AppState::CLEANING, app.getState());

    // 5. Verify database records for the completed inspection:
    // a) Exactly 35 measurements saved
    std::string meas_count = queryDB("SELECT count(*) FROM measurements;");
    TEST_ASSERT_EQUAL_STRING("35", meas_count.c_str());

    // b) All 35 measurements belong to the exact same inspection_id
    std::string distinct_insp_count = queryDB("SELECT count(DISTINCT inspection_id) FROM measurements;");
    TEST_ASSERT_EQUAL_STRING("1", distinct_insp_count.c_str());

    // c) Exactly 1 inspection record with status 'completed'
    std::string insp_status = queryDB("SELECT status FROM inspections LIMIT 1;");
    TEST_ASSERT_EQUAL_STRING("completed", insp_status.c_str());

    // d) Exactly 1 confirmed anomaly event created with status 'open'
    std::string anom_count = queryDB("SELECT count(*) FROM anomaly_events;");
    TEST_ASSERT_EQUAL_STRING("1", anom_count.c_str());
    std::string anom_status = queryDB("SELECT status FROM anomaly_events LIMIT 1;");
    TEST_ASSERT_EQUAL_STRING("open", anom_status.c_str());

    // e) Anomaly has at least 2 confirming measurements
    std::string confirming_count = queryDB("SELECT cardinality(confirming_measurement_ids) FROM anomaly_events LIMIT 1;");
    TEST_ASSERT_TRUE_MESSAGE(std::stoi(confirming_count) >= 2, "Anomaly must reference at least 2 confirming measurements");

    // 6. Actuate Cleaning
    // Moves to hotspot target, runs spray cycle, reports to POST /cleanings
    // and transitions to WAITING_VERIFICATION.
    app.tick();
    TEST_ASSERT_EQUAL(AppState::WAITING_VERIFICATION, app.getState());
    TEST_ASSERT_TRUE(spray.pump_activations >= 1);

    // 7. Verify Cleaning record in DB:
    // Anomaly MUST STILL BE 'open'! (Cleaning ingestion does NOT close anomaly)
    std::string anom_post_clean = queryDB("SELECT status FROM anomaly_events LIMIT 1;");
    TEST_ASSERT_EQUAL_STRING("open", anom_post_clean.c_str());

    std::string clean_count = queryDB("SELECT count(*) FROM cleaning_operations;");
    TEST_ASSERT_EQUAL_STRING("1", clean_count.c_str());
    std::string clean_result = queryDB("SELECT post_cleaning_result FROM cleaning_operations LIMIT 1;");
    TEST_ASSERT_EQUAL_STRING("pending", clean_result.c_str());

    // 8. Cooldown wait: simulate passing 30 minutes (1801 seconds)
    time_provider.advance(1801);

    // Cleaned surface -> camera no longer sees hotspot!
    camera.hotspot_active = false;

    // Tick: Cooldown elapsed -> Transitions to VERIFYING
    app.tick();
    TEST_ASSERT_EQUAL(AppState::VERIFYING, app.getState());

    // 9. Verification Scan:
    // Captures verification telemetry, confirms NO hotspot, finalizes verification inspection.
    // Backend evaluates resolved -> updates cleaning to 'resolved' and anomaly to 'resolved'!
    app.tick();
    TEST_ASSERT_EQUAL(AppState::SYNCING, app.getState());

    // 10. Syncing -> ack config -> back to IDLE
    app.tick();
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());

    // 11. Final Database Assertions:
    // Cleaning operation is now resolved!
    std::string clean_final = queryDB("SELECT post_cleaning_result FROM cleaning_operations LIMIT 1;");
    TEST_ASSERT_EQUAL_STRING("resolved", clean_final.c_str());

    // Anomaly event is now resolved!
    std::string anom_final = queryDB("SELECT status FROM anomaly_events LIMIT 1;");
    TEST_ASSERT_EQUAL_STRING("resolved", anom_final.c_str());

    std::string anom_closed = queryDB("SELECT closed_at IS NOT NULL FROM anomaly_events LIMIT 1;");
    TEST_ASSERT_EQUAL_STRING("t", anom_closed.c_str());
}

void test_e2e_idempotency_telemetry_resend() {
    cleanDatabaseTables();

    std::string backend_url = getBackendUrl();
    FakeE2EStorage storage;
    FakeE2EWaterSensor water;
    FakeE2EMotionController motion;
    FakeE2EThermalCamera camera;

    HttpCloudClient client(backend_url, &storage, &water, &motion, &camera);
    TEST_ASSERT_TRUE(client.init());
    TEST_ASSERT_TRUE(client.claimDevice());

    std::string insp_id = "55000000-0000-0000-0000-000000000001";
    std::string meas_id = "55000000-0000-0000-0000-000000000011";

    IngestTelemetryBatchInput input;
    input.inspection_source_event_id = insp_id;
    input.inspection_type = "scheduled";
    input.started_at_epoch = 1730721600;

    float v = 18.5f, a = 4.2f, p = 77.7f;
    std::vector<float> frame(768, 30.0f);

    TelemetryMeasurementItem item;
    item.source_event_id = meas_id;
    item.measured_at_epoch = 1730721605;
    item.x_position_cm = 20.0f;
    item.max_temperature_c = 35.0f;
    item.voltage_v = &v;
    item.current_a = &a;
    item.power_w = &p;
    item.thermal_frame = frame.data();
    item.thermal_frame_size = 768;
    input.batch.push_back(item);

    // 1. Initial send: returns 201 Created
    bool ok1 = client.ingestTelemetryBatch(input);
    TEST_ASSERT_TRUE_MESSAGE(ok1, "Initial telemetry batch send failed!");

    std::string count_before = queryDB("SELECT count(*) FROM measurements WHERE source_event_id = '55000000-0000-0000-0000-000000000011';");
    TEST_ASSERT_EQUAL_STRING("1", count_before.c_str());

    // 2. Idempotent resend with identical data: returns 201 Created without duplicate
    bool ok2 = client.ingestTelemetryBatch(input);
    TEST_ASSERT_TRUE_MESSAGE(ok2, "Idempotent telemetry batch resend failed!");

    std::string count_after = queryDB("SELECT count(*) FROM measurements WHERE source_event_id = '55000000-0000-0000-0000-000000000011';");
    TEST_ASSERT_EQUAL_STRING("1", count_after.c_str());

    // 3. Divergent resend with same source_event_id but different temperature (+10.0 C): returns 409 Conflict!
    input.batch[0].max_temperature_c = 45.0f;
    client.clearConflictError();
    bool ok3 = client.ingestTelemetryBatch(input);
    TEST_ASSERT_FALSE_MESSAGE(ok3, "Divergent telemetry batch should fail!");
    TEST_ASSERT_TRUE_MESSAGE(client.hadConflictError(), "Client should have flagged 409 Conflict error!");

    // Ensure database value was not corrupted by the conflicting resend
    std::string db_max_temp = queryDB("SELECT round(max_temperature_c, 0)::int FROM measurements WHERE source_event_id = '55000000-0000-0000-0000-000000000011';");
    TEST_ASSERT_EQUAL_STRING("35", db_max_temp.c_str());
}

void test_e2e_interrupted_cleaning_and_retry_pending() {
    cleanDatabaseTables();

    std::string backend_url = getBackendUrl();
    FakeE2EStorage storage;
    FakeE2EWaterSensor water;
    FakeE2EThermalCamera camera;
    FakeE2EMotionController motion;
    motion.camera = &camera;
    FakeE2EPowerMeter power;
    FakeE2ESprayActuator spray;
    FakeE2ETimeProvider time_provider;

    HttpCloudClient client(backend_url, &storage, &water, &motion, &camera);
    TEST_ASSERT_TRUE(client.init());
    TEST_ASSERT_TRUE(client.claimDevice());

    ThermoscanApp app(&camera, &power, &motion, &spray, &water, &storage, &client, &time_provider);
    TEST_ASSERT_TRUE(app.init());

    // 1. Initial Scan & Finalize to produce an open anomaly
    app.tick(); // BOOT -> IDLE
    app.triggerManualInspection();
    app.tick(); // IDLE -> SCANNING
    app.tick(); // SCANNING -> ANALYZING
    app.tick(); // ANALYZING -> CLEANING

    std::string anom_id = queryDB("SELECT id FROM anomaly_events LIMIT 1;");
    TEST_ASSERT_TRUE(!anom_id.empty());

    // 2. Simulate Water Depletion during cleaning spray:
    // Allows evaluateBeforeSpray (check 1) to pass, then trips during monitorDuringSpray (check 2)
    water.checks_remaining_before_depletion = 2;

    app.tick(); // CLEANING: starts spray, monitorDuringSpray trips -> pump stopped, reported status = 'failed'
    TEST_ASSERT_EQUAL(AppState::WAITING_VERIFICATION, app.getState());

    std::string clean_status = queryDB("SELECT status FROM cleaning_operations LIMIT 1;");
    TEST_ASSERT_EQUAL_STRING("failed", clean_status.c_str());

    // 3. Cooldown passes (30 minutes)
    time_provider.advance(1801);

    // Hotspot is STILL PRESENT (cleaning was interrupted/failed)
    camera.hotspot_active = true;

    app.tick(); // WAITING_VERIFICATION -> VERIFYING

    // 4. Verification runs with persisting hotspot
    app.tick(); // VERIFYING -> Finalizes verification with persisting hotspot -> IDLE (retry allowed)
    TEST_ASSERT_EQUAL(AppState::IDLE, app.getState());

    // 5. Backend verification assertion:
    // Failed wash + persisting hotspot -> Anomaly MUST remain OPEN with retry_pending = true!
    std::string anom_status = queryDB("SELECT status FROM anomaly_events LIMIT 1;");
    TEST_ASSERT_EQUAL_STRING("open", anom_status.c_str());

    std::string retry_pending = queryDB("SELECT retry_pending FROM anomaly_events LIMIT 1;");
    TEST_ASSERT_EQUAL_STRING("t", retry_pending.c_str());
}

int main(int argc, char** argv) {
    ensureTestSeedDataExists();

    UNITY_BEGIN();
    RUN_TEST(test_e2e_device_claim_and_configuration);
    RUN_TEST(test_e2e_full_cycle_scan_finalize_cleaning_verification);
    RUN_TEST(test_e2e_idempotency_telemetry_resend);
    RUN_TEST(test_e2e_interrupted_cleaning_and_retry_pending);
    int status = UNITY_END();

    cleanAllTestData();
    return status;
}
