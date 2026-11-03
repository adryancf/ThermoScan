#include "thermoscan_app.h"
#include <cmath>
#include <algorithm>

#if defined(ARDUINO) || defined(ESP32)
#include <Arduino.h>
#endif

namespace app {

ThermoscanApp::ThermoscanApp(IThermalCamera* camera,
                             IPowerMeter* power_meter,
                             IMotionController* motion,
                             ISprayActuator* spray,
                             IWaterSensor* water_sensor,
                             IStorage* storage,
                             ICloudClient* cloud,
                             ITimeProvider* time_provider)
    : camera_(camera),
      power_meter_(power_meter),
      motion_(motion),
      spray_(spray),
      water_sensor_(water_sensor),
      storage_(storage),
      cloud_(cloud),
      time_provider_(time_provider) {}

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
        // If time is not yet synchronized, allow verification conservatively
        return true;
    }
    return domain::isSolarWindowValid(config_.latitude,
                                     config_.longitude,
                                     config_.azimuth,
                                     config_.tilt,
                                     config_.min_solar_angle,
                                     now);
}

void ThermoscanApp::executeEmergencyStop() {
    if (spray_ != nullptr) {
        spray_->stopPump();
    }
    state_ = AppState::ERROR_HALT;
}

bool ThermoscanApp::init() {
    state_ = AppState::BOOT_INIT;
    handleBootInit();
    return (state_ != AppState::ERROR_HALT);
}

void ThermoscanApp::saveCurrentStateToNvs() {
    if (storage_ == nullptr) return;

    StorageState s;
    s.operation_status = getStateName();
    s.effective_attempts = cleaning_sm_.getEffectiveAttempts();
    s.spray_ended_timestamp = cleaning_sm_.getSprayEndedTimestamp();
    s.pending_verification = (state_ == AppState::WAITING_VERIFICATION ||
                              state_ == AppState::VERIFYING);
    s.next_inspection_timestamp = next_inspection_time_;
    if (active_hotspot_.confirmed) {
        s.anomaly_event_id = "anom_" + std::to_string(static_cast<int>(active_hotspot_.target_x_cm));
    }
    storage_->saveAll(s);
}

void ThermoscanApp::restoreStateFromNvs() {
    if (storage_ == nullptr) return;

    StorageState s;
    if (storage_->loadAll(s)) {
        next_inspection_time_ = s.next_inspection_timestamp;

        // SAFE RECOVERY: If a spray cycle was completed before power cut and awaiting verification
        if (s.pending_verification && s.spray_ended_timestamp > 0) {
            cleaning_sm_.restoreState(CleaningStatus::COMPLETED,
                                      AnomalyResult::OPEN,
                                      s.effective_attempts,
                                      s.spray_ended_timestamp);
            state_ = AppState::WAITING_VERIFICATION;
        } else {
            cleaning_sm_.restoreState(CleaningStatus::IDLE,
                                      AnomalyResult::OPEN,
                                      s.effective_attempts,
                                      0);
        }
    }
}

void ThermoscanApp::handleBootInit() {
    // SAFE BOOT GUARANTEE: Force pump OFF immediately before anything else
    if (spray_ != nullptr) {
        spray_->stopPump();
    }

    // Hardware subsystems initialization
    bool init_ok = true;
    if (storage_ != nullptr) init_ok &= storage_->init();
    if (motion_ != nullptr)  init_ok &= motion_->init();
    if (spray_ != nullptr)   init_ok &= spray_->init();
    if (camera_ != nullptr)  init_ok &= camera_->init();
    if (power_meter_ != nullptr) init_ok &= power_meter_->init();
    if (cloud_ != nullptr)   init_ok &= cloud_->init();

    // Hardware self-diagnosis
    if (motion_ != nullptr && !motion_->checkLimitsIntegrity()) {
        executeEmergencyStop();
        return;
    }

    // Physical carriage homing to mechanical NC limit switch at X=0
    if (motion_ != nullptr && !motion_->home()) {
        executeEmergencyStop();
        return;
    }

    // Conservative NVS state restoration
    restoreStateFromNvs();

    // If no verification was pending from prior power cycle, proceed to IDLE
    if (state_ == AppState::BOOT_INIT) {
        state_ = AppState::IDLE;
    }
}

void ThermoscanApp::triggerManualInspection() {
    manual_inspection_requested_ = true;
}

void ThermoscanApp::triggerManualCleaning(float target_x_cm) {
    manual_cleaning_requested_ = true;
    manual_cleaning_target_x_ = target_x_cm;
}

void ThermoscanApp::tick() {
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
            break;
    }
}

