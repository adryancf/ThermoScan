#ifndef THERMOSCAN_DOMAIN_QUANTIZED_FRAME_H
#define THERMOSCAN_DOMAIN_QUANTIZED_FRAME_H

#include <cstdint>
#include <cstddef>
#include <string>
#include <cmath>
#include "hal/i_thermal_camera.h"

namespace domain {

/**
 * @brief Memory-efficient quantized thermal acquisition.
 *
 * Quantizes 768 float pixels to 16-bit signed integers at 0.1 °C resolution.
 * Memory footprint per frame:
 *   768 * 2 bytes = 1,536 bytes (~1.5 KB) vs 3,072 bytes (float).
 *
 * 35 acquisitions occupy ~53.8 KB in RAM, comfortably fitting within
 * ESP32 free heap (~150 KB) without triggering Out-Of-Memory (OOM).
 *
 * Special values:
 * - INT16_MIN (-32768): Sentinela para pixel inválido, ausente ou NaN.
 */
struct QuantizedThermalFrame {
    static constexpr int16_t INVALID_PIXEL = -32768; // INT16_MIN
    static constexpr float SCALE           = 10.0f;   // 0.1 °C resolution
    static constexpr size_t PIXEL_COUNT    = 768;

    float x_position_cm{0.0f};
    uint32_t measured_at_epoch{0};
    std::string source_event_id{};
    bool valid{false};
    int16_t pixels[PIXEL_COUNT];

    static int16_t fromFloat(float temp_c) {
        if (std::isnan(temp_c) || temp_c < -40.0f || temp_c > 300.0f) {
            return INVALID_PIXEL;
        }
        return static_cast<int16_t>(std::round(temp_c * SCALE));
    }

    static float toFloat(int16_t q) {
        if (q == INVALID_PIXEL) {
            return NAN;
        }
        return static_cast<float>(q) / SCALE;
    }

    void loadFromThermalFrame(const ThermalFrame& frame,
                              float x_cm,
                              uint32_t measured_at,
                              const std::string& source_id) {
        x_position_cm = x_cm;
        measured_at_epoch = measured_at;
        source_event_id = source_id;
        valid = frame.valid;

        for (size_t i = 0; i < PIXEL_COUNT; ++i) {
            pixels[i] = fromFloat(frame.pixels[i]);
        }
    }
};

} // namespace domain

#endif // THERMOSCAN_DOMAIN_QUANTIZED_FRAME_H

