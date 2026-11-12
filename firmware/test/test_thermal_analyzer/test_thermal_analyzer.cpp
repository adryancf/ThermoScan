#include <unity.h>
#include <cmath>
#include <vector>
#include "domain/thermal_analyzer.h"
#include "pinout.h"

using domain::QuantizedThermalFrame;

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
    // HOTSPOT_THRESHOLD_DELTA_C = 8.0f -> candidate threshold = 33.0f

    // Row 5, Col 10: 32.9f -> NOT candidate (< 33.0f)
    acq.frame.pixels[5 * 32 + 10] = 32.9f;

    // Row 5, Col 20: 33.0f -> Candidate (>= 33.0f)
    acq.frame.pixels[5 * 32 + 20] = 33.0f;

    // Row 8, Col 15: 42.0f -> Candidate (>= 33.0f)
    acq.frame.pixels[8 * 32 + 15] = 42.0f;

    auto candidates = analyzer.findCandidates(acq, baseline);
    TEST_ASSERT_EQUAL_UINT32(2, candidates.size());

    TEST_ASSERT_EQUAL_INT(20, candidates[0].col);
    TEST_ASSERT_EQUAL_INT(5, candidates[0].row);
    TEST_ASSERT_EQUAL_FLOAT(33.0f, candidates[0].temp_c);

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
    acq0.frame.pixels[10 * 32 + 20] = 38.0f; // Isolated hot pixel (delta = 13.0 C, non-critical)

    // Acq 1 at X = 2.0 cm is clean (all baseline 25.0°C)
    ScanAcquisition acq1;
    acq1.x_position_cm = 2.0f;
    acq1.valid = true;
    acq1.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq1.frame.pixels[i] = 25.0f;
    }

    // Acq 2 at X = 4.0 cm is clean (all baseline 25.0°C)
    ScanAcquisition acq2;
    acq2.x_position_cm = 4.0f;
    acq2.valid = true;
    acq2.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq2.frame.pixels[i] = 25.0f;
    }

    std::vector<ScanAcquisition> scan = {acq0, acq1, acq2};

    // When querying confirmed hotspots only (default), isolated non-critical candidate is rejected!
    auto confirmed_hotspots = analyzer.analyzeScan(scan, 0.5f, true);
    TEST_ASSERT_EQUAL_UINT32(0, confirmed_hotspots.size());

    // When querying all candidates, it is returned with confirmed == false
    auto all_hotspots = analyzer.analyzeScan(scan, 0.5f, false);
    TEST_ASSERT_EQUAL_UINT32(1, all_hotspots.size());
    TEST_ASSERT_FALSE(all_hotspots[0].confirmed);
    TEST_ASSERT_EQUAL_FLOAT(38.0f, all_hotspots[0].max_temp_c);
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
    acq0.frame.pixels[10 * 32 + 20] = 38.0f; // non-critical delta 13 C

    // Acq 1 at X = 2.0 cm has NaN at row 10, col 7 (overlap area)
    ScanAcquisition acq1;
    acq1.x_position_cm = 2.0f;
    acq1.valid = true;
    acq1.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq1.frame.pixels[i] = 25.0f;
    }
    acq1.frame.pixels[10 * 32 + 7] = 0.0f / 0.0f; // NaN in matching overlap pixel!

    ScanAcquisition acq2;
    acq2.x_position_cm = 4.0f;
    acq2.valid = true;
    acq2.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq2.frame.pixels[i] = 25.0f;
    }

    std::vector<ScanAcquisition> scan = {acq0, acq1, acq2};

    // Invalid pixels in overlap CANNOT confirm anomaly alone!
    auto hotspots = analyzer.analyzeScan(scan, 0.5f, true);
    TEST_ASSERT_EQUAL_UINT32(0, hotspots.size());
}

void test_spatial_tolerance_exact_limit(void) {
    ThermalAnalyzer analyzer;

    ScanAcquisition acq0;
    acq0.x_position_cm = 0.0f;
    acq0.valid = true;
    acq0.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq0.frame.pixels[i] = 25.0f;
    // Acq 0 (X=0.0): col 20 -> X_global = 0.0 + (20/32)*5.0 = 3.125 cm
    acq0.frame.pixels[10 * 32 + 20] = 38.0f;

    ScanAcquisition acq1;
    acq1.x_position_cm = 2.0f;
    acq1.valid = true;
    acq1.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq1.frame.pixels[i] = 25.0f;
    // Acq 1 (X=2.0): col 10 -> X_global = 2.0 + (10/32)*5.0 = 3.5625 cm
    // Difference = 3.5625 - 3.125 = 0.4375 cm
    acq1.frame.pixels[10 * 32 + 10] = 38.0f;

    std::vector<ScanAcquisition> scan = {acq0, acq1};

    // When tolerance is set EXACTLY to 0.4375f, difference <= tolerance is satisfied (exact boundary condition)
    auto confirmed = analyzer.analyzeScan(scan, 0.4375f, true);
    TEST_ASSERT_EQUAL_UINT32(1, confirmed.size());
    TEST_ASSERT_TRUE(confirmed[0].confirmed);
}

