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
        cleaning_sm_.resetForNewAnomaly();
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
    inspection_source_event_id_ = utils::generateUUIDv4();
    inspection_started_at_ = getCurrentTime();
    inspection_scheduled_for_ = (time_provider_ && time_provider_->isTimeSynchronized())
                                ? inspection_started_at_ : 0;

    histogram_.reset();
    quantized_frames_.clear();
    current_batch_.clear();
    scan_truncated_by_memory_ = false;

    utils::HeapTracker::start();

    const float max_x = config_.panel_length_cm;
    float current_x = 0.0f;

    // Local structures to maintain lifetime of batch pointers during ingestion
    std::vector<std::vector<float>> batch_frames_data;
    std::vector<PowerSnapshot> batch_power_data;
    batch_frames_data.reserve(5);
    batch_power_data.reserve(5);

    while (current_x <= max_x) {
        // Truncation check: safe limit of 35 acquisitions (0 to 68 cm rail, ~73 cm thermal coverage)
        if (quantized_frames_.size() >= SCAN_MAX_ACQUISITIONS) {
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
            power_meter_->readSnapshot(power);
        }

        if (frame_ok) {
            histogram_.addFrame(frame);

            std::string meas_id = utils::generateUUIDv4();
            uint32_t meas_time = getCurrentTime();

            domain::QuantizedThermalFrame qf;
            qf.loadFromThermalFrame(frame, current_x, meas_time, meas_id);
            quantized_frames_.push_back(qf);

            // Compute frame max temperature
            float max_temp = -999.0f;
            for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
                if (frame.pixels[i] > max_temp) max_temp = frame.pixels[i];
            }

            // Prepare batch buffers
            std::vector<float> frame_copy(frame.pixels, frame.pixels + ThermalFrame::PIXEL_COUNT);
            batch_frames_data.push_back(frame_copy);
            batch_power_data.push_back(power);

            TelemetryMeasurementItem item;
            item.source_event_id = meas_id;
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

            // Check if batch is full (5 items) or scan reached end/truncation
            const bool is_last_step = ((current_x + STEP_SIZE_CM) > max_x) ||
                                      (quantized_frames_.size() >= SCAN_MAX_ACQUISITIONS);

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

                // Immediately release batch transmission buffers from RAM
                current_batch_.clear();
                batch_frames_data.clear();
                batch_power_data.clear();
            }
        }

        current_x += STEP_SIZE_CM;
    }

    // Return linear carriage to origin X = 0.0 cm
    if (motion_ != nullptr) {
        motion_->moveToXCm(0.0f);
    }

    utils::HeapTracker::update();

    if (!quantized_frames_.empty()) {
        state_ = AppState::ANALYZING;
    } else {
        state_ = AppState::IDLE;
    }
}

