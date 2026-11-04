#ifndef THERMOSCAN_HAL_ESP32_MLX90640_CAMERA_H
#define THERMOSCAN_HAL_ESP32_MLX90640_CAMERA_H

#if defined(ARDUINO) || defined(ESP32)

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_MLX90640.h>
#include <ESP32Servo.h>
#include "pinout.h"
#include "hal/i_thermal_camera.h"

namespace hal_esp32 {

/**
 * @brief MLX90640 32x24 Far-Infrared Thermal Camera HAL using Adafruit MLX90640 driver.
 * Reuses tested I2C configuration at 400kHz on address 0x33 and drives camera tilt servo.
 */
class Mlx90640Camera : public IThermalCamera {
public:
    explicit Mlx90640Camera(uint8_t sda_pin = I2C_SDA_PIN,
                            uint8_t scl_pin = I2C_SCL_PIN,
                            uint8_t i2c_addr = 0x33,
                            uint8_t servo_pin = CAMERA_SERVO_PWM_PIN);
    ~Mlx90640Camera() override;

    bool init() override;
    bool captureFrame(ThermalFrame& out) override;
    bool isHealthy() override;
    bool setTiltAngle(float angle_deg) override;
    float getTiltAngle() const override;

private:
    uint8_t sda_pin_;
    uint8_t scl_pin_;
    uint8_t i2c_addr_;
    uint8_t servo_pin_;

    Adafruit_MLX90640 mlx_;
    Servo servo_;
    float current_tilt_angle_{CAMERA_DEFAULT_ANGLE};
    bool initialized_{false};
};

} // namespace hal_esp32

#endif // ARDUINO || ESP32

#endif // THERMOSCAN_HAL_ESP32_MLX90640_CAMERA_H
