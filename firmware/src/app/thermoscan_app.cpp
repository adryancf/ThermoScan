#include "thermoscan_app.h"
#include <cmath>
#include <algorithm>
#include <ArduinoJson.h>

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
        // Sem horário confiável, não presumir janela solar válida
        return false;
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
    if (motion_ != nullptr) {
        motion_->emergencyStop();
    }
    state_ = AppState::ERROR_HALT;
}

void ThermoscanApp::returnToSafeIdle() {
    if (spray_ != nullptr) {
        spray_->stopPump();
    }
    if (motion_ != nullptr) {
        motion_->disableMotor();
    }
    state_ = AppState::IDLE;
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
    s.active_hotspot_x_cm = active_hotspot_.target_x_cm;
    s.baseline_temp_c = baseline_temp_c_;
    s.cleaning_operation_id = current_cleaning_op_id_;
    s.inspection_source_event_id = inspection_source_event_id_;
    if (!active_anomaly_id_.empty()) {
        s.anomaly_event_id = active_anomaly_id_;
    } else if (active_hotspot_.confirmed) {
        s.anomaly_event_id = active_hotspot_.origin_measurement_event_id;
    }
    storage_->saveAll(s);
}

void ThermoscanApp::restoreStateFromNvs() {
    if (storage_ == nullptr) return;

    StorageState s;
    if (storage_->loadAll(s)) {
        next_inspection_time_ = s.next_inspection_timestamp;
        active_hotspot_.target_x_cm = s.active_hotspot_x_cm;
        active_hotspot_.confirmed = s.pending_verification;
        active_hotspot_.origin_measurement_event_id = s.anomaly_event_id;
        active_anomaly_id_ = s.anomaly_event_id;
        baseline_temp_c_ = s.baseline_temp_c;
        current_cleaning_op_id_ = s.cleaning_operation_id;
        inspection_source_event_id_ = s.inspection_source_event_id;

        // Restore cleaning queue from NVS
        storage_->getCleaningQueue(cleaning_queue_);

        if (!cleaning_queue_.empty()) {
            bool has_cleaned = false;
            bool has_pending = false;
            for (const auto& qh : cleaning_queue_) {
                if (qh.verification_status == "cleaned") has_cleaned = true;
                if (qh.verification_status == "pending") has_pending = true;
            }

            if (has_cleaned && s.spray_ended_timestamp > 0) {
                cleaning_sm_.restoreState(CleaningStatus::COMPLETED,
                                          AnomalyResult::OPEN,
                                          s.effective_attempts,
                                          s.spray_ended_timestamp);
                state_ = AppState::WAITING_VERIFICATION;
            } else if (has_pending) {
                cleaning_sm_.restoreState(CleaningStatus::IDLE,
                                          AnomalyResult::OPEN,
                                          s.effective_attempts,
                                          0);
                state_ = AppState::CLEANING;
            } else {
                cleaning_queue_.clear();
                storage_->clearCleaningQueue();
                state_ = AppState::IDLE;
            }
        } else if (s.pending_verification && s.spray_ended_timestamp > 0) {
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
    // SAFE BOOT GUARANTEE: Force pump OFF and stepper disabled immediately
    if (spray_ != nullptr) {
        spray_->stopPump();
    }
    if (motion_ != nullptr) {
        motion_->disableMotor();
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
            if (motion_ != nullptr) motion_->disableMotor();
            break;
    }
}

void ThermoscanApp::handleIdle() {
    const uint32_t now = getCurrentTime();

    // Periodic telemetry ping (only if clock is synchronized, preventing loop when now == 0)
    if (cloud_ != nullptr && now > 0 &&
        (now - last_ping_time_) >= static_cast<uint32_t>(config_.ping_interval_seconds)) {
        cloud_->sendPing();
        last_ping_time_ = now;
        if (cloud_->isConfigurationPending()) {
            config_update_pending_ = true;
            config_sync_failed_waiting_ping_ = false;
        }
    }

    // 1. Manual commands have highest priority
    if (manual_inspection_requested_) {
        manual_inspection_requested_ = false;
        state_ = AppState::SCANNING;
        return;
    }

    if (manual_cleaning_requested_) {
        manual_cleaning_requested_ = false;
        cleaning_queue_.clear();
        domain::PanelPositionInfo pos = domain::resolvePanelPosition(
            config_.panel_count, config_.panel_length_cm, config_.panel_spacing_cm, manual_cleaning_target_x_);
        QueuedHotspot qh;
        qh.panel_index = pos.panel_index;
        qh.target_x_cm = manual_cleaning_target_x_;
        qh.anomaly_event_id = utils::generateUUIDv4();
        qh.cleaning_operation_id = "";
        qh.attempts = 0;
        qh.verification_status = "pending";
        qh.baseline_temp_c = baseline_temp_c_;
        cleaning_queue_.push_back(qh);

        active_hotspot_.target_x_cm = manual_cleaning_target_x_;
        active_hotspot_.confirmed = true;
        cleaning_sm_.resetForNewAnomaly();
        if (storage_ != nullptr) {
            storage_->saveCleaningQueue(cleaning_queue_);
        }
        state_ = AppState::CLEANING;
        return;
    }

    // 2. Pending configuration synchronization
    if (config_update_pending_ && !config_sync_failed_waiting_ping_) {
        state_ = AppState::SYNCING;
        return;
    }

    // 3. Scheduled inspection evaluation
    if (now > 0 && next_inspection_time_ > 0 && now >= next_inspection_time_) {
        if (checkSolarWindow()) {
            state_ = AppState::SCANNING;
            return;
        }
    }
}

void ThermoscanApp::handleScanning() {
    inspection_source_event_id_ = utils::generateUUIDv4();
    inspection_started_at_ = getCurrentTime();
    inspection_scheduled_for_ = (time_provider_ && time_provider_->isTimeSynchronized())
                                ? inspection_started_at_ : 0;

    all_confirmed_hotspots_.clear();
    current_batch_.clear();
    scan_truncated_by_memory_ = false;

    utils::HeapTracker::start();

    const uint8_t total_panels = (config_.panel_count > 0) ? static_cast<uint8_t>(config_.panel_count) : 1;

    for (uint8_t p = 1; p <= total_panels; ++p) {
        float p_start = 0.0f, p_end = 0.0f;
        domain::getPanelBounds(p, config_.panel_length_cm, config_.panel_spacing_cm, p_start, p_end);

        histogram_.reset();
        quantized_frames_.clear();
        bool panel_truncated = false;

        float current_x = p_start;

        std::vector<std::vector<float>> batch_frames_data;
        std::vector<PowerSnapshot> batch_power_data;
        batch_frames_data.reserve(5);
        batch_power_data.reserve(5);

        while (current_x <= p_end + 1e-3f) {
            if (quantized_frames_.size() >= MAX_PANEL_ACQUISITIONS) {
                panel_truncated = true;
                scan_truncated_by_memory_ = true;
                break;
            }

            if (motion_ != nullptr) {
                motion_->moveToXCm(current_x);
            }

            ThermalFrame frame;
            bool frame_ok = false;
            if (camera_ != nullptr) {
                frame_ok = camera_->captureFrame(frame);
            }

            PowerSnapshot power;
            if (power_meter_ != nullptr) {
                power_meter_->readSnapshotForPanel(p, power);
            }

            if (frame_ok) {
                histogram_.addFrame(frame);

                std::string meas_id = utils::generateUUIDv4();
                uint32_t meas_time = getCurrentTime();

                domain::QuantizedThermalFrame qf;
                qf.loadFromThermalFrame(frame, current_x, meas_time, meas_id);
                quantized_frames_.push_back(qf);

                float max_temp = -999.0f;
                for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
                    if (frame.pixels[i] > max_temp) max_temp = frame.pixels[i];
                }

                std::vector<float> frame_copy(frame.pixels, frame.pixels + ThermalFrame::PIXEL_COUNT);
                batch_frames_data.push_back(frame_copy);
                batch_power_data.push_back(power);

                TelemetryMeasurementItem item;
                item.source_event_id = meas_id;
                item.panel_index = p;
                item.measured_at_epoch = meas_time;
                item.x_position_cm = current_x;
                item.max_temperature_c = max_temp;

                size_t idx = batch_power_data.size() - 1;
                if (batch_power_data[idx].valid) {
                    item.voltage_v = &batch_power_data[idx].voltage_v;
                    item.current_a = &batch_power_data[idx].current_a;
                    item.power_w = &batch_power_data[idx].power_w;
                } else {
                    item.voltage_v = nullptr;
                    item.current_a = nullptr;
                    item.power_w = nullptr;
                }

                item.thermal_frame = batch_frames_data[idx].data();
                item.thermal_frame_size = ThermalFrame::PIXEL_COUNT;
                current_batch_.push_back(item);

                const bool is_last_step = ((current_x + STEP_SIZE_CM) > (p_end + 1e-3f)) ||
                                          (quantized_frames_.size() >= MAX_PANEL_ACQUISITIONS);

                if (current_batch_.size() >= 5 || is_last_step) {
                    if (cloud_ != nullptr) {
                        IngestTelemetryBatchInput batch_input;
                        batch_input.inspection_source_event_id = inspection_source_event_id_;
                        batch_input.inspection_type = "scheduled";
                        batch_input.started_at_epoch = inspection_started_at_;
                        batch_input.scheduled_for_epoch = inspection_scheduled_for_;
                        batch_input.batch = current_batch_;

                        cloud_->ingestTelemetryBatch(batch_input);
                    }

                    current_batch_.clear();
                    batch_frames_data.clear();
                    batch_power_data.clear();
                }
            }

            current_x += STEP_SIZE_CM;
        }

        // Panel baseline calculation
        float panel_baseline = histogram_.calculateMedian();
        if (panel_baseline <= 0.0f) {
            panel_baseline = 25.0f;
        }
        if (p < 16) {
            panel_baselines_[p] = panel_baseline;
        }
        baseline_temp_c_ = panel_baseline;

        auto confirmed = thermal_analyzer_.analyzeQuantizedScan(
            quantized_frames_, panel_baseline, ThermalAnalyzer::DEFAULT_POSITION_TOLERANCE_CM, true);

        PanelThermalResultInput p_input;
        p_input.panel_index = p;
        p_input.baseline_temperature_c = panel_baseline;
        p_input.truncated_by_memory = panel_truncated;
        p_input.finished_at_epoch = getCurrentTime();

        for (const auto& ev : confirmed) {
            ConfirmedHotspotOutput ho;
            ho.source_event_id = utils::generateUUIDv4();
            ho.panel_index = p;
            ho.global_x_position_cm = ev.target_x_cm;
            ho.row_index = ev.row;
            ho.max_temperature_c = ev.max_temp_c;
            ho.detected_at_epoch = p_input.finished_at_epoch;
            ho.origin_measurement_event_id = ev.origin_measurement_event_id;
            ho.confirming_event_ids = ev.confirming_event_ids;
            p_input.confirmed_hotspots.push_back(ho);
            all_confirmed_hotspots_.push_back(ho);
        }

        // Submit panel thermal result with retry & backoff
        bool result_accepted = false;
        if (cloud_ != nullptr) {
            for (int retry = 0; retry < 3; ++retry) {
                if (cloud_->submitPanelThermalResult(inspection_source_event_id_, p_input)) {
                    result_accepted = true;
                    break;
                }
#if defined(ARDUINO) || defined(ESP32)
                delay(500 * (retry + 1));
#endif
            }
        } else {
            result_accepted = true;
        }

        // Release quantized memory per panel strictly after transmission
        quantized_frames_.clear();
        quantized_frames_.shrink_to_fit();

        // Inter-panel gap traversal: move carriage across gap without capturing or spraying
        if (p < total_panels) {
            float next_start = 0.0f, next_end = 0.0f;
            domain::getPanelBounds(p + 1, config_.panel_length_cm, config_.panel_spacing_cm, next_start, next_end);
            if (motion_ != nullptr) {
                motion_->moveToXCm(next_start);
            }
        }
    }

    // Return linear carriage to origin X = 0.0 cm
    if (motion_ != nullptr) {
        motion_->moveToXCm(0.0f);
    }

    utils::HeapTracker::update();

    state_ = AppState::ANALYZING;
}

void ThermoscanApp::handleAnalyzing() {
    FinalizeInspectionInput fin;
    fin.finished_at_epoch = getCurrentTime();
    fin.baseline_temperature_c = 0.0f; // backend computes consolidated average across panel results
    fin.confirmed_hotspots = all_confirmed_hotspots_;

    if (cloud_ != nullptr) {
        cloud_->finalizeInspection(inspection_source_event_id_, fin);
        active_anomaly_id_ = cloud_->getLastConfirmedAnomalyId();
    }

    utils::HeapTracker::stop();

    cleaning_queue_.clear();

    if (!all_confirmed_hotspots_.empty()) {
        // Sort hotspots by ascending global X position
        std::sort(all_confirmed_hotspots_.begin(), all_confirmed_hotspots_.end(),
                  [](const ConfirmedHotspotOutput& a, const ConfirmedHotspotOutput& b) {
                      return a.global_x_position_cm < b.global_x_position_cm;
                  });

        for (const auto& ho : all_confirmed_hotspots_) {
            QueuedHotspot qh;
            qh.panel_index = ho.panel_index;
            qh.target_x_cm = ho.global_x_position_cm;
            qh.anomaly_event_id = !active_anomaly_id_.empty() ? active_anomaly_id_ : ho.source_event_id;
            qh.cleaning_operation_id = "";
            qh.attempts = 0;
            qh.verification_status = "pending";
            qh.baseline_temp_c = (ho.panel_index < 16 && panel_baselines_[ho.panel_index] > 0.0f)
                                 ? panel_baselines_[ho.panel_index] : baseline_temp_c_;
            cleaning_queue_.push_back(qh);
        }

        active_hotspot_.target_x_cm = cleaning_queue_[0].target_x_cm;
        active_hotspot_.confirmed = true;
        cleaning_sm_.resetForNewAnomaly();

        if (storage_ != nullptr) {
            storage_->saveCleaningQueue(cleaning_queue_);
        }
        saveCurrentStateToNvs();
        state_ = AppState::CLEANING;
    } else {
        const uint32_t now = getCurrentTime();
        if (now > 0) {
            next_inspection_time_ = now + static_cast<uint32_t>(config_.interval_days * 86400);
        }
        if (storage_ != nullptr) {
            storage_->clearCleaningQueue();
        }
        saveCurrentStateToNvs();
        state_ = AppState::SYNCING;
    }
}

void ThermoscanApp::handleCleaning() {
    if (cleaning_queue_.empty()) {
        state_ = AppState::SYNCING;
        return;
    }

    bool any_sprayed = false;
    uint32_t last_spray_end = 0;

    for (size_t i = 0; i < cleaning_queue_.size(); ++i) {
        auto& qh = cleaning_queue_[i];
        if (qh.verification_status != "pending") {
            if (qh.verification_status == "cleaned") {
                any_sprayed = true;
            }
            continue;
        }

        // Check if target is in gap
        domain::PanelPositionInfo pos = domain::resolvePanelPosition(
            config_.panel_count, config_.panel_length_cm, config_.panel_spacing_cm, qh.target_x_cm);

        const bool water_ok = (water_sensor_ != nullptr) ? water_sensor_->isWaterAvailable() : true;
        const bool is_in_gap = pos.in_gap;

        // Evaluate pre-spray safety interlocks with is_in_gap
        if (!cleaning_sm_.evaluateBeforeSpray(qh.baseline_temp_c, water_ok, is_in_gap)) {
            CleaningReportInput cr;
            cr.anomaly_event_id = qh.anomaly_event_id;
            cr.panel_index = qh.panel_index;
            cr.target_x_position_cm = qh.target_x_cm;
            cr.pump_actuated = false;
            cr.attempt_number = 0;
            cr.duration_seconds = 0.0f;
            cr.status = "refused";
            cr.failure_reason = cleaning_sm_.getReason();

            if (cloud_ != nullptr) {
                std::string out_id;
                cloud_->ingestCleaningReport(cr, out_id);
            }
            qh.verification_status = "refused";
            if (storage_ != nullptr) {
                storage_->saveCleaningQueue(cleaning_queue_);
            }
            // If failure reason is target_in_gap, continue to next hotspot without consuming attempts
            if (is_in_gap) {
                continue;
            }
            // If water depleted or extreme overheat, stop cleaning loop
            break;
        }

        // Position carriage at target X and align nozzle
        if (motion_ != nullptr) {
            motion_->moveToXCm(qh.target_x_cm);
        }
        if (spray_ != nullptr) {
            spray_->setNozzleAngle(90.0f);
#if defined(ARDUINO) || defined(ESP32)
            delay(SERVO_SETTLE_DELAY_MS);
#endif
        }

        cleaning_sm_.startSpray();
        const uint32_t start_time = getCurrentTime();

        if (spray_ != nullptr) {
            spray_->startPump();
        }

        bool spray_interrupted = false;
        for (int step = 0; step < 35; ++step) {
            const bool fluid = (water_sensor_ != nullptr) ? water_sensor_->isWaterAvailable() : true;
            const uint32_t check_now = getCurrentTime();
            if (!cleaning_sm_.monitorDuringSpray(fluid, check_now)) {
                if (spray_ != nullptr) spray_->stopPump();
                spray_interrupted = true;
                break;
            }
#if defined(ARDUINO) || defined(ESP32)
            delay(100);
#endif
        }

        const uint32_t end_time = getCurrentTime();
        if (!spray_interrupted) {
            if (spray_ != nullptr) spray_->stopPump();
            cleaning_sm_.finishSpray(end_time);
        }
        last_spray_end = end_time;
        any_sprayed = true;

        CleaningReportInput cr;
        cr.anomaly_event_id = qh.anomaly_event_id;
        cr.panel_index = qh.panel_index;
        cr.target_x_position_cm = qh.target_x_cm;
        cr.pump_actuated = true;
        cr.attempt_number = cleaning_sm_.getEffectiveAttempts();
        cr.duration_seconds = (end_time >= start_time) ? (end_time - start_time) : 3.5f;
        cr.status = (cleaning_sm_.getStatus() == domain::CleaningStatus::COMPLETED) ? "completed" : "failed";
        cr.failure_reason = cleaning_sm_.getReason();

        if (cloud_ != nullptr) {
            cloud_->ingestCleaningReport(cr, qh.cleaning_operation_id);
        }

        qh.attempts = cleaning_sm_.getEffectiveAttempts();
        qh.verification_status = "cleaned";

        if (storage_ != nullptr) {
            storage_->saveCleaningQueue(cleaning_queue_);
        }
    }

    // Return carriage to home
    if (motion_ != nullptr) {
        motion_->moveToXCm(0.0f);
    }

    if (any_sprayed) {
        if (last_spray_end > 0) {
            cleaning_sm_.setSprayEndedTimestamp(last_spray_end);
        }
        saveCurrentStateToNvs();
        state_ = AppState::WAITING_VERIFICATION;
    } else {
        saveCurrentStateToNvs();
        state_ = AppState::SYNCING;
    }
}

void ThermoscanApp::handleWaitingVerification() {
    const uint32_t now = getCurrentTime();
    const bool solar_ok = checkSolarWindow();

    // Strict 1800-second cooldown AND valid solar elevation window
    if (cleaning_sm_.canStartVerification(now, solar_ok)) {
        state_ = AppState::VERIFYING;
        return;
    }

    // Send periodic health pings while in cooldown wait (if now > 0)
    if (cloud_ != nullptr && now > 0 &&
        (now - last_ping_time_) >= static_cast<uint32_t>(config_.ping_interval_seconds)) {
        cloud_->sendPing();
        last_ping_time_ = now;
        if (cloud_->isConfigurationPending()) {
            config_update_pending_ = true;
            config_sync_failed_waiting_ping_ = false;
        }
    }
}

void ThermoscanApp::handleVerifying() {
    bool any_retry_allowed = false;
    for (auto& qh : cleaning_queue_) {
        if (qh.verification_status != "cleaned") {
            continue;
        }

        // Determine bounds of target panel
        float p_start = 0.0f, p_end = config_.panel_length_cm;
        if (qh.panel_index > 0) {
            domain::getPanelBounds(qh.panel_index, config_.panel_length_cm, config_.panel_spacing_cm, p_start, p_end);
        }

        float x1 = qh.target_x_cm;
        float x2 = (x1 + 2.0f <= p_end) ? (x1 + 2.0f) : (x1 - 2.0f);
        if (x2 < p_start) x2 = p_start;

        std::string verif_insp_id = utils::generateUUIDv4();
        uint32_t now = getCurrentTime();

        IngestTelemetryBatchInput batch_input;
        batch_input.inspection_source_event_id = verif_insp_id;
        batch_input.inspection_type = "verification";
        batch_input.cleaning_operation_id = qh.cleaning_operation_id;
        batch_input.started_at_epoch = now;
        batch_input.scheduled_for_epoch = now;

        // Measurement 1
        if (motion_ != nullptr) motion_->moveToXCm(x1);
        ThermalFrame frame1;
        bool valid1 = (camera_ != nullptr) ? camera_->captureFrame(frame1) : false;
        PowerSnapshot power1;
        if (power_meter_ != nullptr) power_meter_->readSnapshotForPanel(qh.panel_index, power1);

        TelemetryMeasurementItem item1;
        item1.source_event_id = utils::generateUUIDv4();
        item1.panel_index = qh.panel_index;
        item1.measured_at_epoch = now;
        item1.x_position_cm = x1;
        float max_t1 = -999.0f;
        if (valid1) {
            for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
                if (frame1.pixels[i] > max_t1) max_t1 = frame1.pixels[i];
            }
        }
        item1.max_temperature_c = max_t1;
        if (power1.valid) {
            item1.voltage_v = &power1.voltage_v;
            item1.current_a = &power1.current_a;
            item1.power_w = &power1.power_w;
        } else {
            item1.voltage_v = nullptr;
            item1.current_a = nullptr;
            item1.power_w = nullptr;
        }
        item1.thermal_frame = frame1.pixels;
        item1.thermal_frame_size = ThermalFrame::PIXEL_COUNT;
        batch_input.batch.push_back(item1);

        // Measurement 2
        if (motion_ != nullptr) motion_->moveToXCm(x2);
        ThermalFrame frame2;
        bool valid2 = (camera_ != nullptr) ? camera_->captureFrame(frame2) : false;
        PowerSnapshot power2;
        if (power_meter_ != nullptr) power_meter_->readSnapshotForPanel(qh.panel_index, power2);

        TelemetryMeasurementItem item2;
        item2.source_event_id = utils::generateUUIDv4();
        item2.panel_index = qh.panel_index;
        item2.measured_at_epoch = now + 1;
        item2.x_position_cm = x2;
        float max_t2 = -999.0f;
        if (valid2) {
            for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
                if (frame2.pixels[i] > max_t2) max_t2 = frame2.pixels[i];
            }
        }
        item2.max_temperature_c = max_t2;
        if (power2.valid) {
            item2.voltage_v = &power2.voltage_v;
            item2.current_a = &power2.current_a;
            item2.power_w = &power2.power_w;
        } else {
            item2.voltage_v = nullptr;
            item2.current_a = nullptr;
            item2.power_w = nullptr;
        }
        item2.thermal_frame = frame2.pixels;
        item2.thermal_frame_size = ThermalFrame::PIXEL_COUNT;
        batch_input.batch.push_back(item2);

        if (cloud_ != nullptr && (valid1 || valid2)) {
            cloud_->ingestTelemetryBatch(batch_input);
        }

        // Compare against panel baseline
        float verif_baseline = (qh.baseline_temp_c > 0.0f) ? qh.baseline_temp_c : baseline_temp_c_;
        bool hotspot_still_present = false;
        if (valid1 && (max_t1 - verif_baseline) >= HOTSPOT_THRESHOLD_DELTA_C) {
            hotspot_still_present = true;
        }
        if (valid2 && (max_t2 - verif_baseline) >= HOTSPOT_THRESHOLD_DELTA_C) {
            hotspot_still_present = true;
        }

        domain::AnomalyResult result = cleaning_sm_.processVerificationResult(hotspot_still_present, (valid1 || valid2));
        if (result == domain::AnomalyResult::OPEN || result == domain::AnomalyResult::PENDING_EVALUATION) {
            any_retry_allowed = true;
        }

        if (cloud_ != nullptr) {
            FinalizeInspectionInput vfin;
            vfin.finished_at_epoch = now + 2;
            vfin.baseline_temperature_c = verif_baseline;
            if (hotspot_still_present) {
                ConfirmedHotspotOutput ho;
                ho.source_event_id = utils::generateUUIDv4();
                ho.panel_index = qh.panel_index;
                ho.global_x_position_cm = x1;
                ho.max_temperature_c = (max_t1 > max_t2) ? max_t1 : max_t2;
                ho.detected_at_epoch = now + 1;
                ho.origin_measurement_event_id = item1.source_event_id;
                ho.confirming_event_ids.push_back(item1.source_event_id);
                ho.confirming_event_ids.push_back(item2.source_event_id);
                vfin.confirmed_hotspots.push_back(ho);
            }
            cloud_->finalizeInspection(verif_insp_id, vfin);
        }

        qh.verification_status = (result == domain::AnomalyResult::RESOLVED) ? "verified" : "unresolved";
        if (storage_ != nullptr) {
            storage_->saveCleaningQueue(cleaning_queue_);
        }
    }

    // Return to home position
    if (motion_ != nullptr) {
        motion_->moveToXCm(0.0f);
    }

    cleaning_queue_.clear();
    if (storage_ != nullptr) {
        storage_->clearCleaningQueue();
    }
    saveCurrentStateToNvs();
    state_ = any_retry_allowed ? AppState::IDLE : AppState::SYNCING;
}

