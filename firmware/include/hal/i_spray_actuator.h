#ifndef THERMOSCAN_HAL_I_SPRAY_ACTUATOR_H
#define THERMOSCAN_HAL_I_SPRAY_ACTUATOR_H

class ISprayActuator {
public:
    virtual ~ISprayActuator() = default;

    virtual bool init() = 0;
    virtual bool setNozzleAngle(float angle_deg) = 0;
    virtual bool startPump() = 0;
    virtual void stopPump() = 0;
    virtual bool isPumpActive() const = 0;
};

#endif // THERMOSCAN_HAL_I_SPRAY_ACTUATOR_H
