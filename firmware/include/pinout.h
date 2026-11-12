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

// INA228 Shunt & Current Configuration
#ifndef INA228_DEFAULT_SHUNT_RESISTANCE_OHM
#define INA228_DEFAULT_SHUNT_RESISTANCE_OHM 0.015f  // Shunt resistor 15 mOhm (0.015 ohm, default on Adafruit INA228 module)
#endif

#ifndef INA228_DEFAULT_MAX_CURRENT_A
#define INA228_DEFAULT_MAX_CURRENT_A 10.0f          // Maximum expected current of 10 A for ADC calibration
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
#define PIN_STEPPER_LIMIT_MIN 35  // Start limit switch (Start X = 0 cm)
#endif

#ifndef PIN_STEPPER_LIMIT_MAX
#define PIN_STEPPER_LIMIT_MAX 34  // End limit switch (End X = X_max)
#endif

#ifndef STEPPER_LIMIT_TRIGGERED_LEVEL
#define STEPPER_LIMIT_TRIGGERED_LEVEL 0  // Logic level when triggered (pressed = 0 / LOW)
#endif

// ----------------------------------------------------------------------------
// Stepper Motor Direction (DRV8825)
// 1 (HIGH) = Direction towards start (X = 0, start limit switch GPIO 35)
// 0 (LOW)  = Direction towards end (X = X_max, end limit switch GPIO 34)
// ----------------------------------------------------------------------------
#ifndef STEPPER_DIR_TOWARDS_START
#define STEPPER_DIR_TOWARDS_START 1
#endif

#ifndef STEPPER_DIR_TOWARDS_END
#define STEPPER_DIR_TOWARDS_END 0
#endif

// Distance (in cm) the carriage advances after hitting the start limit switch
// to position itself exactly at the active edge of the solar panel (X = 0.0 cm).
#ifndef STEPPER_HOME_OFFSET_CM
#define STEPPER_HOME_OFFSET_CM 7.0f
#endif

// ----------------------------------------------------------------------------
// Stepper Motor Speed (pulse interval in microseconds)
// Lower value = Faster | Higher value = Slower
// ----------------------------------------------------------------------------
#ifndef STEPPER_SPEED_HOMING_US
#define STEPPER_SPEED_HOMING_US 1800   // Speed during homing (start search and 7 cm offset move)
#endif

#ifndef STEPPER_SPEED_NORMAL_US
#define STEPPER_SPEED_NORMAL_US 1200   // Speed during normal travel (inspection and cleaning)
#endif

// Backward compatibility alias
#ifndef PIN_STEPPER_LIMIT_NC
#define PIN_STEPPER_LIMIT_NC PIN_STEPPER_LIMIT_MIN
#endif

constexpr uint8_t  STEPPER_STEP_PIN         = PIN_STEPPER_STEP;
constexpr uint8_t  STEPPER_DIR_PIN          = PIN_STEPPER_DIR;
constexpr uint8_t  STEPPER_EN_PIN           = PIN_STEPPER_EN;
constexpr uint8_t  STEPPER_LIMIT_MIN_PIN    = PIN_STEPPER_LIMIT_MIN;
constexpr uint8_t  STEPPER_LIMIT_MAX_PIN    = PIN_STEPPER_LIMIT_MAX;
constexpr uint8_t  STEPPER_LIMIT_NC_PIN     = STEPPER_LIMIT_MIN_PIN;
constexpr uint8_t  STEPPER_LIMIT_ACTIVE_VAL = STEPPER_LIMIT_TRIGGERED_LEVEL;
constexpr uint8_t  STEPPER_DIR_START_VAL    = STEPPER_DIR_TOWARDS_START;
constexpr uint8_t  STEPPER_DIR_END_VAL      = STEPPER_DIR_TOWARDS_END;
constexpr float    HOME_OFFSET_CM           = STEPPER_HOME_OFFSET_CM;
constexpr float    STEPPER_HOMING_OFFSET_CM = STEPPER_HOME_OFFSET_CM;
constexpr uint32_t STEPPER_HOMING_DELAY_US  = STEPPER_SPEED_HOMING_US;
constexpr uint32_t STEPPER_NORMAL_DELAY_US  = STEPPER_SPEED_NORMAL_US;

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

#ifndef CAMERA_SERVO_DEFAULT_ANGLE_DEG
#define CAMERA_SERVO_DEFAULT_ANGLE_DEG 110.0f // Configurable fixed angle for camera servo
#endif

#ifndef NOZZLE_SERVO_DEFAULT_ANGLE_DEG
#define NOZZLE_SERVO_DEFAULT_ANGLE_DEG 70.0f // Configurable fixed angle for spray nozzle servo
#endif

#ifndef PIN_STATUS_LED
#define PIN_STATUS_LED 2     // Diagnostic / system status LED (onboard GPIO 2)
#endif

