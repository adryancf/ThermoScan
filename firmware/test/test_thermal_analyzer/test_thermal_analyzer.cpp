#include <unity.h>
#include <cmath>
#include <vector>
#include "domain/thermal_analyzer.h"
#include "pinout.h"

void setUp(void) {}
void tearDown(void) {}

void test_coordinate_transformation(void) {
    // Formula: X_global = X + (col / 32.0f) * 5.0f
    TEST_ASSERT_EQUAL_FLOAT(0.0f, ThermalAnalyzer::calculateGlobalX(0.0f, 0));
    TEST_ASSERT_EQUAL_FLOAT(3.125f, ThermalAnalyzer::calculateGlobalX(0.0f, 20));
    TEST_ASSERT_EQUAL_FLOAT(2.0f, ThermalAnalyzer::calculateGlobalX(2.0f, 0));
    TEST_ASSERT_EQUAL_FLOAT(3.09375f, ThermalAnalyzer::calculateGlobalX(2.0f, 7));
    TEST_ASSERT_EQUAL_FLOAT(10.0f + (31.0f / 32.0f) * 5.0f, ThermalAnalyzer::calculateGlobalX(10.0f, 31));
}

void test_baseline_calculation_odd_and_even(void) {
    ThermalAnalyzer analyzer;

    // Odd number of valid pixels: 5 pixels
    ScanAcquisition acq_odd;
    acq_odd.valid = true;
    acq_odd.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq_odd.frame.pixels[i] = -50.0f; // invalid by default
    }
    // Set 5 valid pixels: 20, 22, 25, 29, 31 -> median should be 25.0
    acq_odd.frame.pixels[0] = 20.0f;
    acq_odd.frame.pixels[1] = 22.0f;
    acq_odd.frame.pixels[2] = 25.0f;
    acq_odd.frame.pixels[3] = 29.0f;
    acq_odd.frame.pixels[4] = 31.0f;

    std::vector<ScanAcquisition> scan_odd = {acq_odd};
    float baseline_odd = analyzer.calculateBaseline(scan_odd);
    TEST_ASSERT_EQUAL_FLOAT(25.0f, baseline_odd);

    // Even number of valid pixels: 4 pixels: 20, 22, 28, 30 -> median (22 + 28) / 2 = 25.0
    ScanAcquisition acq_even;
    acq_even.valid = true;
    acq_even.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq_even.frame.pixels[i] = -50.0f;
    }
    acq_even.frame.pixels[0] = 20.0f;
    acq_even.frame.pixels[1] = 22.0f;
    acq_even.frame.pixels[2] = 28.0f;
    acq_even.frame.pixels[3] = 30.0f;

    std::vector<ScanAcquisition> scan_even = {acq_even};
    float baseline_even = analyzer.calculateBaseline(scan_even);
    TEST_ASSERT_EQUAL_FLOAT(25.0f, baseline_even);
}

void test_baseline_discards_nan_and_out_of_range(void) {
    ThermalAnalyzer analyzer;

    ScanAcquisition acq;
    acq.valid = true;
    acq.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq.frame.pixels[i] = 0.0f / 0.0f; // NaN
    }

    // Insert invalid temperatures and 3 valid ones: 24.0, 25.0, 26.0
    acq.frame.pixels[0] = -40.0f;  // boundary invalid (<= -40.0)
    acq.frame.pixels[1] = -55.0f;  // out of range
    acq.frame.pixels[2] = 350.0f;  // out of range (> 300.0)
    acq.frame.pixels[3] = 24.0f;   // valid
    acq.frame.pixels[4] = 25.0f;   // valid (median)
    acq.frame.pixels[5] = 26.0f;   // valid

    std::vector<ScanAcquisition> acquisitions = {acq};
    float baseline = analyzer.calculateBaseline(acquisitions);
    TEST_ASSERT_EQUAL_FLOAT(25.0f, baseline);
}

void test_candidate_detection_threshold(void) {
    ThermalAnalyzer analyzer;

    ScanAcquisition acq;
    acq.x_position_cm = 0.0f;
    acq.valid = true;
    acq.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq.frame.pixels[i] = 25.0f; // baseline
    }

    const float baseline = 25.0f;
    // HOTSPOT_THRESHOLD_DELTA_C = 10.0f -> candidate threshold = 35.0f

    // Row 5, Col 10: 34.9f -> NOT candidate (< 35.0f)
    acq.frame.pixels[5 * 32 + 10] = 34.9f;

    // Row 5, Col 20: 35.0f -> Candidate (>= 35.0f)
    acq.frame.pixels[5 * 32 + 20] = 35.0f;

    // Row 8, Col 15: 42.0f -> Candidate (>= 35.0f)
    acq.frame.pixels[8 * 32 + 15] = 42.0f;

    auto candidates = analyzer.findCandidates(acq, baseline);
    TEST_ASSERT_EQUAL_UINT32(2, candidates.size());

    TEST_ASSERT_EQUAL_INT(20, candidates[0].col);
    TEST_ASSERT_EQUAL_INT(5, candidates[0].row);
    TEST_ASSERT_EQUAL_FLOAT(35.0f, candidates[0].temp_c);

    TEST_ASSERT_EQUAL_INT(15, candidates[1].col);
    TEST_ASSERT_EQUAL_INT(8, candidates[1].row);
    TEST_ASSERT_EQUAL_FLOAT(42.0f, candidates[1].temp_c);
}

