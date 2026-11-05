#include "domain/cleaning_state_machine.h"

namespace domain {

bool CleaningStateMachine::evaluateBeforeSpray(float baseline_temp_c, bool water_available, bool is_in_gap) {
    if (is_in_gap) {
        status_ = CleaningStatus::REFUSED;
        reason_ = "target_in_gap";
        return false;
    }

    if (baseline_temp_c > MAX_BASE_TEMP_C) {
        status_ = CleaningStatus::REFUSED;
        reason_ = "thermal_shock_risk";
        return false;
    }

    if (!water_available) {
        status_ = CleaningStatus::REFUSED;
        reason_ = "insufficient_water";
        return false;
    }

    if (effective_attempts_ >= MAX_CLEANING_ATTEMPTS) {
        status_ = CleaningStatus::REFUSED;
        reason_ = "max_attempts_exceeded";
        return false;
    }

    reason_.clear();
    return true;
}

bool CleaningStateMachine::startSpray() {
    if (effective_attempts_ >= MAX_CLEANING_ATTEMPTS) {
        status_ = CleaningStatus::REFUSED;
        reason_ = "max_attempts_exceeded";
        return false;
    }

    effective_attempts_++;
    status_ = CleaningStatus::IN_PROGRESS;
    reason_.clear();
    return true;
}

bool CleaningStateMachine::monitorDuringSpray(bool water_available, uint32_t current_time_sec) {
    if (status_ != CleaningStatus::IN_PROGRESS) {
        return false;
    }

    if (!water_available) {
        status_ = CleaningStatus::FAILED;
        reason_ = "water_depleted_during_cleaning";
        spray_ended_timestamp_ = current_time_sec;
        return false;
    }

    return true;
}

bool CleaningStateMachine::finishSpray(uint32_t current_time_sec) {
    if (status_ != CleaningStatus::IN_PROGRESS) {
        return false;
    }

    status_ = CleaningStatus::COMPLETED;
    spray_ended_timestamp_ = current_time_sec;
    reason_.clear();
    return true;
}

bool CleaningStateMachine::canStartVerification(uint32_t current_time_sec,
                                              uint32_t spray_end_sec,
                                              bool is_solar_window_valid) {
    if (!is_solar_window_valid) {
        return false;
    }

    if (current_time_sec < spray_end_sec) {
        return false;
    }

    if ((current_time_sec - spray_end_sec) < POST_CLEANING_WAIT_SECONDS) {
        return false;
    }

    return true;
}

bool CleaningStateMachine::canStartVerification(uint32_t current_time_sec,
                                              bool is_solar_window_valid) const {
    return canStartVerification(current_time_sec, spray_ended_timestamp_, is_solar_window_valid);
}

AnomalyResult CleaningStateMachine::processVerificationResult(bool hotspot_still_present,
                                                            bool verification_valid) {
    if (!verification_valid) {
        anomaly_result_ = AnomalyResult::PENDING_EVALUATION;
        return anomaly_result_;
    }

    if (!hotspot_still_present) {
        anomaly_result_ = AnomalyResult::RESOLVED;
        return anomaly_result_;
    }

    // Hotspot is still present after verification
    if (status_ == CleaningStatus::COMPLETED) {
        // Single completed wash did not resolve -> UNRESOLVED (no automatic re-wash)
        anomaly_result_ = AnomalyResult::UNRESOLVED;
        return anomaly_result_;
    }

    if (status_ == CleaningStatus::FAILED && effective_attempts_ < MAX_CLEANING_ATTEMPTS) {
        // Interrupted spray with attempts remaining -> OPEN (retry allowed after conditions met)
        anomaly_result_ = AnomalyResult::OPEN;
        return anomaly_result_;
    }

    // Attempt budget reached or default
    anomaly_result_ = AnomalyResult::UNRESOLVED;
    return anomaly_result_;
}

void CleaningStateMachine::reset() {
    status_ = CleaningStatus::IDLE;
    anomaly_result_ = AnomalyResult::OPEN;
    effective_attempts_ = 0;
    spray_ended_timestamp_ = 0;
    reason_.clear();
}

void CleaningStateMachine::resetForNewAnomaly() {
    status_ = CleaningStatus::IDLE;
    anomaly_result_ = AnomalyResult::OPEN;
    effective_attempts_ = 0;
    spray_ended_timestamp_ = 0;
    reason_.clear();
}

void CleaningStateMachine::restoreState(CleaningStatus status,
                                      AnomalyResult result,
                                      uint8_t effective_attempts,
                                      uint32_t spray_ended_sec) {
    status_ = status;
    anomaly_result_ = result;
    effective_attempts_ = effective_attempts;
    spray_ended_timestamp_ = spray_ended_sec;
    reason_.clear();
}

} // namespace domain
