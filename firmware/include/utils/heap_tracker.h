#ifndef THERMOSCAN_UTILS_HEAP_TRACKER_H
#define THERMOSCAN_UTILS_HEAP_TRACKER_H

#include <cstddef>
#include <cstdint>

namespace utils {

struct HeapMetrics {
    size_t heap_before{0};
    size_t min_heap_during{0};
    size_t heap_after{0};
    size_t largest_block_min{0};

    size_t getNetAllocated() const {
        return (heap_before > heap_after) ? (heap_before - heap_after) : 0;
    }

    size_t getPeakConsumption() const {
        return (heap_before > min_heap_during) ? (heap_before - min_heap_during) : 0;
    }

    bool hasSafeMargin(size_t required_margin_bytes = 40960) const { // 40 KB
        return min_heap_during >= required_margin_bytes;
    }
};

class HeapTracker {
public:
    static void start();
    static void update();
    static HeapMetrics stop();
    static size_t getCurrentFreeHeap();
    static size_t getMinimumFreeHeap();

    // Simulation helpers for unit tests in native environment
    static void simulateHeapUsage(size_t simulated_free_heap);
    static void resetSimulation();

private:
    static HeapMetrics metrics_;
    static bool tracking_;
    static bool simulated_;
    static size_t simulated_free_heap_;
};

} // namespace utils

#endif // THERMOSCAN_UTILS_HEAP_TRACKER_H