void ThermoscanApp::handleAnalyzing() {
    baseline_temp_c_ = histogram_.calculateMedian();

    auto confirmed = thermal_analyzer_.analyzeQuantizedScan(
        quantized_frames_, baseline_temp_c_, ThermalAnalyzer::DEFAULT_POSITION_TOLERANCE_CM, true);

    FinalizeInspectionInput fin;
    fin.finished_at_epoch = getCurrentTime();
    fin.baseline_temperature_c = baseline_temp_c_;

    for (const auto& ev : confirmed) {
        ConfirmedHotspotOutput ho;
        ho.source_event_id = utils::generateUUIDv4();
        ho.global_x_position_cm = ev.target_x_cm;
        ho.row_index = ev.row;
        ho.max_temperature_c = ev.max_temp_c;
        ho.detected_at_epoch = fin.finished_at_epoch;
        ho.origin_measurement_event_id = ev.origin_measurement_event_id;
        ho.confirming_event_ids = ev.confirming_event_ids;
        fin.confirmed_hotspots.push_back(ho);
    }

    if (cloud_ != nullptr) {
        cloud_->finalizeInspection(inspection_source_event_id_, fin);
        active_anomaly_id_ = cloud_->getLastConfirmedAnomalyId();
    }

    utils::HeapTracker::stop();

    // Release quantized thermal frame matrices strictly after successful finalization
    quantized_frames_.clear();
    quantized_frames_.shrink_to_fit();

    if (!confirmed.empty()) {
        // Pick primary anomaly with highest thermal delta
        domain::HotspotEvent worst = confirmed[0];
        for (const auto& ev : confirmed) {
            if (ev.max_temp_c > worst.max_temp_c) {
                worst = ev;
            }
        }
        active_hotspot_ = worst;
        cleaning_sm_.resetForNewAnomaly();
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
        // Interlock refused spray: status refused, pump_actuated false, attempt not consumed
        CleaningReportInput cr;
        cr.anomaly_event_id = active_anomaly_id_;
        cr.target_x_position_cm = active_hotspot_.target_x_cm;
        cr.pump_actuated = false;
        cr.attempt_number = 0;
        cr.duration_seconds = 0.0f;
        cr.status = "refused";
        cr.failure_reason = cleaning_sm_.getReason();

        if (cloud_ != nullptr) {
            std::string out_id;
            cloud_->ingestCleaningReport(cr, out_id);
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
#if defined(ARDUINO) || defined(ESP32)
        delay(SERVO_SETTLE_DELAY_MS);
#endif
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
        const uint32_t check_now = getCurrentTime();
        if (!cleaning_sm_.monitorDuringSpray(fluid, check_now)) {
            // Fluid depleted: immediately halt pump and record interruption timestamp
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

    const uint32_t end_time = getCurrentTime();
    if (!spray_interrupted) {
        if (spray_ != nullptr) {
            spray_->stopPump();
        }
        cleaning_sm_.finishSpray(end_time);
    }

    // Report cleaning actuation record to cloud
    CleaningReportInput cr;
    cr.anomaly_event_id = active_anomaly_id_;
    cr.target_x_position_cm = active_hotspot_.target_x_cm;
    cr.pump_actuated = true;
    cr.attempt_number = cleaning_sm_.getEffectiveAttempts();
    cr.duration_seconds = (end_time >= start_time) ? (end_time - start_time) : 3.5f;
    cr.status = (cleaning_sm_.getStatus() == domain::CleaningStatus::COMPLETED) ? "completed" : "failed";
    cr.failure_reason = cleaning_sm_.getReason();

    if (cloud_ != nullptr) {
        cloud_->ingestCleaningReport(cr, current_cleaning_op_id_);
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

    // Send periodic health pings while in cooldown wait (if now > 0)
    if (cloud_ != nullptr && now > 0 &&
        (now - last_ping_time_) >= static_cast<uint32_t>(config_.ping_interval_seconds)) {
        cloud_->sendPing();
        last_ping_time_ = now;
    }
}

void ThermoscanApp::handleVerifying() {
    float x1 = active_hotspot_.target_x_cm;
    float x2 = (x1 + 2.0f <= config_.panel_length_cm) ? (x1 + 2.0f) : (x1 - 2.0f);
    if (x2 < 0.0f) x2 = 0.0f;

    std::string verif_insp_id = utils::generateUUIDv4();
    uint32_t now = getCurrentTime();

    IngestTelemetryBatchInput batch_input;
    batch_input.inspection_source_event_id = verif_insp_id;
    batch_input.inspection_type = "verification";
    batch_input.cleaning_operation_id = current_cleaning_op_id_;
    batch_input.started_at_epoch = now;
    batch_input.scheduled_for_epoch = now;

    // Measurement 1
    if (motion_ != nullptr) motion_->moveToXCm(x1);
    ThermalFrame frame1;
    bool valid1 = (camera_ != nullptr) ? camera_->captureFrame(frame1) : false;
    PowerSnapshot power1;
    if (power_meter_ != nullptr) power_meter_->readSnapshot(power1);

    TelemetryMeasurementItem item1;
    item1.source_event_id = utils::generateUUIDv4();
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
    if (power_meter_ != nullptr) power_meter_->readSnapshot(power2);

    TelemetryMeasurementItem item2;
    item2.source_event_id = utils::generateUUIDv4();
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

    bool hotspot_still_present = false;
    if (valid1 && (max_t1 - baseline_temp_c_) >= HOTSPOT_THRESHOLD_DELTA_C) {
        hotspot_still_present = true;
    }
    if (valid2 && (max_t2 - baseline_temp_c_) >= HOTSPOT_THRESHOLD_DELTA_C) {
        hotspot_still_present = true;
    }

    domain::AnomalyResult result = cleaning_sm_.processVerificationResult(hotspot_still_present, (valid1 || valid2));

    // Finalize verification inspection on cloud (this allows the backend to update cleaning & anomaly)
    if (cloud_ != nullptr) {
        FinalizeInspectionInput vfin;
        vfin.finished_at_epoch = now + 2;
        vfin.baseline_temperature_c = baseline_temp_c_;
        if (hotspot_still_present) {
            ConfirmedHotspotOutput ho;
            ho.source_event_id = utils::generateUUIDv4();
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

    // Return to home position
    if (motion_ != nullptr) {
        motion_->moveToXCm(0.0f);
    }

    if (result == domain::AnomalyResult::RESOLVED) {
        active_hotspot_ = domain::HotspotEvent{};
        active_anomaly_id_.clear();
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
        if (cloud_->getConfiguration(cfg_json)) {
            cloud_->ackConfiguration(config_.config_version);
        }
    }
    state_ = AppState::IDLE;
}

} // namespace app
