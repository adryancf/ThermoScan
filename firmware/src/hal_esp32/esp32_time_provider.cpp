#if defined(ARDUINO) || defined(ESP32)

#include "esp32_time_provider.h"

namespace hal_esp32 {

Esp32TimeProvider::Esp32TimeProvider(const char* ntp_server1, const char* ntp_server2)
    : ntp_server1_(ntp_server1), ntp_server2_(ntp_server2) {}

void Esp32TimeProvider::syncNtp() {
    // 0 offset, 0 daylight offset, UTC reference
    configTime(0, 0, ntp_server1_, ntp_server2_);
}

uint32_t Esp32TimeProvider::getEpochSeconds() const {
    time_t now = 0;
    time(&now);
    return static_cast<uint32_t>(now);
}

bool Esp32TimeProvider::isTimeSynchronized() const {
    // Timestamps > 1700000000 (after Nov 2023) verify NTP sync
    return getEpochSeconds() > 1700000000;
}

} // namespace hal_esp32

#endif // ARDUINO || ESP32
