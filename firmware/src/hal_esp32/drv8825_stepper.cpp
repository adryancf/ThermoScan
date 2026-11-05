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
    // Fim de curso acionado: quando apertado fica 0 (LOW)
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

    // Se o fim de curso inicial (GPIO 35) já estiver pressionado no boot,
    // afasta suavemente em direção ao final (DIR = LOW) até liberar o sensor.
    if (isMinLimitReached()) {
        digitalWrite(dir_pin_, STEPPER_DIR_TOWARDS_END);
        const int maxReleaseSteps = static_cast<int>(3.0f * steps_per_cm_);
        for (int i = 0; i < maxReleaseSteps; ++i) {
            pulseStep(1500);
            if (!isMinLimitReached()) {
                // Afasta mais alguns passos para garantir alívio mecânico da chave
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

        // Se após o recuo a chave continuar acusando acionada, aborta por segurança
        if (isMinLimitReached()) {
            enableMotor(false);
            is_homed_ = false;
            return false;
        }
    }

    // 1. Move em direção ao início (DIR = HIGH) até acionar o fim de curso de início (GPIO 35)
    digitalWrite(dir_pin_, STEPPER_DIR_TOWARDS_START);
    const uint32_t maxHomingSteps = static_cast<uint32_t>(1000.0f * steps_per_cm_); // Fail-safe (10m)
    bool hitLimit = false;

    for (uint32_t step = 0; step < maxHomingSteps; ++step) {
        if (isMinLimitReached()) {
            // Debounce mecânico: aguarda 2ms e reconfirma
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

    // Parada mínima (5 ms) para inversão suave sem atraso perceptível
    delay(5);

    // 2. Avança exatamente a constante de offset (STEPPER_HOME_OFFSET_CM = 7.0 cm)
    // na direção do final (STEPPER_DIR_TOWARDS_END) para posicionar o carrinho no início útil do painel.
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

    // Calibração concluída com sucesso: define posição de trabalho X = 0.0 cm
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

    // delta_cm > 0: avançando em direção ao final (+X -> STEPPER_DIR_TOWARDS_END / LOW)
    // delta_cm < 0: recuando em direção ao início (-X -> STEPPER_DIR_TOWARDS_START / HIGH)
    bool movingTowardsEnd = (delta_cm > 0.0f);
    digitalWrite(dir_pin_, movingTowardsEnd ? STEPPER_DIR_TOWARDS_END : STEPPER_DIR_TOWARDS_START);

    uint32_t totalSteps = static_cast<uint32_t>(std::abs(delta_cm) * steps_per_cm_ + 0.5f);
    for (uint32_t step = 0; step < totalSteps; ++step) {
        // Se estiver recuando em direção ao início e atingir o fim de curso inicial (trava de segurança)
        if (!movingTowardsEnd && isMinLimitReached()) {
            const float offset_cm = (home_offset_cm_ > 0.0f) ? home_offset_cm_ : STEPPER_HOME_OFFSET_CM;
            current_x_cm_ = (offset_cm > 0.0f) ? -offset_cm : 0.0f;
            enableMotor(false);
            return true;
        }
        // Se estiver avançando em direção ao final e atingir o fim de curso final (trava de segurança)
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
