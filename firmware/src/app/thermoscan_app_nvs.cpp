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

void ThermoscanApp::saveCurrentStateToNvs() {
    if (storage_ == nullptr) return;

    StorageState s;
    storage_->getModuleId(s.module_id);
    s.config_version = config_.config_version;
    s.operation_status = getStateName();
    s.effective_attempts = cleaning_sm_.getEffectiveAttempts();
    s.spray_ended_timestamp = cleaning_sm_.getSprayEndedTimestamp();
    s.pending_verification = (state_ == AppState::WAITING_VERIFICATION ||
                              state_ == AppState::VERIFYING);
    s.next_inspection_timestamp = next_inspection_time_;
    s.active_hotspot_x_cm = active_hotspot_.target_x_cm;
    s.active_panel_index = (active_hotspot_.panel_index > 0) ? active_hotspot_.panel_index : 1;
    s.baseline_temp_c = baseline_temp_c_;
    s.cleaning_operation_id = current_cleaning_op_id_;
    s.inspection_source_event_id = inspection_source_event_id_;
    s.last_completed_panel = last_completed_panel_;
    s.inspection_crash_retries = inspection_crash_retries_;
    if (!active_anomaly_id_.empty()) {
        s.anomaly_event_id = active_anomaly_id_;
    } else if (active_hotspot_.confirmed) {
        s.anomaly_event_id = active_hotspot_.origin_measurement_event_id;
    }
    storage_->saveAll(s);
}

