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

// Fim de curso (Limit switch) NC (Normally Closed) logic:
// Set to GPIO 23 by default to avoid conflict with I2C SCL (GPIO 22).
// Set to 22 if using legacy bench wiring with remapped I2C pins.
#ifndef PIN_STEPPER_LIMIT_NC
#define PIN_STEPPER_LIMIT_NC 23
#endif

// Legacy bench aliases for documentation / backward compatibility reference
#ifndef PIN_STEPPER_EN_LEGACY
#define PIN_STEPPER_EN_LEGACY 21
#endif

#ifndef PIN_STEPPER_LIMIT_NC_LEGACY
#define PIN_STEPPER_LIMIT_NC_LEGACY 22
#endif

constexpr uint8_t STEPPER_STEP_PIN     = PIN_STEPPER_STEP;
constexpr uint8_t STEPPER_DIR_PIN      = PIN_STEPPER_DIR;
constexpr uint8_t STEPPER_EN_PIN       = PIN_STEPPER_EN;
constexpr uint8_t STEPPER_LIMIT_NC_PIN = PIN_STEPPER_LIMIT_NC;

// ----------------------------------------------------------------------------
// Water Sensor (Binary Capacitive Liquid Level)
// ----------------------------------------------------------------------------
#ifndef PIN_WATER_SENSOR
#define PIN_WATER_SENSOR 34  // Capacitive liquid level sensor (Input-only GPIO 34)
#endif

constexpr uint8_t WATER_SENSOR_PIN = PIN_WATER_SENSOR;

// ----------------------------------------------------------------------------
// Actuators: Spray Pump MOSFET & Tilt Servo PWM
// ----------------------------------------------------------------------------
#ifndef PIN_PUMP_MOSFET
#define PIN_PUMP_MOSFET 25   // Gate of 12V spray pump driver MOSFET
#endif

#ifndef PIN_SERVO_PWM
#define PIN_SERVO_PWM 26     // Nozzle tilt angle adjustment servo PWM
#endif

#ifndef PIN_STATUS_LED
#define PIN_STATUS_LED 2     // Diagnostic / system status LED (onboard GPIO 2)
#endif

constexpr uint8_t PUMP_MOSFET_PIN = PIN_PUMP_MOSFET;
constexpr uint8_t SERVO_PWM_PIN   = PIN_SERVO_PWM;
constexpr uint8_t STATUS_LED_PIN  = PIN_STATUS_LED;

// ============================================================================
// Kinematic & Geometric System Constants
// ============================================================================
constexpr float STEP_SIZE_CM                  = 2.0f;     // Linear displacement per inspection interval (cm)
constexpr float FOV_OPTICAL_CM                = 5.0f;     // Camera optical field of view coverage width (cm)
constexpr float OVERLAP_PERCENT               = 60.0f;    // Overlap percentage between consecutive captures (%)
constexpr float MAX_BASE_TEMP_C               = 60.0f;    // Maximum acceptable baseline operating temperature (°C)
constexpr float HOTSPOT_THRESHOLD_DELTA_C     = 10.0f;    // Thermal delta over baseline indicating hotspot (°C)
constexpr uint32_t MAX_CLEANING_ATTEMPTS      = 3;        // Maximum consecutive spray cleaning attempts per anomaly
constexpr uint32_t POST_CLEANING_WAIT_SECONDS = 1800;     // Cooldown / dry wait time before post-cleaning verification (30 min)

#endif // THERMOSCAN_PINOUT_H