void test_spatial_tolerance_above_limit(void) {
    ThermalAnalyzer analyzer;

    ScanAcquisition acq0;
    acq0.x_position_cm = 0.0f;
    acq0.valid = true;
    acq0.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq0.frame.pixels[i] = 25.0f;
    // Acq 0 (X=0.0): col 20 -> X_global = 3.125 cm
    acq0.frame.pixels[10 * 32 + 20] = 38.0f;

    ScanAcquisition acq1;
    acq1.x_position_cm = 2.0f;
    acq1.valid = true;
    acq1.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq1.frame.pixels[i] = 25.0f;
    // Acq 1 (X=2.0): col 15 -> X_global = 2.0 + (15/32)*5.0 = 4.34375 cm
    // Difference = |4.34375 - 3.125| = 1.21875 cm (> default 0.8 cm tolerance)
    acq1.frame.pixels[10 * 32 + 15] = 38.0f;

    ScanAcquisition acq2;
    acq2.x_position_cm = 4.0f;
    acq2.valid = true;
    acq2.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq2.frame.pixels[i] = 25.0f;

    std::vector<ScanAcquisition> scan = {acq0, acq1, acq2};

    // With default tolerance (0.8 cm), difference of 1.21875 cm exceeds limit -> REJECTED
    auto confirmed = analyzer.analyzeScan(scan, SPATIAL_TOLERANCE_CM, true);
    TEST_ASSERT_EQUAL_UINT32(0, confirmed.size());
}

void test_multiple_hot_pixels_cluster(void) {
    ThermalAnalyzer analyzer;

    ScanAcquisition acq0;
    acq0.x_position_cm = 0.0f;
    acq0.valid = true;
    acq0.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq0.frame.pixels[i] = 25.0f;
    // Multi-pixel hotspot cluster on row 8 (cols 18, 19, 20) with peak 52.0°C
    acq0.frame.pixels[8 * 32 + 18] = 40.0f;
    acq0.frame.pixels[8 * 32 + 19] = 52.0f; // Peak
    acq0.frame.pixels[8 * 32 + 20] = 44.0f;

    ScanAcquisition acq1;
    acq1.x_position_cm = 2.0f;
    acq1.valid = true;
    acq1.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq1.frame.pixels[i] = 25.0f;
    // Matching cluster in overlapping area on row 8 (cols 6, 7)
    acq1.frame.pixels[8 * 32 + 6] = 50.0f;
    acq1.frame.pixels[8 * 32 + 7] = 43.0f;

    std::vector<ScanAcquisition> scan = {acq0, acq1};
    auto confirmed = analyzer.analyzeScan(scan, SPATIAL_TOLERANCE_CM, true);

    TEST_ASSERT_TRUE(confirmed.size() >= 1);
    TEST_ASSERT_EQUAL_INT(8, confirmed[0].row);
    // Peak temperature captured
    TEST_ASSERT_TRUE(confirmed[0].max_temp_c >= 50.0f);
}

void test_two_distinct_nearby_anomalies(void) {
    ThermalAnalyzer analyzer;

    ScanAcquisition acq0;
    acq0.x_position_cm = 0.0f;
    acq0.valid = true;
    acq0.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq0.frame.pixels[i] = 25.0f;
    // Anomaly 1: row 5, col 19 (X_global = 2.96875 cm)
    acq0.frame.pixels[5 * 32 + 19] = 45.0f;
    // Anomaly 2: row 18, col 21 (X_global = 3.28125 cm)
    acq0.frame.pixels[18 * 32 + 21] = 49.0f;

    ScanAcquisition acq1;
    acq1.x_position_cm = 2.0f;
    acq1.valid = true;
    acq1.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq1.frame.pixels[i] = 25.0f;
    // Anomaly 1 match: row 5, col 6 (X_global = 2.0 + 6/32*5.0 = 2.9375 cm)
    acq1.frame.pixels[5 * 32 + 6] = 46.0f;
    // Anomaly 2 match: row 18, col 8 (X_global = 2.0 + 8/32*5.0 = 3.25 cm)
    acq1.frame.pixels[18 * 32 + 8] = 51.0f;

    std::vector<ScanAcquisition> scan = {acq0, acq1};
    auto confirmed = analyzer.analyzeScan(scan, SPATIAL_TOLERANCE_CM, true);

    // Exactly 2 distinct anomalies confirmed (one on row 5, one on row 18)
    TEST_ASSERT_EQUAL_UINT32(2, confirmed.size());
    bool found_row5 = false;
    bool found_row18 = false;
    for (const auto& ev : confirmed) {
        if (ev.row == 5) found_row5 = true;
        if (ev.row == 18) found_row18 = true;
    }
    TEST_ASSERT_TRUE(found_row5);
    TEST_ASSERT_TRUE(found_row18);
}

