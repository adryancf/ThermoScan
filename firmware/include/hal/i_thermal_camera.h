#ifndef THERMOSCAN_HAL_I_THERMAL_CAMERA_H
#define THERMOSCAN_HAL_I_THERMAL_CAMERA_H

#include <cstddef>
#include <cstdint>

struct ThermalFrame {
    static constexpr size_t PIXEL_COUNT = 768; // MLX90640 32x24 pixels
    float pixels[PIXEL_COUNT];
    bool valid{false};
};

class IThermalCamera {
public:
    virtual ~IThermalCamera() = default;

    virtual bool init() = 0;
    virtual bool captureFrame(ThermalFrame& out) = 0;
    virtual bool isHealthy() = 0;
};

#endif // THERMOSCAN_HAL_I_THERMAL_CAMERA_H