void ThermoscanApp::handleIdle() {
    const uint32_t now = getCurrentTime();

    // Periodic telemetry ping
    if (cloud_ != nullptr && (now == 0 || (now - last_ping_time_) >= static_cast<uint32_t>(config_.ping_interval_seconds))) {
        cloud_->sendPing();
        last_ping_time_ = now;
    }

    // Check manual override requests
    if (manual_inspection_requested_) {
        manual_inspection_requested_ = false;
        state_ = AppState::SCANNING;
        return;
    }

    if (manual_cleaning_requested_) {
        manual_cleaning_requested_ = false;
        active_hotspot_.target_x_cm = manual_cleaning_target_x_;
        active_hotspot_.confirmed = true;
        state_ = AppState::CLEANING;
        return;
    }

    // Scheduled inspection evaluation
    if (now > 0 && next_inspection_time_ > 0 && now >= next_inspection_time_) {
        if (checkSolarWindow()) {
            state_ = AppState::SCANNING;
            return;
        }
    }
}

void ThermoscanApp::handleScanning() {
    acquisitions_.clear();

    const float max_x = config_.panel_length_cm;
    float current_x = 0.0f;

    while (current_x <= max_x) {
        if (motion_ != nullptr) {
            motion_->moveToXCm(current_x);
        }

        domain::ScanAcquisition acq;
        acq.x_position_cm = current_x;

        if (camera_ != nullptr) {
            acq.valid = camera_->captureFrame(acq.frame);
        }

        PowerSnapshot power;
        if (power_meter_ != nullptr) {
            power_meter_->readSnapshot(power);
        }

        if (acq.valid) {
            acquisitions_.push_back(acq);

            // Ingest telemetry per scan step
            if (cloud_ != nullptr) {
                float max_temp = -999.0f;
                float sum_temp = 0.0f;
                for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
                    float t = acq.frame.pixels[i];
                    if (t > max_temp) max_temp = t;
                    sum_temp += t;
                }
                float avg_temp = sum_temp / static_cast<float>(ThermalFrame::PIXEL_COUNT);

                TelemetryPayload tp;
                tp.x_position_cm = current_x;
                tp.ambient_temp_c = avg_temp;
                tp.max_temp_c = max_temp;
                tp.delta_temp_c = max_temp - avg_temp;
                tp.bus_voltage_v = power.voltage_v;
                tp.current_a = power.current_a;
                tp.power_w = power.power_w;
                tp.timestamp = getCurrentTime();
                tp.status = "SCANNING";
                cloud_->ingestTelemetry(tp);
            }

            // Controlled memory guard: if frame buffer reaches safe RAM ceiling,
            // stop further acquisitions to prevent heap exhaustion and proceed with partial scan
            if (acquisitions_.size() >= SCAN_MAX_ACQUISITIONS) {
                break;
            }
        }

        current_x += STEP_SIZE_CM;
    }

    // Return linear carriage to origin X = 0.0 cm
    if (motion_ != nullptr) {
        motion_->moveToXCm(0.0f);
    }

    if (!acquisitions_.empty()) {
        state_ = AppState::ANALYZING;
    } else {
        state_ = AppState::IDLE;
    }
}

void ThermoscanApp::handleAnalyzing() {
    baseline_temp_c_ = thermal_analyzer_.calculateBaseline(acquisitions_);

    std::vector<domain::HotspotEvent> confirmed =
        thermal_analyzer_.analyzeScan(acquisitions_, ThermalAnalyzer::DEFAULT_POSITION_TOLERANCE_CM, true);

    if (!confirmed.empty()) {
        // Pick primary anomaly with highest thermal delta
        domain::HotspotEvent worst = confirmed[0];
        for (const auto& ev : confirmed) {
            if (ev.max_temp_c > worst.max_temp_c) {
                worst = ev;
            }
        }
        active_hotspot_ = worst;
        saveCurrentStateToNvs();
        state_ = AppState::CLEANING;
    } else {
        // No anomalies detected: schedule next periodic scan
        const uint32_t now = getCurrentTime();
        if (now > 0) {
            next_inspection_time_ = now + static_cast<uint32_t>(config_.interval_days * 86400);
        }
        saveCurrentStateToNvs();
        state_ = AppState::SYNCING;
    }
}

