#include "thermoscan_app.h"
#include <cmath>
#include <algorithm>
#include <ArduinoJson.h>

#if defined(ARDUINO) || defined(ESP32)
#include <Arduino.h>
#include "diagnostics/web_diagnostics.h"
#define Serial diagnostics::getGlobalDualSerial()
#else
#include "hal/native_net_compat.h"
#endif

namespace app {

ThermoscanApp::ThermoscanApp(IThermalCamera* camera,
                             IPowerMeter* power_meter,
                             IMotionController* motion,
                             ISprayActuator* spray,
                             IWaterSensor* water_sensor,
                             IStorage* storage,
                             ICloudClient* cloud,
                             ITimeProvider* time_provider,
                             IBackupStorage* backup_storage)
    : camera_(camera),
      power_meter_(power_meter),
      motion_(motion),
      spray_(spray),
      water_sensor_(water_sensor),
      storage_(storage),
      cloud_(cloud),
      time_provider_(time_provider),
      backup_storage_(backup_storage) {}

const char* ThermoscanApp::getStateName() const {
    switch (state_) {
        case AppState::BOOT_INIT:            return "BOOT_INIT";
        case AppState::IDLE:                 return "IDLE";
        case AppState::SCANNING:             return "SCANNING";
        case AppState::ANALYZING:            return "ANALYZING";
        case AppState::CLEANING:             return "CLEANING";
        case AppState::WAITING_VERIFICATION: return "WAITING_VERIFICATION";
        case AppState::VERIFYING:            return "VERIFYING";
        case AppState::SYNCING:              return "SYNCING";
        case AppState::ERROR_HALT:           return "ERROR_HALT";
        default:                             return "UNKNOWN";
    }
}

uint32_t ThermoscanApp::getCurrentTime() const {
    if (time_provider_ != nullptr && time_provider_->isTimeSynchronized()) {
        return time_provider_->getEpochSeconds();
    }
    return 0;
}

bool ThermoscanApp::checkSolarWindow() const {
    const uint32_t now = getCurrentTime();
    if (now == 0) {
        // Without reliable wall-clock time, do not assume a valid solar window
        return false;
    }
    return domain::isSolarWindowValid(config_.latitude,
                                     config_.longitude,
                                     config_.azimuth,
                                     config_.tilt,
                                     config_.min_solar_angle,
                                     now);
}

void ThermoscanApp::transitionTo(AppState new_state, const char* detail) {
    state_ = new_state;
    last_state_detail_ = detail;
    const char* state_name = getStateName();
    const uint32_t now = getCurrentTime();
    if (cloud_ != nullptr) {
        cloud_->setFirmwareState(state_name, detail);
        cloud_->recordStateTransition(state_name, detail, now);
        bool heap_ok = true;
#if defined(ARDUINO) || defined(ESP32)
        heap_ok = (ESP.getFreeHeap() >= 45000);
#endif
        if (cloud_->isConnected() && heap_ok) {
            cloud_->sendPing();
        }
    }
}

void ThermoscanApp::executeEmergencyStop(const char* detail) {
    if (spray_ != nullptr) {
        spray_->stopPump();
    }
    if (motion_ != nullptr) {
        motion_->emergencyStop();
    }
    transitionTo(AppState::ERROR_HALT, detail);
}

void ThermoscanApp::returnToSafeIdle() {
    if (spray_ != nullptr) {
        spray_->stopPump();
    }
    if (motion_ != nullptr) {
        motion_->disableMotor();
    }
    transitionTo(AppState::IDLE);
}

bool ThermoscanApp::init() {
    transitionTo(AppState::BOOT_INIT);
    handleBootInit();
    return (state_ != AppState::ERROR_HALT);
}


void ThermoscanApp::triggerManualInspection() {
    manual_inspection_requested_ = true;
}

void ThermoscanApp::triggerManualCleaning(float target_x_cm) {
    manual_cleaning_requested_ = true;
    manual_cleaning_target_x_ = target_x_cm;
}

static const char* appStateToString(AppState s) {
    switch (s) {
        case AppState::BOOT_INIT: return "BOOT_INIT";
        case AppState::IDLE: return "IDLE";
        case AppState::SCANNING: return "SCANNING";
        case AppState::ANALYZING: return "ANALYZING";
        case AppState::CLEANING: return "CLEANING";
        case AppState::WAITING_VERIFICATION: return "WAITING_VERIFICATION (Cooldown 30min)";
        case AppState::VERIFYING: return "VERIFYING (Confirming resolution)";
        case AppState::SYNCING: return "SYNCING (Synchronizing config)";
        case AppState::ERROR_HALT: return "ERROR_HALT";
        default: return "UNKNOWN";
    }
}

void ThermoscanApp::tick() {
    if (state_ != last_logged_state_) {
        Serial.printf("[STATE] ESP state transition: %s -> %s\n",
                      appStateToString(last_logged_state_), appStateToString(state_));
        last_logged_state_ = state_;
    }

    switch (state_) {
        case AppState::BOOT_INIT:
            handleBootInit();
            break;
        case AppState::IDLE:
            handleIdle();
            break;
        case AppState::SCANNING:
            handleScanning();
            break;
        case AppState::ANALYZING:
            handleAnalyzing();
            break;
        case AppState::CLEANING:
            handleCleaning();
            break;
        case AppState::WAITING_VERIFICATION:
            handleWaitingVerification();
            break;
        case AppState::VERIFYING:
            handleVerifying();
            break;
        case AppState::SYNCING:
            handleSyncing();
            break;
        case AppState::ERROR_HALT:
            if (spray_ != nullptr) spray_->stopPump();
            if (motion_ != nullptr) motion_->disableMotor();
            break;
    }
}


} // namespace app
