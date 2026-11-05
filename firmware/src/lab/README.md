# Hardware Lab & Isolated Experiments (`src/lab/`)

This directory contains standalone sketches, hardware bring-up tests, calibration tools, and bench experiments created during prototyping and initial hardware validation.

> [!NOTE]
> The code in this folder is **isolated and not part of the ThermoScan production firmware build**.
> It is automatically excluded from the main PlatformIO build target via `build_src_filter = +<*> -<lab/>`.

---

## Directory Structure

### 1. `mlx90640_tests/`
Initial bring-up and validation scripts for the MLX90640 thermal sensor:
* **`simpleTest.cpp` / `main.cpp`:** Basic sketches for raw 32x24 pixel acquisition over I2C (Wire).
* **`viewMap.py` / `thermalMatrix.py`:** Python helper scripts for reading serial output and rendering real-time false-color thermal heatmaps on a PC.

### 2. `nema17_tests/`
Linear rail kinematics and driver tests:
* **`main.cpp`:** Step pulse generation and direction alternation test for the DRV8825 stepper driver.
* **`fim_de_curso.cpp`:** Mechanical endstop limit switch verification (pull-up validation and reverse-step clearance upon trigger).

### 3. `pin_scanner/`
* **`main.cpp`:** I2C bus scanner and ESP32 pin utility to identify connected peripheral addresses (e.g., 0x33 for MLX90640 and 0x40..0x42 for INA228).
* Can be compiled independently using:
  ```bash
  pio run -e pin_scanner -t upload
  ```
