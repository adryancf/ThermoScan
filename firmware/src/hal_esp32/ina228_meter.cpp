#if defined(ARDUINO) || defined(ESP32)

#include "ina228_meter.h"
#include "pinout.h"
#include <cmath>

namespace hal_esp32 {

Ina228Meter::Ina228Meter(uint8_t default_i2c_addr, float shunt_res_ohm, float max_current_a)
    : shunt_res_ohm_(shunt_res_ohm), max_current_a_(max_current_a) {
    // Map default channel addresses
    channels_[0].addr = (default_i2c_addr != 0) ? default_i2c_addr : getInaAddressForPanel(1);
    channels_[1].addr = getInaAddressForPanel(2);
    channels_[2].addr = getInaAddressForPanel(3);
}

void Ina228Meter::setShunt(float shunt_res_ohm, float max_current_a) {
    shunt_res_ohm_ = shunt_res_ohm;
    max_current_a_ = max_current_a;
    for (uint8_t i = 0; i < MAX_CHANNELS; ++i) {
        if (channels_[i].ready) {
            channels_[i].ina.setShunt(shunt_res_ohm_, max_current_a_);
        }
    }
}

bool Ina228Meter::initChannel(PanelChannel& ch) {
    if (ch.addr == 0x00) {
        return false;
    }
    if (ch.ready) {
        return true;
    }

    // Fast I2C ACK probe to avoid allocating or throwing timeouts if sensor is absent
    Wire.beginTransmission(ch.addr);
    if (Wire.endTransmission() != 0) {
        ch.ready = false;
        return false;
    }

    if (!ch.ina.begin(ch.addr, &Wire)) {
        ch.ready = false;
        return false;
    }

    ch.ina.setShunt(shunt_res_ohm_, max_current_a_);
    ch.ready = true;
    return true;
}

bool Ina228Meter::init() {
    initialized_ = initChannel(channels_[0]);
    return initialized_;
}

bool Ina228Meter::readFromIna(Adafruit_INA228& ina, PowerSnapshot& out) {
    // Adafruit_INA228 API units:
    // readBusVoltage() -> mV
    // readCurrent()    -> mA
    // readPower()      -> mW
    float bus_voltage_mv = ina.readBusVoltage();
    float current_ma = ina.readCurrent();
    float power_mw = ina.readPower();

    if (std::isnan(bus_voltage_mv) || std::isnan(current_ma) || std::isnan(power_mw) ||
        std::isinf(bus_voltage_mv) || std::isinf(current_ma) || std::isinf(power_mw) ||
        bus_voltage_mv < 0.0f) {
        out.valid = false;
        out.voltage_v = 0.0f;
        out.current_a = 0.0f;
        out.power_w = 0.0f;
        return false;
    }

    out.voltage_v = bus_voltage_mv / 1000.0f;
    out.current_a = current_ma / 1000.0f;
    out.power_w = power_mw / 1000.0f;
    out.valid = true;
    return true;
}

bool Ina228Meter::readSnapshot(PowerSnapshot& out) {
    if (!channels_[0].ready && !initChannel(channels_[0])) {
        out.valid = false;
        out.voltage_v = 0.0f;
        out.current_a = 0.0f;
        out.power_w = 0.0f;
        return false;
    }

    return readFromIna(channels_[0].ina, out);
}

bool Ina228Meter::readSnapshotForPanel(uint8_t panel_index, PowerSnapshot& out) {
    if (panel_index < 1 || panel_index > MAX_CHANNELS) {
        out.valid = false;
        out.voltage_v = 0.0f;
        out.current_a = 0.0f;
        out.power_w = 0.0f;
        return false;
    }

    PanelChannel& ch = channels_[panel_index - 1];
    if (!ch.ready && !initChannel(ch)) {
        out.valid = false;
        out.voltage_v = 0.0f;
        out.current_a = 0.0f;
        out.power_w = 0.0f;
        return false;
    }

    return readFromIna(ch.ina, out);
}

} // namespace hal_esp32

#endif // ARDUINO || ESP32
