#if defined(ARDUINO) || defined(ESP32)

#include "drv8825_stepper.h"
#include <cmath>

namespace hal_esp32 {

Drv8825Stepper::Drv8825Stepper(uint8_t step_pin,
                               uint8_t dir_pin,
                               uint8_t en_pin,
                               uint8_t limit_pin,
                               float steps_per_cm)
    : step_pin_(step_pin),
      dir_pin_(dir_pin),
      en_pin_(en_pin),
      limit_pin_(limit_pin),
      steps_per_cm_(steps_per_cm) {}

Drv8825Stepper::~Drv8825Stepper() {
    enableMotor(false);
}

bool Drv8825Stepper::init() {
    pinMode(step_pin_, OUTPUT);
    pinMode(dir_pin_, OUTPUT);
    pinMode(en_pin_, OUTPUT);
    pinMode(limit_pin_, INPUT_PULLUP);

    digitalWrite(step_pin_, LOW);
    digitalWrite(dir_pin_, LOW);
    // Disable driver by default on boot to prevent coil heating
    enableMotor(false);

    initialized_ = true;
    return true;
}

void Drv8825Stepper::enableMotor(bool enable) {
    // DRV8825: EN is Active-LOW (LOW = Enabled, HIGH = Disabled)
    digitalWrite(en_pin_, enable ? LOW : HIGH);
}

bool Drv8825Stepper::isLimitReached() const {
    // NC limit switch connected to GND with INPUT_PULLUP:
    // Closed circuit (normal resting state) -> GND -> LOW
    // Depressed / triggered (or wire cut fail-safe) -> OPEN circuit -> pulled HIGH
    return digitalRead(limit_pin_) == HIGH;
}

bool Drv8825Stepper::checkLimitsIntegrity() {
    if (!initialized_) {
        init();
    }
    // Limit switch must return a clean digital logic level
    int state = digitalRead(limit_pin_);
    return (state == LOW || state == HIGH);
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
    delay(10);

    // If currently touching switch (or switch wire is disconnected/open circuit):
    // Back away +2.0 cm towards positive rail travel.
    if (isLimitReached()) {
        digitalWrite(dir_pin_, HIGH); // Forward direction (+X)
        const int backoffSteps = static_cast<int>(2.0f * steps_per_cm_);
        for (int i = 0; i < backoffSteps; ++i) {
            pulseStep(1200);
            if ((i % 50) == 0) {
                yield();
            }
        }
        delay(30);

        // If after 2.0 cm backoff the switch is STILL indicating limit reached (HIGH),
        // the NC wire is broken or disconnected! Abort immediately for hardware safety.
        if (isLimitReached()) {
            enableMotor(false);
            is_homed_ = false;
            return false;
        }
    }

    // Move backward towards X=0 until limit switch opens (HIGH)
    digitalWrite(dir_pin_, LOW); // Reverse direction (-X towards NC switch)
    const uint32_t maxHomingSteps = static_cast<uint32_t>(300.0f * steps_per_cm_); // 300 cm fail-safe
    bool hitLimit = false;

    for (uint32_t step = 0; step < maxHomingSteps; ++step) {
        if (isLimitReached()) {
            hitLimit = true;
            break;
        }
        pulseStep(1000);
        if ((step % 50) == 0) {
            yield();
        }
    }

    if (!hitLimit) {
        enableMotor(false);
        is_homed_ = false;
        return false;
    }

    // Small back-off (+0.5 cm) for fine calibration
    digitalWrite(dir_pin_, HIGH);
    const int fineBackoff = static_cast<int>(0.5f * steps_per_cm_);
    for (int i = 0; i < fineBackoff; ++i) {
        pulseStep(1500);
        if ((i % 50) == 0) {
            yield();
        }
    }
    delay(20);

    // Slow approach towards limit switch
    digitalWrite(dir_pin_, LOW);
    for (int i = 0; i < fineBackoff * 2; ++i) {
        if (isLimitReached()) {
            break;
        }
        pulseStep(2000);
        if ((i % 50) == 0) {
            yield();
        }
    }

    // Calibration complete: set origin X = 0.0 cm
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

    bool movingForward = (delta_cm > 0.0f);
    digitalWrite(dir_pin_, movingForward ? HIGH : LOW);

    uint32_t totalSteps = static_cast<uint32_t>(std::abs(delta_cm) * steps_per_cm_ + 0.5f);
    for (uint32_t step = 0; step < totalSteps; ++step) {
        // If moving backwards and limit switch is triggered, stop immediately
        if (!movingForward && isLimitReached()) {
            current_x_cm_ = 0.0f;
            enableMotor(false);
            return true;
        }
        pulseStep(1000);
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
