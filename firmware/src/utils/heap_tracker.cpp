#include "utils/heap_tracker.h"
#include <algorithm>

#if defined(ESP32)
#include "esp_system.h"
#include "esp_heap_caps.h"
#endif

namespace utils {

HeapMetrics HeapTracker::metrics_{};
bool HeapTracker::tracking_{false};
bool HeapTracker::simulated_{false};
size_t HeapTracker::simulated_free_heap_{160 * 1024}; // 160 KB default for simulation

size_t HeapTracker::getCurrentFreeHeap() {
    if (simulated_) {
        return simulated_free_heap_;
    }
#if defined(ESP32)
    return esp_get_free_heap_size();
#else
    return 160 * 1024;
#endif
}

size_t HeapTracker::getMinimumFreeHeap() {
    if (simulated_) {
        return simulated_free_heap_;
    }
#if defined(ESP32)
    return esp_get_minimum_free_heap_size();
#else
    return 140 * 1024;
#endif
}

void HeapTracker::start() {
    tracking_ = true;
    metrics_.heap_before = getCurrentFreeHeap();
    metrics_.min_heap_during = metrics_.heap_before;
    metrics_.heap_after = 0;
#if defined(ESP32)
    metrics_.largest_block_min = heap_caps_get_largest_free_block(MALLOC_CAP_8BIT);
#else
    metrics_.largest_block_min = 100 * 1024;
#endif
}

void HeapTracker::update() {
    if (!tracking_) return;
    size_t current = getCurrentFreeHeap();
    if (current < metrics_.min_heap_during) {
        metrics_.min_heap_during = current;
    }
#if defined(ESP32)
    size_t largest = heap_caps_get_largest_free_block(MALLOC_CAP_8BIT);
    if (largest < metrics_.largest_block_min) {
        metrics_.largest_block_min = largest;
    }
#endif
}

HeapMetrics HeapTracker::stop() {
    update();
    metrics_.heap_after = getCurrentFreeHeap();
    tracking_ = false;
    return metrics_;
}

void HeapTracker::simulateHeapUsage(size_t simulated_free_heap) {
    simulated_ = true;
    simulated_free_heap_ = simulated_free_heap;
    if (tracking_ && simulated_free_heap < metrics_.min_heap_during) {
        metrics_.min_heap_during = simulated_free_heap;
    }
}

void HeapTracker::resetSimulation() {
    simulated_ = false;
    simulated_free_heap_ = 160 * 1024;
}

} // namespace utils

