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

uint32_t ThermoscanApp::getUptimeMs() const {
    if (time_provider_ != nullptr) {
        return time_provider_->getUptimeMs();
    }
#if defined(ARDUINO) || defined(ESP32)
    return static_cast<uint32_t>(millis());
#else
    return 0;
#endif
}

bool ThermoscanApp::checkSolarWindow() const {
#if DEMO_BYPASS_SOLAR_WINDOW
    return true;
#else
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
#endif
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

void ThermoscanApp::executeFullReset() {
    Serial.println(F("[RESET] Executing full firmware reset routine (Red Button)..."));

    // 1. Immediately halt spray pump and heap tracker
    if (spray_ != nullptr) {
        spray_->stopPump();
    }
    utils::HeapTracker::stop();

    // 2. Release all dynamic vectors and shrink capacity to reclaim heap
    quantized_frames_.clear();
    quantized_frames_.shrink_to_fit();
    current_batch_.clear();
    current_batch_.shrink_to_fit();
    cleaning_queue_.clear();
    cleaning_queue_.shrink_to_fit();
    all_confirmed_hotspots_.clear();
    all_confirmed_hotspots_.shrink_to_fit();
    confirmed_anomaly_records_.clear();
    confirmed_anomaly_records_.shrink_to_fit();

    // 3. Reset domain state machines & histogram
    histogram_.reset();
    cleaning_sm_.restoreState(domain::CleaningStatus::IDLE, domain::AnomalyResult::OPEN, 0, 0);

    // 4. Remove SD backups BEFORE clearing source event / backup ID strings
    if (backup_storage_ != nullptr && backup_storage_->isAvailable()) {
        backup_storage_->purgeTempFiles();
        if (!inspection_source_event_id_.empty()) {
            backup_storage_->removeScanBackup(inspection_source_event_id_);
        }
        if (!pending_sync_backup_id_.empty() && pending_sync_backup_id_ != inspection_source_event_id_) {
            backup_storage_->removeScanBackup(pending_sync_backup_id_);
        }
    }

    // 5. Clear operational strings, IDs, counters, and flags
    inspection_source_event_id_.clear();
    pending_sync_backup_id_.clear();
    restored_operation_status_.clear();
    current_cleaning_op_id_.clear();
    active_anomaly_id_.clear();
    last_completed_panel_ = 0;
    inspection_crash_retries_ = 0;
    inspection_started_at_ = 0;
    inspection_scheduled_for_ = 0;
    active_queue_index_ = 0;
    active_hotspot_ = {};
    scan_truncated_by_memory_ = false;
    all_panels_accepted_ = true;
    last_abort_reason_.clear();
    pending_abort_insp_id_.clear();
    pending_abort_reason_.clear();
    manual_inspection_requested_ = false;
    manual_cleaning_requested_ = false;
    manual_cleaning_active_ = false;
    manual_cleaning_target_x_ = 0.0f;
    has_pinged_ = false;
    last_ping_ms_ = 0;
    has_reclaimed_ = false;
    last_reclaim_ms_ = 0;

    // 6. Clear operational NVS (preserve module_id, device_token, config_version)
    if (storage_ != nullptr) {
        uint32_t persisted_cfg_ver = 0;
        if (storage_->getConfigVersion(persisted_cfg_ver) && persisted_cfg_ver > 0) {
            config_.config_version = persisted_cfg_ver;
        }
        storage_->clearInspectionProgress();
        storage_->clearCleaningQueue();
        storage_->clearPendingAbort();
    }

    // 7. Return carriage to home X=0 if homed
    if (motion_ != nullptr && motion_->isHomed()) {
        motion_->moveToXCm(0.0f);
    }

    // 8. Clear pending flags, queue reset_ack for next HTTP 200 ping, transition to IDLE, and persist NVS
    if (cloud_ != nullptr) {
        cloud_->clearManualInspectionPending();
        cloud_->clearManualCleaningPending();
        cloud_->clearResetPending();
        cloud_->setResetAckPending(true);
    }
    transitionTo(AppState::IDLE, "user_reset");
    saveCurrentStateToNvs();
}

void ThermoscanApp::handleErrorHalt() {
    if (spray_ != nullptr) spray_->stopPump();
    if (motion_ != nullptr) motion_->disableMotor();

    if (cloud_ != nullptr && cloud_->isResetPending()) {
        executeFullReset();
        return;
    }

    const uint32_t now_ms = getUptimeMs();
    const bool due_for_ping = (!has_pinged_ && now_ms > 0) ||
                              (has_pinged_ && (now_ms - last_ping_ms_) >= 5000UL);
    if (cloud_ != nullptr && due_for_ping) {
        cloud_->sendPing();
        last_ping_ms_ = now_ms;
        has_pinged_ = true;
        if (cloud_->isResetPending()) {
            executeFullReset();
            return;
        }
    }
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
            handleErrorHalt();
            break;
    }
}


} // namespace app
