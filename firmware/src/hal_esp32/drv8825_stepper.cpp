#if defined(ARDUINO) || defined(ESP32)

#include "drv8825_stepper.h"
#include <cmath>

namespace hal_esp32 {

Drv8825Stepper::Drv8825Stepper(uint8_t step_pin,
                               uint8_t dir_pin,
                               uint8_t en_pin,
                               uint8_t limit_min_pin,
                               uint8_t limit_max_pin,
                               float steps_per_cm,
                               float home_offset_cm)
    : step_pin_(step_pin),
      dir_pin_(dir_pin),
      en_pin_(en_pin),
      limit_min_pin_(limit_min_pin),
      limit_max_pin_(limit_max_pin),
      steps_per_cm_(steps_per_cm),
      home_offset_cm_(home_offset_cm) {}

Drv8825Stepper::~Drv8825Stepper() {
    enableMotor(false);
}

bool Drv8825Stepper::init() {
    pinMode(step_pin_, OUTPUT);
    pinMode(dir_pin_, OUTPUT);
    pinMode(en_pin_, OUTPUT);
    pinMode(limit_min_pin_, INPUT_PULLUP);
    if (limit_max_pin_ != 255) {
        pinMode(limit_max_pin_, INPUT_PULLUP);
    }

    digitalWrite(step_pin_, LOW);
    digitalWrite(dir_pin_, STEPPER_DIR_TOWARDS_END);
    // Disable driver by default on boot to prevent coil heating
    enableMotor(false);

    initialized_ = true;
    return true;
}

void Drv8825Stepper::enableMotor(bool enable) {
    // DRV8825: EN is Active-LOW (LOW = Enabled, HIGH = Disabled)
    digitalWrite(en_pin_, enable ? LOW : HIGH);
}

bool Drv8825Stepper::isMinLimitReached() const {
    // Endstop triggered: reads active level 0 (LOW) when pressed
    return digitalRead(limit_min_pin_) == STEPPER_LIMIT_ACTIVE_VAL;
}

bool Drv8825Stepper::isMaxLimitReached() const {
    if (limit_max_pin_ == 255) return false;
    return digitalRead(limit_max_pin_) == STEPPER_LIMIT_ACTIVE_VAL;
}

bool Drv8825Stepper::isLimitReached() const {
    return isMinLimitReached();
}

bool Drv8825Stepper::checkLimitsIntegrity() {
    if (!initialized_) {
        init();
    }
    int state_min = digitalRead(limit_min_pin_);
    bool ok = (state_min == LOW || state_min == HIGH);
    if (limit_max_pin_ != 255) {
        int state_max = digitalRead(limit_max_pin_);
        ok &= (state_max == LOW || state_max == HIGH);
    }
    return ok;
}

void Drv8825Stepper::pulseStep(uint32_t delay_us) {
    digitalWrite(step_pin_, HIGH);
    delayMicroseconds(delay_us);
    digitalWrite(step_pin_, LOW);
    delayMicroseconds(delay_us);
}

bool Drv8825Stepper::home() {
    if (!initialized_) {
        init();
    }
    enableMotor(true);
    delay(15);

    // If home limit switch (GPIO 35) is already pressed on boot,
    // smoothly back off towards the end (DIR = LOW) until switch releases.
    if (isMinLimitReached()) {
        digitalWrite(dir_pin_, STEPPER_DIR_TOWARDS_END);
        const int maxReleaseSteps = static_cast<int>(3.0f * steps_per_cm_);
        for (int i = 0; i < maxReleaseSteps; ++i) {
            pulseStep(1500);
            if (!isMinLimitReached()) {
                // Back off a few extra steps to ensure mechanical clearance
                for (int j = 0; j < static_cast<int>(0.5f * steps_per_cm_); ++j) {
                    pulseStep(1500);
                }
                break;
            }
            if ((i % 50) == 0) {
                yield();
            }
        }
        delay(50);

        // If switch remains pressed after backing off, abort for safety
        if (isMinLimitReached()) {
            enableMotor(false);
            is_homed_ = false;
            return false;
        }
    }

    // 1. Move towards start (DIR = HIGH) until start limit switch triggers (GPIO 35)
    digitalWrite(dir_pin_, STEPPER_DIR_TOWARDS_START);
    const uint32_t maxHomingSteps = static_cast<uint32_t>(1000.0f * steps_per_cm_); // Fail-safe (10m)
    bool hitLimit = false;

    for (uint32_t step = 0; step < maxHomingSteps; ++step) {
        if (isMinLimitReached()) {
            // Mechanical debounce: wait 2ms and re-verify
            delayMicroseconds(2000);
            if (isMinLimitReached()) {
                hitLimit = true;
                break;
            }
        }
        pulseStep(STEPPER_SPEED_HOMING_US);
        if ((step % 50) == 0) {
            yield();
        }
    }

    if (!hitLimit) {
        enableMotor(false);
        is_homed_ = false;
        return false;
    }

    // Minimal stop delay (5 ms) for smooth direction reversal without perceptible lag
    delay(5);

    // 2. Advance exactly by the offset distance (STEPPER_HOME_OFFSET_CM = 7.0 cm)
    // towards the end (STEPPER_DIR_TOWARDS_END) to position the carriage at the start of the panel.
    const float offset_cm = (home_offset_cm_ > 0.0f) ? home_offset_cm_ : STEPPER_HOME_OFFSET_CM;
    if (offset_cm > 0.0f) {
        digitalWrite(dir_pin_, STEPPER_DIR_TOWARDS_END);
        delay(5);
        const uint32_t offsetSteps = static_cast<uint32_t>(offset_cm * steps_per_cm_ + 0.5f);
        for (uint32_t i = 0; i < offsetSteps; ++i) {
            if (isMaxLimitReached()) {
                enableMotor(false);
                is_homed_ = false;
                return false;
            }
            pulseStep(STEPPER_SPEED_HOMING_US);
            if ((i % 50) == 0) {
                yield();
            }
        }
        delay(20);
    }

    // Homing completed successfully: set work coordinate X = 0.0 cm
    current_x_cm_ = 0.0f;
    is_homed_ = true;
    enableMotor(false);
    return true;
}

void Drv8825Stepper::disableMotor() {
    enableMotor(false);
}

void Drv8825Stepper::emergencyStop() {
    enableMotor(false);
}

bool Drv8825Stepper::moveToXCm(float target_x_cm) {
    if (!initialized_) {
        init();
    }
    if (!checkLimitsIntegrity()) {
        return false;
    }

    if (target_x_cm < 0.0f) {
        target_x_cm = 0.0f;
    }

    float delta_cm = target_x_cm - current_x_cm_;
    if (std::abs(delta_cm) < 0.01f) {
        return true;
    }

    enableMotor(true);
    delay(5);

    // delta_cm > 0: advancing towards the end (+X -> STEPPER_DIR_TOWARDS_END / LOW)
    // delta_cm < 0: moving back towards start (-X -> STEPPER_DIR_TOWARDS_START / HIGH)
    bool movingTowardsEnd = (delta_cm > 0.0f);
    digitalWrite(dir_pin_, movingTowardsEnd ? STEPPER_DIR_TOWARDS_END : STEPPER_DIR_TOWARDS_START);

    uint32_t totalSteps = static_cast<uint32_t>(std::abs(delta_cm) * steps_per_cm_ + 0.5f);
    for (uint32_t step = 0; step < totalSteps; ++step) {
        // If moving towards start and start limit switch triggers (safety interlock)
        if (!movingTowardsEnd && isMinLimitReached()) {
            const float offset_cm = (home_offset_cm_ > 0.0f) ? home_offset_cm_ : STEPPER_HOME_OFFSET_CM;
            current_x_cm_ = (offset_cm > 0.0f) ? -offset_cm : 0.0f;
            enableMotor(false);
            return true;
        }
        // If moving towards end and end limit switch triggers (safety interlock)
        if (movingTowardsEnd && isMaxLimitReached()) {
            current_x_cm_ = current_x_cm_ + static_cast<float>(step) / steps_per_cm_;
            enableMotor(false);
            return true;
        }
        pulseStep(STEPPER_SPEED_NORMAL_US);
        if ((step % 50) == 0) {
            yield();
        }
    }

    current_x_cm_ = target_x_cm;
    enableMotor(false);
    return true;
}

float Drv8825Stepper::getXPositionCm() const {
    return current_x_cm_;
}

bool Drv8825Stepper::stepRelativeCm(float delta_cm) {
    return moveToXCm(current_x_cm_ + delta_cm);
}

} // namespace hal_esp32

#endif // ARDUINO || ESP32
