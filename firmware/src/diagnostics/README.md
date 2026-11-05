# Bench Diagnostics Module (`src/diagnostics/`)

This directory contains the interactive bench diagnostics and diagnostic web server infrastructure for the ThermoScan embedded device. It enables individual validation of all onboard sensors, actuators, and cloud connectivity prior to autonomous field deployment.

---

## Components

### 1. `bench_diagnostics.h` / `bench_diagnostics.cpp`
Central diagnostic engine implementing an interactive test catalog accessible via the Serial monitor or web terminal.

* **Available Commands (`diag <command>`):**
  * `diag list`: Lists all available bench tests and descriptions.
  * `diag all`: Runs all hardware tests sequentially with a consolidated summary.
  * `diag mlx`: Captures a frame from the MLX90640 thermal camera and validates 768-pixel sanity.
  * `diag motor`: Steps the NEMA17 motor (+2.0 cm forward and returns to origin), verifying smooth motion.
  * `diag homing`: Executes homing routine to find the NC start limit switch (GPIO 35) and advances by the 7.0 cm panel offset.
  * `diag pump`: Pulses the spray pump for 500 ms (requires operator confirmation and non-empty water reservoir).
  * `diag camera-servo`: Tests the camera tilt servo at 0°, 45°, and 90°.
  * `diag nozzle-servo`: Sweeps the spray nozzle servo across -45°, 0°, and +45°.
  * `diag ina`: Scans I2C addresses for INA228 power monitors and reads voltage ($V$), current ($I$), and power ($W$).
  * `diag water`: Reads the capacitive water level sensor.
  * `diag scan`: Bench verification scan cycle (point at $X=0$, advances $+2.0\text{ cm}$, captures second point, and returns to origin).
  * `diag safety`: Validates emergency stop interlocks and immediate motor/pump de-energization.
  * `diag nvs`: Tests read and write operations on internal non-volatile storage.
  * `diag clock`: Verifies UTC wall-clock synchronization via NTP.
  * `diag backend`: Sends a telemetry ping to the cloud REST API and checks response.

### 2. `web_diagnostics.h`
Embedded web interface and live serial stream proxy:
* **`WebDiagnosticsServer`:** Lightweight asynchronous HTTP server accessible on the local network at `http://thermoscan.local` or via the ESP32 IP address. Provides quick-action test buttons and a live interactive console.
* **`DualSerialProxy`:** Intercepts hardware UART serial output and mirrors all logs into a circular RAM buffer, enabling real-time wireless log streaming in web browsers.