void ThermoscanApp::handleSyncing() {
    // Only fetch configuration if a pending update was marked
    if (!config_update_pending_) {
        state_ = AppState::IDLE;
        return;
    }

    if (cloud_ == nullptr || !cloud_->isConnected()) {
        config_sync_failed_waiting_ping_ = true;
        state_ = AppState::IDLE;
        return;
    }

    std::string cfg_json;
    if (!cloud_->getConfiguration(cfg_json)) {
        // getConfiguration failed: keep pending flag true, return to IDLE, retry on next ping
        config_sync_failed_waiting_ping_ = true;
        state_ = AppState::IDLE;
        return;
    }

    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, cfg_json.c_str());
    if (err) {
        last_config_error_ = "json_parse_error";
        config_sync_failed_waiting_ping_ = true;
        state_ = AppState::IDLE;
        return;
    }

    // 1. Version validation
    uint32_t ver = doc["config_version"] | 0;
    if (ver == 0) {
        last_config_error_ = "invalid_version";
        config_sync_failed_waiting_ping_ = true;
        state_ = AppState::IDLE;
        return;
    }

    // 2. Geometry validation
    if (!doc["geometry"].is<JsonObject>()) {
        last_config_error_ = "missing_geometry";
        config_sync_failed_waiting_ping_ = true;
        state_ = AppState::IDLE;
        return;
    }

    float len = doc["geometry"]["panel_length_cm"] | 0.0f;
    float width = doc["geometry"]["panel_width_cm"] | 0.0f;
    int32_t count = doc["geometry"]["panel_count"] | 0;
    float space = doc["geometry"]["panel_spacing_cm"] | -1.0f;

    if (len <= 0.0f || width <= 0.0f || count < 1 || space < 0.0f) {
        last_config_error_ = "invalid_geometry";
        config_sync_failed_waiting_ping_ = true;
        state_ = AppState::IDLE;
        return;
    }

    // 3. Solar angle validation (0 to 90 degrees)
    float min_solar = doc["min_solar_angle"] | -1.0f;
    if (min_solar < 0.0f || min_solar > 90.0f) {
        last_config_error_ = "invalid_solar_angle";
        config_sync_failed_waiting_ping_ = true;
        state_ = AppState::IDLE;
        return;
    }

    // 4. Interval validation (>= 1 day)
    int32_t interval_d = doc["interval_days"] | 0;
    if (interval_d < 1) {
        last_config_error_ = "invalid_interval";
        config_sync_failed_waiting_ping_ = true;
        state_ = AppState::IDLE;
        return;
    }

    // 5. Ping interval validation (>= 10 seconds)
    int32_t ping_s = doc["ping_interval_seconds"] | 0;
    if (ping_s < 10) {
        last_config_error_ = "invalid_ping_interval";
        config_sync_failed_waiting_ping_ = true;
        state_ = AppState::IDLE;
        return;
    }

    // 6. Coordinates validation (optional latitude -90..90, longitude -180..180)
    float lat = config_.latitude;
    if (doc["latitude"].is<float>()) {
        lat = doc["latitude"].as<float>();
        if (lat < -90.0f || lat > 90.0f) {
            last_config_error_ = "invalid_latitude";
            config_sync_failed_waiting_ping_ = true;
            state_ = AppState::IDLE;
            return;
        }
    }

    float lon = config_.longitude;
    if (doc["longitude"].is<float>()) {
        lon = doc["longitude"].as<float>();
        if (lon < -180.0f || lon > 180.0f) {
            last_config_error_ = "invalid_longitude";
            config_sync_failed_waiting_ping_ = true;
            state_ = AppState::IDLE;
            return;
        }
    }

    // All parameters validated successfully!
    last_config_error_.clear();
    const bool interval_changed = (interval_d != config_.interval_days);

    // Apply to RAM
    config_.config_version = ver;
    config_.panel_length_cm = len;
    config_.panel_width_cm = width;
    config_.panel_count = count;
    config_.panel_spacing_cm = space;
    config_.min_solar_angle = min_solar;
    config_.interval_days = interval_d;
    config_.ping_interval_seconds = ping_s;
    config_.latitude = lat;
    config_.longitude = lon;

    // Apply to NVS Flash
    if (storage_ != nullptr) {
        storage_->saveConfigVersion(ver);
        storage_->saveGeometry(len, width, count, space);
        storage_->saveMinSolarAngle(min_solar);
        storage_->saveIntervalDays(interval_d);
        storage_->savePingIntervalSeconds(ping_s);
    }

    // Recalculate scheduled inspection timestamp if interval changed or if first provisioned
    if (interval_changed || next_inspection_time_ == 0) {
        const uint32_t now = getCurrentTime();
        if (now > 0) {
            next_inspection_time_ = now + static_cast<uint32_t>(config_.interval_days * 86400);
            if (storage_ != nullptr) {
                storage_->saveNextInspectionTimestamp(next_inspection_time_);
            }
        }
    }

    // Send acknowledgment only after successful RAM & NVS persistence
    cloud_->ackConfiguration(config_.config_version);
    cloud_->clearConfigurationPending();

    config_update_pending_ = false;
    config_sync_failed_waiting_ping_ = false;
    state_ = AppState::IDLE;
}

} // namespace app
