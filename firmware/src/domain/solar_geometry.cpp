#include "domain/solar_geometry.h"
#include <cmath>
#include <ctime>
#include <algorithm>

namespace domain {

namespace {

constexpr float PI_F = 3.14159265358979323846f;
constexpr float DEG_TO_RAD_F = PI_F / 180.0f;
constexpr float RAD_TO_DEG_F = 180.0f / PI_F;

template <typename T>
constexpr const T& clampValue(const T& v, const T& lo, const T& hi) {
    return (v < lo) ? lo : (hi < v) ? hi : v;
}

struct UtcDate {
    int year;
    int doy;    // 0-based day of year (0..365)
    float hour; // fractional hour (0.0 .. 23.999...)
};

UtcDate epochToUtcDate(uint32_t epoch_seconds) {
    const time_t raw_time = static_cast<time_t>(epoch_seconds);
    struct tm tm_info;
#if defined(_WIN32)
    gmtime_s(&tm_info, &raw_time);
#else
    gmtime_r(&raw_time, &tm_info);
#endif

    const float hour = static_cast<float>(tm_info.tm_hour) +
                       static_cast<float>(tm_info.tm_min) / 60.0f +
                       static_cast<float>(tm_info.tm_sec) / 3600.0f;

    return {tm_info.tm_year + 1900, tm_info.tm_yday, hour};
}

} // namespace

float calculateSolarElevationDeg(float latitude, float longitude, uint32_t epoch_seconds) {
    const UtcDate utc = epochToUtcDate(epoch_seconds);

    // Fractional year in radians
    const float gamma = (2.0f * PI_F / 365.25f) * (static_cast<float>(utc.doy) + (utc.hour - 12.0f) / 24.0f);

    // Equation of time in minutes (NOAA approximation)
    const float eot = 229.18f * (0.000075f +
                                 0.001868f * std::cos(gamma) -
                                 0.032077f * std::sin(gamma) -
                                 0.014615f * std::cos(2.0f * gamma) -
                                 0.040849f * std::sin(2.0f * gamma));

    // Solar declination in radians
    const float decl = 0.006918f -
                       0.399912f * std::cos(gamma) +
                       0.070257f * std::sin(gamma) -
                       0.006758f * std::cos(2.0f * gamma) +
                       0.000907f * std::sin(2.0f * gamma) -
                       0.002697f * std::cos(3.0f * gamma) +
                       0.00148f  * std::sin(3.0f * gamma);

    // Time offset in minutes
    const float time_offset = eot + 4.0f * longitude;

    // True solar time in minutes
    const float tst = utc.hour * 60.0f + time_offset;

    // Solar hour angle in degrees (-180° to +180°)
    float ha_deg = (tst / 4.0f) - 180.0f;
    while (ha_deg > 180.0f) ha_deg -= 360.0f;
    while (ha_deg < -180.0f) ha_deg += 360.0f;

    const float ha_rad = ha_deg * DEG_TO_RAD_F;
    const float lat_rad = latitude * DEG_TO_RAD_F;

    // Solar elevation angle sine
    float sin_elevation = std::sin(lat_rad) * std::sin(decl) +
                          std::cos(lat_rad) * std::cos(decl) * std::cos(ha_rad);

    // Clamp for numerical safety
    sin_elevation = clampValue(sin_elevation, -1.0f, 1.0f);

    return std::asin(sin_elevation) * RAD_TO_DEG_F;
}

float calculateCosineScore(float latitude,
                           float longitude,
                           float azimuth,
                           float tilt,
                           uint32_t epoch_seconds) {
    const float elevation_deg = calculateSolarElevationDeg(latitude, longitude, epoch_seconds);
    if (elevation_deg <= 0.0f) {
        return 0.0f; // Sun is below horizon
    }

    const float elevation_rad = elevation_deg * DEG_TO_RAD_F;
    const float tilt_rad = tilt * DEG_TO_RAD_F;

    // Utc date and angles for solar azimuth
    const UtcDate utc = epochToUtcDate(epoch_seconds);
    const float gamma = (2.0f * PI_F / 365.25f) * (static_cast<float>(utc.doy) + (utc.hour - 12.0f) / 24.0f);
    const float decl = 0.006918f - 0.399912f * std::cos(gamma) + 0.070257f * std::sin(gamma);
    const float eot = 229.18f * (0.000075f + 0.001868f * std::cos(gamma) - 0.032077f * std::sin(gamma));
    const float time_offset = eot + 4.0f * longitude;
    const float tst = utc.hour * 60.0f + time_offset;
    float ha_deg = (tst / 4.0f) - 180.0f;
    while (ha_deg > 180.0f) ha_deg -= 360.0f;
    while (ha_deg < -180.0f) ha_deg += 360.0f;
    const float ha_rad = ha_deg * DEG_TO_RAD_F;
    const float lat_rad = latitude * DEG_TO_RAD_F;

    // Solar azimuth calculation
    const float cos_zenith = std::sin(elevation_rad);
    const float sin_zenith = std::max(0.001f, std::cos(elevation_rad));
    float cos_azimuth = (std::sin(decl) * std::cos(lat_rad) - std::cos(decl) * std::sin(lat_rad) * std::cos(ha_rad)) / sin_zenith;
    cos_azimuth = clampValue(cos_azimuth, -1.0f, 1.0f);

    float solar_azimuth_rad = std::acos(cos_azimuth);
    if (ha_rad > 0.0f) {
        solar_azimuth_rad = 2.0f * PI_F - solar_azimuth_rad;
    }

    const float panel_azimuth_rad = azimuth * DEG_TO_RAD_F;

    // Angle of incidence cos(theta)
    const float cos_inc = std::sin(elevation_rad) * std::cos(tilt_rad) +
                          std::cos(elevation_rad) * std::sin(tilt_rad) * std::cos(solar_azimuth_rad - panel_azimuth_rad);

    return clampValue(cos_inc, 0.0f, 1.0f);
}

bool isSolarWindowValid(float latitude,
                        float longitude,
                        float azimuth,
                        float tilt,
                        float min_solar_angle,
                        uint32_t epoch_seconds) {
    (void)azimuth;
    (void)tilt;
    const float elevation = calculateSolarElevationDeg(latitude, longitude, epoch_seconds);
    return elevation >= min_solar_angle;
}

} // namespace domain
