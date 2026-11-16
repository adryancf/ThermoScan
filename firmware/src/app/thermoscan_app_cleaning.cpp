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

        active_queue_index_ = i;
        active_hotspot_.panel_index = qh.panel_index;
        active_hotspot_.target_x_cm = qh.target_x_cm;
        active_hotspot_.confirmed = true;
        active_anomaly_id_ = qh.anomaly_event_id;

        // Synchronize cleaning_sm_ with THIS hotspot's attempt count before evaluation/spray
        cleaning_sm_.restoreState(domain::CleaningStatus::IDLE,
                                  domain::AnomalyResult::OPEN,
                                  qh.attempts,
                                  0);

        Serial.printf("[CLEANING] Evaluating target %u/%u: Panel %d, X = %.1f cm (Attempt %d)...\n",
                      i + 1, cleaning_queue_.size(), qh.panel_index, qh.target_x_cm, qh.attempts);

        // Check if target is in gap
        domain::PanelPositionInfo pos = domain::resolvePanelPosition(
            config_.panel_count, config_.panel_length_cm, config_.panel_spacing_cm, qh.target_x_cm);

        const bool water_ok = (water_sensor_ != nullptr) ? water_sensor_->isWaterAvailable() : true;
        const bool is_in_gap = pos.in_gap;

        // Evaluate pre-spray safety interlocks with is_in_gap
        if (!cleaning_sm_.evaluateBeforeSpray(qh.baseline_temp_c, water_ok, is_in_gap)) {
            Serial.printf("[CLEANING] Cleaning REFUSED for X = %.1f cm! Reason: %s (in_gap=%d, water_ok=%d)\n",
                          qh.target_x_cm, cleaning_sm_.getReason().c_str(), is_in_gap, water_ok);

            CleaningReportInput cr;
            cr.source_event_id = utils::generateUUIDv4();
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
            // If failure reason is target_in_gap or max_attempts_exceeded for this hotspot, continue to next hotspot
            if (is_in_gap || cleaning_sm_.getReason() == "max_attempts_exceeded") {
                continue;
            }
            // If water depleted or extreme overheat, stop cleaning loop
            break;
        }

        Serial.printf("[CLEANING] Moving to X = %.1f cm and aligning nozzle to %.1f deg...\n", qh.target_x_cm, NOZZLE_DEFAULT_ANGLE);

        // Position carriage at target X and align nozzle
        if (motion_ != nullptr) {
            motion_->moveToXCm(qh.target_x_cm);
        }
        if (spray_ != nullptr) {
            spray_->setNozzleAngle(NOZZLE_DEFAULT_ANGLE);
#if defined(ARDUINO) || defined(ESP32)
            delay(SERVO_SETTLE_DELAY_MS);
#endif
        }

        Serial.printf("[CLEANING] Triggering water spray...\n");
        cleaning_sm_.startSpray();
        const uint32_t start_time = getCurrentTime();

        if (spray_ != nullptr) {
            spray_->startPump();
        }

        bool spray_interrupted = false;
        constexpr uint32_t step_ms = thermoscan_config::SPRAY_STEP_MS;
        const int total_steps = static_cast<int>(DEFAULT_SPRAY_DURATION_MS / step_ms);
        for (int step = 0; step < total_steps; ++step) {
            const bool fluid = (water_sensor_ != nullptr) ? water_sensor_->isWaterAvailable() : true;
            const uint32_t check_now = getCurrentTime();
            if (!cleaning_sm_.monitorDuringSpray(fluid, check_now)) {
                if (spray_ != nullptr) spray_->stopPump();
                spray_interrupted = true;
                Serial.println(F("[CLEANING] Spray interrupted: Water depletion detected!"));
                break;
            }
#if defined(ARDUINO) || defined(ESP32)
            delay(step_ms);
#endif
        }
        if (!spray_interrupted && (DEFAULT_SPRAY_DURATION_MS % step_ms) > 0) {
#if defined(ARDUINO) || defined(ESP32)
            delay(DEFAULT_SPRAY_DURATION_MS % step_ms);
#endif
        }

        const uint32_t end_time = getCurrentTime();
        if (!spray_interrupted) {
            if (spray_ != nullptr) spray_->stopPump();
            cleaning_sm_.finishSpray(end_time);
            Serial.println(F("[CLEANING] Spray completed successfully."));
        }
        last_spray_end = end_time;
        any_sprayed = true;

        CleaningReportInput cr;
        cr.source_event_id = utils::generateUUIDv4();
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

        current_cleaning_op_id_ = qh.cleaning_operation_id;
        qh.attempts = cleaning_sm_.getEffectiveAttempts();
        qh.spray_interrupted = spray_interrupted;
        qh.verification_status = "cleaned";

        if (storage_ != nullptr) {
            storage_->saveCleaningQueue(cleaning_queue_);
        }

        // If water was depleted during spray, stop washing further hotspots in this pass
        if (spray_interrupted) {
            break;
        }
    }

    // Return carriage to home
    if (motion_ != nullptr) {
        motion_->moveToXCm(0.0f);
    }

    if (manual_cleaning_active_) {
        manual_cleaning_active_ = false;
        if (cloud_ != nullptr) {
            cloud_->setManualCleaningAckPending(true);
            cloud_->sendPing();
        }
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
        if (cloud_->isManualInspectionPending()) {
            cloud_->clearManualInspectionPending();
            triggerManualInspection();
        }
        if (cloud_->isManualCleaningPending()) {
            const float target_x = cloud_->getManualCleaningTargetXCm();
            cloud_->clearManualCleaningPending();
            triggerManualCleaning(target_x);
        }
    }
}

