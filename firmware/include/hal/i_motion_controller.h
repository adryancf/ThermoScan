#ifndef THERMOSCAN_HAL_I_MOTION_CONTROLLER_H
#define THERMOSCAN_HAL_I_MOTION_CONTROLLER_H

#include <cstdint>

class IMotionController {
public:
    virtual ~IMotionController() = default;

    virtual bool init() = 0;
    virtual bool home() = 0;
    virtual bool moveToXCm(float target_x_cm) = 0;
    virtual float getXPositionCm() const = 0;
    virtual bool checkLimitsIntegrity() = 0;
    virtual void disableMotor() = 0;
    virtual void emergencyStop() = 0;
};

#endif // THERMOSCAN_HAL_I_MOTION_CONTROLLER_H
