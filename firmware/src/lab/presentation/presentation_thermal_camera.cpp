#include "presentation_thermal_camera.h"
#include <cmath>
#include <algorithm>

namespace presentation {

PresentationThermalCamera::PresentationThermalCamera(IThermalCamera* real_camera,
                                                     IMotionController* motion,
                                                     PresentationContext* ctx)
    : real_camera_(real_camera), motion_(motion), ctx_(ctx) {}

bool PresentationThermalCamera::init() {
    bool ok = (real_camera_ != nullptr) ? real_camera_->init() : false;
    if (!ok && ctx_ != nullptr && ctx_->isFallbackOnHwErrorEnabled()) {
        return true;
    }
    return ok;
}

bool PresentationThermalCamera::isHealthy() {
    if (real_camera_ != nullptr && real_camera_->isHealthy()) {
        return true;
    }
    return (ctx_ != nullptr && ctx_->isFallbackOnHwErrorEnabled());
}

bool PresentationThermalCamera::setTiltAngle(float angle_deg) {
    if (real_camera_ != nullptr) {
        return real_camera_->setTiltAngle(angle_deg);
    }
    return true;
}

float PresentationThermalCamera::getTiltAngle() const {
    if (real_camera_ != nullptr) {
        return real_camera_->getTiltAngle();
    }
    return 90.0f;
}

float PresentationThermalCamera::computeBaseline(const ThermalFrame& frame) {
    float sum = 0.0f;
    size_t count = 0;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        float t = frame.pixels[i];
        if (t >= -20.0f && t <= 120.0f && !std::isnan(t) && !std::isinf(t)) {
            sum += t;
            count++;
        }
    }
    if (count == 0) {
        return SYNTHETIC_ROOM_TEMP_DEFAULT_C;
    }
    return sum / static_cast<float>(count);
}

void PresentationThermalCamera::injectCluster(ThermalFrame& frame,
                                              float baseline_temp,
                                              float delta_temp,
                                              int center_row,
                                              int center_col) {
    // 32 columns, 24 rows
    constexpr int ROWS = 24;
    constexpr int COLS = 32;

    for (int r = center_row - 2; r <= center_row + 2; ++r) {
        if (r < 0 || r >= ROWS) continue;
        for (int c = center_col - 2; c <= center_col + 2; ++c) {
            if (c < 0 || c >= COLS) continue;

            float dr = static_cast<float>(r - center_row);
            float dc = static_cast<float>(c - center_col);
            float dist_sq = dr * dr + dc * dc;

            // Gaussian attenuation: 1.0 at center, ~0.6 at r=1, ~0.15 at r=2
            float factor = std::exp(-dist_sq / 1.8f);
            float target_temp = baseline_temp + (delta_temp * factor);

            size_t idx = static_cast<size_t>(r * COLS + c);
            if (target_temp > frame.pixels[idx]) {
                frame.pixels[idx] = target_temp;
            }
        }
    }
}

bool PresentationThermalCamera::captureFrame(ThermalFrame& out) {
    bool captured = false;
    if (real_camera_ != nullptr) {
        captured = real_camera_->captureFrame(out);
    }

    if (!captured) {
        if (ctx_ != nullptr && ctx_->isFallbackOnHwErrorEnabled()) {
            // Synthesize nominal room frame
            out.valid = true;
            for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
                out.pixels[i] = SYNTHETIC_ROOM_TEMP_DEFAULT_C;
            }
        } else {
            out.valid = false;
            return false;
        }
    }

    if (ctx_ == nullptr || !ctx_->isEnabled()) {
        return out.valid;
    }

    float current_x = (motion_ != nullptr) ? motion_->getXPositionCm() : 0.0f;
    float baseline = computeBaseline(out);

    for (size_t i = 0; i < DEMO_TARGETS_COUNT; ++i) {
        const auto& tgt = DEMO_TARGETS[i];
        float dist = std::fabs(current_x - tgt.x_position_cm);

        if (dist <= tgt.detection_radius_cm) {
            // Check if this hotspot is cleaned and eligible for resolution
            if (tgt.resolve_after_spray && ctx_->isCleaned(tgt.panel_index)) {
                // Resolved! Do not inject.
                continue;
            }

            // Calculate peak delta slightly modulated by distance to target center
            float spatial_attenuation = 1.0f - (dist / (tgt.detection_radius_cm * 1.5f));
            if (spatial_attenuation < 0.6f) spatial_attenuation = 0.6f;
            float eff_delta = tgt.delta_temp_c * spatial_attenuation;

            injectCluster(out, baseline, eff_delta, 12, 16);
        }
    }

    return out.valid;
}

} // namespace presentation