void test_custom_fov_calibration_parameter(void) {
    // Default analyzer uses strictly 5.0 cm FOV and 0.8 cm tolerance
    ThermalAnalyzer default_analyzer;
    TEST_ASSERT_EQUAL_FLOAT(5.0f, default_analyzer.getCalibratedFovWidthCm());
    TEST_ASSERT_EQUAL_FLOAT(0.8f, default_analyzer.getSpatialToleranceCm());
    TEST_ASSERT_EQUAL_FLOAT(2.5f, default_analyzer.calculateGlobalX(0.0f, 16));

    // Custom analyzer calibrated on bench with a 6.0 cm optical footprint and 0.4 cm tolerance
    ThermalAnalyzer bench_analyzer(6.0f, 0.4f);
    TEST_ASSERT_EQUAL_FLOAT(6.0f, bench_analyzer.getCalibratedFovWidthCm());
    TEST_ASSERT_EQUAL_FLOAT(0.4f, bench_analyzer.getSpatialToleranceCm());
    // Formula: 0.0 + (16 / 32) * 6.0 = 3.0 cm
    TEST_ASSERT_EQUAL_FLOAT(3.0f, bench_analyzer.calculateGlobalX(0.0f, 16, 6.0f));
}

void test_edge_candidate_clamping_to_panel_bounds_prevents_gap_projection(void) {
    ThermalAnalyzer analyzer;

    // Panel 1 bounds: [0.0, 20.0 cm]. Gap is (20.0, 22.0).
    // Last two acquisitions on Panel 1 at X = 18.0 cm and X = 20.0 cm.
    // A hot pixel near the right edge of the FOV (e.g. col 28 at X=18 -> 22.375 cm, col 16 at X=20 -> 22.5 cm)
    // would project into the gap if unclamped!
    ThermalFrame f0, f1;
    f0.valid = true;
    f1.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        f0.pixels[i] = 25.0f;
        f1.pixels[i] = 25.0f;
    }
    f0.pixels[6 * 32 + 28] = 48.0f; // Unclamped X_global = 18.0 + (28/32)*5 = 22.375 cm
    f1.pixels[6 * 32 + 16] = 49.0f; // Unclamped X_global = 20.0 + (16/32)*5 = 22.500 cm

    domain::QuantizedThermalFrame qf0, qf1;
    qf0.loadFromThermalFrame(f0, 18.0f, 1000, "meas-edge-0");
    qf1.loadFromThermalFrame(f1, 20.0f, 1001, "meas-edge-1");

    std::vector<domain::QuantizedThermalFrame> qframes = {qf0, qf1};

    // Analyze with Panel 1 bounds [0.0f, 20.0f] and panel_index = 1
    auto confirmed = analyzer.analyzeQuantizedScan(qframes, 25.0f, 0.5f, true, 0.0f, 20.0f, 1);

    TEST_ASSERT_EQUAL_UINT32(1, confirmed.size());
    TEST_ASSERT_EQUAL_UINT8(1, confirmed[0].panel_index);
    // Clamped strictly to panel_end_cm = 20.0 cm (never in gap > 20.0 cm!)
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 20.0f, confirmed[0].target_x_cm);
}

