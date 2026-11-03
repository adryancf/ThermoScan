#include <unity.h>
#include "domain/cleaning_state_machine.h"
#include "pinout.h"

void setUp(void) {}
void tearDown(void) {}

void test_refusal_due_to_high_baseline_temp(void) {
    CleaningStateMachine sm;

    // Baseline temperature exceeds safety limit (> 60.0°C)
    const float high_temp = 65.5f;
    const bool water_ok = true;

    bool result = sm.evaluateBeforeSpray(high_temp, water_ok);

    TEST_ASSERT_FALSE(result);
    TEST_ASSERT_EQUAL(CleaningStatus::REFUSED, sm.getStatus());
    TEST_ASSERT_EQUAL_STRING("thermal_shock_risk", sm.getReason().c_str());
    TEST_ASSERT_EQUAL_UINT8(0, sm.getEffectiveAttempts()); // Attempt budget NOT consumed
}

void test_refusal_due_to_insufficient_water_before_spray(void) {
    CleaningStateMachine sm;

    // Normal baseline (35.0°C), but no water available
    const float normal_temp = 35.0f;
    const bool water_available = false;

    bool result = sm.evaluateBeforeSpray(normal_temp, water_available);

    TEST_ASSERT_FALSE(result);
    TEST_ASSERT_EQUAL(CleaningStatus::REFUSED, sm.getStatus());
    TEST_ASSERT_EQUAL_STRING("insufficient_water", sm.getReason().c_str());
    TEST_ASSERT_EQUAL_UINT8(0, sm.getEffectiveAttempts()); // Attempt budget NOT consumed
}

void test_interruption_due_to_water_depletion_during_spray(void) {
    CleaningStateMachine sm;

    // Safe pre-evaluation
    TEST_ASSERT_TRUE(sm.evaluateBeforeSpray(35.0f, true));

    // Spray starts
    TEST_ASSERT_TRUE(sm.startSpray());
    TEST_ASSERT_EQUAL(CleaningStatus::IN_PROGRESS, sm.getStatus());
    TEST_ASSERT_EQUAL_UINT8(1, sm.getEffectiveAttempts());

    // Water runs out mid-spray
    bool still_ok = sm.monitorDuringSpray(false);
    TEST_ASSERT_FALSE(still_ok);
    TEST_ASSERT_EQUAL(CleaningStatus::FAILED, sm.getStatus());
    TEST_ASSERT_EQUAL_STRING("water_depleted_during_cleaning", sm.getReason().c_str());
    TEST_ASSERT_EQUAL_UINT8(1, sm.getEffectiveAttempts()); // Attempt WAS consumed
}

void test_mandatory_30_minute_cooldown(void) {
    CleaningStateMachine sm;
    const uint32_t spray_end_epoch = 10000;

    // Spray completed at t = 10000
    sm.evaluateBeforeSpray(35.0f, true);
    sm.startSpray();
    sm.finishSpray(spray_end_epoch);
    TEST_ASSERT_EQUAL(CleaningStatus::COMPLETED, sm.getStatus());
    TEST_ASSERT_EQUAL_UINT32(spray_end_epoch, sm.getSprayEndedTimestamp());

    const bool solar_ok = true;

    // At 29 minutes (1740 seconds elapsed): BLOCKED
    TEST_ASSERT_FALSE(sm.canStartVerification(spray_end_epoch + 1740, solar_ok));

    // At 29 min 59 sec (1799 seconds elapsed): BLOCKED
    TEST_ASSERT_FALSE(sm.canStartVerification(spray_end_epoch + 1799, solar_ok));

    // At exactly 30 minutes (1800 seconds elapsed): ALLOWED
    TEST_ASSERT_TRUE(sm.canStartVerification(spray_end_epoch + 1800, solar_ok));

    // At 35 minutes (2100 seconds elapsed): ALLOWED
    TEST_ASSERT_TRUE(sm.canStartVerification(spray_end_epoch + 2100, solar_ok));
}

void test_solar_window_lock_on_verification(void) {
    CleaningStateMachine sm;
    const uint32_t spray_end_epoch = 10000;

    sm.restoreState(CleaningStatus::COMPLETED, AnomalyResult::OPEN, 1, spray_end_epoch);

    // After 35 minutes (cooldown satisfied), but solar window is invalid: BLOCKED
    TEST_ASSERT_FALSE(sm.canStartVerification(spray_end_epoch + 2100, false));

    // Only allowed if BOTH cooldown and solar window are satisfied
    TEST_ASSERT_TRUE(sm.canStartVerification(spray_end_epoch + 2100, true));
}

void test_verification_resolved(void) {
    CleaningStateMachine sm;
    const uint32_t spray_end_epoch = 10000;
    sm.restoreState(CleaningStatus::COMPLETED, AnomalyResult::OPEN, 1, spray_end_epoch);

    // Post-inspection: hotspot is gone, verification is valid
    AnomalyResult res = sm.processVerificationResult(false, true);

    TEST_ASSERT_EQUAL(AnomalyResult::RESOLVED, res);
    TEST_ASSERT_EQUAL(AnomalyResult::RESOLVED, sm.getAnomalyResult());
}

