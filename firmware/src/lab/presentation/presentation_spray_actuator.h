#pragma once

#include "hal/i_spray_actuator.h"
#include "hal/i_motion_controller.h"
#include "presentation_context.h"

namespace presentation {

class PresentationSprayActuator : public ISprayActuator {
public:
    PresentationSprayActuator(ISprayActuator* real_spray,
                              IMotionController* motion,
                              PresentationContext* ctx)
        : real_spray_(real_spray), motion_(motion), ctx_(ctx) {}

    bool init() override {
        return (real_spray_ != nullptr) ? real_spray_->init() : true;
    }

    bool setNozzleAngle(float angle_deg) override {
        return (real_spray_ != nullptr) ? real_spray_->setNozzleAngle(angle_deg) : true;
    }

    bool startPump() override {
        if (ctx_ != nullptr && motion_ != nullptr) {
            float current_x = motion_->getXPositionCm();
            ctx_->recordSprayAt(current_x);
        }
        return (real_spray_ != nullptr) ? real_spray_->startPump() : true;
    }

    void stopPump() override {
        if (real_spray_ != nullptr) {
            real_spray_->stopPump();
        }
    }

    bool isPumpActive() const override {
        return (real_spray_ != nullptr) ? real_spray_->isPumpActive() : false;
    }

private:
    ISprayActuator* real_spray_{nullptr};
    IMotionController* motion_{nullptr};
    PresentationContext* ctx_{nullptr};
};

} // namespace presentation
