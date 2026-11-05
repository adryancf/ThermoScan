# ThermoScan Firmware

Firmware for the **ThermoScan** embedded device based on the **ESP32** microcontroller. The system automates localized radiometric thermal inspection of photovoltaic panels, identifies confirmed hotspot anomalies, executes safety-interlocked localized water cleanings, and synchronizes telemetry with the Go backend via authenticated HTTPS REST.

---

## 1. Architectural Overview

The firmware is designed following the **Hexagonal / Ports & Adapters** architecture to ensure strict decoupling, testability, and adherence to clean code principles:

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        Application Orchestration                       │
│                        ThermoscanApp (Life Cycle)                      │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
    ┌───────────────────────────────┴───────────────────────────────┐
    │                         Domain Core                           │
    │         (Pure C++17, Zero Arduino/Hardware Dependencies)      │
    │                                                               │
    │   • ThermalAnalyzer: Full-sequence baseline median, candidate │
    │     detection (+10°C), consecutive spatial confirmation (60%) │
    │   • CleaningStateMachine: 3-attempt budget, safety interlocks,│
    │     30-minute post-cleaning cooldown, and verification logic  │
    │   • SolarGeometry: NOAA solar elevation and cosine score      │
    └───────────────────────────────┬───────────────────────────────┘
                                    │
    ┌───────────────────────────────┴───────────────────────────────┐
    │                  HAL (Hardware Abstraction Layer)             │
    │                      Pure C++ Interfaces                      │
    │                                                               │
    │   [IThermalCamera]   [IMotionController]   [ISprayActuator]   │
    │   [IPowerMeter]      [IWaterSensor]        [IStorage]         │
    │   [ICloudClient]     [ITimeProvider]                          │
    └───────▲───────────────────────▲───────────────────────▲───────┘
            │                       │                       │
 ┌──────────┴─────────┐  ┌──────────┴─────────┐  ┌──────────┴─────────┐
 │ ESP32 Real Drivers │  │ Mock HAL Drivers   │  │ Test Bench Scripts │
 │ • MLX90640 (I2C)   │  │ • MockCamera       │  │ • Retained legacy  │
 │ • INA219 (I2C)     │  │ • MockMotion       │  │   scripts in       │
 │ • DRV8825 (GPIO)   │  │ • MockStorage      │  │   MLX90640/ &      │
 │ • NVS (Preferences)│  │ (Used in 100%      │  │   NEMA17/          │
 │ • HTTPClient       │  │  native tests)     │  │                    │
 └────────────────────┘  └────────────────────┘  └────────────────────┘
```

---

## 2. Directory Structure

```text
firmware/
├── platformio.ini                        # Dual environments: esp32dev & native
├── include/
│   ├── pinout.h                          # Centralized GPIO pins and physical constants
│   └── hal/                              # Pure C++ interfaces
│       ├── i_thermal_camera.h
│       ├── i_power_meter.h
│       ├── i_motion_controller.h
│       ├── i_spray_actuator.h
│       ├── i_water_sensor.h
│       ├── i_storage.h                   # Non-volatile storage abstraction
│       ├── i_cloud_client.h              # Cloud communication interface
│       └── i_time_provider.h
├── src/
│   ├── main.cpp                          # Entry point (driver wiring, setup & loop)
│   ├── app/                              # Application state machine orchestrator
│   │   ├── thermoscan_app.h
│   │   └── thermoscan_app.cpp
│   ├── domain/                           # Pure domain logic (100% testable on PC)
│   │   ├── thermal_analyzer.h / .cpp
│   │   ├── cleaning_state_machine.h / .cpp
│   │   ├── solar_geometry.h / .cpp
│   │   └── panel_geometry.h              # Pure multi-panel geometry & string rail math
│   ├── hal_esp32/                        # ESP32 concrete driver implementations
│   │   ├── capacitive_water_sensor.h / .cpp
│   │   ├── drv8825_stepper.h / .cpp
│   │   ├── pump_servo_spray.h / .cpp
│   │   ├── mlx90640_camera.h / .cpp
│   │   ├── ina219_meter.h / .cpp
│   │   ├── esp32_time_provider.h / .cpp
│   │   ├── nvs_storage.h / .cpp
│   │   └── http_cloud_client.h / .cpp
│   ├── MLX90640/                         # Preserved original sensor bench tests
│   └── NEMA17/                           # Preserved original motor bench tests
└── test/                                 # 11 Unit test suites executed via pio test
    ├── test_hal_sanity/test_sanity.cpp
    ├── test_thermal_analyzer/test_thermal_analyzer.cpp
    ├── test_cleaning_state_machine/test_cleaning_state_machine.cpp
    ├── test_solar_geometry/test_solar_geometry.cpp
    ├── test_thermoscan_app/test_thermoscan_app.cpp
    ├── test_histogram_quantization/test_histogram_quantization.cpp
    ├── test_network_resilience/test_network_resilience.cpp
    ├── test_json_contracts/test_json_contracts.cpp
    ├── test_e2e_integration/test_e2e_integration.cpp
    ├── test_bench_diagnostics/test_bench_diagnostics.cpp
    └── test_panel_geometry/test_panel_geometry.cpp
