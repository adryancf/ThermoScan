#if defined(ARDUINO) || defined(ESP32)

#include "ina219_meter.h"
#include <cmath>

namespace hal_esp32 {

Ina219Meter::Ina219Meter(uint8_t i2c_addr)
    : i2c_addr_(i2c_addr), ina219_(i2c_addr) {}

bool Ina219Meter::init() {
    if (!ina219_.begin(&Wire)) {
        initialized_ = false;
        return false;
    }
    initialized_ = true;
    return true;
}

bool Ina219Meter::readSnapshot(PowerSnapshot& out) {
    if (!initialized_ && !init()) {
        out.valid = false;
        return false;
    }

    float bus_voltage_v = ina219_.getBusVoltage_V();
    float current_ma = ina219_.getCurrent_mA();
    float power_mw = ina219_.getPower_mW();

    if (std::isnan(bus_voltage_v) || std::isnan(current_ma)) {
        out.valid = false;
        return false;
    }

    out.voltage_v = bus_voltage_v;
    out.current_a = current_ma / 1000.0f;
    out.power_w = power_mw / 1000.0f;
    out.valid = true;
    return true;
}

} // namespace hal_esp32

#endif // ARDUINO || ESP32