void ThermoscanApp::restoreStateFromNvs() {
    if (storage_ == nullptr) return;

    // Restore persisted multi-panel geometry and schedule parameters if valid
    float g_len = config_.panel_length_cm;
    float g_wid = config_.panel_width_cm;
    int32_t g_cnt = config_.panel_count;
    float g_spc = config_.panel_spacing_cm;
    if (storage_->getGeometry(g_len, g_wid, g_cnt, g_spc)) {
        if (g_len > 0.0f && g_wid > 0.0f && g_cnt >= 1 && g_spc >= 0.0f) {
            config_.panel_length_cm = g_len;
            config_.panel_width_cm = g_wid;
            config_.panel_count = g_cnt;
            config_.panel_spacing_cm = g_spc;
        }
    }

    int32_t saved_ping_int = 0;
    if (storage_->getPingIntervalSeconds(saved_ping_int) && saved_ping_int >= 5) {
        config_.ping_interval_seconds = saved_ping_int;
    }

    float saved_min_solar = config_.min_solar_angle;
    if (storage_->getMinSolarAngle(saved_min_solar) && saved_min_solar >= 0.0f && saved_min_solar <= 90.0f) {
        config_.min_solar_angle = saved_min_solar;
    }

    int32_t saved_interval_d = config_.interval_days;
    if (storage_->getIntervalDays(saved_interval_d) && saved_interval_d >= 1) {
        config_.interval_days = saved_interval_d;
    }

    float saved_lat = config_.latitude;
    float saved_lon = config_.longitude;
    float saved_azim = config_.azimuth;
    float saved_tilt = config_.tilt;
    if (storage_->getLocationAndOrientation(saved_lat, saved_lon, saved_azim, saved_tilt)) {
        if (saved_lat >= -90.0f && saved_lat <= 90.0f &&
            saved_lon >= -180.0f && saved_lon <= 180.0f &&
            saved_azim >= 0.0f && saved_azim < 360.0f &&
            saved_tilt >= 0.0f && saved_tilt <= 90.0f) {
            config_.latitude = saved_lat;
            config_.longitude = saved_lon;
            config_.azimuth = saved_azim;
            config_.tilt = saved_tilt;
        }
    }

    float saved_hs_delta = config_.hotspot_threshold_delta_c;
    if (storage_->getHotspotThresholdDeltaC(saved_hs_delta) && saved_hs_delta > 0.0f && saved_hs_delta <= 50.0f) {
        config_.hotspot_threshold_delta_c = saved_hs_delta;
        thermal_analyzer_.setHotspotThresholdDeltaC(saved_hs_delta);
    }

    StorageState s;
    if (storage_->loadAll(s)) {
        if (s.config_version > 0) {
            config_.config_version = s.config_version;
        }
        next_inspection_time_ = s.next_inspection_timestamp;
        active_hotspot_.panel_index = (s.active_panel_index > 0) ? s.active_panel_index : 1;
        active_hotspot_.target_x_cm = s.active_hotspot_x_cm;
        active_hotspot_.confirmed = s.pending_verification;
        active_hotspot_.origin_measurement_event_id = s.anomaly_event_id;
        active_anomaly_id_ = s.anomaly_event_id;
        baseline_temp_c_ = (s.baseline_temp_c > 0.0f) ? s.baseline_temp_c : 25.0f;
        current_cleaning_op_id_ = s.cleaning_operation_id;
        inspection_source_event_id_ = s.inspection_source_event_id;
        last_completed_panel_ = s.last_completed_panel;
        inspection_crash_retries_ = s.inspection_crash_retries;
        restored_operation_status_ = s.operation_status;

        if (inspection_source_event_id_.empty()) {
            storage_->getInspectionProgress(inspection_source_event_id_, last_completed_panel_, inspection_crash_retries_);
        }

        // Restore cleaning queue from NVS
        storage_->getCleaningQueue(cleaning_queue_);

        if (!cleaning_queue_.empty()) {
            bool has_cleaned = false;
            bool has_pending = false;
            uint8_t restored_attempts = s.effective_attempts;
            for (const auto& qh : cleaning_queue_) {
                if (qh.verification_status == "cleaned") {
                    has_cleaned = true;
                    restored_attempts = qh.attempts;
                }
                if (qh.verification_status == "pending") {
                    has_pending = true;
                }
            }

            if (has_cleaned && s.spray_ended_timestamp > 0) {
                cleaning_sm_.restoreState(CleaningStatus::COMPLETED,
                                          AnomalyResult::OPEN,
                                          restored_attempts,
                                          s.spray_ended_timestamp);
                transitionTo(AppState::WAITING_VERIFICATION, "cooldown_wait");
            } else if (has_pending) {
                for (const auto& qh : cleaning_queue_) {
                    if (qh.verification_status == "pending") {
                        active_hotspot_.panel_index = qh.panel_index;
                        active_hotspot_.target_x_cm = qh.target_x_cm;
                        restored_attempts = qh.attempts;
                        break;
                    }
                }
                cleaning_sm_.restoreState(CleaningStatus::IDLE,
                                          AnomalyResult::OPEN,
                                          restored_attempts,
                                          0);
                transitionTo(AppState::CLEANING);
            } else {
                cleaning_queue_.clear();
                storage_->clearCleaningQueue();
                transitionTo(AppState::IDLE);
            }
        } else if (s.pending_verification && s.spray_ended_timestamp > 0) {
            QueuedHotspot qh;
            qh.panel_index = active_hotspot_.panel_index;
            qh.target_x_cm = s.active_hotspot_x_cm;
            qh.anomaly_event_id = s.anomaly_event_id;
            qh.cleaning_operation_id = s.cleaning_operation_id;
            qh.attempts = s.effective_attempts;
            qh.verification_status = "cleaned";
            qh.baseline_temp_c = baseline_temp_c_;
            cleaning_queue_.push_back(qh);

            cleaning_sm_.restoreState(CleaningStatus::COMPLETED,
                                      AnomalyResult::OPEN,
                                      s.effective_attempts,
                                      s.spray_ended_timestamp);
            transitionTo(AppState::WAITING_VERIFICATION, "cooldown_wait");
        } else {
            cleaning_sm_.restoreState(CleaningStatus::IDLE,
                                      AnomalyResult::OPEN,
                                      s.effective_attempts,
                                      0);
        }
    }
}