```

---

## 3. Centralized Pinout & Constants (`include/pinout.h`)

All pin assignments and physical thresholds are centralized in [`include/pinout.h`](file:///home/acf/Downloads/Faculdade/8/oficinas_3/ThermoScan/firmware/include/pinout.h). Every pin definition is guarded by `#ifndef`, allowing seamless override via build flags or compilation variables without editing C++ source files.

### Default Pinout
| Signal | Default GPIO | Notes |
| :--- | :--- | :--- |
| **I2C SDA** | `21` | MLX90640 thermal camera (`0x33`) & INA219 power meters (`0x40`, `0x41`, `0x42`) |
| **I2C SCL** | `22` | MLX90640 thermal camera & INA219 power meters |
| **STEPPER STEP** | `19` | DRV8825 step pulse |
| **STEPPER DIR** | `18` | DRV8825 direction control |
| **STEPPER EN** | `5` | DRV8825 driver enable (active LOW) |
| **ENDSTOP LIMIT NC** | `23` | Normally Closed (NC) microswitch at $X = 0\text{ cm}$ (`INPUT_PULLUP`) |
| **WATER LEVEL SENSOR** | `34` | Contactless binary capacitive sensor |
| **PUMP MOSFET** | `25` | 12V mini-pump power stage (forced LOW at boot) |
| **SERVO NOZZLE PWM** | `26` | Nozzle tilt servo (~$-60^\circ$ to $0^\circ$) |
| **STATUS LED** | `2` | Onboard status and diagnostic LED |

### INA219 Multi-Panel Resolution
All components resolve INA219 I2C addresses exclusively through `getInaAddressForPanel(panel_index)`:
- Panel 1 $\to$ `0x40`
- Panel 2 $\to$ `0x41`
- Panel 3 $\to$ `0x42`
- Unconfigured / > 3 $\to$ `0x00` (reports `valid = false`, thermal scan continues uninterrupted).

### Core Physical Constants
- `STEP_SIZE_CM = 2.0f`: Fixed carriage displacement between consecutive acquisitions.
- `FOV_OPTICAL_CM = 5.0f`: Fixed usable optical footprint of the MLX90640.
- `OVERLAP_PERCENT = 60.0f`: Nominal spatial overlap between consecutive frames ($3.0\text{ cm}$).
- `MAX_PANEL_ACQUISITIONS = 35`: Maximum allowable frames buffered in RAM per panel (~68 cm). RAM is freed after each panel.
- `MAX_BASE_TEMP_C = 60.0f`: Maximum allowable baseline temperature before spraying (thermal shock prevention).
- `HOTSPOT_THRESHOLD_DELTA_C = 10.0f`: Fixed temperature difference threshold ($\Delta T \ge +10.0^\circ\text{C}$).
- `MAX_CLEANING_ATTEMPTS = 3`: Strict cap of 3 pump actuations per anomaly event.
- `POST_CLEANING_WAIT_SECONDS = 1800`: Mandatory 30-minute thermal stabilization cooldown prior to post-clean verification.

---

## 4. Thermal Acquisition & Hotspot Detection

