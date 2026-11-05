#ifndef THERMOSCAN_DOMAIN_PANEL_GEOMETRY_H
#define THERMOSCAN_DOMAIN_PANEL_GEOMETRY_H

#include <cstdint>
#include <cmath>

namespace domain {

struct PanelPositionInfo {
    uint8_t panel_index{1};     // 1-indexed (1..panel_count), 0 if in gap or out of bounds
    float   local_x_cm{0.0f};    // relative coordinate within panel
    bool    in_gap{false};       // true if inside inter-panel gap
    bool    within_bounds{true}; // true if within string [0, total_length]
    float   panel_start_cm{0.0f};
    float   panel_end_cm{0.0f};
    uint8_t nearest_panel{1};
};

static inline float calculateTotalStringLength(uint8_t panel_count, float panel_length_cm, float panel_spacing_cm) {
    if (panel_count == 0 || panel_length_cm <= 0.0f) {
        return 0.0f;
    }
    if (panel_spacing_cm < 0.0f) {
        panel_spacing_cm = 0.0f;
    }
    return (static_cast<float>(panel_count) * panel_length_cm) +
           (static_cast<float>(panel_count - 1) * panel_spacing_cm);
}

static inline float calculateTotalStringLengthCm(uint8_t panel_count, float panel_length_cm, float panel_spacing_cm) {
    return calculateTotalStringLength(panel_count, panel_length_cm, panel_spacing_cm);
}

static inline float getPanelStartCm(uint8_t panel_index, float panel_length_cm, float panel_spacing_cm) {
    if (panel_index == 0 || panel_length_cm <= 0.0f) {
        return 0.0f;
    }
    if (panel_spacing_cm < 0.0f) {
        panel_spacing_cm = 0.0f;
    }
    return static_cast<float>(panel_index - 1) * (panel_length_cm + panel_spacing_cm);
}

static inline float getPanelEndCm(uint8_t panel_index, float panel_length_cm, float panel_spacing_cm) {
    if (panel_index == 0 || panel_length_cm <= 0.0f) {
        return 0.0f;
    }
    return getPanelStartCm(panel_index, panel_length_cm, panel_spacing_cm) + panel_length_cm;
}

static inline void getPanelBounds(uint8_t panel_index, float panel_length_cm, float panel_spacing_cm, float& start_cm, float& end_cm) {
    start_cm = getPanelStartCm(panel_index, panel_length_cm, panel_spacing_cm);
    end_cm = getPanelEndCm(panel_index, panel_length_cm, panel_spacing_cm);
}

static inline PanelPositionInfo resolvePanelPosition(uint8_t panel_count, float panel_length_cm, float panel_spacing_cm, float x_position_cm) {
    PanelPositionInfo res;
    if (panel_count == 0) {
        panel_count = 1;
    }
    if (panel_length_cm <= 0.0f) {
        res.panel_index = 1;
        res.local_x_cm = x_position_cm;
        res.in_gap = false;
        res.within_bounds = true;
        res.nearest_panel = 1;
        return res;
    }
    if (panel_spacing_cm < 0.0f) {
        panel_spacing_cm = 0.0f;
    }

    constexpr float tolerance = 1e-3f;
    float total_length = calculateTotalStringLength(panel_count, panel_length_cm, panel_spacing_cm);

    if (x_position_cm < -tolerance || x_position_cm > total_length + tolerance) {
        res.panel_index = 0;
        res.local_x_cm = 0.0f;
        res.in_gap = false;
        res.within_bounds = false;
        res.nearest_panel = (x_position_cm > total_length) ? panel_count : 1;
        return res;
    }

    if (std::abs(x_position_cm) < tolerance) {
        x_position_cm = 0.0f;
    }
    if (std::abs(x_position_cm - total_length) < tolerance) {
        x_position_cm = total_length;
    }

    for (uint8_t p = 1; p <= panel_count; ++p) {
        float start_cm = 0.0f, end_cm = 0.0f;
        getPanelBounds(p, panel_length_cm, panel_spacing_cm, start_cm, end_cm);

        if (x_position_cm >= start_cm - tolerance && x_position_cm <= end_cm + tolerance) {
            float local_x = x_position_cm - start_cm;
            if (local_x < 0.0f) local_x = 0.0f;
            if (local_x > panel_length_cm) local_x = panel_length_cm;

            res.panel_index = p;
            res.local_x_cm = local_x;
            res.in_gap = false;
            res.within_bounds = true;
            res.panel_start_cm = start_cm;
            res.panel_end_cm = end_cm;
            res.nearest_panel = p;
            return res;
        }

        if (p < panel_count && panel_spacing_cm > 0.0f) {
            float next_start_cm = 0.0f, next_end_cm = 0.0f;
            getPanelBounds(p + 1, panel_length_cm, panel_spacing_cm, next_start_cm, next_end_cm);
            if (x_position_cm > end_cm + tolerance && x_position_cm < next_start_cm - tolerance) {
                uint8_t nearest = p;
                if (x_position_cm >= (end_cm + next_start_cm) / 2.0f) {
                    nearest = p + 1;
                }
                res.panel_index = 0;
                res.local_x_cm = x_position_cm - start_cm;
                res.in_gap = true;
                res.within_bounds = true;
                res.panel_start_cm = end_cm;
                res.panel_end_cm = next_start_cm;
                res.nearest_panel = nearest;
                return res;
            }
        }
    }

    res.panel_index = 0;
    res.local_x_cm = 0.0f;
    res.in_gap = true;
    res.within_bounds = false;
    res.nearest_panel = 1;
    return res;
}

static inline bool isCoordinateInGap(uint8_t panel_count, float panel_length_cm, float panel_spacing_cm, float x_position_cm) {
    PanelPositionInfo info = resolvePanelPosition(panel_count, panel_length_cm, panel_spacing_cm, x_position_cm);
    return info.in_gap;
}

} // namespace domain

#endif // THERMOSCAN_DOMAIN_PANEL_GEOMETRY_H
