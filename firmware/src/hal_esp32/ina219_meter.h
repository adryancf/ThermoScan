#ifndef THERMOSCAN_HAL_ESP32_INA219_METER_H
#define THERMOSCAN_HAL_ESP32_INA219_METER_H

#if defined(ARDUINO) || defined(ESP32)

#include "ina228_meter.h"

namespace hal_esp32 {

/**
 * @brief Backward compatibility alias: Ina219Meter maps to Ina228Meter.
 */
using Ina219Meter = Ina228Meter;

} // namespace hal_esp32

#endif // ARDUINO || ESP32

#endif // THERMOSCAN_HAL_ESP32_INA219_METER_H