void ThermoscanApp::handleCleaning() {
    const bool water_ok = (water_sensor_ != nullptr) ? water_sensor_->isWaterAvailable() : true;

    // Evaluate pre-spray safety interlocks
    if (!cleaning_sm_.evaluateBeforeSpray(baseline_temp_c_, water_ok)) {
        // Interlock refused spray (high temp, water missing, or max attempts reached)
        CleaningPayload cp;
        cp.anomaly_event_id = active_hotspot_.confirmed ? "anom_" + std::to_string(static_cast<int>(active_hotspot_.target_x_cm)) : "";
        cp.x_position_cm = active_hotspot_.target_x_cm;
        cp.cleaning_attempts = cleaning_sm_.getEffectiveAttempts();
        cp.water_available = water_ok;
        cp.success = false;
        if (cloud_ != nullptr) {
            cloud_->ingestCleaning(cp);
        }
        saveCurrentStateToNvs();
        state_ = AppState::SYNCING;
        return;
    }

    // Position carriage at target X and align nozzle
    if (motion_ != nullptr) {
        motion_->moveToXCm(active_hotspot_.target_x_cm);
    }
    if (spray_ != nullptr) {
        spray_->setNozzleAngle(90.0f);
    }

    // Start spray sequence
    cleaning_sm_.startSpray();
    const uint32_t start_time = getCurrentTime();

    if (spray_ != nullptr) {
        spray_->startPump();
    }

    // Active fluid supervision during 3.5s spray duration (35 checks * 100ms)
    bool spray_interrupted = false;
    for (int i = 0; i < 35; ++i) {
        const bool fluid = (water_sensor_ != nullptr) ? water_sensor_->isWaterAvailable() : true;
        if (!cleaning_sm_.monitorDuringSpray(fluid)) {
            // Fluid depleted: immediately halt pump
            if (spray_ != nullptr) {
                spray_->stopPump();
            }
            spray_interrupted = true;
            break;
        }
#if defined(ARDUINO) || defined(ESP32)
        delay(100);
#endif
    }

    if (!spray_interrupted) {
        if (spray_ != nullptr) {
            spray_->stopPump();
        }
        cleaning_sm_.finishSpray(getCurrentTime());
    }

    // Report cleaning actuation record to cloud
    CleaningPayload cp;
    cp.anomaly_event_id = active_hotspot_.confirmed ? "anom_" + std::to_string(static_cast<int>(active_hotspot_.target_x_cm)) : "";
    cp.x_position_cm = active_hotspot_.target_x_cm;
    cp.cleaning_attempts = cleaning_sm_.getEffectiveAttempts();
    cp.started_timestamp = start_time;
    cp.ended_timestamp = getCurrentTime();
    cp.water_available = (water_sensor_ != nullptr) ? water_sensor_->isWaterAvailable() : true;
    cp.success = (cleaning_sm_.getStatus() == domain::CleaningStatus::COMPLETED);
    if (cloud_ != nullptr) {
        cloud_->ingestCleaning(cp);
    }

    // Return carriage to home
    if (motion_ != nullptr) {
        motion_->moveToXCm(0.0f);
    }

    // Persist active verification state to NVS
    saveCurrentStateToNvs();
    state_ = AppState::WAITING_VERIFICATION;
}

void ThermoscanApp::handleWaitingVerification() {
    const uint32_t now = getCurrentTime();
    const bool solar_ok = checkSolarWindow();

    // Strict 1800-second cooldown AND valid solar elevation window
    if (cleaning_sm_.canStartVerification(now, solar_ok)) {
        state_ = AppState::VERIFYING;
        return;
    }

    // Send periodic health pings while in cooldown wait
    if (cloud_ != nullptr && (now - last_ping_time_) >= static_cast<uint32_t>(config_.ping_interval_seconds)) {
        cloud_->sendPing();
        last_ping_time_ = now;
    }
}

void ThermoscanApp::handleVerifying() {
    // Re-position at target coordinate
    if (motion_ != nullptr) {
        motion_->moveToXCm(active_hotspot_.target_x_cm);
    }

    ThermalFrame frame;
    bool valid = false;
    if (camera_ != nullptr) {
        valid = camera_->captureFrame(frame);
    }

    bool hotspot_still_present = false;
    if (valid) {
        float max_t = -999.0f;
        for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
            if (frame.pixels[i] > max_t) max_t = frame.pixels[i];
        }
        hotspot_still_present = (max_t - baseline_temp_c_) >= HOTSPOT_THRESHOLD_DELTA_C;
    }

    domain::AnomalyResult result = cleaning_sm_.processVerificationResult(hotspot_still_present, valid);

    // Return to home position
    if (motion_ != nullptr) {
        motion_->moveToXCm(0.0f);
    }

    if (result == domain::AnomalyResult::RESOLVED) {
        active_hotspot_ = domain::HotspotEvent{};
        saveCurrentStateToNvs();
        state_ = AppState::SYNCING;
    } else if (result == domain::AnomalyResult::UNRESOLVED) {
        saveCurrentStateToNvs();
        state_ = AppState::SYNCING;
    } else {
        // PENDING_EVALUATION or OPEN (retry allowed after conditions recover)
        saveCurrentStateToNvs();
        state_ = AppState::IDLE;
    }
}

void ThermoscanApp::handleSyncing() {
    if (cloud_ != nullptr && cloud_->isConnected()) {
        cloud_->sendPing();
        std::string cfg_json;
        cloud_->getConfiguration(cfg_json);
    }
    state_ = AppState::IDLE;
}

} // namespace app
