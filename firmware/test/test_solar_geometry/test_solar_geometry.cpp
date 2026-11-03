#include <unity.h>
#include "domain/solar_geometry.h"

void setUp(void) {}
void tearDown(void) {}

void test_solar_elevation_noon_vs_night(void) {
    // March 20, 2024 (Equinox)
    // 12:00:00 UTC = 1710936000 epoch seconds
    const uint32_t noon_epoch = 1710936000;
    // 00:00:00 UTC = 1710892800 epoch seconds
    const uint32_t midnight_epoch = 1710892800;

    const float lat = 0.0f; // Equator
    const float lon = 0.0f; // Prime Meridian

    float elev_noon = calculateSolarElevationDeg(lat, lon, noon_epoch);
    TEST_ASSERT_FLOAT_WITHIN(5.0f, 90.0f, elev_noon); // Near 90 degrees at solar noon at equator

    float elev_midnight = calculateSolarElevationDeg(lat, lon, midnight_epoch);
    TEST_ASSERT_TRUE(elev_midnight < 0.0f); // Well below horizon at night
}

void test_solar_window_validity(void) {
    const uint32_t noon_epoch = 1710936000;
    const uint32_t midnight_epoch = 1710892800;
    const float lat = -23.55f; // São Paulo
    const float lon = -46.63f;
    const float min_solar_angle = 30.0f;

    // Local noon in São Paulo is around 12:00 - (-46.63 * 4 / 60) ~ 15:00 UTC
    // March 20, 2024 15:00:00 UTC = 1710936000 + 3*3600 = 1710946800
    const uint32_t sp_noon_epoch = 1710946800;

    bool valid_noon = isSolarWindowValid(lat, lon, 0.0f, 20.0f, min_solar_angle, sp_noon_epoch);
    TEST_ASSERT_TRUE(valid_noon);

    bool valid_midnight = isSolarWindowValid(lat, lon, 0.0f, 20.0f, min_solar_angle, midnight_epoch);
    TEST_ASSERT_FALSE(valid_midnight);

    // If min_solar_angle is set unreasonably high (e.g. 85° in SP at equinox where max elevation ~66°):
    bool valid_impossible = isSolarWindowValid(lat, lon, 0.0f, 20.0f, 85.0f, sp_noon_epoch);
    TEST_ASSERT_FALSE(valid_impossible);
}

void test_cosine_score_properties(void) {
    const uint32_t midnight_epoch = 1710892800;
    const float lat = 0.0f;
    const float lon = 0.0f;

    // At night, cosine score must be strictly 0.0
    float score_night = calculateCosineScore(lat, lon, 0.0f, 0.0f, midnight_epoch);
    TEST_ASSERT_EQUAL_FLOAT(0.0f, score_night);

    // At solar noon at equator, flat panel (tilt=0) has normal facing straight up (zenith)
    // Sun is at elevation ~90°, so cos(incidence) should be ~1.0
    const uint32_t noon_epoch = 1710936000;
    float score_noon = calculateCosineScore(lat, lon, 0.0f, 0.0f, noon_epoch);
    TEST_ASSERT_FLOAT_WITHIN(0.05f, 1.0f, score_noon);
}

int main(int argc, char **argv) {
    UNITY_BEGIN();
    RUN_TEST(test_solar_elevation_noon_vs_night);
    RUN_TEST(test_solar_window_validity);
    RUN_TEST(test_cosine_score_properties);
    return UNITY_END();
}
