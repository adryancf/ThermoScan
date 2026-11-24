#ifndef THERMOSCAN_PINOUT_H
#define THERMOSCAN_PINOUT_H

#include <cstdint>

// ============================================================================
// ThermoScan Hardware Pinout Configuration
// ============================================================================
// Notes on I2C vs Stepper Pin Allocation:
// On standard ESP32 boards, the primary hardware I2C bus (Wire) uses:
//   - SDA: GPIO 21
//   - SCL: GPIO 22
// In early bench tests (firmware/src/NEMA17), the stepper driver used:
//   - EN: GPIO 21
//   - LIMIT: GPIO 22
// To prevent GPIO bus contention when both I2C sensors (MLX90640, INA219) and
// the NEMA17 stepper are connected, we provide non-conflicting defaults (EN=5,
// LIMIT=23) while keeping every pin fully configurable via #ifndef / build flags.
// ============================================================================

// ----------------------------------------------------------------------------
// I2C Bus Pins (MLX90640 Thermal Camera & INA219 Power Monitor)
// ----------------------------------------------------------------------------
#ifndef PIN_I2C_SDA
#define PIN_I2C_SDA 21  // ESP32 Hardware I2C Serial Data
#endif

#ifndef PIN_I2C_SCL
#define PIN_I2C_SCL 22  // ESP32 Hardware I2C Serial Clock
#endif

constexpr uint8_t I2C_SDA_PIN = PIN_I2C_SDA;
constexpr uint8_t I2C_SCL_PIN = PIN_I2C_SCL;

// ----------------------------------------------------------------------------
// INA228 / INA219 Power Meter Fixed Panel I2C Address Mapping
// ----------------------------------------------------------------------------
#ifndef INA228_ADDR_PANEL_1
#define INA228_ADDR_PANEL_1 0x40
#endif

#ifndef INA228_ADDR_PANEL_2
#define INA228_ADDR_PANEL_2 0x41
#endif

#ifndef INA228_ADDR_PANEL_3
#define INA228_ADDR_PANEL_3 0x42
#endif

#ifndef INA228_ADDR_DEFAULT
#define INA228_ADDR_DEFAULT INA228_ADDR_PANEL_1
#endif

// Backward compatibility defines with legacy INA219 naming
#ifndef INA219_ADDR_PANEL_1
#define INA219_ADDR_PANEL_1 INA228_ADDR_PANEL_1
#endif

#ifndef INA219_ADDR_PANEL_2
#define INA219_ADDR_PANEL_2 INA228_ADDR_PANEL_2
#endif

#ifndef INA219_ADDR_PANEL_3
#define INA219_ADDR_PANEL_3 INA228_ADDR_PANEL_3
#endif

#ifndef INA219_ADDR_DEFAULT
#define INA219_ADDR_DEFAULT INA228_ADDR_DEFAULT
#endif

/**
 * @brief Resolves I2C address for a given panel index (1-indexed).
 * Returns 0x00 if panel has no mapped INA sensor (sensor absent).
 */
static inline uint8_t getInaAddressForPanel(uint8_t panel_index) {
    switch (panel_index) {
        case 1: return INA219_ADDR_PANEL_1;
        case 2: return INA219_ADDR_PANEL_2;
        case 3: return INA219_ADDR_PANEL_3;
        default: return 0x00;
    }
}

// ----------------------------------------------------------------------------
// NEMA17 Stepper Motor / DRV8825 Driver Pins
// ----------------------------------------------------------------------------
#ifndef PIN_STEPPER_STEP
#define PIN_STEPPER_STEP 19  // DRV8825 STEP pulse (1 pulse = 1 microstep)
#endif

#ifndef PIN_STEPPER_DIR
#define PIN_STEPPER_DIR 18   // DRV8825 DIR (direction of rotation)
#endif

// EN pin: Active LOW on DRV8825.
// Set to GPIO 5 by default to avoid conflict with I2C SDA (GPIO 21).
// Set to 21 if using legacy bench wiring with remapped I2C pins.
#ifndef PIN_STEPPER_EN
#define PIN_STEPPER_EN 5
#endif

