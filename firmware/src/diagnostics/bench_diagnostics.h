#ifndef THERMOSCAN_DIAGNOSTICS_BENCH_DIAGNOSTICS_H
#define THERMOSCAN_DIAGNOSTICS_BENCH_DIAGNOSTICS_H

#include <string>
#include <vector>
#include <cstdint>
#include <cstdarg>
#include <cmath>

#if defined(ARDUINO) || defined(ESP32)
#include <Arduino.h>
#include <WiFi.h>
#endif

#include "hal/i_storage.h"
#include "hal/i_time_provider.h"
#include "hal/i_cloud_client.h"
#include "hal/i_thermal_camera.h"
#include "hal/i_motion_controller.h"
#include "hal/i_power_meter.h"
#include "hal/i_water_sensor.h"
#include "hal/i_spray_actuator.h"
#include "app/thermoscan_app.h"

namespace diagnostics {

enum class TestStatus {
    PASS,
    FAIL,
    MANUAL
};

inline const char* testStatusToString(TestStatus s) {
    switch (s) {
        case TestStatus::PASS: return "PASS";
        case TestStatus::FAIL: return "FAIL";
        case TestStatus::MANUAL: return "MANUAL";
    }
    return "UNKNOWN";
}

struct TestResult {
    std::string name;
    TestStatus status{TestStatus::PASS};
    std::string details;
    uint32_t duration_ms{0};
    std::string failure_cause;
};

class IConsole {
public:
    virtual ~IConsole() = default;
    virtual void print(const char* s) = 0;
    virtual void print(const std::string& s) { print(s.c_str()); }
    virtual void println(const char* s = "") = 0;
    virtual void println(const std::string& s) { println(s.c_str()); }
    virtual void printf(const char* format, ...) = 0;
    virtual bool available() = 0;
    virtual int read() = 0;
    virtual std::string readLine(uint32_t timeout_ms = 10000) = 0;
};

#if defined(ARDUINO) || defined(ESP32)
class SerialConsole : public IConsole {
public:
    explicit SerialConsole(Stream& stream = Serial) : stream_(stream) {}

    void print(const char* s) override {
        stream_.print(s);
    }

    void println(const char* s = "") override {
        stream_.println(s);
    }

    void printf(const char* format, ...) override {
        char buf[256];
        va_list args;
        va_start(args, format);
        vsnprintf(buf, sizeof(buf), format, args);
        va_end(args);
        stream_.print(buf);
    }

    bool available() override {
        return stream_.available() > 0;
    }

    int read() override {
        return stream_.read();
    }

    std::string readLine(uint32_t timeout_ms = 10000) override {
        uint32_t start = millis();
        String res = "";
        while (millis() - start < timeout_ms) {
            if (stream_.available() > 0) {
                char c = (char)stream_.read();
                if (c == '\n' || c == '\r') {
                    if (res.length() > 0) break;
                } else {
                    res += c;
                }
            }
            delay(10);
        }
        res.trim();
        return res.c_str();
    }

private:
    Stream& stream_;
};
#endif

class BenchDiagnostics {
public:
    BenchDiagnostics(IStorage* storage,
                     ITimeProvider* time_provider,
                     ICloudClient* cloud,
                     IThermalCamera* camera,
                     IMotionController* motion,
                     IPowerMeter* power_meter,
                     IWaterSensor* water_sensor,
                     ISprayActuator* spray,
                     app::ThermoscanApp* app,
                     IConsole* console);

    bool handleCommand(const std::string& cmd_line);

    // Individual tests
    TestResult testNvs();
    TestResult testClock();
    TestResult testWifi();
    TestResult testBackend();
    TestResult testMlx(bool watch = false);
    TestResult testIna();
    TestResult testWater();
    TestResult testMotor(bool require_confirmation = true);
    TestResult testHoming();
    TestResult testPump(bool require_confirmation = true);
    TestResult testNozzleServo();
    TestResult testCameraServo();
    TestResult testScan();
    TestResult testSafety();

    // Sequence & List
    void printList();
    void runAll();

    // Formatting helper
    void printTestResult(const TestResult& res);

private:
    IStorage* storage_{nullptr};
    ITimeProvider* time_provider_{nullptr};
    ICloudClient* cloud_{nullptr};
    IThermalCamera* camera_{nullptr};
    IMotionController* motion_{nullptr};
    IPowerMeter* power_meter_{nullptr};
    IWaterSensor* water_sensor_{nullptr};
    ISprayActuator* spray_{nullptr};
    app::ThermoscanApp* app_{nullptr};
    IConsole* console_{nullptr};

    uint32_t getElapsedMs(uint32_t start_ms) const;
    uint32_t nowMs() const;
    void delayMs(uint32_t ms) const;
};

} // namespace diagnostics

#endif // THERMOSCAN_DIAGNOSTICS_BENCH_DIAGNOSTICS_H
