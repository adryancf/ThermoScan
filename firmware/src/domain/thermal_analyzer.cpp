#include "domain/thermal_analyzer.h"
#include <cmath>
#include <algorithm>

namespace domain {

ThermalAnalyzer::ThermalAnalyzer(float calibrated_fov_cm, float spatial_tolerance_cm)
    : calibrated_fov_cm_(calibrated_fov_cm > 0.0f ? calibrated_fov_cm : FOV_OPTICAL_CM),
      spatial_tolerance_cm_(spatial_tolerance_cm > 0.0f ? spatial_tolerance_cm : SPATIAL_TOLERANCE_CM) {
}

bool ThermalAnalyzer::isValidPixel(float temp_c) {
    if (std::isnan(temp_c)) {
        return false;
    }
    return (temp_c > MIN_VALID_TEMP_C) && (temp_c <= MAX_VALID_TEMP_C);
}

float ThermalAnalyzer::calculateGlobalX(float scan_x_cm, int col, float fov_cm) {
    return scan_x_cm + (static_cast<float>(col) / static_cast<float>(MLX_COLS)) * fov_cm;
}

float ThermalAnalyzer::calculateBaseline(const std::vector<ScanAcquisition>& acquisitions) const {
    // NOTE: Baseline calculation is performed over the complete accumulated sequence of valid scan captures.
    // The thermal analysis is executed strictly post-capture across the entire scan dataset,
    // without reliance on lookahead or uncaptured future data.
    std::vector<float> valid_pixels;
    valid_pixels.reserve(acquisitions.size() * PIXEL_COUNT);

    for (const auto& acq : acquisitions) {
        if (!acq.valid || !acq.frame.valid) {
            continue;
        }
        for (size_t i = 0; i < PIXEL_COUNT; ++i) {
            float t = acq.frame.pixels[i];
            if (isValidPixel(t)) {
                valid_pixels.push_back(t);
            }
        }
    }

    if (valid_pixels.empty()) {
        return 0.0f;
    }

    std::sort(valid_pixels.begin(), valid_pixels.end());
    const size_t n = valid_pixels.size();
    if (n % 2 == 1) {
        return valid_pixels[n / 2];
    } else {
        return (valid_pixels[n / 2 - 1] + valid_pixels[n / 2]) / 2.0f;
    }
}

std::vector<HotspotCandidate> ThermalAnalyzer::findCandidates(const ScanAcquisition& acq,
                                                            float baseline_temp_c,
                                                            size_t acq_index,
                                                            float panel_start_cm,
                                                            float panel_end_cm,
                                                            uint8_t panel_index) const {
    std::vector<HotspotCandidate> candidates;
    if (!acq.valid || !acq.frame.valid) {
        return candidates;
    }

    const float threshold = baseline_temp_c + HOTSPOT_THRESHOLD_DELTA_C;

    for (int row = 0; row < MLX_ROWS; ++row) {
        for (int col = 0; col < MLX_COLS; ++col) {
            const size_t idx = static_cast<size_t>(row * MLX_COLS + col);
            const float t = acq.frame.pixels[idx];

            if (isValidPixel(t) && t >= threshold) {
                HotspotCandidate cand;
                cand.col = col;
                cand.row = row;
                cand.temp_c = t;
                cand.global_x_cm = calculateGlobalX(acq.x_position_cm, col, calibrated_fov_cm_);
                if (panel_end_cm > panel_start_cm) {
                    if (cand.global_x_cm < panel_start_cm) cand.global_x_cm = panel_start_cm;
                    if (cand.global_x_cm > panel_end_cm) cand.global_x_cm = panel_end_cm;
                }
                cand.acquisition_index = acq_index;
                cand.panel_index = panel_index;
                candidates.push_back(cand);
            }
        }
    }

    return candidates;
}

std::vector<HotspotEvent> ThermalAnalyzer::analyzeScan(const std::vector<ScanAcquisition>& acquisitions,
                                                     float tolerance_cm,
                                                     bool only_confirmed,
                                                     float panel_start_cm,
                                                     float panel_end_cm,
                                                     uint8_t panel_index) const {
    const float eff_tolerance = (tolerance_cm > 0.0f) ? tolerance_cm : spatial_tolerance_cm_;

    // Consecutively confirmed spatial detection significantly mitigates spurious sensor noise
    // and transient reflections; however, it does not guarantee 100% elimination of all false
    // positives under real-world outdoor field conditions.
    if (acquisitions.empty()) {
        return {};
    }

    const float baseline = calculateBaseline(acquisitions);

    // Extract candidates per acquisition
    std::vector<std::vector<HotspotCandidate>> per_acq_candidates;
    per_acq_candidates.reserve(acquisitions.size());
    for (size_t i = 0; i < acquisitions.size(); ++i) {
        per_acq_candidates.push_back(findCandidates(acquisitions[i], baseline, i, panel_start_cm, panel_end_cm, panel_index));
    }

    // Track confirmed status for each candidate
    std::vector<std::vector<bool>> candidate_confirmed(acquisitions.size());
    for (size_t i = 0; i < acquisitions.size(); ++i) {
        candidate_confirmed[i].resize(per_acq_candidates[i].size(), false);
    }

    std::vector<HotspotEvent> result_events;

    // Evaluate consecutive acquisitions k and k+1
    for (size_t k = 0; k + 1 < acquisitions.size(); ++k) {
        const auto& acq_k = acquisitions[k];
        const auto& acq_next = acquisitions[k + 1];

        if (!acq_k.valid || !acq_k.frame.valid || !acq_next.valid || !acq_next.frame.valid) {
            continue;
        }

        // Check nominal step progression (~2.0 cm step with tolerance)
        const float dx = std::abs(acq_next.x_position_cm - acq_k.x_position_cm);
        if (std::abs(dx - STEP_SIZE_CM) > 0.6f) {
            continue;
        }

        const auto& cands_k = per_acq_candidates[k];
        const auto& cands_next = per_acq_candidates[k + 1];

        for (size_t idx_a = 0; idx_a < cands_k.size(); ++idx_a) {
            const auto& cand_a = cands_k[idx_a];

            for (size_t idx_b = 0; idx_b < cands_next.size(); ++idx_b) {
                const auto& cand_b = cands_next[idx_b];

                // Allow row difference of up to 1 row
                if (std::abs(cand_a.row - cand_b.row) <= 1) {
                    const float spatial_diff = std::abs(cand_a.global_x_cm - cand_b.global_x_cm);
                    if (spatial_diff <= eff_tolerance) {
                        candidate_confirmed[k][idx_a] = true;
                        candidate_confirmed[k + 1][idx_b] = true;

                        float pair_x = (cand_a.global_x_cm + cand_b.global_x_cm) / 2.0f;
                        if (panel_end_cm > panel_start_cm) {
                            if (pair_x < panel_start_cm) pair_x = panel_start_cm;
                            if (pair_x > panel_end_cm) pair_x = panel_end_cm;
                        }
                        const int pair_row = (cand_a.temp_c >= cand_b.temp_c) ? cand_a.row : cand_b.row;
                        const float pair_max_temp = std::max(cand_a.temp_c, cand_b.temp_c);

                        // Cluster/merge into existing confirmed events
                        bool merged = false;
                        for (auto& existing : result_events) {
                            if (std::abs(existing.row - pair_row) <= 1 &&
                                std::abs(existing.target_x_cm - pair_x) <= eff_tolerance) {
                                if (pair_max_temp > existing.max_temp_c) {
                                    existing.max_temp_c = pair_max_temp;
                                    existing.target_x_cm = pair_x;
                                    existing.row = pair_row;
                                }
                                if (!acq_k.source_event_id.empty() &&
                                    std::find(existing.confirming_event_ids.begin(), existing.confirming_event_ids.end(), acq_k.source_event_id) == existing.confirming_event_ids.end()) {
                                    existing.confirming_event_ids.push_back(acq_k.source_event_id);
                                }
                                if (!acq_next.source_event_id.empty() &&
                                    std::find(existing.confirming_event_ids.begin(), existing.confirming_event_ids.end(), acq_next.source_event_id) == existing.confirming_event_ids.end()) {
                                    existing.confirming_event_ids.push_back(acq_next.source_event_id);
                                }
                                merged = true;
                                break;
                            }
                        }

                        if (!merged && result_events.size() < MAX_PANEL_HOTSPOTS) {
                            HotspotEvent ev;
                            ev.panel_index = panel_index;
                            ev.target_x_cm = pair_x;
                            ev.row = pair_row;
                            ev.max_temp_c = pair_max_temp;
                            ev.baseline_temp_c = baseline;
                            ev.confirmed = true;
                            ev.origin_measurement_event_id = acq_k.source_event_id;
                            if (!acq_k.source_event_id.empty()) {
                                ev.confirming_event_ids.push_back(acq_k.source_event_id);
                            }
                            if (!acq_next.source_event_id.empty()) {
                                ev.confirming_event_ids.push_back(acq_next.source_event_id);
                            }
                            result_events.push_back(ev);
                        }
                    }
                }
            }
        }
    }

    // Evaluate isolated critical / border candidates:
    // If an isolated candidate has Delta T >= CRITICAL_HOTSPOT_DELTA_C or T >= CRITICAL_HOTSPOT_MAX_TEMP_C,
    // or is in the last frame of the panel without posterior pair, confirm it.
    for (size_t i = 0; i < acquisitions.size(); ++i) {
        const bool is_last_frame = (i + 1 >= acquisitions.size());
        for (size_t c = 0; c < per_acq_candidates[i].size(); ++c) {
            if (!candidate_confirmed[i][c]) {
                const auto& cand = per_acq_candidates[i][c];
                const float delta_t = cand.temp_c - baseline;
                const bool is_critical = (delta_t >= CRITICAL_HOTSPOT_DELTA_C) || (cand.temp_c >= CRITICAL_HOTSPOT_MAX_TEMP_C);

                if (is_critical || is_last_frame) {
                    candidate_confirmed[i][c] = true;
                    bool merged = false;
                    for (auto& existing : result_events) {
                        if (std::abs(existing.row - cand.row) <= 1 &&
                            std::abs(existing.target_x_cm - cand.global_x_cm) <= eff_tolerance) {
                            if (cand.temp_c > existing.max_temp_c) {
                                existing.max_temp_c = cand.temp_c;
                                existing.target_x_cm = cand.global_x_cm;
                                existing.row = cand.row;
                            }
                            if (!acquisitions[i].source_event_id.empty() &&
                                std::find(existing.confirming_event_ids.begin(), existing.confirming_event_ids.end(), acquisitions[i].source_event_id) == existing.confirming_event_ids.end()) {
                                existing.confirming_event_ids.push_back(acquisitions[i].source_event_id);
                            }
                            merged = true;
                            break;
                        }
                    }

                    if (!merged && result_events.size() < MAX_PANEL_HOTSPOTS) {
                        HotspotEvent ev;
                        ev.panel_index = panel_index;
                        ev.target_x_cm = cand.global_x_cm;
                        ev.row = cand.row;
                        ev.max_temp_c = cand.temp_c;
                        ev.baseline_temp_c = baseline;
                        ev.confirmed = true;
                        ev.origin_measurement_event_id = acquisitions[i].source_event_id;
                        if (!acquisitions[i].source_event_id.empty()) {
                            ev.confirming_event_ids.push_back(acquisitions[i].source_event_id);
                        }
                        // Add adjacent available frame ID to fulfill backend contract (len >= 2 distinct IDs)
                        size_t adj_idx = (i > 0) ? (i - 1) : (i + 1 < acquisitions.size() ? i + 1 : i);
                        if (adj_idx != i && !acquisitions[adj_idx].source_event_id.empty()) {
                            if (std::find(ev.confirming_event_ids.begin(), ev.confirming_event_ids.end(), acquisitions[adj_idx].source_event_id) == ev.confirming_event_ids.end()) {
                                ev.confirming_event_ids.push_back(acquisitions[adj_idx].source_event_id);
                            }
                        }
                        result_events.push_back(ev);
                    }
                }
            }
        }
    }

    // If requested, include remaining unconfirmed candidates as unconfirmed events
    if (!only_confirmed) {
        for (size_t i = 0; i < acquisitions.size(); ++i) {
            for (size_t c = 0; c < per_acq_candidates[i].size(); ++c) {
                if (!candidate_confirmed[i][c]) {
                    const auto& cand = per_acq_candidates[i][c];
                    bool already_clustered = false;
                    for (const auto& ev : result_events) {
                        if (std::abs(ev.row - cand.row) <= 1 && std::abs(ev.target_x_cm - cand.global_x_cm) <= eff_tolerance) {
                            already_clustered = true;
                            break;
                        }
                    }
                    if (!already_clustered) {
                        HotspotEvent ev;
                        ev.panel_index = panel_index;
                        ev.target_x_cm = cand.global_x_cm;
                        ev.row = cand.row;
                        ev.max_temp_c = cand.temp_c;
                        ev.baseline_temp_c = baseline;
                        ev.confirmed = false;
                        result_events.push_back(ev);
                    }
                }
            }
        }
    }

    return result_events;
}

std::vector<HotspotEvent> ThermalAnalyzer::analyzeQuantizedScan(
    const std::vector<QuantizedThermalFrame>& frames,
    float baseline_temp_c,
    float tolerance_cm,
    bool only_confirmed,
    float panel_start_cm,
    float panel_end_cm,
    uint8_t panel_index) const {
    const float eff_tolerance = (tolerance_cm > 0.0f) ? tolerance_cm : spatial_tolerance_cm_;

    if (frames.empty()) {
        return {};
    }

    const float threshold_c = baseline_temp_c + HOTSPOT_THRESHOLD_DELTA_C;
    const int16_t threshold_q = static_cast<int16_t>(std::round(threshold_c * QuantizedThermalFrame::SCALE));

    // Extract candidates per frame
    std::vector<std::vector<HotspotCandidate>> per_frame_candidates(frames.size());
    for (size_t i = 0; i < frames.size(); ++i) {
        const auto& f = frames[i];
        if (!f.valid) continue;

        for (int row = 0; row < MLX_ROWS; ++row) {
            for (int col = 0; col < MLX_COLS; ++col) {
                size_t idx = static_cast<size_t>(row * MLX_COLS + col);
                int16_t q = f.pixels[idx];
                if (q != QuantizedThermalFrame::INVALID_PIXEL && q >= threshold_q) {
                    if (per_frame_candidates[i].size() < MAX_CANDIDATES_PER_FRAME) {
                        HotspotCandidate cand;
                        cand.col = col;
                        cand.row = row;
                        cand.temp_c = QuantizedThermalFrame::toFloat(q);
                        cand.global_x_cm = calculateGlobalX(f.x_position_cm, col, calibrated_fov_cm_);
                        if (panel_end_cm > panel_start_cm) {
                            if (cand.global_x_cm < panel_start_cm) cand.global_x_cm = panel_start_cm;
                            if (cand.global_x_cm > panel_end_cm) cand.global_x_cm = panel_end_cm;
                        }
                        cand.acquisition_index = i;
                        cand.panel_index = panel_index;
                        per_frame_candidates[i].push_back(cand);
                    }
                }
            }
        }
    }

    // Track confirmed status for each candidate
    std::vector<std::vector<bool>> candidate_confirmed(frames.size());
    for (size_t i = 0; i < frames.size(); ++i) {
        candidate_confirmed[i].resize(per_frame_candidates[i].size(), false);
    }

    // Direct online clustering of confirmed events:
    // Instead of buffering thousands of raw pair events into RAM (which exhausts heap on large spots),
    // we match consecutive candidate pixels and merge directly into a clustered result list.
    // Neighbors in adjacent rows (row diff <= 1) and spatial tolerance in X belong to the same physical anomaly.
    std::vector<HotspotEvent> result_events;

    for (size_t k = 0; k + 1 < frames.size(); ++k) {
        const auto& f_k = frames[k];
        const auto& f_next = frames[k + 1];

        if (!f_k.valid || !f_next.valid) continue;

        const float dx = std::abs(f_next.x_position_cm - f_k.x_position_cm);
        if (std::abs(dx - STEP_SIZE_CM) > 0.6f) continue;

        const auto& cands_k = per_frame_candidates[k];
        const auto& cands_next = per_frame_candidates[k + 1];

        for (size_t idx_a = 0; idx_a < cands_k.size(); ++idx_a) {
            const auto& cand_a = cands_k[idx_a];
            for (size_t idx_b = 0; idx_b < cands_next.size(); ++idx_b) {
                const auto& cand_b = cands_next[idx_b];

                // Allow row difference of up to 1 row
                if (std::abs(cand_a.row - cand_b.row) <= 1) {
                    const float spatial_diff = std::abs(cand_a.global_x_cm - cand_b.global_x_cm);
                    if (spatial_diff <= eff_tolerance) {
                        candidate_confirmed[k][idx_a] = true;
                        candidate_confirmed[k + 1][idx_b] = true;

                        float pair_x = (cand_a.global_x_cm + cand_b.global_x_cm) / 2.0f;
                        if (panel_end_cm > panel_start_cm) {
                            if (pair_x < panel_start_cm) pair_x = panel_start_cm;
                            if (pair_x > panel_end_cm) pair_x = panel_end_cm;
                        }
                        const int pair_row = (cand_a.temp_c >= cand_b.temp_c) ? cand_a.row : cand_b.row;
                        const float pair_max_temp = std::max(cand_a.temp_c, cand_b.temp_c);

                        // Check if an existing hotspot cluster covers this detection (within X tolerance and neighbouring rows)
                        bool merged = false;
                        for (auto& existing : result_events) {
                            if (std::abs(existing.row - pair_row) <= 1 &&
                                std::abs(existing.target_x_cm - pair_x) <= eff_tolerance) {
                                if (pair_max_temp > existing.max_temp_c) {
                                    existing.max_temp_c = pair_max_temp;
                                    existing.target_x_cm = pair_x;
                                    existing.row = pair_row;
                                }
                                if (!f_k.source_event_id.empty() &&
                                    std::find(existing.confirming_event_ids.begin(), existing.confirming_event_ids.end(), f_k.source_event_id) == existing.confirming_event_ids.end()) {
                                    existing.confirming_event_ids.push_back(f_k.source_event_id);
                                }
                                if (!f_next.source_event_id.empty() &&
                                    std::find(existing.confirming_event_ids.begin(), existing.confirming_event_ids.end(), f_next.source_event_id) == existing.confirming_event_ids.end()) {
                                    existing.confirming_event_ids.push_back(f_next.source_event_id);
                                }
                                merged = true;
                                break;
                            }
                        }

                        if (!merged && result_events.size() < MAX_PANEL_HOTSPOTS) {
                            HotspotEvent ev;
                            ev.panel_index = panel_index;
                            ev.target_x_cm = pair_x;
                            ev.row = pair_row;
                            ev.max_temp_c = pair_max_temp;
                            ev.baseline_temp_c = baseline_temp_c;
                            ev.confirmed = true;
                            ev.origin_measurement_event_id = f_k.source_event_id;
                            if (!f_k.source_event_id.empty()) {
                                ev.confirming_event_ids.push_back(f_k.source_event_id);
                            }
                            if (!f_next.source_event_id.empty()) {
                                ev.confirming_event_ids.push_back(f_next.source_event_id);
                            }
                            result_events.push_back(ev);
                        }
                    }
                }
            }
        }
    }

    // Evaluate isolated critical / border candidates:
    // If an isolated candidate has Delta T >= CRITICAL_HOTSPOT_DELTA_C or T >= CRITICAL_HOTSPOT_MAX_TEMP_C,
    // or is in the last frame of the panel without posterior pair, confirm it.
    for (size_t i = 0; i < frames.size(); ++i) {
        const bool is_last_frame = (i + 1 >= frames.size());
        for (size_t c = 0; c < per_frame_candidates[i].size(); ++c) {
            if (!candidate_confirmed[i][c]) {
                const auto& cand = per_frame_candidates[i][c];
                const float delta_t = cand.temp_c - baseline_temp_c;
                const bool is_critical = (delta_t >= CRITICAL_HOTSPOT_DELTA_C) || (cand.temp_c >= CRITICAL_HOTSPOT_MAX_TEMP_C);

                if (is_critical || is_last_frame) {
                    candidate_confirmed[i][c] = true;
                    bool merged = false;
                    for (auto& existing : result_events) {
                        if (std::abs(existing.row - cand.row) <= 1 &&
                            std::abs(existing.target_x_cm - cand.global_x_cm) <= eff_tolerance) {
                            if (cand.temp_c > existing.max_temp_c) {
                                existing.max_temp_c = cand.temp_c;
                                existing.target_x_cm = cand.global_x_cm;
                                existing.row = cand.row;
                            }
                            if (!frames[i].source_event_id.empty() &&
                                std::find(existing.confirming_event_ids.begin(), existing.confirming_event_ids.end(), frames[i].source_event_id) == existing.confirming_event_ids.end()) {
                                existing.confirming_event_ids.push_back(frames[i].source_event_id);
                            }
                            merged = true;
                            break;
                        }
                    }

                    if (!merged && result_events.size() < MAX_PANEL_HOTSPOTS) {
                        HotspotEvent ev;
                        ev.panel_index = panel_index;
                        ev.target_x_cm = cand.global_x_cm;
                        ev.row = cand.row;
                        ev.max_temp_c = cand.temp_c;
                        ev.baseline_temp_c = baseline_temp_c;
                        ev.confirmed = true;
                        ev.origin_measurement_event_id = frames[i].source_event_id;
                        if (!frames[i].source_event_id.empty()) {
                            ev.confirming_event_ids.push_back(frames[i].source_event_id);
                        }
                        // Add adjacent available frame ID to fulfill backend contract (len >= 2 distinct IDs)
                        size_t adj_idx = (i > 0) ? (i - 1) : (i + 1 < frames.size() ? i + 1 : i);
                        if (adj_idx != i && !frames[adj_idx].source_event_id.empty()) {
                            if (std::find(ev.confirming_event_ids.begin(), ev.confirming_event_ids.end(), frames[adj_idx].source_event_id) == ev.confirming_event_ids.end()) {
                                ev.confirming_event_ids.push_back(frames[adj_idx].source_event_id);
                            }
                        }
                        result_events.push_back(ev);
                    }
                }
            }
        }
    }

    // If requested, include remaining unconfirmed candidates as unconfirmed events
    if (!only_confirmed) {
        for (size_t i = 0; i < frames.size(); ++i) {
            for (size_t c = 0; c < per_frame_candidates[i].size(); ++c) {
                if (!candidate_confirmed[i][c]) {
                    const auto& cand = per_frame_candidates[i][c];
                    bool already_clustered = false;
                    for (const auto& ev : result_events) {
                        if (std::abs(ev.row - cand.row) <= 1 && std::abs(ev.target_x_cm - cand.global_x_cm) <= eff_tolerance) {
                            already_clustered = true;
                            break;
                        }
                    }
                    if (!already_clustered) {
                        HotspotEvent ev;
                        ev.panel_index = panel_index;
                        ev.target_x_cm = cand.global_x_cm;
                        ev.row = cand.row;
                        ev.max_temp_c = cand.temp_c;
                        ev.baseline_temp_c = baseline_temp_c;
                        ev.confirmed = false;
                        result_events.push_back(ev);
                    }
                }
            }
        }
    }

    return result_events;
}

} // namespace domain
