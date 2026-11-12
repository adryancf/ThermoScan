#pragma once

#include "hal/i_thermal_camera.h"
#include "hal/i_motion_controller.h"
#include "presentation_config.h"
#include "presentation_context.h"

namespace presentation {

class PresentationThermalCamera : public IThermalCamera {
public:
    PresentationThermalCamera(IThermalCamera* real_camera,
                              IMotionController* motion,
                              PresentationContext* ctx);

    bool init() override;
    bool captureFrame(ThermalFrame& out) override;
    bool isHealthy() override;
    bool setTiltAngle(float angle_deg) override;
    float getTiltAngle() const override;

    // Helper to compute frame baseline
    static float computeBaseline(const ThermalFrame& frame);

    // Helper to inject a realistic gaussian thermal cluster into a frame
    static void injectCluster(ThermalFrame& frame,
                              float baseline_temp,
                              float delta_temp,
                              int center_row = 12,
                              int center_col = 16);

private:
    IThermalCamera* real_camera_{nullptr};
    IMotionController* motion_{nullptr};
    PresentationContext* ctx_{nullptr};
};

} // namespace presentation
