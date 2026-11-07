#include "utils/uuid_generator.h"
#include <cstdio>
#include <cstdint>

#if defined(ESP32)
#include "esp_system.h"
#if __has_include("esp_random.h")
#include "esp_random.h"  // ESP-IDF 5 / Arduino-ESP32 3.x moved esp_random() here
#endif
#else
#include <random>
#endif

namespace utils {

std::string generateUUIDv4() {
    uint8_t bytes[16];

#if defined(ESP32)
    for (size_t i = 0; i < 16; i += 4) {
        uint32_t r = esp_random();
        bytes[i] = static_cast<uint8_t>(r & 0xFF);
        bytes[i + 1] = static_cast<uint8_t>((r >> 8) & 0xFF);
        bytes[i + 2] = static_cast<uint8_t>((r >> 16) & 0xFF);
        bytes[i + 3] = static_cast<uint8_t>((r >> 24) & 0xFF);
    }
#else
    static std::random_device rd;
    static std::mt19937_64 gen(rd());
    static std::uniform_int_distribution<uint64_t> dis;

    uint64_t part1 = dis(gen);
    uint64_t part2 = dis(gen);
    for (size_t i = 0; i < 8; ++i) {
        bytes[i] = static_cast<uint8_t>((part1 >> (i * 8)) & 0xFF);
        bytes[i + 8] = static_cast<uint8_t>((part2 >> (i * 8)) & 0xFF);
    }
#endif

    // RFC 4122 v4 compliance:
    // Set version to 4: bits 4-7 of time_hi_and_version to 0100 (0x40)
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    // Set variant to RFC 4122: bits 6-7 of clock_seq_hi_and_reserved to 10 (0x80)
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    char buf[37];
    std::snprintf(buf, sizeof(buf),
                  "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                  bytes[0], bytes[1], bytes[2], bytes[3],
                  bytes[4], bytes[5],
                  bytes[6], bytes[7],
                  bytes[8], bytes[9],
                  bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]);

    return std::string(buf);
}

} // namespace utils

