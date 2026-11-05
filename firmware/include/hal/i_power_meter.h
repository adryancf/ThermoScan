#ifndef THERMOSCAN_HAL_I_POWER_METER_H
#define THERMOSCAN_HAL_I_POWER_METER_H

#include <cstdint>

struct PowerSnapshot {
    float voltage_v{0.0f};
    float current_a{0.0f};
    float power_w{0.0f};
    bool valid{false};
};

class IPowerMeter {
public:
    virtual ~IPowerMeter() = default;

    virtual bool init() = 0;
    virtual bool readSnapshot(PowerSnapshot& out) = 0;
    virtual bool readSnapshotForPanel(uint8_t panel_index, PowerSnapshot& out) {
        (void)panel_index;
        return readSnapshot(out);
    }
};

#endif // THERMOSCAN_HAL_I_POWER_METER_H
