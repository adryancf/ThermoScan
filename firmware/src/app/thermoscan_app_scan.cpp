#include "thermoscan_app.h"
#include "thermoscan_config.h"
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

void ThermoscanApp::handleIdle() {
    const uint32_t now = getCurrentTime();

    if (cloud_ != nullptr && cloud_->isResetPending()) {
        executeFullReset();
        return;
    }

    // Flush any pending offline scan abort once connectivity is restored
    if (!pending_abort_insp_id_.empty() && cloud_ != nullptr && cloud_->isConnected()) {
        const std::string reason = pending_abort_reason_.empty() ? "network_disconnected" : pending_abort_reason_;
        if (cloud_->abortInspection(pending_abort_insp_id_, reason)) {
            Serial.printf("[SYNC] Pending abort synced for inspection %s (reason=%s)\n",
                          pending_abort_insp_id_.c_str(), reason.c_str());
            cloud_->recordStateTransition("ABORT_SYNCED", reason.c_str(), getCurrentTime());
            pending_abort_insp_id_.clear();
            pending_abort_reason_.clear();
            if (storage_ != nullptr) {
                storage_->clearPendingAbort();
            }
        }
    }

    // Check if cloud client reported pending configuration or manual inspection from startup/claim ping
    if (cloud_ != nullptr && cloud_->isConfigurationPending()) {
        config_update_pending_ = true;
        config_sync_failed_waiting_ping_ = false;
    }
    if (cloud_ != nullptr && cloud_->isManualInspectionPending()) {
        cloud_->clearManualInspectionPending();
        Serial.println(F("[APP] Ping detected pending manual inspection request from backend!"));
        triggerManualInspection();
    }
    if (cloud_ != nullptr && cloud_->isManualCleaningPending()) {
        const float target_x = cloud_->getManualCleaningTargetXCm();
        cloud_->clearManualCleaningPending();
        Serial.printf("[APP] Ping detected pending manual cleaning request from backend (target_x=%.1f cm)!\n", target_x);
        triggerManualCleaning(target_x);
    }

    // Determine ping interval: use fast ping (5s) when initial configuration is not yet synchronized,
    // otherwise use standard configured interval (default 5s)
    const uint32_t effective_ping_interval_ms =
        ((config_.config_version == 0 || config_update_pending_)
             ? 5UL
             : static_cast<uint32_t>(config_.ping_interval_seconds)) * 1000UL;

    // Periodic telemetry ping timed by monotonic uptime (works even when NTP/UTC clock is not synced)
    const uint32_t now_ms = getUptimeMs();
    const bool due_for_ping = (!has_pinged_ && now_ms > 0) ||
                              (has_pinged_ && (now_ms - last_ping_ms_) >= effective_ping_interval_ms);
    if (cloud_ != nullptr && due_for_ping) {
        cloud_->sendPing();
        last_ping_ms_ = now_ms;
        has_pinged_ = true;
        if (cloud_->isResetPending()) {
            executeFullReset();
            return;
        }
        if (cloud_->isConfigurationPending()) {
            config_update_pending_ = true;
            config_sync_failed_waiting_ping_ = false;
        }
        if (cloud_->isManualInspectionPending()) {
            cloud_->clearManualInspectionPending();
            Serial.println(F("[APP] Periodic ping detected pending manual inspection request!"));
            triggerManualInspection();
        }
        if (cloud_->isManualCleaningPending()) {
            const float target_x = cloud_->getManualCleaningTargetXCm();
            cloud_->clearManualCleaningPending();
            Serial.printf("[APP] Periodic ping detected pending manual cleaning request (target_x=%.1f cm)!\n", target_x);
            triggerManualCleaning(target_x);
        }
    }

    // Check for authorization error (HTTP 401): device token revoked or unregistered on backend
    if (cloud_ != nullptr && cloud_->hadAuthError()) {
        constexpr uint32_t reclaim_interval_ms = 10000UL; // retry claim every 10 seconds
        const bool due_for_reclaim = !has_reclaimed_ || (now_ms - last_reclaim_ms_) >= reclaim_interval_ms;
        if (due_for_reclaim) {
            last_reclaim_ms_ = now_ms;
            has_reclaimed_ = true;
            Serial.println(F("[APP] HTTP 401 detected: Device token revoked or invalid. Initiating automatic re-claim..."));
            if (cloud_->claimDevice()) {
                Serial.println(F("[APP] Automatic hardware re-claim succeeded! Syncing new configuration..."));
                cloud_->clearAuthError();
                config_update_pending_ = true;
                config_sync_failed_waiting_ping_ = false;
                has_reclaimed_ = false;
                last_reclaim_ms_ = 0;
            } else {
                Serial.println(F("[APP] Automatic re-claim attempt deferred/failed. Will retry on next interval."));
            }
        }
    }

    // 1. Manual commands have highest priority
    if (manual_inspection_requested_) {
        manual_inspection_requested_ = false;
        if (cloud_ != nullptr) {
            cloud_->clearManualInspectionPending();
        }
        Serial.println(F("[APP] State transition: IDLE -> SCANNING (Starting manual inspection)"));
        transitionTo(AppState::SCANNING);
        return;
    }

    if (manual_cleaning_requested_) {
        manual_cleaning_requested_ = false;
        manual_cleaning_active_ = true;
        cleaning_queue_.clear();
        transitionTo(AppState::CLEANING);
        return;
    }

    // 2. Pending configuration synchronization
    if (config_update_pending_ && !config_sync_failed_waiting_ping_) {
        transitionTo(AppState::SYNCING);
        return;
    }

    // 3. Scheduled inspection evaluation
    if (now > 0 && next_inspection_time_ > 0 && now >= next_inspection_time_) {
        if (checkSolarWindow()) {
            Serial.println(F("[APP] State transition: IDLE -> SCANNING (Starting scheduled inspection)"));
            transitionTo(AppState::SCANNING);
            return;
        }
    }
}

