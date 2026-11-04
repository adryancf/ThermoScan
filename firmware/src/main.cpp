#if defined(ARDUINO) || defined(ESP32)

#include <Arduino.h>
#include <WiFi.h>

#include "pinout.h"
#include "hal_esp32/nvs_storage.h"
#include "hal_esp32/capacitive_water_sensor.h"
#include "hal_esp32/drv8825_stepper.h"
#include "hal_esp32/pump_servo_spray.h"
#include "hal_esp32/mlx90640_camera.h"
#include "hal_esp32/ina219_meter.h"
#include "hal_esp32/esp32_time_provider.h"
#include "hal_esp32/http_cloud_client.h"
#include "app/thermoscan_app.h"
#include "diagnostics/bench_diagnostics.h"

// WiFi Configuration (overridable via compiler build flags)
#ifndef WIFI_SSID
#define WIFI_SSID "ThermoScan_AP"
#endif

#ifndef WIFI_PASSWORD
#define WIFI_PASSWORD "thermoscan2026"
#endif

#ifndef BACKEND_URL
#define BACKEND_URL "http://192.168.1.100:8080"
#endif

// Hardware Drivers & Infrastructure Layer Instantiation
static hal_esp32::NvsStorage g_storage;
static hal_esp32::CapacitiveWaterSensor g_water(WATER_SENSOR_PIN);
static hal_esp32::Drv8825Stepper g_stepper(STEPPER_STEP_PIN, STEPPER_DIR_PIN, STEPPER_EN_PIN, STEPPER_LIMIT_NC_PIN);
static hal_esp32::PumpServoSpray g_spray(PUMP_MOSFET_PIN, SERVO_PWM_PIN, &g_water);
static hal_esp32::Mlx90640Camera g_camera(I2C_SDA_PIN, I2C_SCL_PIN, 0x33, CAMERA_SERVO_PWM_PIN);
static hal_esp32::Ina219Meter g_ina219(0x40);
static hal_esp32::Esp32TimeProvider g_time_provider("pool.ntp.org", "time.nist.gov");
static hal_esp32::HttpCloudClient g_cloud(BACKEND_URL, &g_storage, &g_water, &g_stepper, &g_camera);

// Application Domain Orchestrator Instantiation
static app::ThermoscanApp g_app(&g_camera,
                                &g_ina219,
                                &g_stepper,
                                &g_spray,
                                &g_water,
                                &g_storage,
                                &g_cloud,
                                &g_time_provider);

// Bench Diagnostics Console & Engine Instantiation
static diagnostics::SerialConsole g_console(Serial);
static diagnostics::BenchDiagnostics g_diagnostics(&g_storage,
                                                   &g_time_provider,
                                                   &g_cloud,
                                                   &g_camera,
                                                   &g_stepper,
                                                   &g_ina219,
                                                   &g_water,
                                                   &g_spray,
                                                   &g_app,
                                                   &g_console);

void setup() {
    Serial.begin(115200);
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
    }

    digitalWrite(STATUS_LED_PIN, LOW);
    Serial.println(F("[SYSTEM] ThermoScan operational. Entering main executive loop."));
    Serial.println(F("[DIAG] Modo de diagnostico de bancada ativo na serial. Digite 'diag list' para comandos."));
}

void loop() {
    // Process incoming serial commands for bench diagnostics
    if (Serial.available()) {
        String line = Serial.readStringUntil('\n');
        line.trim();
        if (line.length() > 0) {
            if (line.startsWith("diag")) {
                g_diagnostics.handleCommand(line.c_str());
            } else {
                Serial.printf("[CMD] Comando desconhecido: '%s'. Digite 'diag list' para a lista de testes.\n", line.c_str());
            }
        }
    }

    g_app.tick();
    delay(20); // FreeRTOS yield
}

#endif // ARDUINO || ESP32
