#if defined(ARDUINO) || defined(ESP32)

#include <Arduino.h>
#include <WiFi.h>

#include "pinout.h"
#include "hal_esp32/nvs_storage.h"
#include "hal_esp32/sd_backup_storage.h"
#include "hal_esp32/capacitive_water_sensor.h"
#include "hal_esp32/drv8825_stepper.h"
#include "hal_esp32/pump_servo_spray.h"
#include "hal_esp32/mlx90640_camera.h"
#include "hal_esp32/ina228_meter.h"
#include "hal_esp32/esp32_time_provider.h"
#include "hal_esp32/http_cloud_client.h"
#include "app/thermoscan_app.h"
#include "diagnostics/bench_diagnostics.h"
#include "diagnostics/web_diagnostics.h"

// WiFi Configuration (overridable via compiler build flags)
#ifndef WIFI_SSID
#define WIFI_SSID "REDE_THERMOSCAN"
#endif

#ifndef WIFI_PASSWORD
#define WIFI_PASSWORD "thermoscan"
#endif

#ifndef BACKEND_URL
#define BACKEND_URL "http://192.168.0.100:8080"
#endif

// loop() runs scans, MLX90640 capture (I2C) and HTTPS on this task. The default 8 KB stack
// overflowed on the first capture (Stack canary watchpoint triggered (loopTask)).
SET_LOOP_TASK_STACK_SIZE(16 * 1024);

// Hardware Drivers & Infrastructure Layer Instantiation
static hal_esp32::NvsStorage g_storage;
static hal_esp32::SdBackupStorage g_backup_storage;
static hal_esp32::CapacitiveWaterSensor g_water(WATER_SENSOR_PIN);
static hal_esp32::Drv8825Stepper g_stepper(STEPPER_STEP_PIN, STEPPER_DIR_PIN, STEPPER_EN_PIN, STEPPER_LIMIT_MIN_PIN, STEPPER_LIMIT_MAX_PIN, DEFAULT_STEPS_PER_CM, HOME_OFFSET_CM);
static hal_esp32::PumpServoSpray g_spray(PUMP_MOSFET_PIN, SERVO_PWM_PIN, &g_water);
static hal_esp32::Mlx90640Camera g_camera(I2C_SDA_PIN, I2C_SCL_PIN, 0x33, CAMERA_SERVO_PWM_PIN);
static hal_esp32::Ina228Meter g_ina228(getInaAddressForPanel(1));
static hal_esp32::Esp32TimeProvider g_time_provider("pool.ntp.org", "time.nist.gov");
static hal_esp32::HttpCloudClient g_cloud(BACKEND_URL, &g_storage, &g_water, &g_stepper, &g_camera);

// Application Domain Orchestrator Instantiation
static app::ThermoscanApp g_app(&g_camera,
                                &g_ina228,
                                &g_stepper,
                                &g_spray,
                                &g_water,
                                &g_storage,
                                &g_cloud,
                                &g_time_provider,
                                &g_backup_storage);

// Bench Diagnostics Console & Engine Instantiation
static diagnostics::DualSerialProxy& g_dual_serial = diagnostics::getGlobalDualSerial();
static diagnostics::WebBufferedConsole g_console(g_dual_serial);
static diagnostics::BenchDiagnostics g_diagnostics(&g_storage,
                                                   &g_time_provider,
                                                   &g_cloud,
                                                   &g_camera,
                                                   &g_stepper,
                                                   &g_ina228,
                                                   &g_water,
                                                   &g_spray,
                                                   &g_app,
                                                   &g_console);
static diagnostics::WebDiagnosticsServer g_web_server(&g_diagnostics, &g_console);

// Route all direct Serial.print / printf in main.cpp to g_dual_serial (Hardware + Web Buffer)
#define Serial g_dual_serial

// Track whether Wi-Fi-dependent services (SNTP + WebServer) have been initialized
static bool g_wifi_services_started = false;
static unsigned long g_last_wifi_check_ms = 0;

/**
 * @brief Non-blocking status LED pattern driver:
 *  - BOOT_INIT (setup): solid ON
 *  - ERROR_HALT:        5 Hz fast blink (100 ms ON / 100 ms OFF)
 *  - Wi-Fi offline:     double pulse every 2 s (100 ms ON, 150 ms OFF, 100 ms ON)
 *  - Active cycle:      1 Hz blink (500 ms ON / 500 ms OFF)
 *  - Healthy IDLE:      heartbeat (100 ms ON every 3 s)
 */
static void updateStatusLed(unsigned long now_ms) {
    bool led_on = false;

    if (g_app.getState() == app::AppState::ERROR_HALT) {
        led_on = ((now_ms % 200UL) < 100UL);
    } else if (WiFi.status() != WL_CONNECTED) {
        const unsigned long phase = now_ms % 2000UL;
        led_on = (phase < 100UL) || (phase >= 250UL && phase < 350UL);
    } else if (g_app.getState() != app::AppState::IDLE) {
        led_on = ((now_ms % 1000UL) < 500UL);
    } else {
        led_on = ((now_ms % 3000UL) < 100UL);
    }

    digitalWrite(STATUS_LED_PIN, led_on ? HIGH : LOW);
}

