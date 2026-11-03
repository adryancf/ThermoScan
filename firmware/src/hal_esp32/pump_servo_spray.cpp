#if defined(ARDUINO) || defined(ESP32)

#include "pump_servo_spray.h"

namespace hal_esp32 {

PumpServoSpray::PumpServoSpray(uint8_t pump_pin, uint8_t servo_pin, IWaterSensor* water_sensor)
    : pump_pin_(pump_pin), servo_pin_(servo_pin), water_sensor_(water_sensor) {
    // SAFE BOOT GUARANTEE: Immediately force MOSFET gate LOW at construction time
    pinMode(pump_pin_, OUTPUT);
    digitalWrite(pump_pin_, LOW);
}

PumpServoSpray::~PumpServoSpray() {
    stopPump();
    if (servo_.attached()) {
        servo_.detach();
    }
}

bool PumpServoSpray::init() {
    // Ensure MOSFET gate is driven LOW
    pinMode(pump_pin_, OUTPUT);
    digitalWrite(pump_pin_, LOW);
    pump_active_ = false;

    // Attach servo for nozzle articulation
    // Standard 50Hz servo PWM allocation on ESP32
    ESP32PWM::allocateTimer(0);
    ESP32PWM::allocateTimer(1);
    servo_.setPeriodHertz(50);
    servo_.attach(servo_pin_, 500, 2500);
    servo_.write(90); // Default centered 90 degrees

    initialized_ = true;
    return true;
}

void PumpServoSpray::setWaterSensor(IWaterSensor* sensor) {
    water_sensor_ = sensor;
}

bool PumpServoSpray::setNozzleAngle(float angle_deg) {
    if (!initialized_) {
        init();
    }
    if (angle_deg < 0.0f) angle_deg = 0.0f;
    if (angle_deg > 180.0f) angle_deg = 180.0f;

    servo_.write(static_cast<int>(angle_deg));
    return true;
}

bool PumpServoSpray::startPump() {
    if (!initialized_) {
        init();
    }
    // Fail-safe water supervision: do not energize pump if water is depleted
    if (water_sensor_ != nullptr && !water_sensor_->isWaterAvailable()) {
        stopPump();
        return false;
    }

    digitalWrite(pump_pin_, HIGH);
    pump_active_ = true;
    return true;
}

void PumpServoSpray::stopPump() {
    digitalWrite(pump_pin_, LOW);
    pump_active_ = false;
}

bool PumpServoSpray::isPumpActive() const {
    return pump_active_;
}

} // namespace hal_esp32

#endif // ARDUINO || ESP32
