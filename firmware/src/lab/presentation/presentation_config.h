#pragma once

#include <cstdint>
#include <vector>

namespace presentation {

struct DemoHotspotTarget {
    uint8_t panel_index;        // Panel index (1, 2...)
    float x_position_cm;        // Target X coordinate along the rail (cm)
    float detection_radius_cm;  // Radius around X where hotspot is visible in camera FOV
    float delta_temp_c;         // Thermal delta over real ambient baseline (°C)
    bool resolve_after_spray;   // true = soiling (disappears after wash), false = permanent fault
};

// ============================================================================
// Presentation Demo Targets Configuration
// ============================================================================
// Panel 1: Soiling hotspot at X = 15.0 cm (cleansed after spray)
// Panel 2: Cell degradation hotspot at X = 40.0 cm (persists after spray)
static const DemoHotspotTarget DEMO_TARGETS[] = {
    {
        .panel_index         = 1,
        .x_position_cm       = 15.0f,
        .detection_radius_cm = 3.5f,
        .delta_temp_c        = 12.0f,
        .resolve_after_spray = true
    },
    {
        .panel_index         = 2,
        .x_position_cm       = 40.0f,
        .detection_radius_cm = 3.5f,
        .delta_temp_c        = 12.0f,
        .resolve_after_spray = false
    }
};

constexpr size_t DEMO_TARGETS_COUNT = sizeof(DEMO_TARGETS) / sizeof(DEMO_TARGETS[0]);

// Safety net: if camera hardware or I2C experiences timeout/fault during live pitch,
// synthesize a nominal healthy room baseline (25.0 °C) instead of aborting inspection.
constexpr bool FALLBACK_ON_HARDWARE_FAILURE_DEFAULT = true;

// Default ambient temperature used when hardware fallback triggers (°C)
constexpr float SYNTHETIC_ROOM_TEMP_DEFAULT_C = 25.0f;

} // namespace presentation