void test_consecutive_spatial_confirmation(void) {
    ThermalAnalyzer analyzer;

    // Simulate 2 consecutive acquisitions along the rail:
    // Step size = 2.0 cm, FOV = 5.0 cm (60% overlap = 3.0 cm)
    // Acq 0 at X = 0.0 cm
    // Acq 1 at X = 2.0 cm
    ScanAcquisition acq0;
    acq0.x_position_cm = 0.0f;
    acq0.valid = true;
    acq0.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq0.frame.pixels[i] = 25.0f;
    }

    ScanAcquisition acq1;
    acq1.x_position_cm = 2.0f;
    acq1.valid = true;
    acq1.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq1.frame.pixels[i] = 25.0f;
    }

    // Place hotspot on physical rail at X ~ 3.1 cm, row 10:
    // In Acq 0 (X=0.0): col 20 gives X_global = 0.0 + (20/32)*5.0 = 3.125 cm
    acq0.frame.pixels[10 * 32 + 20] = 45.0f;

    // In Acq 1 (X=2.0): col 7 gives X_global = 2.0 + (7/32)*5.0 = 3.09375 cm
    // Spatial difference = |3.125 - 3.09375| = 0.03125 cm (< 0.5 cm tolerance)
    acq1.frame.pixels[10 * 32 + 7] = 47.5f;

    std::vector<ScanAcquisition> scan = {acq0, acq1};
    auto hotspots = analyzer.analyzeScan(scan);

    // Exactly 1 confirmed hotspot event
    TEST_ASSERT_EQUAL_UINT32(1, hotspots.size());
    TEST_ASSERT_TRUE(hotspots[0].confirmed);
    TEST_ASSERT_EQUAL_INT(10, hotspots[0].row);
    TEST_ASSERT_EQUAL_FLOAT(47.5f, hotspots[0].max_temp_c);
    TEST_ASSERT_FLOAT_WITHIN(0.1f, 3.11f, hotspots[0].target_x_cm);
}

void test_rejection_of_isolated_single_frame_false_positive(void) {
    ThermalAnalyzer analyzer;

    // Acq 0 at X = 0.0 cm has an isolated hot pixel (e.g. reflection / sensor glitch)
    ScanAcquisition acq0;
    acq0.x_position_cm = 0.0f;
    acq0.valid = true;
    acq0.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq0.frame.pixels[i] = 25.0f;
    }
    acq0.frame.pixels[10 * 32 + 20] = 48.0f; // Isolated hot pixel

    // Acq 1 at X = 2.0 cm is clean (all baseline 25.0°C)
    ScanAcquisition acq1;
    acq1.x_position_cm = 2.0f;
    acq1.valid = true;
    acq1.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq1.frame.pixels[i] = 25.0f;
    }

    std::vector<ScanAcquisition> scan = {acq0, acq1};

    // When querying confirmed hotspots only (default), isolated candidate is rejected!
    auto confirmed_hotspots = analyzer.analyzeScan(scan, 0.5f, true);
    TEST_ASSERT_EQUAL_UINT32(0, confirmed_hotspots.size());

    // When querying all candidates, it is returned with confirmed == false
    auto all_hotspots = analyzer.analyzeScan(scan, 0.5f, false);
    TEST_ASSERT_EQUAL_UINT32(1, all_hotspots.size());
    TEST_ASSERT_FALSE(all_hotspots[0].confirmed);
    TEST_ASSERT_EQUAL_FLOAT(48.0f, all_hotspots[0].max_temp_c);
}

void test_discard_invalid_pixels_in_overlap_region(void) {
    ThermalAnalyzer analyzer;

    // Acq 0 at X = 0.0 cm has a candidate at row 10, col 20 (X_global = 3.125 cm)
    ScanAcquisition acq0;
    acq0.x_position_cm = 0.0f;
    acq0.valid = true;
    acq0.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq0.frame.pixels[i] = 25.0f;
    }
    acq0.frame.pixels[10 * 32 + 20] = 45.0f;

    // Acq 1 at X = 2.0 cm has NaN at row 10, col 7 (overlap area)
    ScanAcquisition acq1;
    acq1.x_position_cm = 2.0f;
    acq1.valid = true;
    acq1.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq1.frame.pixels[i] = 25.0f;
    }
    acq1.frame.pixels[10 * 32 + 7] = 0.0f / 0.0f; // NaN in matching overlap pixel!

    std::vector<ScanAcquisition> scan = {acq0, acq1};

    // Invalid pixels in overlap CANNOT confirm anomaly alone!
    auto hotspots = analyzer.analyzeScan(scan, 0.5f, true);
    TEST_ASSERT_EQUAL_UINT32(0, hotspots.size());
}

int main(int argc, char **argv) {
    UNITY_BEGIN();
    RUN_TEST(test_coordinate_transformation);
    RUN_TEST(test_baseline_calculation_odd_and_even);
    RUN_TEST(test_baseline_discards_nan_and_out_of_range);
    RUN_TEST(test_candidate_detection_threshold);
    RUN_TEST(test_consecutive_spatial_confirmation);
    RUN_TEST(test_rejection_of_isolated_single_frame_false_positive);
    RUN_TEST(test_discard_invalid_pixels_in_overlap_region);
    return UNITY_END();
}
