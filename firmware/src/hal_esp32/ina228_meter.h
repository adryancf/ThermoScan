#ifndef THERMOSCAN_HAL_ESP32_INA228_METER_H
#define THERMOSCAN_HAL_ESP32_INA228_METER_H

#if defined(ARDUINO) || defined(ESP32)

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_INA228.h>
#include "pinout.h"
#include "hal/i_power_meter.h"

namespace hal_esp32 {

/**
 * @brief INA228 Precision High-Side DC Voltage & Current Sensor driver.
 * Supports multi-panel resolution over shared I2C bus.
 */
class Ina228Meter : public IPowerMeter {
public:
    explicit Ina228Meter(uint8_t default_i2c_addr = getInaAddressForPanel(1),
                         float shunt_res_ohm = INA228_DEFAULT_SHUNT_RESISTANCE_OHM,
                         float max_current_a = INA228_DEFAULT_MAX_CURRENT_A);
    ~Ina228Meter() override = default;

    bool init() override;
    bool readSnapshot(PowerSnapshot& out) override;
    bool readSnapshotForPanel(uint8_t panel_index, PowerSnapshot& out) override;

    void setShunt(float shunt_res_ohm, float max_current_a);

private:
    float shunt_res_ohm_;
    float max_current_a_;
    bool initialized_{false};

    struct PanelChannel {
        uint8_t addr{0};
        Adafruit_INA228 ina;
        bool ready{false};
    };

    static constexpr uint8_t MAX_CHANNELS = 3;
    PanelChannel channels_[MAX_CHANNELS];

    bool initChannel(PanelChannel& ch);
    bool readFromIna(Adafruit_INA228& ina, PowerSnapshot& out);
};

} // namespace hal_esp32

#endif // ARDUINO || ESP32

#endif // THERMOSCAN_HAL_ESP32_INA228_METER_H
