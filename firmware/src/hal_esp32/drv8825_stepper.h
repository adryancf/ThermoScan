#ifndef THERMOSCAN_HAL_ESP32_DRV8825_STEPPER_H
#define THERMOSCAN_HAL_ESP32_DRV8825_STEPPER_H

#if defined(ARDUINO) || defined(ESP32)

#include <Arduino.h>
#include "pinout.h"
#include "hal/i_motion_controller.h"

namespace hal_esp32 {

/**
 * @brief DRV8825 Stepper driver and linear axis controller with NC limit switch.
 * Controls linear carriage motion along the solar panel inspection rail.
 */
class Drv8825Stepper : public IMotionController {
public:
    Drv8825Stepper(uint8_t step_pin = STEPPER_STEP_PIN,
                   uint8_t dir_pin = STEPPER_DIR_PIN,
                   uint8_t en_pin = STEPPER_EN_PIN,
                   uint8_t limit_pin = STEPPER_LIMIT_NC_PIN,
                   float steps_per_cm = 50.0f);
    ~Drv8825Stepper() override;

    bool init() override;
    bool home() override;
    bool moveToXCm(float target_x_cm) override;
    float getXPositionCm() const override;
    bool checkLimitsIntegrity() override;

    // Helper functions
    bool stepRelativeCm(float delta_cm);
    void enableMotor(bool enable);
    bool isLimitReached() const;

private:
    uint8_t step_pin_;
    uint8_t dir_pin_;
    uint8_t en_pin_;
    uint8_t limit_pin_;
    float steps_per_cm_;

    float current_x_cm_{0.0f};
    bool is_homed_{false};
    bool initialized_{false};

    void pulseStep(uint32_t delay_us = 1000);
};

} // namespace hal_esp32

#endif // ARDUINO || ESP32

#endif // THERMOSCAN_HAL_ESP32_DRV8825_STEPPER_H
