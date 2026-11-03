#ifndef THERMOSCAN_HAL_ESP32_MLX90640_CAMERA_H
#define THERMOSCAN_HAL_ESP32_MLX90640_CAMERA_H

#if defined(ARDUINO) || defined(ESP32)

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_MLX90640.h>
#include "pinout.h"
#include "hal/i_thermal_camera.h"

namespace hal_esp32 {

/**
 * @brief MLX90640 32x24 Far-Infrared Thermal Camera HAL using Adafruit MLX90640 driver.
 * Reuses tested I2C configuration at 400kHz on address 0x33.
 */
class Mlx90640Camera : public IThermalCamera {
public:
    explicit Mlx90640Camera(uint8_t sda_pin = I2C_SDA_PIN,
                            uint8_t scl_pin = I2C_SCL_PIN,
                            uint8_t i2c_addr = 0x33);
    ~Mlx90640Camera() override = default;

    bool init() override;
    bool captureFrame(ThermalFrame& out) override;
    bool isHealthy() override;

private:
    uint8_t sda_pin_;
    uint8_t scl_pin_;
    uint8_t i2c_addr_;

    Adafruit_MLX90640 mlx_;
    bool initialized_{false};
};

} // namespace hal_esp32

#endif // ARDUINO || ESP32

#endif // THERMOSCAN_HAL_ESP32_MLX90640_CAMERA_H
