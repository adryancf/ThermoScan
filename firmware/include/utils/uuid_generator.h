#ifndef THERMOSCAN_UTILS_UUID_GENERATOR_H
#define THERMOSCAN_UTILS_UUID_GENERATOR_H

#include <string>

namespace utils {

/**
 * @brief Generates an RFC 4122 compliant UUID v4 string (36 characters).
 * Uses hardware random number generator (esp_random()) on ESP32,
 * or standard pseudorandom generator on host/native platforms.
 */
std::string generateUUIDv4();

} // namespace utils

#endif // THERMOSCAN_UTILS_UUID_GENERATOR_H
