#pragma once

#include "presentation_config.h"
#include <cmath>

namespace presentation {

class PresentationContext {
public:
    PresentationContext(bool enabled = true, bool fallback_on_hw_error = FALLBACK_ON_HARDWARE_FAILURE_DEFAULT)
        : enabled_(enabled), fallback_on_hw_error_(fallback_on_hw_error) {}

    bool isEnabled() const { return enabled_; }
    void setEnabled(bool enabled) { enabled_ = enabled; }

    bool isFallbackOnHwErrorEnabled() const { return fallback_on_hw_error_; }
    void setFallbackOnHwErrorEnabled(bool fallback) { fallback_on_hw_error_ = fallback; }

    void recordSprayAt(float x_cm) {
        for (size_t i = 0; i < DEMO_TARGETS_COUNT; ++i) {
            if (std::fabs(x_cm - DEMO_TARGETS[i].x_position_cm) <= 6.0f) {
                if (DEMO_TARGETS[i].panel_index == 1) {
                    p1_cleaned_ = true;
                } else if (DEMO_TARGETS[i].panel_index == 2) {
                    p2_cleaned_ = true;
                }
            }
        }
    }

    bool isCleaned(uint8_t panel_index) const {
        if (panel_index == 1) return p1_cleaned_;
        if (panel_index == 2) return p2_cleaned_;
        return false;
    }

    void reset() {
        p1_cleaned_ = false;
        p2_cleaned_ = false;
    }

private:
    bool enabled_{true};
    bool fallback_on_hw_error_{true};
    bool p1_cleaned_{false};
    bool p2_cleaned_{false};
};

} // namespace presentation