void test_completed_spray_persisting_hotspot_is_unresolved(void) {
    CleaningStateMachine sm;
    const uint32_t spray_end_epoch = 10000;

    // Wash was COMPLETED, 1 attempt used
    sm.restoreState(CleaningStatus::COMPLETED, AnomalyResult::OPEN, 1, spray_end_epoch);

    // Verification performed: hotspot is STILL present
    AnomalyResult res = sm.processVerificationResult(true, true);

    // Rule: Completed spray where hotspot persists transitions to UNRESOLVED (no automatic re-wash)
    TEST_ASSERT_EQUAL(AnomalyResult::UNRESOLVED, res);
    TEST_ASSERT_EQUAL(AnomalyResult::UNRESOLVED, sm.getAnomalyResult());
}

void test_interrupted_spray_persisting_hotspot_remains_open(void) {
    CleaningStateMachine sm;
    const uint32_t spray_end_epoch = 10000;

    // Wash was FAILED (e.g. water ran out), 1 attempt used (< 3)
    sm.restoreState(CleaningStatus::FAILED, AnomalyResult::OPEN, 1, spray_end_epoch);

    // Verification performed: hotspot is still present
    AnomalyResult res = sm.processVerificationResult(true, true);

    // Rule: Interrupted wash with attempts < 3 remains OPEN (retry allowed after conditions restored)
    TEST_ASSERT_EQUAL(AnomalyResult::OPEN, res);
    TEST_ASSERT_EQUAL(AnomalyResult::OPEN, sm.getAnomalyResult());
}

void test_strict_cap_on_cleaning_attempts_no_fourth_activation(void) {
    CleaningStateMachine sm;

    // Attempt 1
    TEST_ASSERT_TRUE(sm.evaluateBeforeSpray(30.0f, true));
    TEST_ASSERT_TRUE(sm.startSpray());
    sm.monitorDuringSpray(false); // Fails (attempt consumed)
    TEST_ASSERT_EQUAL_UINT8(1, sm.getEffectiveAttempts());

    // Attempt 2
    TEST_ASSERT_TRUE(sm.evaluateBeforeSpray(30.0f, true));
    TEST_ASSERT_TRUE(sm.startSpray());
    sm.monitorDuringSpray(false); // Fails (attempt consumed)
    TEST_ASSERT_EQUAL_UINT8(2, sm.getEffectiveAttempts());

    // Attempt 3
    TEST_ASSERT_TRUE(sm.evaluateBeforeSpray(30.0f, true));
    TEST_ASSERT_TRUE(sm.startSpray());
    sm.monitorDuringSpray(false); // Fails (attempt consumed)
    TEST_ASSERT_EQUAL_UINT8(3, sm.getEffectiveAttempts());

    // 4th activation attempt: MUST BE REFUSED
    bool eval_4 = sm.evaluateBeforeSpray(30.0f, true);
    TEST_ASSERT_FALSE(eval_4);
    TEST_ASSERT_EQUAL(CleaningStatus::REFUSED, sm.getStatus());
    TEST_ASSERT_EQUAL_STRING("max_attempts_exceeded", sm.getReason().c_str());

    // startSpray directly: MUST FAIL
    bool start_4 = sm.startSpray();
    TEST_ASSERT_FALSE(start_4);
    TEST_ASSERT_EQUAL_UINT8(3, sm.getEffectiveAttempts()); // Remains strictly capped at 3

    // Post-inspection with 3 attempts reached transitions to UNRESOLVED
    sm.processVerificationResult(true, true);
    TEST_ASSERT_EQUAL(AnomalyResult::UNRESOLVED, sm.getAnomalyResult());
}

void test_invalid_verification_keeps_pending_evaluation(void) {
    CleaningStateMachine sm;
    const uint32_t spray_end_epoch = 10000;
    sm.restoreState(CleaningStatus::COMPLETED, AnomalyResult::OPEN, 1, spray_end_epoch);

    // Verification measurement itself is invalid (e.g. sensor failure or interrupted scan)
    AnomalyResult res = sm.processVerificationResult(true, false);

    TEST_ASSERT_EQUAL(AnomalyResult::PENDING_EVALUATION, res);
    TEST_ASSERT_EQUAL(AnomalyResult::PENDING_EVALUATION, sm.getAnomalyResult());

    // Even if hotspot was reported false, invalid verification remains PENDING_EVALUATION
    res = sm.processVerificationResult(false, false);
    TEST_ASSERT_EQUAL(AnomalyResult::PENDING_EVALUATION, res);
    TEST_ASSERT_EQUAL(AnomalyResult::PENDING_EVALUATION, sm.getAnomalyResult());
}

int main(int argc, char **argv) {
    UNITY_BEGIN();
    RUN_TEST(test_refusal_due_to_high_baseline_temp);
    RUN_TEST(test_refusal_due_to_insufficient_water_before_spray);
    RUN_TEST(test_interruption_due_to_water_depletion_during_spray);
    RUN_TEST(test_mandatory_30_minute_cooldown);
    RUN_TEST(test_solar_window_lock_on_verification);
    RUN_TEST(test_verification_resolved);
    RUN_TEST(test_completed_spray_persisting_hotspot_is_unresolved);
    RUN_TEST(test_interrupted_spray_persisting_hotspot_remains_open);
    RUN_TEST(test_strict_cap_on_cleaning_attempts_no_fourth_activation);
    RUN_TEST(test_invalid_verification_keeps_pending_evaluation);
    return UNITY_END();
}