bool ThermoscanApp::flushScanTelemetryBatch(std::vector<std::vector<float>>& batch_frames_data,
                                            std::vector<PowerSnapshot>& batch_power_data,
                                            std::vector<std::string>& failed_meas_ids) {
    if (current_batch_.empty()) {
        return true;
    }

    if (cloud_ != nullptr) {
        IngestTelemetryBatchInput batch_input;
        batch_input.inspection_source_event_id = inspection_source_event_id_;
        batch_input.inspection_type = "scheduled";
        batch_input.started_at_epoch = inspection_started_at_;
        batch_input.scheduled_for_epoch = inspection_scheduled_for_;
        batch_input.batch = current_batch_;

        bool ingested = false;
        for (int retry = 0; retry < 3; ++retry) {
            if (cloud_->ingestTelemetryBatch(batch_input)) {
                ingested = true;
                break;
            }
#if defined(ARDUINO) || defined(ESP32)
            delay(300 * (retry + 1));
#endif
        }

        // Fallback: If batch failed (e.g. heap exhaustion during large JSON/TLS),
        // retry sending each item individually to minimize memory peak
        if (!ingested) {
            if (current_batch_.size() > 1) {
                Serial.println(F("[SCAN] Batch submission failed. Retrying telemetry item-by-item..."));
                for (size_t single_idx = 0; single_idx < current_batch_.size(); ++single_idx) {
                    IngestTelemetryBatchInput single_input;
                    single_input.inspection_source_event_id = inspection_source_event_id_;
                    single_input.inspection_type = "scheduled";
                    single_input.started_at_epoch = inspection_started_at_;
                    single_input.scheduled_for_epoch = inspection_scheduled_for_;
                    single_input.batch.push_back(current_batch_[single_idx]);

                    bool single_ok = false;
                    for (int retry = 0; retry < 2; ++retry) {
                        if (cloud_->ingestTelemetryBatch(single_input)) {
                            single_ok = true;
                            break;
                        }
#if defined(ARDUINO) || defined(ESP32)
                        delay(200);
#endif
                    }
                    if (!single_ok) {
                        failed_meas_ids.push_back(current_batch_[single_idx].source_event_id);
                    }
                }
            } else {
                failed_meas_ids.push_back(current_batch_[0].source_event_id);
            }
        }
    }

    current_batch_.clear();
    batch_frames_data.clear();
    batch_power_data.clear();

    if (cloud_ != nullptr) {
        bool heap_ok = true;
#if defined(ARDUINO) || defined(ESP32)
        heap_ok = (ESP.getFreeHeap() >= 45000);
#endif
        if (heap_ok) {
            cloud_->sendPing();
            if (cloud_->isResetPending()) {
                return false;
            }
        }
    }
    return true;
}

