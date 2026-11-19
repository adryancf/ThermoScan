#ifndef THERMOSCAN_CONFIG_H
#define THERMOSCAN_CONFIG_H

#include <cstddef>
#include <cstdint>

namespace thermoscan_config {

// Number of thermal frames buffered in RAM before sending a telemetry batch.
constexpr size_t TELEMETRY_BATCH_CHUNK_SIZE = 3;

// Maximum boot-recovery attempts for a pending inspection before aborting to IDLE.
constexpr uint8_t MAX_INSPECTION_CRASH_RETRIES = 1;

// Polling interval (ms) while monitoring water level during active spray.
constexpr uint32_t SPRAY_STEP_MS = 100;

} // namespace thermoscan_config

// ============================================================================
// Kinematic, Geometric & Calibration System Constants
// ============================================================================
constexpr float STEP_SIZE_CM                  = 2.0f;     // Linear displacement per inspection interval (cm)

#ifndef CALIBRATED_FOV_WIDTH_CM
#define CALIBRATED_FOV_WIDTH_CM 5.0f
#endif
constexpr float FOV_OPTICAL_CM                = CALIBRATED_FOV_WIDTH_CM;

constexpr float OVERLAP_PERCENT               = 60.0f;    // Overlap percentage between consecutive captures (%)
constexpr float MAX_BASE_TEMP_C               = 60.0f;    // Maximum acceptable baseline operating temperature (°C)
constexpr float HOTSPOT_THRESHOLD_DELTA_C     = 8.0f;     // Thermal delta over baseline indicating hotspot (°C)
constexpr float CRITICAL_HOTSPOT_DELTA_C      = 20.0f;    // Critical hotspot delta over baseline (°C)
constexpr float CRITICAL_HOTSPOT_MAX_TEMP_C   = 65.0f;    // Critical hotspot absolute maximum temperature (°C)
constexpr uint32_t MAX_CLEANING_ATTEMPTS      = 3;        // Maximum consecutive spray cleaning attempts per anomaly

#ifndef POST_CLEANING_WAIT_SECONDS
#define POST_CLEANING_WAIT_SECONDS 60
#endif

#ifndef DEMO_BYPASS_SOLAR_WINDOW
#define DEMO_BYPASS_SOLAR_WINDOW 0
#endif

#ifndef SPRAY_DURATION_MS
#define SPRAY_DURATION_MS 2500  // Default: 2.5 seconds (2500 ms)
#endif
constexpr uint32_t DEFAULT_SPRAY_DURATION_MS = SPRAY_DURATION_MS;

#ifdef SPATIAL_TOLERANCE_DEFAULT_CM
#undef SPATIAL_TOLERANCE_DEFAULT_CM
#endif
constexpr float SPATIAL_TOLERANCE_DEFAULT_CM  = 0.8f;
constexpr float SPATIAL_TOLERANCE_CM          = SPATIAL_TOLERANCE_DEFAULT_CM;

#ifndef STEPS_PER_CM_DEFAULT
#define STEPS_PER_CM_DEFAULT 50.0f  // Default for full-step bench setup; use 800.0f for 1/16 microstepping
#endif
constexpr float DEFAULT_STEPS_PER_CM = STEPS_PER_CM_DEFAULT;

constexpr uint32_t SERVO_SETTLE_DELAY_MS = 300;

#ifndef MAX_SCAN_ACQUISITIONS
#define MAX_SCAN_ACQUISITIONS 55
#endif
constexpr size_t SCAN_MAX_ACQUISITIONS        = MAX_SCAN_ACQUISITIONS;

#ifndef MAX_PANEL_ACQUISITIONS
#define MAX_PANEL_ACQUISITIONS 55
#endif
constexpr size_t PANEL_MAX_ACQUISITIONS       = MAX_PANEL_ACQUISITIONS;

// ============================================================================
// Sensor & Actuator Calibration Parameters
// ============================================================================
// INA228 Shunt & Current Configuration
#ifndef INA228_DEFAULT_SHUNT_RESISTANCE_OHM
#define INA228_DEFAULT_SHUNT_RESISTANCE_OHM 0.015f  // Shunt resistor 15 mOhm (0.015 ohm)
#endif

#ifndef INA228_DEFAULT_MAX_CURRENT_A
#define INA228_DEFAULT_MAX_CURRENT_A 10.0f          // Maximum expected current of 10 A for ADC calibration
#endif

// Linear Rail Endstops & Stepper Logic / Calibration
#ifndef STEPPER_LIMIT_TRIGGERED_LEVEL
#define STEPPER_LIMIT_TRIGGERED_LEVEL 0  // Logic level when triggered (pressed = 0 / LOW)
#endif

#ifndef STEPPER_DIR_TOWARDS_START
#define STEPPER_DIR_TOWARDS_START 1
#endif

#ifndef STEPPER_DIR_TOWARDS_END
#define STEPPER_DIR_TOWARDS_END 0
#endif

#ifndef STEPPER_HOME_OFFSET_CM
#define STEPPER_HOME_OFFSET_CM 7.0f
#endif

#ifndef STEPPER_SPEED_HOMING_US
#define STEPPER_SPEED_HOMING_US 1800   // Speed during homing (us)
#endif

#ifndef STEPPER_SPEED_NORMAL_US
#define STEPPER_SPEED_NORMAL_US 1200   // Speed during normal travel (us)
#endif

constexpr uint8_t  STEPPER_LIMIT_ACTIVE_VAL = STEPPER_LIMIT_TRIGGERED_LEVEL;
constexpr uint8_t  STEPPER_DIR_START_VAL    = STEPPER_DIR_TOWARDS_START;
constexpr uint8_t  STEPPER_DIR_END_VAL      = STEPPER_DIR_TOWARDS_END;
constexpr float    HOME_OFFSET_CM           = STEPPER_HOME_OFFSET_CM;
constexpr float    STEPPER_HOMING_OFFSET_CM = STEPPER_HOME_OFFSET_CM;
constexpr uint32_t STEPPER_HOMING_DELAY_US  = STEPPER_SPEED_HOMING_US;
constexpr uint32_t STEPPER_NORMAL_DELAY_US  = STEPPER_SPEED_NORMAL_US;

// Servo Default Angles
#ifndef CAMERA_SERVO_DEFAULT_ANGLE_DEG
#define CAMERA_SERVO_DEFAULT_ANGLE_DEG 110.0f
#endif

#ifndef NOZZLE_SERVO_DEFAULT_ANGLE_DEG
#define NOZZLE_SERVO_DEFAULT_ANGLE_DEG 70.0f
#endif

constexpr float CAMERA_DEFAULT_ANGLE = CAMERA_SERVO_DEFAULT_ANGLE_DEG;
constexpr float NOZZLE_DEFAULT_ANGLE = NOZZLE_SERVO_DEFAULT_ANGLE_DEG;

#endif // THERMOSCAN_CONFIG_H
