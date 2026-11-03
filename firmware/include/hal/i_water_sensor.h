#ifndef THERMOSCAN_HAL_I_WATER_SENSOR_H
#define THERMOSCAN_HAL_I_WATER_SENSOR_H

enum class WaterStatus {
    AVAILABLE,
    DEPLETED,
    SENSOR_ERROR
};

class IWaterSensor {
public:
    virtual ~IWaterSensor() = default;

    virtual WaterStatus readStatus() = 0;
    virtual bool isWaterAvailable() = 0;
};

#endif // THERMOSCAN_HAL_I_WATER_SENSOR_H