void test_line_matching_adjacent_rows(void) {
    ThermalAnalyzer analyzer;

    // Test row + 1 match (row 10 in acq0 and row 11 in acq1)
    ScanAcquisition acq0;
    acq0.x_position_cm = 0.0f;
    acq0.valid = true;
    acq0.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq0.frame.pixels[i] = 25.0f;
    // Row 10, col 20: X_global = 3.125 cm
    acq0.frame.pixels[10 * 32 + 20] = 38.0f;

    ScanAcquisition acq1;
    acq1.x_position_cm = 2.0f;
    acq1.valid = true;
    acq1.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq1.frame.pixels[i] = 25.0f;
    // Row 11 (row + 1), col 7: X_global = 2.0 + (7/32)*5.0 = 3.09375 cm (diff = 0.031 cm <= 0.8 cm)
    acq1.frame.pixels[11 * 32 + 7] = 39.0f;

    ScanAcquisition acq2;
    acq2.x_position_cm = 4.0f;
    acq2.valid = true;
    acq2.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq2.frame.pixels[i] = 25.0f;

    std::vector<ScanAcquisition> scan1 = {acq0, acq1, acq2};
    auto confirmed1 = analyzer.analyzeScan(scan1, SPATIAL_TOLERANCE_CM, true);
    TEST_ASSERT_EQUAL_UINT32(1, confirmed1.size());
    TEST_ASSERT_EQUAL_INT(11, confirmed1[0].row);
    TEST_ASSERT_EQUAL_FLOAT(39.0f, confirmed1[0].max_temp_c);

    // Test row - 1 match (row 10 in acq0 and row 9 in acq1)
    acq1.frame.pixels[11 * 32 + 7] = 25.0f;
    acq1.frame.pixels[9 * 32 + 7] = 39.0f;
    std::vector<ScanAcquisition> scan2 = {acq0, acq1, acq2};
    auto confirmed2 = analyzer.analyzeScan(scan2, SPATIAL_TOLERANCE_CM, true);
    TEST_ASSERT_EQUAL_UINT32(1, confirmed2.size());
    TEST_ASSERT_EQUAL_INT(9, confirmed2[0].row);

    // Test row difference > 1 (row 10 in acq0 and row 12 in acq1: diff = 2) -> REJECTED
    acq1.frame.pixels[9 * 32 + 7] = 25.0f;
    acq1.frame.pixels[12 * 32 + 7] = 39.0f;
    std::vector<ScanAcquisition> scan3 = {acq0, acq1, acq2};
    auto confirmed3 = analyzer.analyzeScan(scan3, SPATIAL_TOLERANCE_CM, true);
    TEST_ASSERT_EQUAL_UINT32(0, confirmed3.size());
}

void test_spatial_tolerance_0_8_cm_boundary(void) {
    ThermalAnalyzer analyzer;

    ScanAcquisition acq0;
    acq0.x_position_cm = 0.0f;
    acq0.valid = true;
    acq0.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq0.frame.pixels[i] = 25.0f;
    // Acq 0: col 20 -> X = 3.125 cm
    acq0.frame.pixels[10 * 32 + 20] = 38.0f;

    ScanAcquisition acq1;
    acq1.x_position_cm = 2.0f;
    acq1.valid = true;
    acq1.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq1.frame.pixels[i] = 25.0f;
    // Acq 1: col 11 -> X = 2.0 + (11/32)*5.0 = 3.71875 cm
    // Difference = 3.71875 - 3.125 = 0.59375 cm (<= default 0.8 cm tolerance)
    acq1.frame.pixels[10 * 32 + 11] = 38.5f;

    ScanAcquisition acq2;
    acq2.x_position_cm = 4.0f;
    acq2.valid = true;
    acq2.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq2.frame.pixels[i] = 25.0f;

    std::vector<ScanAcquisition> scan = {acq0, acq1, acq2};
    // Using default spatial tolerance (0.8 cm)
    auto confirmed = analyzer.analyzeScan(scan);
    TEST_ASSERT_EQUAL_UINT32(1, confirmed.size());
    TEST_ASSERT_TRUE(confirmed[0].confirmed);
}

