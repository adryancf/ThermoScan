#include <unity.h>
#include "domain/temperature_histogram.h"
#include "domain/quantized_frame.h"
#include "domain/thermal_analyzer.h"
#include "utils/heap_tracker.h"
#include "utils/uuid_generator.h"
#include <vector>
#include <cmath>
#include <algorithm>

using namespace domain;
using namespace utils;

void setUp(void) {}
void tearDown(void) {}

void test_histogram_basic_median() {
    TemperatureHistogram hist;

    // Add 100 pixels at 30.0 °C, 100 pixels at 40.0 °C
    for (int i = 0; i < 100; ++i) {
        hist.addPixel(30.0f);
        hist.addPixel(40.0f);
    }
    // Total 200 pixels -> median should be around 35.0 °C (or between 30 and 40)
    float median = hist.calculateMedian();
    TEST_ASSERT_FLOAT_WITHIN(1.0f, 35.0f, median);
}

void test_histogram_range_distinction() {
    TemperatureHistogram hist;

    // Add normal pixels in range [-20, 120]
    for (int i = 0; i < 50; ++i) {
        hist.addPixel(25.0f);
    }
    TEST_ASSERT_EQUAL(50, hist.getTotalCount());

    // Add pixels outside histogram range (documented requirement: participate in quantized frame,
    // but excluded from baseline histogram)
    hist.addPixel(-35.0f); // valid sensor pixel, outside histogram [-20, 120]
    hist.addPixel(150.0f); // valid sensor pixel, outside histogram [-20, 120]
    hist.addPixel(NAN);    // invalid pixel

    // Total count in histogram must remain 50
    TEST_ASSERT_EQUAL(50, hist.getTotalCount());
    TEST_ASSERT_FLOAT_WITHIN(0.2f, 25.0f, hist.calculateMedian());
}

void test_quantized_frame_conversion_and_size() {
    // Check exact size: 768 * 2 = 1,536 bytes
    QuantizedThermalFrame qf;
    TEST_ASSERT_EQUAL(1536, sizeof(qf.pixels));

    // Test conversion
    int16_t q1 = QuantizedThermalFrame::fromFloat(42.3f);
    TEST_ASSERT_EQUAL(423, q1);
    TEST_ASSERT_FLOAT_WITHIN(0.05f, 42.3f, QuantizedThermalFrame::toFloat(q1));

    // Test negative conversion
    int16_t q2 = QuantizedThermalFrame::fromFloat(-15.6f);
    TEST_ASSERT_EQUAL(-156, q2);
    TEST_ASSERT_FLOAT_WITHIN(0.05f, -15.6f, QuantizedThermalFrame::toFloat(q2));

    // Test out-of-range & NaN mapping to INVALID_PIXEL
    TEST_ASSERT_EQUAL(QuantizedThermalFrame::INVALID_PIXEL, QuantizedThermalFrame::fromFloat(NAN));
    TEST_ASSERT_EQUAL(QuantizedThermalFrame::INVALID_PIXEL, QuantizedThermalFrame::fromFloat(-45.0f));
    TEST_ASSERT_EQUAL(QuantizedThermalFrame::INVALID_PIXEL, QuantizedThermalFrame::fromFloat(350.0f));
}

