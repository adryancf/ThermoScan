#include <unity.h>
#include "domain/panel_geometry.h"
#include "pinout.h"
#include <cmath>

void test_panel_geometry_total_length() {
    // Single panel 100 cm, 0 spacing
    float len1 = domain::calculateTotalStringLength(1, 100.0f, 0.0f);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 100.0f, len1);

    // 3 panels 100 cm, 2.0 cm spacing -> 3 * 100 + 2 * 2 = 304 cm
    float len3 = domain::calculateTotalStringLength(3, 100.0f, 2.0f);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 304.0f, len3);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 304.0f, domain::calculateTotalStringLengthCm(3, 100.0f, 2.0f));

    // Edge cases
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 0.0f, domain::calculateTotalStringLength(0, 100.0f, 2.0f));
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 0.0f, domain::calculateTotalStringLength(3, -10.0f, 2.0f));
}

void test_panel_geometry_bounds() {
    float start = 0.0f, end = 0.0f;

    // Panel 1: [0, 100]
    domain::getPanelBounds(1, 100.0f, 2.0f, start, end);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 0.0f, start);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 100.0f, end);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 0.0f, domain::getPanelStartCm(1, 100.0f, 2.0f));
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 100.0f, domain::getPanelEndCm(1, 100.0f, 2.0f));

    // Panel 2: [102, 202]
    domain::getPanelBounds(2, 100.0f, 2.0f, start, end);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 102.0f, start);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 202.0f, end);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 102.0f, domain::getPanelStartCm(2, 100.0f, 2.0f));
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 202.0f, domain::getPanelEndCm(2, 100.0f, 2.0f));

    // Panel 3: [204, 304]
    domain::getPanelBounds(3, 100.0f, 2.0f, start, end);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 204.0f, start);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 304.0f, end);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 204.0f, domain::getPanelStartCm(3, 100.0f, 2.0f));
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 304.0f, domain::getPanelEndCm(3, 100.0f, 2.0f));
}

void test_panel_geometry_resolve_positions() {
    // 3 panels of 100 cm, 2 cm gap
    // Point on Panel 1 at 25.0 cm
    auto p1 = domain::resolvePanelPosition(3, 100.0f, 2.0f, 25.0f);
    TEST_ASSERT_EQUAL_UINT8(1, p1.panel_index);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 25.0f, p1.local_x_cm);
    TEST_ASSERT_FALSE(p1.in_gap);
    TEST_ASSERT_TRUE(p1.within_bounds);

    // Point in Gap 1 at 101.0 cm (between 100 and 102)
    auto g1 = domain::resolvePanelPosition(3, 100.0f, 2.0f, 101.0f);
    TEST_ASSERT_EQUAL_UINT8(0, g1.panel_index);
    TEST_ASSERT_TRUE(g1.in_gap);
    TEST_ASSERT_TRUE(g1.within_bounds);
    TEST_ASSERT_TRUE(domain::isCoordinateInGap(3, 100.0f, 2.0f, 101.0f));

    // Point on Panel 2 at 150.0 cm -> local X = 150 - 102 = 48 cm
    auto p2 = domain::resolvePanelPosition(3, 100.0f, 2.0f, 150.0f);
    TEST_ASSERT_EQUAL_UINT8(2, p2.panel_index);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 48.0f, p2.local_x_cm);
    TEST_ASSERT_FALSE(p2.in_gap);

    // Point in Gap 2 at 203.0 cm
    TEST_ASSERT_TRUE(domain::isCoordinateInGap(3, 100.0f, 2.0f, 203.0f));

    // Boundary points
    auto b0 = domain::resolvePanelPosition(3, 100.0f, 2.0f, 0.0f);
    TEST_ASSERT_EQUAL_UINT8(1, b0.panel_index);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 0.0f, b0.local_x_cm);
    TEST_ASSERT_FALSE(b0.in_gap);

    auto b100 = domain::resolvePanelPosition(3, 100.0f, 2.0f, 100.0f);
    TEST_ASSERT_EQUAL_UINT8(1, b100.panel_index);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 100.0f, b100.local_x_cm);
    TEST_ASSERT_FALSE(b100.in_gap);

    auto b102 = domain::resolvePanelPosition(3, 100.0f, 2.0f, 102.0f);
    TEST_ASSERT_EQUAL_UINT8(2, b102.panel_index);
    TEST_ASSERT_FLOAT_WITHIN(1e-3f, 0.0f, b102.local_x_cm);
    TEST_ASSERT_FALSE(b102.in_gap);

    // Out of bounds
    auto out_left = domain::resolvePanelPosition(3, 100.0f, 2.0f, -5.0f);
    TEST_ASSERT_FALSE(out_left.within_bounds);

    auto out_right = domain::resolvePanelPosition(3, 100.0f, 2.0f, 310.0f);
    TEST_ASSERT_FALSE(out_right.within_bounds);
}

void test_ina219_fixed_address_mapping() {
    TEST_ASSERT_EQUAL_HEX8(0x40, getInaAddressForPanel(1));
    TEST_ASSERT_EQUAL_HEX8(0x41, getInaAddressForPanel(2));
    TEST_ASSERT_EQUAL_HEX8(0x42, getInaAddressForPanel(3));
    TEST_ASSERT_EQUAL_HEX8(0x00, getInaAddressForPanel(4));
    TEST_ASSERT_EQUAL_HEX8(0x00, getInaAddressForPanel(0));
    TEST_ASSERT_EQUAL_HEX8(0x00, getInaAddressForPanel(255));
}

int main(int argc, char** argv) {
    UNITY_BEGIN();
    RUN_TEST(test_panel_geometry_total_length);
    RUN_TEST(test_panel_geometry_bounds);
    RUN_TEST(test_panel_geometry_resolve_positions);
    RUN_TEST(test_ina219_fixed_address_mapping);
    return UNITY_END();
}
