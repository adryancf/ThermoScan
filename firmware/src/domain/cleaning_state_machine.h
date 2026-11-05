#ifndef THERMOSCAN_DOMAIN_CLEANING_STATE_MACHINE_H
#define THERMOSCAN_DOMAIN_CLEANING_STATE_MACHINE_H

#include <cstdint>
#include <string>
#include "pinout.h"

namespace domain {

/**
 * @brief State representing the current status of the spray cleaning actuator operation.
 */
enum class CleaningStatus {
    IDLE,
    REFUSED,
    IN_PROGRESS,
    COMPLETED,
    FAILED
};

/**
 * @brief Result lifecycle state of a detected thermal anomaly.
 */
enum class AnomalyResult {
    OPEN,
    RESOLVED,
    UNRESOLVED,
    PENDING_EVALUATION
};

/**
 * @brief Domain state machine managing spray cleaning attempts, safety interlocks,
 * cooldown timers, and post-cleaning verification outcomes.
 */
class CleaningStateMachine {
public:
    CleaningStateMachine() = default;

    /**
     * @brief Pre-spray safety and condition evaluation.
     * Evaluates baseline temperature, water supply, and cleaning attempt budget.
     *
     * Interlocks:
     * - is_in_gap == true -> REFUSED ("target_in_gap"). No attempt consumed.
     * - baseline_temp_c > 60.0°C (MAX_BASE_TEMP_C) -> REFUSED ("thermal_shock_risk"). No attempt consumed.
     * - water_available == false -> REFUSED ("insufficient_water"). No attempt consumed.
     * - effective_attempts >= 3 (MAX_CLEANING_ATTEMPTS) -> REFUSED ("max_attempts_exceeded"). No attempt consumed.
     *
     * @return true if safe to proceed with spray, false if refused.
     */
    bool evaluateBeforeSpray(float baseline_temp_c, bool water_available, bool is_in_gap = false);

    /**
     * @brief Initiates spray actuation.
     * Transitions state to IN_PROGRESS and increments the effective attempt counter.
     *
     * @return true if started successfully, false if budget exceeded.
     */
    bool startSpray();

    /**
     * @brief Continuously monitors fluid level while spray is active.
     * If water is depleted during cleaning, halts operation immediately,
     * transitions to FAILED ("water_depleted_during_cleaning"), records the real
     * spray termination timestamp to enforce the mandatory 30-min cooldown,
     * and preserves the consumed attempt.
     *
     * @param water_available Current water sensor reading.
     * @param current_time_sec Current epoch timestamp in seconds.
     * @return true if water is still available, false if depleted.
     */
    bool monitorDuringSpray(bool water_available, uint32_t current_time_sec = 0);

    /**
     * @brief Concludes successful spray actuation.
     * Transitions state to COMPLETED and stores the spray end epoch timestamp.
     *
     * @param current_time_sec Current epoch timestamp in seconds.
     * @return true if transitioned from IN_PROGRESS to COMPLETED.
     */
    bool finishSpray(uint32_t current_time_sec);

    /**
     * @brief Evaluates whether post-cleaning verification inspection is permitted.
     *
     * Strict requirements:
     * - Elapsed time since spray end must be >= 1800 seconds (POST_CLEANING_WAIT_SECONDS = 30 min).
     * - Solar window must be valid (is_solar_window_valid == true).
     *
     * @param current_time_sec Current epoch timestamp in seconds.
     * @param spray_end_sec Epoch timestamp when spray concluded.
     * @param is_solar_window_valid Flag indicating if solar elevation meets minimum threshold.
     * @return true only if both cooldown and solar window conditions are satisfied.
     */
    static bool canStartVerification(uint32_t current_time_sec,
                                     uint32_t spray_end_sec,
                                     bool is_solar_window_valid);

    /**
     * @brief Overload using the internal stored spray_ended_timestamp.
     */
    bool canStartVerification(uint32_t current_time_sec, bool is_solar_window_valid) const;

    /**
     * @brief Processes post-cleaning inspection results and updates anomaly lifecycle state.
     *
     * Rules:
     * - verification_valid == false -> PENDING_EVALUATION (inconclusive post-inspection).
     * - hotspot_still_present == false -> RESOLVED.
     * - hotspot_still_present == true:
     *   - If cleaning was COMPLETED -> UNRESOLVED (single completed wash did not resolve, no auto re-wash).
     *   - If cleaning was FAILED (interrupted) and effective_attempts < 3 -> OPEN (retry allowed after water refilled,
     *     valid solar window, and new 30 min cooldown).
     *   - If effective_attempts >= 3 -> UNRESOLVED (attempt budget exhausted, no 4th activation).
     */
    AnomalyResult processVerificationResult(bool hotspot_still_present, bool verification_valid);

    // State inspection accessors
    CleaningStatus getStatus() const { return status_; }
    AnomalyResult getAnomalyResult() const { return anomaly_result_; }
    uint8_t getEffectiveAttempts() const { return effective_attempts_; }
    uint32_t getSprayEndedTimestamp() const { return spray_ended_timestamp_; }
    void setSprayEndedTimestamp(uint32_t ts) { spray_ended_timestamp_ = ts; }
    const std::string& getReason() const { return reason_; }

    // State management
    void reset();
    void resetForNewAnomaly();
    void restoreState(CleaningStatus status,
                      AnomalyResult result,
                      uint8_t effective_attempts,
                      uint32_t spray_ended_sec);

private:
    CleaningStatus status_{CleaningStatus::IDLE};
    AnomalyResult anomaly_result_{AnomalyResult::OPEN};
    uint8_t effective_attempts_{0};
    uint32_t spray_ended_timestamp_{0};
    std::string reason_{""};
};

} // namespace domain

// Aliases in global namespace for convenience
using domain::CleaningStatus;
using domain::AnomalyResult;
using domain::CleaningStateMachine;

#endif // THERMOSCAN_DOMAIN_CLEANING_STATE_MACHINE_H
