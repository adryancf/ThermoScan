#ifndef THERMOSCAN_HAL_ESP32_CAPACITIVE_WATER_SENSOR_H
#define THERMOSCAN_HAL_ESP32_CAPACITIVE_WATER_SENSOR_H

#if defined(ARDUINO) || defined(ESP32)

#include <Arduino.h>
#include "pinout.h"
#include "hal/i_water_sensor.h"

namespace hal_esp32 {

/**
 * @brief Binary capacitive liquid level sensor driver for ESP32.
 * Connected to GPIO 34 (WATER_SENSOR_PIN).
 * Senses fluid availability in the spray reservoir.
 */
class CapacitiveWaterSensor : public IWaterSensor {
public:
    explicit CapacitiveWaterSensor(uint8_t pin = WATER_SENSOR_PIN, bool active_high = true);
    ~CapacitiveWaterSensor() override = default;

    bool init();
    WaterStatus readStatus() override;
    bool isWaterAvailable() override;

private:
    uint8_t pin_;
    bool active_high_;
    bool initialized_{false};
};

} // namespace hal_esp32

#endif // ARDUINO || ESP32

#endif // THERMOSCAN_HAL_ESP32_CAPACITIVE_WATER_SENSOR_H
