#ifndef THERMOSCAN_HAL_I_TIME_PROVIDER_H
#define THERMOSCAN_HAL_I_TIME_PROVIDER_H

#include <cstdint>

class ITimeProvider {
public:
    virtual ~ITimeProvider() = default;

    virtual uint32_t getEpochSeconds() const = 0;
    virtual bool isTimeSynchronized() const = 0;
};

#endif // THERMOSCAN_HAL_I_TIME_PROVIDER_H
