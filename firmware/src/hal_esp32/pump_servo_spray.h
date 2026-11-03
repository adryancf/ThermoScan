#ifndef THERMOSCAN_HAL_ESP32_PUMP_SERVO_SPRAY_H
#define THERMOSCAN_HAL_ESP32_PUMP_SERVO_SPRAY_H

#if defined(ARDUINO) || defined(ESP32)

#include <Arduino.h>
#include <ESP32Servo.h>
#include "pinout.h"
#include "hal/i_spray_actuator.h"
#include "hal/i_water_sensor.h"

namespace hal_esp32 {

/**
 * @brief Spray cleaning actuator HAL controlling the 12V pump MOSFET and nozzle servo.
 * Strict Fail-Safe: Pump is immediately forced to LOW upon power-up and construction.
 */
class PumpServoSpray : public ISprayActuator {
public:
    PumpServoSpray(uint8_t pump_pin = PUMP_MOSFET_PIN,
                   uint8_t servo_pin = SERVO_PWM_PIN,
                   IWaterSensor* water_sensor = nullptr);
    ~PumpServoSpray() override;

    bool init() override;
    bool setNozzleAngle(float angle_deg) override;
    bool startPump() override;
    void stopPump() override;
    bool isPumpActive() const override;

    void setWaterSensor(IWaterSensor* sensor);

private:
    uint8_t pump_pin_;
    uint8_t servo_pin_;
    IWaterSensor* water_sensor_{nullptr};

    Servo servo_;
    bool pump_active_{false};
    bool initialized_{false};
};

} // namespace hal_esp32

#endif // ARDUINO || ESP32

#endif // THERMOSCAN_HAL_ESP32_PUMP_SERVO_SPRAY_H