void ThermoscanApp::handleVerifying() {
    bool any_retry_allowed = false;
    uint32_t last_spray_end = cleaning_sm_.getSprayEndedTimestamp();

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

        Serial.printf("[VERIFYING] Point X = %.1f cm (Panel %d): T_max1 = %.1f C, T_max2 = %.1f C, Baseline = %.1f C -> %s\n",
                      qh.target_x_cm, qh.panel_index, max_t1, max_t2, verif_baseline,
                      hotspot_still_present ? "HOTSPOT STILL PRESENT" : "HOTSPOT RESOLVED SUCCESSFULLY");

        // Synchronize cleaning_sm_ with THIS hotspot's cleaning status and attempt count
        cleaning_sm_.restoreState(
            qh.spray_interrupted ? domain::CleaningStatus::FAILED : domain::CleaningStatus::COMPLETED,
            domain::AnomalyResult::OPEN,
            qh.attempts,
            last_spray_end);

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

        if (result == domain::AnomalyResult::OPEN && qh.attempts < MAX_CLEANING_ATTEMPTS) {
            // Retain interrupted hotspot for retry on next cleaning pass
            qh.verification_status = "pending";
            qh.spray_interrupted = false;
        } else {
            qh.verification_status = (result == domain::AnomalyResult::RESOLVED) ? "verified" : "unresolved";
        }
        if (storage_ != nullptr) {
            storage_->saveCleaningQueue(cleaning_queue_);
        }
    }

    // Return to home position
    if (motion_ != nullptr) {
        motion_->moveToXCm(0.0f);
    }

    // Retain only pending hotspots (e.g. interrupted washes eligible for retry)
    std::vector<QueuedHotspot> retained_queue;
    for (const auto& qh : cleaning_queue_) {
        if (qh.verification_status == "pending" && qh.attempts < MAX_CLEANING_ATTEMPTS) {
            retained_queue.push_back(qh);
        }
    }
    cleaning_queue_ = retained_queue;
    if (storage_ != nullptr) {
        if (cleaning_queue_.empty()) {
            storage_->clearCleaningQueue();
        } else {
            storage_->saveCleaningQueue(cleaning_queue_);
        }
    }

    if (!any_retry_allowed && cleaning_queue_.empty()) {
        const uint32_t now = getCurrentTime();
        if (now > 0 && next_inspection_time_ <= now) {
            next_inspection_time_ = now + static_cast<uint32_t>(config_.interval_days * 86400);
            if (storage_ != nullptr) {
                storage_->saveNextInspectionTimestamp(next_inspection_time_);
            }
        }
    }

    saveCurrentStateToNvs();
    state_ = any_retry_allowed ? AppState::IDLE : AppState::SYNCING;
}


} // namespace app
