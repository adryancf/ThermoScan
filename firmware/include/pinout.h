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
#define INA228_DEFAULT_SHUNT_RESISTANCE_OHM 0.015f  // Resistor shunt de 15 mOhm (0.015 ohm, padrão do módulo Adafruit INA228)
#endif

#ifndef INA228_DEFAULT_MAX_CURRENT_A
#define INA228_DEFAULT_MAX_CURRENT_A 10.0f          // Corrente máxima esperada de 10 A para calibração do ADC
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
// Fins de Curso (Endstops) do Trilho Linear
// Configuração de dois fins de curso: Começo (X=0) e Final (X=Xmax)
// Lógica física: Quando apertado fica 0 (LOW), em repouso fica 1 (HIGH)
// ----------------------------------------------------------------------------
#ifndef PIN_STEPPER_LIMIT_MIN
#define PIN_STEPPER_LIMIT_MIN 35  // Fim de curso inicial (Começo X = 0 cm)
#endif

#ifndef PIN_STEPPER_LIMIT_MAX
#define PIN_STEPPER_LIMIT_MAX 34  // Fim de curso final (Fim de curso X = X_max)
#endif

#ifndef STEPPER_LIMIT_TRIGGERED_LEVEL
#define STEPPER_LIMIT_TRIGGERED_LEVEL 0  // Nível lógico quando acionado (apertado = 0 / LOW)
#endif

// ----------------------------------------------------------------------------
// Direção do Motor de Passo (DRV8825)
// 1 (HIGH) = Direção até o início (X = 0, Fim de curso inicial GPIO 35)
// 0 (LOW)  = Direção até o final (X = X_max, Fim de curso final GPIO 34)
// ----------------------------------------------------------------------------
#ifndef STEPPER_DIR_TOWARDS_START
#define STEPPER_DIR_TOWARDS_START 1
#endif

#ifndef STEPPER_DIR_TOWARDS_END
#define STEPPER_DIR_TOWARDS_END 0
#endif

// Distância (em cm) que o carrinho avança após acionar o fim de curso de início
// para se posicionar exatamente na borda inicial do painel solar (X = 0.0 cm).
#ifndef STEPPER_HOME_OFFSET_CM
#define STEPPER_HOME_OFFSET_CM 7.0f
#endif

// ----------------------------------------------------------------------------
// Velocidade do Motor de Passo (Intervalo em microssegundos entre pulsos)
// Menor valor = Mais rápido | Maior valor = Mais lento
// ----------------------------------------------------------------------------
#ifndef STEPPER_SPEED_HOMING_US
#define STEPPER_SPEED_HOMING_US 1800   // Velocidade durante o homing (busca do início e avanço dos 7 cm)
#endif

#ifndef STEPPER_SPEED_NORMAL_US
#define STEPPER_SPEED_NORMAL_US 1200   // Velocidade durante deslocamento normal (inspeção e limpeza)
#endif

// Alias de retrocompatibilidade
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
#define CAMERA_SERVO_DEFAULT_ANGLE_DEG 90.0f // Configurable fixed angle for camera servo
#endif

#ifndef PIN_STATUS_LED
#define PIN_STATUS_LED 2     // Diagnostic / system status LED (onboard GPIO 2)
#endif

constexpr uint8_t PUMP_MOSFET_PIN         = PIN_PUMP_MOSFET;
constexpr uint8_t SERVO_PWM_PIN           = PIN_SERVO_PWM;
constexpr uint8_t CAMERA_SERVO_PWM_PIN    = PIN_CAMERA_SERVO_PWM;
constexpr float   CAMERA_DEFAULT_ANGLE    = CAMERA_SERVO_DEFAULT_ANGLE_DEG;
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
constexpr float HOTSPOT_THRESHOLD_DELTA_C     = 10.0f;    // Thermal delta over baseline indicating hotspot (°C)
constexpr uint32_t MAX_CLEANING_ATTEMPTS      = 3;        // Maximum consecutive spray cleaning attempts per anomaly
constexpr uint32_t POST_CLEANING_WAIT_SECONDS = 1800;     // Cooldown / dry wait time before post-cleaning verification (30 min)

// Spatial tolerance for consecutive acquisition hotspot matching (cm):
#ifndef SPATIAL_TOLERANCE_DEFAULT_CM
#define SPATIAL_TOLERANCE_DEFAULT_CM 0.5f
#endif
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
// With 35 acquisitions at 2.0 cm step, rail travel is 0 to 68 cm and thermal FOV coverage
// reaches ~73 cm (68 cm + 5.0 cm FOV). If panel_length_cm exceeds 68 cm, scan truncates safely.
#ifndef MAX_SCAN_ACQUISITIONS
#define MAX_SCAN_ACQUISITIONS 35
#endif
constexpr size_t SCAN_MAX_ACQUISITIONS        = MAX_SCAN_ACQUISITIONS;

// Maximum scan acquisitions buffered in RAM per panel.
// In multi-panel mode, buffered frames are released after each panel result is confirmed by the backend.
#ifndef MAX_PANEL_ACQUISITIONS
#define MAX_PANEL_ACQUISITIONS 35
#endif
constexpr size_t PANEL_MAX_ACQUISITIONS       = MAX_PANEL_ACQUISITIONS;

#endif // THERMOSCAN_PINOUT_H
