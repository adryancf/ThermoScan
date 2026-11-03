#ifndef THERMOSCAN_HAL_ESP32_ESP32_TIME_PROVIDER_H
#define THERMOSCAN_HAL_ESP32_ESP32_TIME_PROVIDER_H

#if defined(ARDUINO) || defined(ESP32)

#include <Arduino.h>
#include <time.h>
#include "hal/i_time_provider.h"

namespace hal_esp32 {

/**
 * @brief ESP32 SNTP time provider.
 * Sincroniza com servidores NTP públicos e fornece epoch seconds em UTC.
 */
class Esp32TimeProvider : public ITimeProvider {
public:
    explicit Esp32TimeProvider(const char* ntp_server1 = "pool.ntp.org",
                               const char* ntp_server2 = "time.nist.gov");
    ~Esp32TimeProvider() override = default;

    void syncNtp();
    uint32_t getEpochSeconds() const override;
    bool isTimeSynchronized() const override;

private:
    const char* ntp_server1_;
    const char* ntp_server2_;
};

} // namespace hal_esp32

#endif // ARDUINO || ESP32

#endif // THERMOSCAN_HAL_ESP32_ESP32_TIME_PROVIDER_H
