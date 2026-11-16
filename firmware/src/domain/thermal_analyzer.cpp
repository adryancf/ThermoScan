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


} // namespace domain
