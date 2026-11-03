#if defined(ARDUINO) || defined(ESP32)

#include "capacitive_water_sensor.h"

namespace hal_esp32 {

CapacitiveWaterSensor::CapacitiveWaterSensor(uint8_t pin, bool active_high)
    : pin_(pin), active_high_(active_high) {}

bool CapacitiveWaterSensor::init() {
    pinMode(pin_, INPUT);
    initialized_ = true;
    return true;
}

WaterStatus CapacitiveWaterSensor::readStatus() {
    if (!initialized_) {
        init();
    }
    const int val = digitalRead(pin_);
    const bool waterPresent = active_high_ ? (val == HIGH) : (val == LOW);
    return waterPresent ? WaterStatus::AVAILABLE : WaterStatus::DEPLETED;
}

bool CapacitiveWaterSensor::isWaterAvailable() {
    return readStatus() == WaterStatus::AVAILABLE;
}

} // namespace hal_esp32

#endif // ARDUINO || ESP32