void ThermoscanApp::handleScanning() {
    if (motion_ != nullptr && !motion_->isHomed()) {
        if (!motion_->home()) {
            executeEmergencyStop("homing_failed");
            return;
        }
    }

    if (inspection_crash_retries_ == 0 && last_completed_panel_ == 0) {
        inspection_source_event_id_ = utils::generateUUIDv4();
        inspection_started_at_ = getCurrentTime();
        inspection_scheduled_for_ = (time_provider_ && time_provider_->isTimeSynchronized())
                                    ? inspection_started_at_ : 0;
        saveCurrentStateToNvs();
    } else {
        if (inspection_started_at_ == 0) {
            inspection_started_at_ = getCurrentTime();
        }
        if (inspection_scheduled_for_ == 0 && time_provider_ && time_provider_->isTimeSynchronized()) {
            inspection_scheduled_for_ = inspection_started_at_;
        }
    }

    all_confirmed_hotspots_.clear();
    confirmed_anomaly_records_.clear();
    current_batch_.clear();
    scan_truncated_by_memory_ = false;
    all_panels_accepted_ = true;
    last_abort_reason_.clear();

    if (backup_storage_ != nullptr && backup_storage_->isAvailable()) {
        backup_storage_->beginScanBackup(inspection_source_event_id_);
    }

    utils::HeapTracker::start();

    const uint8_t total_panels = (config_.panel_count > 0) ? static_cast<uint8_t>(config_.panel_count) : 1;
    panel_baselines_.assign(static_cast<size_t>(total_panels) + 1, 25.0f);
    Serial.printf("[SCAN] %s inspection scan cycle. Event ID: %s, Total Panels: %u, Resuming from Panel: %u\n",
                  (last_completed_panel_ > 0 ? "Resuming" : "Starting"),
                  inspection_source_event_id_.c_str(), total_panels, static_cast<unsigned>(last_completed_panel_ + 1));

    for (uint8_t p = last_completed_panel_ + 1; p <= total_panels; ++p) {
        float p_start = 0.0f, p_end = 0.0f;
        domain::getPanelBounds(p, config_.panel_length_cm, config_.panel_spacing_cm, p_start, p_end);
        Serial.printf("[SCAN] Scanning Panel %u: Range X = [%.1f cm -> %.1f cm]\n", p, p_start, p_end);

        // If resuming and p > 1, move carriage directly to the start position of panel p
        if (p > 1 && motion_ != nullptr) {
            motion_->moveToXCm(p_start);
        }

        histogram_.reset();
        quantized_frames_.clear();

        // Pre-reserve capacity to avoid vector reallocations and heap fragmentation during scan
        size_t expected_steps = static_cast<size_t>((p_end - p_start) / STEP_SIZE_CM) + 2;
        if (expected_steps > MAX_PANEL_ACQUISITIONS) {
            expected_steps = MAX_PANEL_ACQUISITIONS;
        }
        quantized_frames_.reserve(expected_steps);

        bool panel_truncated = false;

        float current_x = p_start;

        // Maintain panel-level representative electrical snapshot (filter out transient 0V drops)
        PowerSnapshot best_panel_power;
        best_panel_power.valid = false;

        std::vector<std::vector<float>> batch_frames_data;
        std::vector<PowerSnapshot> batch_power_data;
        std::vector<std::string> failed_meas_ids;
        bool panel_cam_fail_logged = false;
        const size_t BATCH_CHUNK_SIZE = thermoscan_config::TELEMETRY_BATCH_CHUNK_SIZE;
        batch_frames_data.reserve(BATCH_CHUNK_SIZE);
        batch_power_data.reserve(BATCH_CHUNK_SIZE);
        current_batch_.reserve(BATCH_CHUNK_SIZE);

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
                for (int cap_retry = 0; cap_retry < 3; ++cap_retry) {
                    frame_ok = camera_->captureFrame(frame);
                    if (frame_ok) {
                        break;
                    }
#if defined(ARDUINO) || defined(ESP32)
                    delay(80 * (cap_retry + 1));
#endif
                }
            }

            PowerSnapshot power;
            if (power_meter_ != nullptr) {
                power_meter_->readSnapshotForPanel(p, power);
            }

            // Consolidate best operational panel electrical reading:
            // If the panel has produced voltage/power, retain that peak across steps to prevent transient 0V dips
            PowerSnapshot effective_power = power;
            if (power.valid && (power.voltage_v > 0.05f || power.power_w > 0.01f)) {
                if (!best_panel_power.valid || power.power_w > best_panel_power.power_w || power.voltage_v > best_panel_power.voltage_v) {
                    best_panel_power = power;
                }
                effective_power = best_panel_power;
            } else if (best_panel_power.valid) {
                effective_power = best_panel_power;
            }

            float max_temp = -999.0f;
            bool has_valid_pixel = false;
            if (frame_ok) {
                for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
                    const float t = frame.pixels[i];
                    if (domain::ThermalAnalyzer::isValidPixel(t)) {
                        if (!has_valid_pixel || t > max_temp) {
                            max_temp = t;
                        }
                        has_valid_pixel = true;
                    }
                }
            }

            if (frame_ok && has_valid_pixel) {
                if (backup_storage_ != nullptr && backup_storage_->isAvailable()) {
                    backup_storage_->appendRawFrame(current_x, frame.pixels);
                }

                histogram_.addFrame(frame);

                std::string meas_id = utils::generateUUIDv4();
                uint32_t meas_time = getCurrentTime();

                domain::QuantizedThermalFrame qf;
                qf.loadFromThermalFrame(frame, current_x, meas_time, meas_id);
                quantized_frames_.push_back(qf);

                std::vector<float> frame_copy(frame.pixels, frame.pixels + ThermalFrame::PIXEL_COUNT);
                batch_frames_data.push_back(std::move(frame_copy));
                batch_power_data.push_back(effective_power);

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

                Serial.printf("[SCAN] Panel %u: X = %.1f cm | T_max = %.1f C | Accumulated batch: %u/%u\n",
                              p, current_x, max_temp, current_batch_.size(), static_cast<unsigned>(BATCH_CHUNK_SIZE));

                if (current_batch_.size() >= BATCH_CHUNK_SIZE) {
                    if (!flushScanTelemetryBatch(batch_frames_data, batch_power_data, failed_meas_ids)) {
                        executeFullReset();
                        return;
                    }
                }
            } else {
                Serial.printf("[SCAN] Warning: Failed to capture thermal frame at X = %.1f cm (skipped)\n", current_x);
                if (!panel_cam_fail_logged && cloud_ != nullptr) {
                    cloud_->recordStateTransition("CAMERA_FAIL", "frame_capture_failed", getCurrentTime());
                    panel_cam_fail_logged = true;
                }
            }

            current_x += STEP_SIZE_CM;
        }

        // Guaranteed flush of any remaining frames in current_batch_ (even if the last step failed)
        if (!current_batch_.empty()) {
            if (!flushScanTelemetryBatch(batch_frames_data, batch_power_data, failed_meas_ids)) {
                executeFullReset();
                return;
            }
        }

        // Drop any frames that failed cloud ingestion and mark inspection for abort
        if (!failed_meas_ids.empty()) {
            all_panels_accepted_ = false;
            last_abort_reason_ = (cloud_ != nullptr && !cloud_->isConnected())
                                     ? "network_disconnected"
                                     : "telemetry_upload_failed";
            quantized_frames_.erase(
                std::remove_if(quantized_frames_.begin(), quantized_frames_.end(),
                               [&failed_meas_ids](const domain::QuantizedThermalFrame& qf) {
                                   return std::find(failed_meas_ids.begin(), failed_meas_ids.end(),
                                                    qf.source_event_id) != failed_meas_ids.end();
                               }),
                quantized_frames_.end());
        }

        // Panel baseline calculation
        float panel_baseline = histogram_.calculateMedian();
        if (panel_baseline <= 0.0f) {
            panel_baseline = 25.0f;
        }
        if (p < panel_baselines_.size()) {
            panel_baselines_[p] = panel_baseline;
        }
        baseline_temp_c_ = panel_baseline;

        auto confirmed = thermal_analyzer_.analyzeQuantizedScan(
            quantized_frames_,
            panel_baseline,
            ThermalAnalyzer::DEFAULT_POSITION_TOLERANCE_CM,
            true,
            p_start,
            p_end,
            p);

        Serial.printf("[SCAN] Panel %u completed: Range [%.1f cm -> %.1f cm] | Baseline: %.1f C | Confirmed hotspots: %u\n",
                      p, p_start, p_end, panel_baseline, confirmed.size());

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
                    auto panel_anoms = cloud_->getLastConfirmedAnomalies();
                    for (const auto& rec : panel_anoms) {
                        bool exists = false;
                        for (const auto& existing : confirmed_anomaly_records_) {
                            if (existing.id == rec.id) {
                                exists = true;
                                break;
                            }
                        }
                        if (!exists) {
                            confirmed_anomaly_records_.push_back(rec);
                        }
                    }
                    break;
                }