### Baseline Timing & Calculation
1. **Accumulation during scan**: During the carriage motion across the X rail, thermal frames ($32 \times 24$ pixels) and electrical snapshots are acquired and buffered in memory.
2. **Retrospective Median**: Once the physical scan sequence completes, `ThermalAnalyzer::calculateBaseline` calculates the **statistical median** of all valid temperatures across all frames of the sequence (central element for odd counts, average of the two middle elements for even counts).
3. **No Lookahead**: The analysis occurs strictly after the sequence acquisition, preventing any dependency on future readings.

### Hotspot Candidate & Spatial Confirmation
- **Candidate Pixel**: Any valid pixel with $T_{\text{pixel}} \ge T_{\text{baseline}} + 10.0^\circ\text{C}$.
- **Spatial Confirmation**:
  - The MLX90640 has 32 columns and 24 rows. The 5.0 cm FOV corresponds to the 32 columns, giving $5.0 / 32 = 0.15625\text{ cm/col}$.
  - Absolute coordinate:
    $$X_{\text{global}} = X_{\text{carriage}} + \left(\frac{\text{col}}{32}\right) \times 5.0\text{ cm}$$
  - When the carriage advances 2.0 cm, the rightmost 60% of frame $k$ overlaps with the leftmost 60% of frame $k+1$.
  - Candidates in consecutive frames $k$ and $k+1$ confirm an anomaly only if they reside on the same row $Y$ and $|X_{\text{global}, k} - X_{\text{global}, k+1}| \le 0.5\text{ cm}$.
- **Invalid Pixels & Noise**:
  - Pixels with NaNs, $\le -40.0^\circ\text{C}$, or $> 300.0^\circ\text{C}$ are discarded.
  - Invalid pixels within the overlap region **cannot** confirm an anomaly by themselves. Both frames must contain valid, matching candidate readings.
  - *Disclaimer*: Consecutive spatial confirmation mitigates transient I2C noise and specular reflections, but does not claim to eliminate 100% of field false positives.

---

## 5. Cleaning State Machine & Safety Interlocks

The cleaning cycle enforces strict interlocks to protect hardware and photovoltaic glass:

1. **Pre-Spray Interlocks (`evaluateBeforeSpray`)**:
   - Baseline Temperature $\le 60.0^\circ\text{C}$: If $T_{\text{base}} > 60.0^\circ\text{C}$, the cleaning is **refused** (`REFUSED`, `"thermal_shock_risk"`).
   - Water Availability: If `water_available == false`, the cleaning is **refused** (`REFUSED`, `"insufficient_water"`).
   - **Refusal Policy**: Prior refusal **does not** consume an attempt from the budget.
2. **Supervised Spraying (`monitorDuringSpray`)**:
   - Pump is activated for 3.5 seconds while directing the nozzle servo.
   - Water level is supervised every 100 ms. If water is depleted during spraying, the pump is **immediately shut down** and the operation is marked as **failed** (`FAILED`, `"water_depleted_during_cleaning"`).
   - Interruption after actuation **consumes 1 attempt**.
3. **Mandatory 30-Minute Cooldown & Solar Window**:
   - Post-cleaning thermal verification **never** runs before 1800 seconds (30 minutes) have elapsed since pump deactivation, allowing water evaporation and thermal stabilization.
   - Verification also waits for a valid solar window (`isSolarWindowValid`), ensuring comparable irradiance.
4. **Post-Cleaning Resolution**:
   - Anomaly vanished $\rightarrow$ `RESOLVED`.
   - Anomaly persists after a completed wash $\rightarrow$ `UNRESOLVED` (no automatic re-wash).
   - Anomaly persists after an interrupted wash and attempts $< 3$ $\rightarrow$ `OPEN` (retry scheduled only after water restoration, safe solar window, and cooldown).
   - Inconclusive/invalid measurement $\rightarrow$ `PENDING_EVALUATION` (never assumes resolution or authorizes unverified washes).
   - **Strict Cap**: A fourth pump actuation is strictly prohibited.

---

## 6. Non-Volatile Persistence (NVS Flash) & Safe Boot

> [!IMPORTANT]
> **No MicroSD / SPI Dependencies in Current Stage**: All persistence is handled by the ESP32 internal NVS Flash via `<Preferences.h>` under namespace `"thermoscan"`.