void setup() {
    g_dual_serial.begin(115200);
    diagnostics::installEspLogHook();
    delay(500);

    Serial.println();
    Serial.println(F("=================================================="));
    Serial.println(F("           ThermoScan ESP32 Firmware v1.4.2       "));
    Serial.println(F("  Autonomous Photovoltaic Inspection & Cleaning   "));
    Serial.println(F("  ZERO MicroSD Policy | NVS Flash Safe-Boot Eng.  "));
    Serial.println(F("=================================================="));

    // Status LED initialization
    pinMode(STATUS_LED_PIN, OUTPUT);
    digitalWrite(STATUS_LED_PIN, HIGH);

    // Safe Boot Interlock: immediately confirm pump is disabled
    g_spray.stopPump();

    // WiFi Connectivity setup
    Serial.printf("[WIFI] Connecting to SSID: %s\n", WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    const unsigned long wifiStart = millis();
    while (WiFi.status() != WL_CONNECTED && (millis() - wifiStart < 8000)) {
        delay(250);
        Serial.print('.');
    }
    Serial.println();

    if (WiFi.status() == WL_CONNECTED) {
        Serial.print(F("[WIFI] Connected! Local IP: "));
        Serial.println(WiFi.localIP());
        Serial.print(F("[WIFI] MAC Address: "));
        Serial.println(WiFi.macAddress());

        // SNTP Clock Synchronization
        Serial.println(F("[SNTP] Synchronizing UTC wall clock..."));
        g_time_provider.syncNtp();

        // Web Diagnostics Server initialization
        g_web_server.begin("thermoscan");
        g_wifi_services_started = true;
        Serial.printf("[WEB] Bench diagnostics dashboard available at: http://%s or http://thermoscan.local\n", WiFi.localIP().toString().c_str());
    } else {
        Serial.println(F("[WIFI] Warning: WiFi not connected. Operating in standalone offline mode."));
    }

    // Hardware and Application Initialization
    Serial.println(F("[INIT] Initializing ThermoScan application orchestrator..."));
    if (!g_app.init()) {
        Serial.println(F("[ERR] Critical initialization failure! Entering ERROR_HALT safe state."));
        digitalWrite(STATUS_LED_PIN, LOW);
        return;
    }

    // Device Cloud Claim check
    std::string mod_id, dev_tok;
    g_storage.getModuleId(mod_id);
    g_storage.getDeviceToken(dev_tok);
    if (mod_id.empty() || dev_tok.empty()) {
        Serial.println(F("[CLOUD] Device unregistered. Initiating hardware claim POST /api/v1/devices/claim..."));
        if (g_cloud.claimDevice()) {
            Serial.printf("[CLOUD] Device claimed successfully! Module ID: %s\n", g_cloud.getModuleId().c_str());
        } else {
            Serial.println(F("[CLOUD] Hardware claim deferred (backend offline or pending registration)."));
        }
    } else {
        Serial.printf("[CLOUD] Module ID registered in NVS: %s\n", mod_id.c_str());
        Serial.println(F("[CLOUD] Sending startup ping to announce online presence..."));
        if (!g_cloud.sendPing() && g_cloud.hadAuthError()) {
            Serial.println(F("[CLOUD] Startup ping returned HTTP 401! Token invalid or revoked. Attempting immediate hardware re-claim..."));
            if (g_cloud.claimDevice()) {
                Serial.printf("[CLOUD] Device re-claimed successfully! New Module ID: %s\n", g_cloud.getModuleId().c_str());
            } else {
                Serial.println(F("[CLOUD] Hardware re-claim deferred (backend offline or pending registration)."));
            }
        }
    }

    digitalWrite(STATUS_LED_PIN, LOW);
    Serial.println(F("[SYSTEM] ThermoScan operational. Entering main executive loop."));
    Serial.println(F("[DIAG] Interactive bench diagnostics active on serial. Type 'diag list' for commands."));
}

void loop() {
    const unsigned long now_ms = millis();
    if (now_ms - g_last_wifi_check_ms >= 10000UL) {
        g_last_wifi_check_ms = now_ms;
        if (WiFi.status() != WL_CONNECTED) {
            Serial.println(F("[WIFI] Disconnected. Attempting reconnect..."));
            WiFi.reconnect();
        } else {
            if (!g_wifi_services_started) {
                Serial.print(F("[WIFI] Reconnected! Local IP: "));
                Serial.println(WiFi.localIP());
                g_time_provider.syncNtp();
                g_web_server.begin("thermoscan");
                g_wifi_services_started = true;
                Serial.printf("[WEB] Bench diagnostics dashboard available at: http://%s or http://thermoscan.local\n", WiFi.localIP().toString().c_str());
            }
            if (g_cloud.getModuleId().empty() || g_cloud.getDeviceToken().empty()) {
                if (g_cloud.claimDevice()) {
                    Serial.printf("[CLOUD] Late claim succeeded! Module ID: %s\n", g_cloud.getModuleId().c_str());
                }
            }
        }
    }

    if (g_wifi_services_started) {
        g_web_server.tick();
    }

    // Process incoming serial commands for bench diagnostics
    if (Serial.available()) {
        String line = Serial.readStringUntil('\n');
        line.trim();
        if (line.length() > 0) {
            std::string cmd = line.c_str();
            if (line.startsWith("diag")) {
                g_diagnostics.handleCommand(cmd);
            } else {
                if (!g_diagnostics.handleCommand("diag " + cmd)) {
                    Serial.printf("[CMD] Unknown command: '%s'. Type 'diag list' for available tests.\n", line.c_str());
                }
            }
        }
    }

    g_app.tick();
    updateStatusLed(millis());
    delay(20); // FreeRTOS yield
}

#endif // ARDUINO || ESP32