constexpr uint8_t PUMP_MOSFET_PIN         = PIN_PUMP_MOSFET;
constexpr uint8_t SERVO_PWM_PIN           = PIN_SERVO_PWM;
constexpr uint8_t CAMERA_SERVO_PWM_PIN    = PIN_CAMERA_SERVO_PWM;
constexpr float   CAMERA_DEFAULT_ANGLE    = CAMERA_SERVO_DEFAULT_ANGLE_DEG;
constexpr float   NOZZLE_DEFAULT_ANGLE    = NOZZLE_SERVO_DEFAULT_ANGLE_DEG;
constexpr uint8_t STATUS_LED_PIN          = PIN_STATUS_LED;

// ============================================================================
// Kinematic, Geometric & Calibration System Constants
// ============================================================================
constexpr float STEP_SIZE_CM                  = 2.0f;     // Linear displacement per inspection interval (cm)

// Spatial Calibration Parameter:
// The physical correspondence of 32 columns covering 5.0 cm depends strictly on camera
// standoff distance to panel surface (~3.5-4.0 cm) and perpendicular lens alignment.
// Configurable via build flag; default value is strictly 5.0 cm.
#ifndef CALIBRATED_FOV_WIDTH_CM
#define CALIBRATED_FOV_WIDTH_CM 5.0f
#endif
constexpr float FOV_OPTICAL_CM                = CALIBRATED_FOV_WIDTH_CM;

constexpr float OVERLAP_PERCENT               = 60.0f;    // Overlap percentage between consecutive captures (%)
constexpr float MAX_BASE_TEMP_C               = 60.0f;    // Maximum acceptable baseline operating temperature (°C)
constexpr float HOTSPOT_THRESHOLD_DELTA_C     = 8.0f;    // Thermal delta over baseline indicating hotspot (°C)
constexpr float CRITICAL_HOTSPOT_DELTA_C      = 20.0f;   // Critical hotspot delta over baseline (°C)
constexpr float CRITICAL_HOTSPOT_MAX_TEMP_C   = 65.0f;   // Critical hotspot absolute maximum temperature (°C)
constexpr uint32_t MAX_CLEANING_ATTEMPTS      = 3;        // Maximum consecutive spray cleaning attempts per anomaly
constexpr uint32_t POST_CLEANING_WAIT_SECONDS = 1800;     // Cooldown / dry wait time before post-cleaning verification (30 min)

// Active water spray pump duration per cleaning cycle (ms):
#ifndef SPRAY_DURATION_MS
#define SPRAY_DURATION_MS 2500  // Default: 2.5 seconds (2500 ms)
#endif
constexpr uint32_t DEFAULT_SPRAY_DURATION_MS = SPRAY_DURATION_MS;

// Spatial tolerance for consecutive acquisition hotspot matching (cm):
#ifdef SPATIAL_TOLERANCE_DEFAULT_CM
#undef SPATIAL_TOLERANCE_DEFAULT_CM
#endif
constexpr float SPATIAL_TOLERANCE_DEFAULT_CM  = 0.8f;
constexpr float SPATIAL_TOLERANCE_CM          = SPATIAL_TOLERANCE_DEFAULT_CM;

// ----------------------------------------------------------------------------
// Kinematic & Motor Calibration Parameters
// ----------------------------------------------------------------------------
#ifndef STEPS_PER_CM_DEFAULT
#define STEPS_PER_CM_DEFAULT 50.0f  // Default for full-step bench setup; use 800.0f for 1/16 microstepping
#endif
constexpr float DEFAULT_STEPS_PER_CM = STEPS_PER_CM_DEFAULT;

// Actuator settling delay for spray servo angle adjustment before pump trigger
constexpr uint32_t SERVO_SETTLE_DELAY_MS = 300;

// Maximum scan acquisitions buffered in RAM during a single inspection pass.
// With 55 acquisitions at 2.0 cm step, rail travel is 0 to 108 cm and thermal FOV coverage
// reaches ~113 cm (108 cm + 5.0 cm FOV). If panel_length_cm exceeds rail coverage, scan truncates safely.
#ifndef MAX_SCAN_ACQUISITIONS
#define MAX_SCAN_ACQUISITIONS 55
#endif
constexpr size_t SCAN_MAX_ACQUISITIONS        = MAX_SCAN_ACQUISITIONS;

// Maximum scan acquisitions buffered in RAM per panel.
// In multi-panel mode, buffered frames are released after each panel result is confirmed by the backend.
#ifndef MAX_PANEL_ACQUISITIONS
#define MAX_PANEL_ACQUISITIONS 55
#endif
constexpr size_t PANEL_MAX_ACQUISITIONS       = MAX_PANEL_ACQUISITIONS;

#endif // THERMOSCAN_PINOUT_H