### Persisted Fields
- `module_id`: Device UUID assigned by backend on claim.
- `device_token`: Secret hardware credential (`dev_sec_...`).
- `config_version`: Version number of currently applied configuration.
- `anomaly_event_id`: ID of active anomaly under treatment.
- `effective_attempts`: Count of pump actuations performed (0 to 3).
- `operation_status`: State of the cleaning cycle.
- `spray_ended_timestamp`: Epoch seconds when water spray terminated.
- `pending_verification`: Boolean flag indicating pending thermal verification.
- `next_inspection_timestamp`: Next scheduled autonomous scan.
- Full array geometry and solar parameters (`panel_length_cm`, `panel_width_cm`, `panel_count`, `panel_spacing_cm`, `min_solar_angle`, `interval_days`, `ping_interval_seconds`).

### Boot Safety Guarantee
- **Pump Safety**: The pump MOSFET pin (GPIO 25) is driven `LOW` immediately in the driver constructor, in `init()`, and in the destructor.
- **Conservative Recovery**: If the ESP32 reboots with an anomaly or pending verification stored in NVS, the pump is **never** turned on automatically. The system recovers state conservatively and transitions directly to `WAITING_VERIFICATION` or `IDLE`.

---

## 7. Cloud Integration (Go Backend Contract)

The firmware integrates natively with the existing Go backend (`software/backend/internal/module/`):

| Action | Route | Auth | Payload / Response |
| :--- | :--- | :--- | :--- |
| **Claim (1st Boot)** | `POST /api/v1/devices/claim` | Public | Envia `mac_address`, flags de diagnóstico. Retorna `module_id` e `device_token`. |
| **Device Ping** | `POST /api/v1/devices/{module_id}/ping` | Bearer `device_token` | Heartbeat com `water_available`, `limits_check_passed`, `thermal_sensor_active`. |
| **Get Configuration** | `GET /api/v1/devices/{module_id}/configuration` | Bearer `device_token` | Recebe geometria, `min_solar_angle`, `interval_days` e `config_version`. |
| **Ack Configuration**| `POST /api/v1/devices/{module_id}/configuration/ack` | Bearer `device_token` | Envia `{ config_version, applied, checksum }`. |
| **Telemetry Ingestion**| `POST /api/v1/devices/{module_id}/telemetry` | Bearer `device_token` | Envia $X$, baseline, temp máxima, flags, V/A/W e matriz térmica 32x24. |
| **Cleaning Ingestion** | `POST /api/v1/devices/{module_id}/cleanings` | Bearer `device_token` | Envia posição alvo, `attempt_number`, duração, status e resultado da verificação. |

> [!NOTE]
> The path parameter `{id}` in `/api/v1/devices/{id}/...` is strictly verified against the `module_id` authenticated by the `device_token`.

---

## 8. Building and Testing

The project uses **PlatformIO**.

### Running Native Unit Tests (on PC, no hardware required)
```bash
cd firmware
pio test -e native
```
All 31 test cases execute in ~3.3 seconds using Desktop GCC/Clang with Unity:
- `test_hal_sanity`: Validates HAL interfaces and physical constants.
- `test_thermal_analyzer` (12 tests): Validates coordinate transforms, median calculation, candidate threshold, spatial confirmation, invalid pixel handling, exact boundary tolerance, tolerance rejection above limit, multi-pixel cluster handling, distinct nearby anomalies, and custom optical FOV width calibration.
- `test_cleaning_state_machine` (10 tests): Validates refusal, interruption, 30-minute timer, solar window locks, resolution states, and the 3-attempt limit.
- `test_solar_geometry` (3 tests): Validates NOAA solar elevation and cosine incidence calculations.
- `test_thermoscan_app` (4 tests): Validates safe boot pump cut, conservative NVS recovery, and emergency limit stop.

### Compiling ESP32 Firmware Binary
```bash
cd firmware
pio run -e esp32dev
```
Binary output: `.pio/build/esp32dev/firmware.bin`

### Uploading to ESP32 Device
```bash
cd firmware
pio run -e esp32dev -t upload
pio device monitor -b 115200
```
