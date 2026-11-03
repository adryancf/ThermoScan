#ifndef THERMOSCAN_HAL_ESP32_INA219_METER_H
#define THERMOSCAN_HAL_ESP32_INA219_METER_H

#if defined(ARDUINO) || defined(ESP32)

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_INA219.h>
#include "hal/i_power_meter.h"

namespace hal_esp32 {

/**
 * @brief INA219 High-Side DC Voltage & Current Sensor driver.
 * Provides panel power telemetries over shared I2C bus.
 */
class Ina219Meter : public IPowerMeter {
public:
    explicit Ina219Meter(uint8_t i2c_addr = 0x40);
    ~Ina219Meter() override = default;

    bool init() override;
    bool readSnapshot(PowerSnapshot& out) override;

private:
    uint8_t i2c_addr_;
    Adafruit_INA219 ina219_;
    bool initialized_{false};
};

} // namespace hal_esp32

#endif // ARDUINO || ESP32

#endif // THERMOSCAN_HAL_ESP32_INA219_METER_H
