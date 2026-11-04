#include "domain/temperature_histogram.h"
#include <cstring>
#include <cmath>

namespace domain {

TemperatureHistogram::TemperatureHistogram() {
    reset();
}

void TemperatureHistogram::reset() {
    std::memset(bins_, 0, sizeof(bins_));
    total_count_ = 0;
}

void TemperatureHistogram::addPixel(float temp_c) {
    if (std::isnan(temp_c)) {
        return;
    }
    // Only pixels within baseline histogram boundaries [-20.0, 120.0] are accumulated
    if (temp_c < HIST_MIN_TEMP_C || temp_c > HIST_MAX_TEMP_C) {
        return;
    }

    int bin_idx = static_cast<int>((temp_c - HIST_MIN_TEMP_C) / RESOLUTION_C);
    if (bin_idx >= 0 && static_cast<size_t>(bin_idx) < NUM_BINS) {
        if (bins_[bin_idx] < 0xFFFF) {
            bins_[bin_idx]++;
        }
        total_count_++;
    }
}

void TemperatureHistogram::addFrame(const ThermalFrame& frame) {
    if (!frame.valid) {
        return;
    }
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        addPixel(frame.pixels[i]);
    }
}

float TemperatureHistogram::calculateMedian() const {
    if (total_count_ == 0) {
        return 0.0f;
    }

    auto getTempForRank = [this](size_t rank) -> float {
        size_t cumulative = 0;
        for (size_t i = 0; i < NUM_BINS; ++i) {
            cumulative += bins_[i];
            if (cumulative > rank) {
                return HIST_MIN_TEMP_C + (static_cast<float>(i) * RESOLUTION_C) + (RESOLUTION_C / 2.0f);
            }
        }
        return HIST_MAX_TEMP_C;
    };

    if (total_count_ % 2 == 1) {
        return getTempForRank(total_count_ / 2);
    } else {
        float m1 = getTempForRank((total_count_ / 2) - 1);
        float m2 = getTempForRank(total_count_ / 2);
        return (m1 + m2) / 2.0f;
    }
}

} // namespace domain
