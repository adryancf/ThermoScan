#ifndef THERMOSCAN_DOMAIN_THERMAL_ANALYZER_H
#define THERMOSCAN_DOMAIN_THERMAL_ANALYZER_H

#include <vector>
#include <cstddef>
#include <cstdint>
#include <string>
#include "pinout.h"
#include "hal/i_thermal_camera.h"
#include "domain/quantized_frame.h"

namespace domain {

/**
 * @brief Represents a single thermal camera acquisition at a specific linear rail position.
 */
struct ScanAcquisition {
    float x_position_cm{0.0f};
    ThermalFrame frame{};
    bool valid{false};
};

/**
 * @brief Intermediate detected candidate pixel with temperature exceeding baseline threshold.
 */
struct HotspotCandidate {
    int col{0};
    int row{0};
    float temp_c{0.0f};
    float global_x_cm{0.0f};
    size_t acquisition_index{0};
    uint8_t panel_index{1};
};

/**
 * @brief Output struct representing a confirmed or evaluated hotspot event.
 */
struct HotspotEvent {
    uint8_t panel_index{1};
    float target_x_cm{0.0f};
    int row{0};
    float max_temp_c{0.0f};
    float baseline_temp_c{0.0f};
    bool confirmed{false};
    std::string origin_measurement_event_id{};
    std::vector<std::string> confirming_event_ids{};
};

/**
 * @brief Pure domain thermal analyzer implementing baseline calculation and
 * consecutive spatial confirmation of thermal anomalies.
 *
 * NOTE ON BASELINE AND DATA PIPELINE:
 * Análise é realizada após a captura da sequência completa, sem depender de leituras futuras.
 * All scan acquisitions along the inspection rail are collected in sequence and analyzed
 * retrospectively. The median baseline calculation uses all valid pixels across all valid frames.
 *
 * NOTE ON FALSE POSITIVE MITIGATION:
 * A confirmação espacial em passos consecutivos reduz ruído e reflexos espúrios,
 * mas não afirma eliminar 100% dos falsos positivos em condições reais de campo.
 */
class ThermalAnalyzer {
public:
    static constexpr int MLX_COLS = 32;
    static constexpr int MLX_ROWS = 24;
    static constexpr size_t PIXEL_COUNT = ThermalFrame::PIXEL_COUNT; // 768
    static constexpr float MIN_VALID_TEMP_C = -40.0f;
    static constexpr float MAX_VALID_TEMP_C = 300.0f;
    static constexpr float DEFAULT_POSITION_TOLERANCE_CM = SPATIAL_TOLERANCE_CM;
    static constexpr float DEFAULT_CALIBRATED_FOV_WIDTH_CM = FOV_OPTICAL_CM;

    /**
     * @brief Constructor allowing configurable optical FOV calibration width and spatial tolerance.
     *
     * SPATIAL CALIBRATION NOTE:
     * The physical correspondence of 32 columns covering 5.0 cm depends strictly on camera
     * standoff distance to panel surface (~3.5-4.0 cm) and perpendicular lens alignment.
     * The default value is strictly 5.0 cm (FOV_OPTICAL_CM).
     */
    explicit ThermalAnalyzer(float calibrated_fov_cm = FOV_OPTICAL_CM,
                             float spatial_tolerance_cm = SPATIAL_TOLERANCE_CM);

    float getCalibratedFovWidthCm() const { return calibrated_fov_cm_; }
    float getSpatialToleranceCm() const { return spatial_tolerance_cm_; }

    /**
     * @brief Checks if a pixel temperature reading is within valid sensor boundaries.
     */
    static bool isValidPixel(float temp_c);

    /**
     * @brief Computes global physical rail coordinate X_global for a given column within a capture at rail X.
     * Formula: X_global = X + (col / 32.0f) * fov_cm
     */
    static float calculateGlobalX(float scan_x_cm, int col, float fov_cm = FOV_OPTICAL_CM);

    /**
     * @brief Calculates median temperature of all valid pixels across all valid acquisitions in the scan.
     * Odd count: exact middle element.
     * Even count: average of the two central elements.
     */
    float calculateBaseline(const std::vector<ScanAcquisition>& acquisitions) const;

    /**
     * @brief Identifies candidate pixels exceeding baseline + HOTSPOT_THRESHOLD_DELTA_C.
     */
    std::vector<HotspotCandidate> findCandidates(const ScanAcquisition& acq,
                                                float baseline_temp_c,
                                                size_t acq_index = 0,
                                                float panel_start_cm = 0.0f,
                                                float panel_end_cm = 0.0f,
                                                uint8_t panel_index = 1) const;

    /**
     * @brief Evaluates the complete scan sequence.
     * Two candidates in consecutive acquisitions (step ~ 2.0 cm, optical overlap ~ 60%)
     * confirm a hotspot if they are on the same row and their global X coordinates
     * match within tolerance.
     *
     * Invalid pixels in the overlap region cannot confirm an anomaly alone.
     * Both consecutive frames must provide valid candidate detections.
     *
     * @param acquisitions Full sequence of scan acquisitions
     * @param tolerance_cm Maximum spatial difference in X_global for consecutive confirmation (negative = use analyzer's configured tolerance)
     * @param only_confirmed When true (default), returns only confirmed hotspots.
     *                       When false, includes unconfirmed candidates with confirmed=false.
     */
    std::vector<HotspotEvent> analyzeScan(const std::vector<ScanAcquisition>& acquisitions,
                                         float tolerance_cm = -1.0f,
                                         bool only_confirmed = true,
                                         float panel_start_cm = 0.0f,
                                         float panel_end_cm = 0.0f,
                                         uint8_t panel_index = 1) const;

    /**
     * @brief Evaluates scan sequence from memory-efficient quantized thermal frames.
     * Candidates are identified using the consolidated baseline temperature (T >= baseline + 10 °C).
     * Two consecutive acquisitions (step ~2 cm, 60% overlap) confirm a hotspot if on the same row
     * and matching in global X within spatial tolerance.
     */
    std::vector<HotspotEvent> analyzeQuantizedScan(const std::vector<QuantizedThermalFrame>& frames,
                                                  float baseline_temp_c,
                                                  float tolerance_cm = -1.0f,
                                                  bool only_confirmed = true,
                                                  float panel_start_cm = 0.0f,
                                                  float panel_end_cm = 0.0f,
                                                  uint8_t panel_index = 1) const;

private:
    float calibrated_fov_cm_{FOV_OPTICAL_CM};
    float spatial_tolerance_cm_{SPATIAL_TOLERANCE_CM};
};

} // namespace domain

// Aliases in global namespace for convenience
using domain::ScanAcquisition;
using domain::HotspotCandidate;
using domain::HotspotEvent;
using domain::ThermalAnalyzer;

#endif // THERMOSCAN_DOMAIN_THERMAL_ANALYZER_H