#if defined(ARDUINO) || defined(ESP32)
                delay(500 * (retry + 1));
#endif
            }
        } else {
            result_accepted = true;
        }

        if (result_accepted) {
            last_completed_panel_ = p;
            if (storage_ != nullptr) {
                storage_->saveInspectionProgress(inspection_source_event_id_, last_completed_panel_, inspection_crash_retries_);
            }
            saveCurrentStateToNvs();
        } else {
            all_panels_accepted_ = false;
            if (last_abort_reason_.empty()) {
                last_abort_reason_ = (cloud_ != nullptr && !cloud_->isConnected())
                                         ? "network_disconnected"
                                         : "panel_result_rejected";
            }
#if defined(ARDUINO) || defined(ESP32)
            Serial.printf("[ERR] Panel %u thermal result not accepted by backend after retries!\n", p);
#endif
        }

        // Release quantized memory and histogram per panel strictly after transmission/retry
        quantized_frames_.clear();
        quantized_frames_.shrink_to_fit();
        histogram_.reset();

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

    if (backup_storage_ != nullptr && backup_storage_->isAvailable()) {
        backup_storage_->commitScanBackup(inspection_source_event_id_);
    }

    Serial.println(F("[SCAN] Scan completed. State transition: SCANNING -> ANALYZING."));
    if (cloud_ != nullptr) {
        cloud_->clearManualInspectionPending();
    }
    quantized_frames_.clear();
    quantized_frames_.shrink_to_fit();
    saveCurrentStateToNvs();
    transitionTo(AppState::ANALYZING);
}

