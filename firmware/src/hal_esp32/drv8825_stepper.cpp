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
    delay(10);

    // Se o fim de curso inicial (GPIO 35) ja estiver acionado:
    // Afasta o carrinho +2.0 cm na direcao positiva (+X).
    if (isMinLimitReached()) {
        digitalWrite(dir_pin_, LOW); // Direcao de avanco (+X)
        const int backoffSteps = static_cast<int>(2.0f * steps_per_cm_);
        for (int i = 0; i < backoffSteps; ++i) {
            if (isMaxLimitReached()) {
                enableMotor(false);
                is_homed_ = false;
                return false;
            }
            pulseStep(1200);
            if ((i % 50) == 0) {
                yield();
            }
        }
        delay(30);

        // Se apos 2.0 cm de recuo a chave ainda estiver acionada,
        // a chave esta travada ou ha problema eletrico. Aborta por seguranca.
        if (isMinLimitReached()) {
            enableMotor(false);
            is_homed_ = false;
            return false;
        }
    }

    // Move para tras em direcao a X=0 ate o fim de curso inicial (GPIO 35) acionar (LOW)
    digitalWrite(dir_pin_, HIGH); // Direcao reversa (-X)
    const uint32_t maxHomingSteps = static_cast<uint32_t>(1000.0f * steps_per_cm_); // 1000 cm (10m) fail-safe
    bool hitLimit = false;

    for (uint32_t step = 0; step < maxHomingSteps; ++step) {
        if (isMinLimitReached()) {
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

    // Pequeno recuo (+0.5 cm) para calibracao fina
    digitalWrite(dir_pin_, LOW);
    const int fineBackoff = static_cast<int>(0.5f * steps_per_cm_);
    for (int i = 0; i < fineBackoff; ++i) {
        pulseStep(1500);
        if ((i % 50) == 0) {
            yield();
        }
    }
    delay(20);

    // Aproximacao lenta em direcao ao fim de curso
    digitalWrite(dir_pin_, HIGH);
    for (int i = 0; i < fineBackoff * 2; ++i) {
        if (isMinLimitReached()) {
            break;
        }
        pulseStep(2000);
        if ((i % 50) == 0) {
            yield();
        }
    }

    // Se houver home_offset_cm configurado (> 0.0 cm), avanca essa distancia
    // para afastar da chave e se posicionar exatamente na borda inicial do painel (X = 0.0 cm).
    if (home_offset_cm_ > 0.0f) {
        digitalWrite(dir_pin_, LOW); // Direcao positiva (+X) em direcao ao painel
        const uint32_t offsetSteps = static_cast<uint32_t>(home_offset_cm_ * steps_per_cm_ + 0.5f);
        for (uint32_t i = 0; i < offsetSteps; ++i) {
            if (isMaxLimitReached()) {
                enableMotor(false);
                is_homed_ = false;
                return false;
            }
            pulseStep(1200);
            if ((i % 50) == 0) {
                yield();
            }
        }
        delay(20);
    }

    // Calibracao concluida: define origem X = 0.0 cm (alinhado com o inicio do painel)
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
        // If moving backwards and minimum limit switch is triggered (safety hard stop), stop immediately
        if (!movingForward && isMinLimitReached()) {
            current_x_cm_ = (home_offset_cm_ > 0.0f) ? -home_offset_cm_ : 0.0f;
            enableMotor(false);
            return true;
        }
        // If moving forward and maximum limit switch is triggered (end of rail), stop immediately to prevent crash
        if (movingForward && isMaxLimitReached()) {
            current_x_cm_ = current_x_cm_ + static_cast<float>(step) / steps_per_cm_;
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