void test_quantized_scan_spatial_confirmation_and_multiple_hotspots() {
    ThermalAnalyzer analyzer(5.0f, 0.5f);

    // Frame 0 at X = 10.0 cm
    QuantizedThermalFrame f0;
    f0.x_position_cm = 10.0f;
    f0.source_event_id = "meas-001";
    f0.valid = true;
    for (size_t i = 0; i < 768; ++i) f0.pixels[i] = QuantizedThermalFrame::fromFloat(30.0f);

    // Hotspot A at row 5, col 20
    // X_global = 10.0 + (20/32.0)*5.0 = 10.0 + 3.125 = 13.125 cm
    f0.pixels[5 * 32 + 20] = QuantizedThermalFrame::fromFloat(50.0f);

    // Hotspot B at row 12, col 10
    // X_global = 10.0 + (10/32.0)*5.0 = 10.0 + 1.5625 = 11.5625 cm
    f0.pixels[12 * 32 + 10] = QuantizedThermalFrame::fromFloat(55.0f);

    // Frame 1 at X = 12.0 cm (step = 2.0 cm, ~60% overlap)
    QuantizedThermalFrame f1;
    f1.x_position_cm = 12.0f;
    f1.source_event_id = "meas-002";
    f1.valid = true;
    for (size_t i = 0; i < 768; ++i) f1.pixels[i] = QuantizedThermalFrame::fromFloat(30.0f);

    // In Frame 1, Hotspot A is at X_global ~ 13.125 cm:
    // col = (13.125 - 12.0) / 5.0 * 32 = 1.125 / 5.0 * 32 = 7.2 -> col 7
    // X_global = 12.0 + (7/32)*5.0 = 13.09375 cm (diff = 0.031 cm <= 0.5 cm eff_tolerance)
    f1.pixels[5 * 32 + 7] = QuantizedThermalFrame::fromFloat(51.0f);

    // In Frame 1, Hotspot B is at X_global ~ 11.56 cm -> outside FOV of Frame 1 (starts at 12 cm)

    std::vector<QuantizedThermalFrame> frames = {f0, f1};
    float baseline = 30.0f; // candidate threshold = 40.0 °C

    auto events = analyzer.analyzeQuantizedScan(frames, baseline, 0.5f, true);

    // Hotspot A must be confirmed (consecutive spatial match)
    TEST_ASSERT_EQUAL(1, events.size());
    TEST_ASSERT_TRUE(events[0].confirmed);
    TEST_ASSERT_EQUAL(5, events[0].row);
    TEST_ASSERT_FLOAT_WITHIN(0.2f, 13.1f, events[0].target_x_cm);
    TEST_ASSERT_FLOAT_WITHIN(0.1f, 51.0f, events[0].max_temp_c);

    // Verify origin and confirming event IDs are tracked
    TEST_ASSERT_EQUAL_STRING("meas-001", events[0].origin_measurement_event_id.c_str());
    TEST_ASSERT_EQUAL(2, events[0].confirming_event_ids.size());
    TEST_ASSERT_EQUAL_STRING("meas-001", events[0].confirming_event_ids[0].c_str());
    TEST_ASSERT_EQUAL_STRING("meas-002", events[0].confirming_event_ids[1].c_str());
}

void test_heap_tracker_and_safe_margin() {
    HeapTracker::start();
    // Simulate 35 quantized frames allocation: 35 * 1.5 KB = ~54 KB
    // Starting free heap = 160 KB -> lowest free heap during scan = ~106 KB
    HeapTracker::simulateHeapUsage(106 * 1024);
    HeapMetrics m = HeapTracker::stop();

    TEST_ASSERT_TRUE(m.hasSafeMargin(40 * 1024)); // 40 KB required margin
    TEST_ASSERT_GREATER_OR_EQUAL(40 * 1024, m.min_heap_during);
    HeapTracker::resetSimulation();
}

void test_uuid_generator_format() {
    std::string uuid = generateUUIDv4();
    TEST_ASSERT_EQUAL(36, uuid.length());
    TEST_ASSERT_EQUAL('-', uuid[8]);
    TEST_ASSERT_EQUAL('-', uuid[13]);
    TEST_ASSERT_EQUAL('-', uuid[18]);
    TEST_ASSERT_EQUAL('-', uuid[23]);
    TEST_ASSERT_EQUAL('4', uuid[14]); // version 4
    char variant = uuid[19];
    TEST_ASSERT_TRUE(variant == '8' || variant == '9' || variant == 'a' || variant == 'b');
}

int main(int argc, char** argv) {
    UNITY_BEGIN();
    RUN_TEST(test_histogram_basic_median);
    RUN_TEST(test_histogram_range_distinction);
    RUN_TEST(test_quantized_frame_conversion_and_size);
    RUN_TEST(test_quantized_scan_spatial_confirmation_and_multiple_hotspots);
    RUN_TEST(test_heap_tracker_and_safe_margin);
    RUN_TEST(test_uuid_generator_format);
    return UNITY_END();
}