void test_critical_hotspot_delta_and_max_temp(void) {
    ThermalAnalyzer analyzer;

    // Test 1: Isolated candidate with Delta T >= 20.0 C (CRITICAL_HOTSPOT_DELTA_C)
    ScanAcquisition acq0;
    acq0.x_position_cm = 0.0f;
    acq0.valid = true;
    acq0.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq0.frame.pixels[i] = 25.0f;
    // 46.0 C - 25.0 C = 21.0 C >= 20.0 C
    acq0.frame.pixels[10 * 32 + 20] = 46.0f;

    ScanAcquisition acq1;
    acq1.x_position_cm = 2.0f;
    acq1.valid = true;
    acq1.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq1.frame.pixels[i] = 25.0f;

    ScanAcquisition acq2;
    acq2.x_position_cm = 4.0f;
    acq2.valid = true;
    acq2.frame.valid = true;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) acq2.frame.pixels[i] = 25.0f;

    std::vector<ScanAcquisition> scan = {acq0, acq1, acq2};
    auto confirmed1 = analyzer.analyzeScan(scan, SPATIAL_TOLERANCE_CM, true);
    TEST_ASSERT_EQUAL_UINT32(1, confirmed1.size());
    TEST_ASSERT_TRUE(confirmed1[0].confirmed);
    TEST_ASSERT_EQUAL_FLOAT(46.0f, confirmed1[0].max_temp_c);

    // Test 2: Isolated candidate with T >= 65.0 C (CRITICAL_HOTSPOT_MAX_TEMP_C)
    // Baseline = 50.0 C, delta = 16.0 C (< 20.0 C), but T = 66.0 C (>= 65.0 C)
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        acq0.frame.pixels[i] = 50.0f;
        acq1.frame.pixels[i] = 50.0f;
        acq2.frame.pixels[i] = 50.0f;
    }
    acq0.frame.pixels[10 * 32 + 20] = 66.0f;
    std::vector<ScanAcquisition> scan2 = {acq0, acq1, acq2};
    auto confirmed2 = analyzer.analyzeScan(scan2, SPATIAL_TOLERANCE_CM, true);
    TEST_ASSERT_EQUAL_UINT32(1, confirmed2.size());
    TEST_ASSERT_TRUE(confirmed2[0].confirmed);
    TEST_ASSERT_EQUAL_FLOAT(66.0f, confirmed2[0].max_temp_c);
}

void test_border_hotspot_last_frame_and_confirming_event_ids(void) {
    ThermalAnalyzer analyzer;

    // Frame 0 at X = 0.0 cm (clean)
    QuantizedThermalFrame qf0;
    qf0.x_position_cm = 0.0f;
    qf0.source_event_id = "meas-frame-0";
    qf0.valid = true;
    for (size_t i = 0; i < 768; ++i) qf0.pixels[i] = QuantizedThermalFrame::fromFloat(25.0f);

    // Frame 1 at X = 2.0 cm (last frame of panel, hot pixel without posterior pair)
    QuantizedThermalFrame qf1;
    qf1.x_position_cm = 2.0f;
    qf1.source_event_id = "meas-frame-1";
    qf1.valid = true;
    for (size_t i = 0; i < 768; ++i) qf1.pixels[i] = QuantizedThermalFrame::fromFloat(25.0f);
    // Non-critical candidate (38.0 C -> delta 13 C < 20 C, T < 65 C)
    qf1.pixels[8 * 32 + 15] = QuantizedThermalFrame::fromFloat(38.0f);

    std::vector<QuantizedThermalFrame> qframes = {qf0, qf1};
    auto confirmed = analyzer.analyzeQuantizedScan(qframes, 25.0f, SPATIAL_TOLERANCE_CM, true);

    // Must be confirmed because it is in the last frame of the panel
    TEST_ASSERT_EQUAL_UINT32(1, confirmed.size());
    TEST_ASSERT_TRUE(confirmed[0].confirmed);
    TEST_ASSERT_EQUAL_INT(8, confirmed[0].row);
    TEST_ASSERT_FLOAT_WITHIN(0.1f, 38.0f, confirmed[0].max_temp_c);

    // Backend contract: len(confirming_event_ids) >= 2 with distinct IDs from this inspection
    TEST_ASSERT_TRUE(confirmed[0].confirming_event_ids.size() >= 2);
    TEST_ASSERT_EQUAL_STRING("meas-frame-1", confirmed[0].confirming_event_ids[0].c_str());
    TEST_ASSERT_EQUAL_STRING("meas-frame-0", confirmed[0].confirming_event_ids[1].c_str());
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
    RUN_TEST(test_spatial_tolerance_exact_limit);
    RUN_TEST(test_spatial_tolerance_above_limit);
    RUN_TEST(test_multiple_hot_pixels_cluster);
    RUN_TEST(test_two_distinct_nearby_anomalies);
    RUN_TEST(test_custom_fov_calibration_parameter);
    RUN_TEST(test_edge_candidate_clamping_to_panel_bounds_prevents_gap_projection);
    RUN_TEST(test_line_matching_adjacent_rows);
    RUN_TEST(test_spatial_tolerance_0_8_cm_boundary);
    RUN_TEST(test_critical_hotspot_delta_and_max_temp);
    RUN_TEST(test_border_hotspot_last_frame_and_confirming_event_ids);
    return UNITY_END();
}
