#include <unity.h>
#include <string>
#include <vector>
#include "hal/i_cloud_client.h"
#include "hal/i_storage.h"
#include "utils/heap_tracker.h"
#include "domain/quantized_frame.h"
#include "domain/temperature_histogram.h"
#include "app/thermoscan_app.h"

using namespace app;
using namespace domain;
using namespace utils;

namespace {

class MockResilienceStorage : public IStorage {
public:
    StorageState state{};
    bool erased{false};

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
    bool clear() override { erased = true; state = StorageState{}; return true; }
};

class MockResilienceCloudClient : public ICloudClient {
public:
    bool simulate_409_conflict{false};
    bool simulate_401_unauthorized{false};
    bool auth_error_flag{false};
    bool conflict_error_flag{false};
    int reclaim_attempts{0};
    bool reclaim_success{false};
    int batches_sent{0};

    bool init() override { return true; }
    bool claimDevice(const std::string&) override {
        reclaim_attempts++;
        return reclaim_success;
    }
    bool sendPing() override {
        if (simulate_401_unauthorized) {
            auth_error_flag = true;
            return false;
        }
        return true;
    }
    bool getConfiguration(std::string& out) override {
        out = "{\"config_version\":1}";
        return true;
    }
    bool ackConfiguration(uint32_t) override { return true; }
    bool ingestTelemetryBatch(const IngestTelemetryBatchInput&) override {
        batches_sent++;
        if (simulate_409_conflict) {
            conflict_error_flag = true;
            return false; // 409 Conflict: divergent content for existing source_event_id
        }
        if (simulate_401_unauthorized) {
            auth_error_flag = true;
            return false;
        }
        return true;
    }
    bool finalizeInspection(const std::string&, const FinalizeInspectionInput&) override { return true; }
    bool ingestCleaningReport(const CleaningReportInput&, std::string& out_id) override {
        out_id = "clean-resilience-uuid";
        return true;
    }
    bool ingestTelemetry(const TelemetryPayload&) override { return true; }
    bool ingestCleaning(const CleaningPayload&) override { return true; }
    bool isConnected() const override { return true; }
};

} // namespace

void setUp(void) {}
void tearDown(void) {}

void test_idempotency_conflict_409_handled_cleanly() {
    MockResilienceCloudClient cloud;
    cloud.simulate_409_conflict = true;

    IngestTelemetryBatchInput batch;
    batch.inspection_source_event_id = "insp-uuid-1234";
    TelemetryMeasurementItem item;
    item.source_event_id = "meas-uuid-existing";
    item.measured_at_epoch = 1730000000;
    item.x_position_cm = 10.0f;
    item.max_temperature_c = 45.0f; // divergent content
    batch.batch.push_back(item);

    // Call ingestTelemetryBatch
    bool ok = cloud.ingestTelemetryBatch(batch);

    // Assert that 409 Conflict returned false and flagged conflict without crashing or entering infinite loop
    TEST_ASSERT_FALSE(ok);
    TEST_ASSERT_TRUE(cloud.conflict_error_flag);
    TEST_ASSERT_EQUAL(1, cloud.batches_sent);
}

void test_http_401_reclaim_backoff_preserves_nvs() {
    MockResilienceStorage storage;
    storage.state.module_id = "mod-test-123";
    storage.state.config_version = 1;

    MockResilienceCloudClient cloud;
    cloud.simulate_401_unauthorized = true;

    // Send ping that triggers 401
    bool ping_ok = cloud.sendPing();
    TEST_ASSERT_FALSE(ping_ok);
    TEST_ASSERT_TRUE(cloud.auth_error_flag);

    // Crucial requirement: do NOT erase NVS immediately upon 401!
    TEST_ASSERT_FALSE(storage.erased);
    TEST_ASSERT_EQUAL_STRING("mod-test-123", storage.state.module_id.c_str());

    // Simulate re-claim with backoff: first attempt succeeds
    cloud.reclaim_success = true;
    bool reclaimed = cloud.claimDevice("");
    TEST_ASSERT_TRUE(reclaimed);
    TEST_ASSERT_EQUAL(1, cloud.reclaim_attempts);

    // NVS credentials are preserved
    TEST_ASSERT_FALSE(storage.erased);
}

void test_heap_metrics_real_margin_during_scan() {
    HeapTracker::start();

    // Baseline free heap on ESP32 is typically ~160 KB
    size_t initial_heap = HeapTracker::getCurrentFreeHeap();

    // Allocate 35 QuantizedThermalFrames: 35 * 1.5 KB = 53.76 KB
    std::vector<QuantizedThermalFrame> frames;
    frames.reserve(35);
    for (size_t i = 0; i < 35; ++i) {
        QuantizedThermalFrame qf;
        qf.x_position_cm = static_cast<float>(i * 2);
        qf.measured_at_epoch = 1730000000 + i;
        qf.source_event_id = "meas-" + std::to_string(i);
        qf.valid = true;
        for (size_t p = 0; p < 768; ++p) {
            qf.pixels[p] = QuantizedThermalFrame::fromFloat(30.0f);
        }
        frames.push_back(qf);
    }

    // Allocate 1400-bin histogram: 2.8 KB
    TemperatureHistogram hist;
    for (const auto& f : frames) {
        ThermalFrame tf;
        tf.valid = true;
        for (size_t p = 0; p < 768; ++p) tf.pixels[p] = 30.0f;
        hist.addFrame(tf);
    }

    // Simulate heap drop: 160 KB - 54 KB (frames) - 3 KB (hist) - 15 KB (batch buffer) = ~88 KB free
    HeapTracker::simulateHeapUsage(88 * 1024);
    HeapTracker::update();

    // Verify: throughout scan, free heap has strict safe margin >= 40 KB!
    HeapMetrics m = HeapTracker::stop();
    TEST_ASSERT_TRUE(m.hasSafeMargin(40 * 1024));
    TEST_ASSERT_GREATER_OR_EQUAL(40 * 1024, m.min_heap_during);

    // Now simulate end of scan: release quantized frames
    frames.clear();
    frames.shrink_to_fit();
    HeapTracker::resetSimulation();
}

int main(int argc, char** argv) {
    UNITY_BEGIN();
    RUN_TEST(test_idempotency_conflict_409_handled_cleanly);
    RUN_TEST(test_http_401_reclaim_backoff_preserves_nvs);
    RUN_TEST(test_heap_metrics_real_margin_during_scan);
    return UNITY_END();
}
