#ifndef THERMOSCAN_DOMAIN_TEMPERATURE_HISTOGRAM_H
#define THERMOSCAN_DOMAIN_TEMPERATURE_HISTOGRAM_H

#include <cstddef>
#include <cstdint>
#include <cmath>
#include "hal/i_thermal_camera.h"

namespace domain {

/**
 * @brief Discrete temperature histogram for streaming O(1) accumulation and
 * zero-heap median baseline calculation.
 *
 * SPECIFICATION & PIXEL RANGE DISTINCTION:
 * - General Sensor Pixel Validity: [-40.0 °C, 300.0 °C] (isValidPixel).
 * - Baseline Histogram Range: [-20.0 °C, 120.0 °C] with 0.1 °C resolution (1400 bins).
 * - Documented Distinction:
 *   Pixels outside the histogram range (e.g. < -20 °C or > 120 °C) participate in the
 *   inspection quantized matrix, but are NOT included in the baseline median calculation.
 *   This protects the baseline from spurious extremes without discarding valid pixels from the frame.
 */
class TemperatureHistogram {
public:
    static constexpr float HIST_MIN_TEMP_C = -20.0f;
    static constexpr float HIST_MAX_TEMP_C = 120.0f;
    static constexpr float RESOLUTION_C    = 0.1f;
    static constexpr size_t NUM_BINS       = 1400; // (120 - (-20)) / 0.1

    TemperatureHistogram();

    void reset();

    /**
     * @brief Adds a single pixel temperature reading.
     * Pixels outside [-20.0, 120.0] are ignored for baseline calculation.
     */
    void addPixel(float temp_c);

    /**
     * @brief Adds all valid pixels from a ThermalFrame.
     */
    void addFrame(const ThermalFrame& frame);

    /**
     * @brief Computes the median temperature of all accumulated valid pixels in the histogram.
     * Returns 0.0f if no pixels were recorded.
     */
    float calculateMedian() const;

    size_t getTotalCount() const { return total_count_; }

private:
    uint16_t bins_[NUM_BINS];
    size_t total_count_{0};
};

} // namespace domain

#endif // THERMOSCAN_DOMAIN_TEMPERATURE_HISTOGRAM_H