void ThermoscanApp::handleBootInit() {
    // SAFE BOOT GUARANTEE: Force pump OFF and stepper disabled immediately
    if (spray_ != nullptr) {
        spray_->stopPump();
    }
    if (motion_ != nullptr) {
        motion_->disableMotor();
    }

    // Hardware subsystems initialization
    bool essential_init_ok = true;
    if (storage_ != nullptr) essential_init_ok &= storage_->init();
    if (backup_storage_ != nullptr) {
        if (backup_storage_->init() && backup_storage_->isAvailable()) {
            backup_storage_->purgeTempFiles();
        }
    }
    if (motion_ != nullptr)  essential_init_ok &= motion_->init();
    if (spray_ != nullptr)   essential_init_ok &= spray_->init();
    if (camera_ != nullptr) {
        if (!camera_->init()) {
            essential_init_ok = false;
            Serial.println(F("[ERR] MLX90640 thermal camera initialization failed (will retry on capture)."));
        }
    }
    if (power_meter_ != nullptr && !power_meter_->init()) {
        Serial.println(F("[INIT] Warning: Power meter (INA228) not detected on I2C (optional)."));
    }
    if (cloud_ != nullptr)   essential_init_ok &= cloud_->init();

    if (!essential_init_ok) {
        Serial.println(F("[ERR] One or more essential hardware subsystems reported initialization issues."));
    }

    // Hardware self-diagnosis
    if (motion_ != nullptr && !motion_->checkLimitsIntegrity()) {
        executeEmergencyStop("limits_check_failed");
        return;
    }

    // Physical carriage homing to mechanical NC limit switch at X=0
    if (motion_ != nullptr && !motion_->home()) {
        executeEmergencyStop("homing_failed");
        return;
    }

    // Conservative NVS state restoration
    restoreStateFromNvs();

    // Check if an inspection was interrupted during ANALYZING or SYNCING
    if ((restored_operation_status_ == "ANALYZING" || restored_operation_status_ == "SYNCING") &&
        state_ == AppState::BOOT_INIT) {
        const bool has_backup = (backup_storage_ != nullptr &&
                                 backup_storage_->isAvailable() &&
                                 !inspection_source_event_id_.empty() &&
                                 backup_storage_->hasScanBackup(inspection_source_event_id_));
        if (has_backup && inspection_crash_retries_ < 2) {
            inspection_crash_retries_++;
            pending_sync_backup_id_ = inspection_source_event_id_;
            transitionTo((restored_operation_status_ == "ANALYZING")
                             ? AppState::ANALYZING
                             : AppState::SYNCING);
            saveCurrentStateToNvs();
            Serial.printf("[APP] Recovering pending %s for inspection ID %s from SD backup (crash retry %u)\n",
                          restored_operation_status_.c_str(),
                          inspection_source_event_id_.c_str(),
                          static_cast<unsigned>(inspection_crash_retries_));
        } else {
            if (has_backup && inspection_crash_retries_ >= 2) {
                Serial.printf("[APP] Backup recovery crash retries exhausted (%u) for inspection ID %s. Resetting to IDLE.\n",
                              static_cast<unsigned>(inspection_crash_retries_),
                              inspection_source_event_id_.c_str());
                if (cloud_ != nullptr) {
                    cloud_->abortInspection(inspection_source_event_id_, "crash_recovery_exhausted");
                }
                backup_storage_->removeScanBackup(inspection_source_event_id_);
            } else {
                Serial.println(F("[APP] Pending ANALYZING/SYNCING has no SD backup available. Resetting to IDLE."));
            }
            inspection_source_event_id_.clear();
            pending_sync_backup_id_.clear();
            last_completed_panel_ = 0;
            inspection_crash_retries_ = 0;
            if (storage_ != nullptr) {
                storage_->clearInspectionProgress();
            }
            transitionTo(AppState::IDLE);
            saveCurrentStateToNvs();
        }
    }

    // Check if an inspection was interrupted by a crash/power cycle during SCANNING
    if (!inspection_source_event_id_.empty() && state_ == AppState::BOOT_INIT) {
        if (inspection_crash_retries_ < MAX_INSPECTION_CRASH_RETRIES) {
            inspection_crash_retries_++;
            saveCurrentStateToNvs();
            transitionTo(AppState::SCANNING);
            Serial.printf("[APP] Resuming interrupted inspection ID %s from panel %u (crash retry %u)\n",
                          inspection_source_event_id_.c_str(),
                          static_cast<unsigned>(last_completed_panel_ + 1),
                          static_cast<unsigned>(inspection_crash_retries_));
        } else {
            Serial.printf("[APP] Inspection crash retries exhausted (%u). Aborting inspection ID %s.\n",
                          static_cast<unsigned>(inspection_crash_retries_),
                          inspection_source_event_id_.c_str());
            if (cloud_ != nullptr) {
                cloud_->abortInspection(inspection_source_event_id_, "crash_recovery_exhausted");
            }
            inspection_source_event_id_.clear();
            last_completed_panel_ = 0;
            inspection_crash_retries_ = 0;
            if (storage_ != nullptr) {
                storage_->clearInspectionProgress();
            }
            saveCurrentStateToNvs();
            transitionTo(AppState::IDLE);
        }
    }

    // If no verification was pending from prior power cycle, proceed to IDLE
    if (state_ == AppState::BOOT_INIT) {
        transitionTo(AppState::IDLE);
    }
}


} // namespace app
