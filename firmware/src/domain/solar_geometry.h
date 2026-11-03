#ifndef THERMOSCAN_DOMAIN_SOLAR_GEOMETRY_H
#define THERMOSCAN_DOMAIN_SOLAR_GEOMETRY_H

#include <cstdint>

namespace domain {

/**
 * @brief Calculates solar elevation angle above the local horizon in degrees.
 *
 * Implements standard NOAA solar position equations using epoch timestamp,
 * local latitude and longitude.
 *
 * @param latitude Geographic latitude in degrees (-90 to +90, North is positive).
 * @param longitude Geographic longitude in degrees (-180 to +180, East is positive).
 * @param epoch_seconds POSIX timestamp (seconds since 1970-01-01 00:00:00 UTC).
 * @return Solar elevation angle in degrees (-90.0° to +90.0°).
 */
float calculateSolarElevationDeg(float latitude, float longitude, uint32_t epoch_seconds);

/**
 * @brief Computes cosine score (cos theta) representing direct irradiance factor on tilted panel.
 *
 * @param latitude Geographic latitude in degrees.
 * @param longitude Geographic longitude in degrees.
 * @param azimuth Panel orientation azimuth in degrees (0° = North, 90° = East, 180° = South, 270° = West).
 * @param tilt Panel tilt angle in degrees from horizontal (0° = flat/horizontal).
 * @param epoch_seconds POSIX timestamp in seconds.
 * @return Cosine of angle of incidence clamped to [0.0, 1.0].
 */
float calculateCosineScore(float latitude,
                           float longitude,
                           float azimuth,
                           float tilt,
                           uint32_t epoch_seconds);

/**
 * @brief Determines if the current solar window satisfies minimum elevation requirements
 * for reliable thermal imaging inspection.
 *
 * @param latitude Geographic latitude in degrees.
 * @param longitude Geographic longitude in degrees.
 * @param azimuth Panel orientation azimuth in degrees.
 * @param tilt Panel tilt angle in degrees.
 * @param min_solar_angle Minimum required solar elevation in degrees (e.g. 30.0°).
 * @param epoch_seconds POSIX timestamp in seconds.
 * @return true if solar elevation is >= min_solar_angle, false otherwise.
 */
bool isSolarWindowValid(float latitude,
                        float longitude,
                        float azimuth,
                        float tilt,
                        float min_solar_angle,
                        uint32_t epoch_seconds);

} // namespace domain

// Global alias for compatibility
using domain::calculateSolarElevationDeg;
using domain::calculateCosineScore;
using domain::isSolarWindowValid;

#endif // THERMOSCAN_DOMAIN_SOLAR_GEOMETRY_H
