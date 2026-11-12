#include <unity.h>
#include "lab/presentation/presentation_mode.h"
#include "hal/i_motion_controller.h"
#include "hal/i_thermal_camera.h"
#include "hal/i_spray_actuator.h"
#include <vector>

using namespace presentation;

class TestMockCamera : public IThermalCamera {
public:
    bool healthy{true};
    bool capture_success{true};
    float room_temp{22.0f};

    bool init() override { return healthy; }
    bool isHealthy() override { return healthy; }
    bool captureFrame(ThermalFrame& out) override {
        if (!capture_success) {
            out.valid = false;
            return false;
        }
        out.valid = true;
        for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
            out.pixels[i] = room_temp;
        }
        return true;
    }
};

class TestMockMotion : public IMotionController {
public:
    float x{0.0f};
    bool init() override { return true; }
    bool home() override { x = 0.0f; return true; }
    bool moveToXCm(float target) override { x = target; return true; }
    float getXPositionCm() const override { return x; }
    bool checkLimitsIntegrity() override { return true; }
    void disableMotor() override {}
    void emergencyStop() override {}
};

class TestMockSpray : public ISprayActuator {
public:
    bool pump_active{false};
    float last_angle{90.0f};
    size_t pump_start_count{0};

    bool init() override { return true; }
    bool setNozzleAngle(float angle_deg) override { last_angle = angle_deg; return true; }
    bool startPump() override { pump_active = true; pump_start_count++; return true; }
    void stopPump() override { pump_active = false; }
    bool isPumpActive() const override { return pump_active; }
};

void setUp() {}
void tearDown() {}

void test_baseline_and_outside_target_area() {
    TestMockCamera real_cam;
    TestMockMotion motion;
    TestMockSpray real_spray;
    PresentationContext ctx;
    PresentationThermalCamera demo_cam(&real_cam, &motion, &ctx);

    // Position carriage away from demo hotspots (e.g. X = 25.0 cm)
    motion.x = 25.0f;
    real_cam.room_temp = 23.0f;

    ThermalFrame frame;
    bool ok = demo_cam.captureFrame(frame);
    TEST_ASSERT_TRUE(ok);
    TEST_ASSERT_TRUE(frame.valid);

    float max_t = -100.0f;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        if (frame.pixels[i] > max_t) max_t = frame.pixels[i];
    }
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 23.0f, max_t);
}

void test_panel1_hotspot_injection_and_resolution() {
    TestMockCamera real_cam;
    TestMockMotion motion;
    TestMockSpray real_spray;
    PresentationContext ctx;
    PresentationThermalCamera demo_cam(&real_cam, &motion, &ctx);
    PresentationSprayActuator demo_spray(&real_spray, &motion, &ctx);

    real_cam.room_temp = 24.0f;

    // 1. Move to Panel 1 hotspot (X = 15.0 cm) -> Should inject hotspot (~24 + 12 = 36 C)
    motion.x = 15.0f;
    ThermalFrame frame1;
    bool ok1 = demo_cam.captureFrame(frame1);
    TEST_ASSERT_TRUE(ok1);

    float max_t1 = -100.0f;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        if (frame1.pixels[i] > max_t1) max_t1 = frame1.pixels[i];
    }
    TEST_ASSERT_TRUE(max_t1 >= 35.0f);
    TEST_ASSERT_TRUE(ctx.isCleaned(1) == false);

    // 2. Perform spray at Panel 1 (X = 15.0 cm)
    demo_spray.startPump();
    TEST_ASSERT_TRUE(real_spray.pump_active);
    TEST_ASSERT_TRUE(ctx.isCleaned(1) == true);
    demo_spray.stopPump();

    // 3. Post-cleaning capture at X = 15.0 cm -> Hotspot should be RESOLVED (back to room temp)
    ThermalFrame frame2;
    bool ok2 = demo_cam.captureFrame(frame2);
    TEST_ASSERT_TRUE(ok2);

    float max_t2 = -100.0f;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        if (frame2.pixels[i] > max_t2) max_t2 = frame2.pixels[i];
    }
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 24.0f, max_t2);
}

void test_panel2_hotspot_injection_and_persistence() {
    TestMockCamera real_cam;
    TestMockMotion motion;
    TestMockSpray real_spray;
    PresentationContext ctx;
    PresentationThermalCamera demo_cam(&real_cam, &motion, &ctx);
    PresentationSprayActuator demo_spray(&real_spray, &motion, &ctx);

    real_cam.room_temp = 25.0f;

    // 1. Move to Panel 2 hotspot (X = 40.0 cm) -> Should inject hotspot (~25 + 12 = 37 C)
    motion.x = 40.0f;
    ThermalFrame frame1;
    bool ok1 = demo_cam.captureFrame(frame1);
    TEST_ASSERT_TRUE(ok1);

    float max_t1 = -100.0f;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        if (frame1.pixels[i] > max_t1) max_t1 = frame1.pixels[i];
    }
    TEST_ASSERT_TRUE(max_t1 >= 36.5f);

    // 2. Perform spray at Panel 2 (X = 40.0 cm)
    demo_spray.startPump();
    TEST_ASSERT_TRUE(ctx.isCleaned(2) == true);
    demo_spray.stopPump();

    // 3. Post-cleaning capture at X = 40.0 cm -> Hotspot MUST STILL PERSIST! (Hardware defect)
    ThermalFrame frame2;
    bool ok2 = demo_cam.captureFrame(frame2);
    TEST_ASSERT_TRUE(ok2);

    float max_t2 = -100.0f;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        if (frame2.pixels[i] > max_t2) max_t2 = frame2.pixels[i];
    }
    TEST_ASSERT_TRUE(max_t2 >= 36.5f);
}

void test_safety_fallback_on_hardware_fault() {
    TestMockCamera real_cam;
    TestMockMotion motion;
    PresentationContext ctx;
    PresentationThermalCamera demo_cam(&real_cam, &motion, &ctx);

    // Simulate complete I2C / camera crash
    real_cam.capture_success = false;
    real_cam.healthy = false;

    // When fallback is enabled:
    ctx.setFallbackOnHwErrorEnabled(true);
    ThermalFrame frame1;
    bool ok1 = demo_cam.captureFrame(frame1);
    TEST_ASSERT_TRUE(ok1);
    TEST_ASSERT_TRUE(frame1.valid);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, SYNTHETIC_ROOM_TEMP_DEFAULT_C, frame1.pixels[0]);

    // When fallback is disabled:
    ctx.setFallbackOnHwErrorEnabled(false);
    ThermalFrame frame2;
    bool ok2 = demo_cam.captureFrame(frame2);
    TEST_ASSERT_FALSE(ok2);
    TEST_ASSERT_FALSE(frame2.valid);
}

int main(int argc, char** argv) {
    UNITY_BEGIN();
    RUN_TEST(test_baseline_and_outside_target_area);
    RUN_TEST(test_panel1_hotspot_injection_and_resolution);
    RUN_TEST(test_panel2_hotspot_injection_and_persistence);
    RUN_TEST(test_safety_fallback_on_hardware_fault);
    return UNITY_END();
}