void ThermoscanApp::handleAnalyzing() {
    if (cloud_ != nullptr && cloud_->isResetPending()) {
        executeFullReset();
        return;
    }

    // Flush any pending offline scan abort once connectivity is restored
    if (!pending_abort_insp_id_.empty() && cloud_ != nullptr && cloud_->isConnected()) {
        const std::string reason = pending_abort_reason_.empty() ? "network_disconnected" : pending_abort_reason_;
        if (cloud_->abortInspection(pending_abort_insp_id_, reason)) {
            Serial.printf("[SYNC] Pending abort synced for inspection %s (reason=%s)\n",
                          pending_abort_insp_id_.c_str(), reason.c_str());
            cloud_->recordStateTransition("ABORT_SYNCED", reason.c_str(), getCurrentTime());
            pending_abort_insp_id_.clear();
            pending_abort_reason_.clear();
            if (storage_ != nullptr) {
                storage_->clearPendingAbort();
            }
        }
    }

    // Safeguard 2: Never finalize inspection as complete if any panel or telemetry batch failed
    if (!all_panels_accepted_) {
        const std::string abort_reason = last_abort_reason_.empty()
                                             ? "panel_result_rejected"
                                             : last_abort_reason_;
#if defined(ARDUINO) || defined(ESP32)
        Serial.printf("[ERR] Aborting inspection (%s) due to upload/network failure.\n", abort_reason.c_str());
#endif
        if (cloud_ != nullptr) {
            cloud_->recordStateTransition("SCAN_ABORTED", abort_reason.c_str(), getCurrentTime());
            if (!cloud_->abortInspection(inspection_source_event_id_, abort_reason)) {
                pending_abort_insp_id_ = inspection_source_event_id_;
                pending_abort_reason_ = abort_reason;
                if (storage_ != nullptr) {
                    storage_->savePendingAbort(pending_abort_insp_id_, pending_abort_reason_);
                }
            }
        }
        if (backup_storage_ != nullptr && backup_storage_->isAvailable() && !inspection_source_event_id_.empty()) {
            backup_storage_->removeScanBackup(inspection_source_event_id_);
        }
        inspection_source_event_id_.clear();
        pending_sync_backup_id_.clear();
        last_abort_reason_.clear();
        last_completed_panel_ = 0;
        inspection_crash_retries_ = 0;
        if (storage_ != nullptr) {
            storage_->clearInspectionProgress();
        }
        if (motion_ != nullptr) {
            motion_->moveToXCm(0.0f);
        }
        utils::HeapTracker::stop();
        saveCurrentStateToNvs();
        transitionTo(AppState::SYNCING);
        return;
    }

    FinalizeInspectionInput fin;
    fin.finished_at_epoch = getCurrentTime();
    fin.baseline_temperature_c = 0.0f; // backend computes consolidated average across panel results
    fin.confirmed_hotspots = all_confirmed_hotspots_;

    bool fin_ok = true;
    if (cloud_ != nullptr) {
        fin_ok = cloud_->finalizeInspection(inspection_source_event_id_, fin);
        active_anomaly_id_ = cloud_->getLastConfirmedAnomalyId();
        auto fin_anoms = cloud_->getLastConfirmedAnomalies();
        for (const auto& rec : fin_anoms) {
            bool exists = false;
            for (const auto& existing : confirmed_anomaly_records_) {
                if (existing.id == rec.id) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                confirmed_anomaly_records_.push_back(rec);
            }
        }
    }

    if (fin_ok) {
        pending_sync_backup_id_ = inspection_source_event_id_;
        inspection_source_event_id_.clear();
        last_completed_panel_ = 0;
        inspection_crash_retries_ = 0;
        if (storage_ != nullptr) {
            storage_->clearInspectionProgress();
        }
        saveCurrentStateToNvs();
    }

    utils::HeapTracker::stop();

    auto previous_queue = cleaning_queue_;
    cleaning_queue_.clear();

    if (!all_confirmed_hotspots_.empty()) {
        // Sort hotspots by ascending global X position
        std::sort(all_confirmed_hotspots_.begin(), all_confirmed_hotspots_.end(),
                  [](const ConfirmedHotspotOutput& a, const ConfirmedHotspotOutput& b) {
                      return a.global_x_position_cm < b.global_x_position_cm;
                  });

        std::vector<bool> used_anom(confirmed_anomaly_records_.size(), false);

        for (const auto& ho : all_confirmed_hotspots_) {
            QueuedHotspot qh;
            qh.panel_index = ho.panel_index;
            qh.target_x_cm = ho.global_x_position_cm;

            // Match authentic backend anomaly UUID from confirmed_anomaly_records_
            std::string matched_id;
            int best_idx = -1;
            float best_diff = 1e9f;
            for (size_t k = 0; k < confirmed_anomaly_records_.size(); ++k) {
                if (used_anom[k]) continue;
                const auto& rec = confirmed_anomaly_records_[k];
                if (rec.panel_index == ho.panel_index) {
                    float diff = std::abs(rec.x_position_cm - ho.global_x_position_cm);
                    if (diff < best_diff) {
                        best_diff = diff;
                        best_idx = static_cast<int>(k);
                    }
                }
            }
            if (best_idx < 0) {
                for (size_t k = 0; k < confirmed_anomaly_records_.size(); ++k) {
                    if (!used_anom[k]) {
                        best_idx = static_cast<int>(k);
                        break;
                    }
                }
            }
            if (best_idx >= 0) {
                used_anom[static_cast<size_t>(best_idx)] = true;
                matched_id = confirmed_anomaly_records_[static_cast<size_t>(best_idx)].id;
            } else if (all_confirmed_hotspots_.size() == 1 && !active_anomaly_id_.empty()) {
                matched_id = active_anomaly_id_;
            } else {
                matched_id = ho.source_event_id;
            }

            qh.anomaly_event_id = matched_id;
            qh.cleaning_operation_id = "";
            qh.attempts = 0;
            for (const auto& prev : previous_queue) {
                if (prev.panel_index == qh.panel_index &&
                    std::abs(prev.target_x_cm - qh.target_x_cm) <= 1.0f &&
                    prev.verification_status == "pending") {
                    qh.attempts = prev.attempts;
                    break;
                }
            }
            qh.verification_status = "pending";
            qh.baseline_temp_c = (ho.panel_index < panel_baselines_.size() && panel_baselines_[ho.panel_index] > 0.0f)
                                 ? panel_baselines_[ho.panel_index] : baseline_temp_c_;
            qh.spray_interrupted = false;
            cleaning_queue_.push_back(qh);
        }

        active_hotspot_.panel_index = cleaning_queue_[0].panel_index;
        active_hotspot_.target_x_cm = cleaning_queue_[0].target_x_cm;
        active_hotspot_.confirmed = true;
        active_anomaly_id_ = cleaning_queue_[0].anomaly_event_id;
        cleaning_sm_.restoreState(domain::CleaningStatus::IDLE,
                                  domain::AnomalyResult::OPEN,
                                  cleaning_queue_[0].attempts,
                                  0);

        if (storage_ != nullptr) {
            storage_->saveCleaningQueue(cleaning_queue_);
        }
        saveCurrentStateToNvs();
        transitionTo(AppState::CLEANING);
    } else {
        const uint32_t now = getCurrentTime();
        if (now > 0) {
            next_inspection_time_ = now + static_cast<uint32_t>(config_.interval_days * 86400);
        }
        if (storage_ != nullptr) {
            storage_->clearCleaningQueue();
        }
        saveCurrentStateToNvs();
        transitionTo(AppState::SYNCING);
    }
}


} // namespace app