// ----------------------------------------------------------------------------
// Linear Rail Endstops (Limit Switches)
// Dual limit switch configuration: Start (X=0) and End (X=Xmax)
// Physical logic: 0 (LOW) when pressed, 1 (HIGH) at rest
// ----------------------------------------------------------------------------
#ifndef PIN_STEPPER_LIMIT_MIN
#define PIN_STEPPER_LIMIT_MIN 34  // Start limit switch (Start X = 0 cm)
#endif

#ifndef PIN_STEPPER_LIMIT_MAX
#define PIN_STEPPER_LIMIT_MAX 35  // End limit switch (End X = X_max)
#endif

// Backward compatibility alias
#ifndef PIN_STEPPER_LIMIT_NC
#define PIN_STEPPER_LIMIT_NC PIN_STEPPER_LIMIT_MIN
#endif

constexpr uint8_t STEPPER_STEP_PIN      = PIN_STEPPER_STEP;
constexpr uint8_t STEPPER_DIR_PIN       = PIN_STEPPER_DIR;
constexpr uint8_t STEPPER_EN_PIN        = PIN_STEPPER_EN;
constexpr uint8_t STEPPER_LIMIT_MIN_PIN = PIN_STEPPER_LIMIT_MIN;
constexpr uint8_t STEPPER_LIMIT_MAX_PIN = PIN_STEPPER_LIMIT_MAX;
constexpr uint8_t STEPPER_LIMIT_NC_PIN  = STEPPER_LIMIT_MIN_PIN;

// ----------------------------------------------------------------------------
// Water Sensor (Binary Capacitive Liquid Level)
// ----------------------------------------------------------------------------
#ifndef PIN_WATER_SENSOR
#define PIN_WATER_SENSOR 17
#endif

constexpr uint8_t WATER_SENSOR_PIN = PIN_WATER_SENSOR;

// ----------------------------------------------------------------------------
// Actuators: Spray Pump MOSFET & Tilt Servo PWM
// ----------------------------------------------------------------------------
#ifndef PIN_PUMP_MOSFET
#define PIN_PUMP_MOSFET 4   // Gate of 12V spray pump driver MOSFET
#endif

#ifndef PIN_SERVO_PWM
#define PIN_SERVO_PWM 13     // Nozzle tilt angle adjustment servo PWM
#endif

#ifndef PIN_CAMERA_SERVO_PWM
#define PIN_CAMERA_SERVO_PWM 32 // Thermal camera orientation / tilt servo PWM
#endif

#ifndef PIN_STATUS_LED
#define PIN_STATUS_LED 2     // Diagnostic / system status LED (onboard GPIO 2)
#endif

constexpr uint8_t PUMP_MOSFET_PIN         = PIN_PUMP_MOSFET;
constexpr uint8_t SERVO_PWM_PIN           = PIN_SERVO_PWM;
constexpr uint8_t CAMERA_SERVO_PWM_PIN    = PIN_CAMERA_SERVO_PWM;
constexpr uint8_t STATUS_LED_PIN          = PIN_STATUS_LED;

// ----------------------------------------------------------------------------
// SPI SD Card Module Pins (ESP32 VSPI defaults)
// ----------------------------------------------------------------------------
#ifndef PIN_SD_CS
#define PIN_SD_CS 14     // Chip Select (CS / SS)
#endif

#ifndef PIN_SD_MOSI
#define PIN_SD_MOSI 27  // Master Out Slave In (MOSI)
#endif

#ifndef PIN_SD_MISO
#define PIN_SD_MISO 25  // Master In Slave Out (MISO)
#endif

#ifndef PIN_SD_SCK
#define PIN_SD_SCK 26   // Serial Clock (SCK)
#endif

constexpr uint8_t SD_CS_PIN   = PIN_SD_CS;
constexpr uint8_t SD_MOSI_PIN = PIN_SD_MOSI;
constexpr uint8_t SD_MISO_PIN = PIN_SD_MISO;
constexpr uint8_t SD_SCK_PIN  = PIN_SD_SCK;

#include "thermoscan_config.h"

#endif // THERMOSCAN_PINOUT_H
