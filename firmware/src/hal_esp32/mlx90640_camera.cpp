#if defined(ARDUINO) || defined(ESP32)

#include "mlx90640_camera.h"
#include <cmath>

namespace hal_esp32 {

Mlx90640Camera::Mlx90640Camera(uint8_t sda_pin, uint8_t scl_pin, uint8_t i2c_addr, uint8_t servo_pin)
    : sda_pin_(sda_pin), scl_pin_(scl_pin), i2c_addr_(i2c_addr), servo_pin_(servo_pin) {}

Mlx90640Camera::~Mlx90640Camera() {
    if (servo_.attached()) {
        servo_.detach();
    }
}

bool Mlx90640Camera::init() {
    Wire.begin(sda_pin_, scl_pin_);
    Wire.setClock(200000); // 200kHz I2C mode: ample margin for 4Hz MLX90640 with higher EMI immunity

    // Initialize Camera Tilt Servo to default configured angle
    if (servo_pin_ != 255 && !servo_.attached()) {
        servo_.setPeriodHertz(50);
        servo_.attach(servo_pin_, 500, 2500);
        setTiltAngle(CAMERA_DEFAULT_ANGLE);
    }

    if (!mlx_.begin(i2c_addr_, &Wire)) {
        initialized_ = false;
        return false;
    }

    mlx_.setMode(MLX90640_CHESS);
    mlx_.setRefreshRate(MLX90640_4_HZ);
    initialized_ = true;
    return true;
}

bool Mlx90640Camera::recoverI2cBus() {
    Wire.end();
    delay(5);

    // Clock out 9 SCL pulses to release any slave holding SDA LOW, then generate a STOP condition
    pinMode(sda_pin_, INPUT_PULLUP);
    pinMode(scl_pin_, OUTPUT);
    for (int i = 0; i < 9; ++i) {
        digitalWrite(scl_pin_, HIGH);
        delayMicroseconds(10);
        digitalWrite(scl_pin_, LOW);
        delayMicroseconds(10);
    }
    // STOP condition: SDA LOW -> SCL HIGH -> SDA HIGH
    pinMode(sda_pin_, OUTPUT);
    digitalWrite(sda_pin_, LOW);
    delayMicroseconds(10);
    digitalWrite(scl_pin_, HIGH);
    delayMicroseconds(10);
    digitalWrite(sda_pin_, HIGH);
    delayMicroseconds(10);

    Wire.begin(sda_pin_, scl_pin_);
    Wire.setClock(200000);
    delay(10);

    if (!mlx_.begin(i2c_addr_, &Wire)) {
        initialized_ = false;
        return false;
    }

    mlx_.setMode(MLX90640_CHESS);
    mlx_.setRefreshRate(MLX90640_4_HZ);
    initialized_ = true;
    return true;
}

bool Mlx90640Camera::setTiltAngle(float angle_deg) {
    if (angle_deg < 0.0f) angle_deg = 0.0f;
    if (angle_deg > 180.0f) angle_deg = 180.0f;
    current_tilt_angle_ = angle_deg;

    if (servo_.attached()) {
        servo_.write(static_cast<int>(angle_deg));
        return true;
    }
    return false;
}

float Mlx90640Camera::getTiltAngle() const {
    return current_tilt_angle_;
}

bool Mlx90640Camera::captureFrame(ThermalFrame& out) {
    if (!initialized_ && !recoverI2cBus()) {
        out.valid = false;
        return false;
    }

    // mlx.getFrame returns 0 on success; attempt automatic I2C bus recovery once on failure
    if (mlx_.getFrame(out.pixels) != 0) {
        if (!recoverI2cBus() || mlx_.getFrame(out.pixels) != 0) {
            initialized_ = false;
            out.valid = false;
            return false;
        }
    }

    // Sanity validation of raw thermal frame
    size_t invalid_count = 0;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        const float t = out.pixels[i];
        if (std::isnan(t) || std::isinf(t) || t < -40.0f || t > 300.0f) {
            invalid_count++;
        }
    }

    // Frame is considered valid if >= 95% of pixels are healthy
    out.valid = (invalid_count < (ThermalFrame::PIXEL_COUNT / 20));
    return out.valid;
}

bool Mlx90640Camera::isHealthy() {
    Wire.beginTransmission(i2c_addr_);
    return (Wire.endTransmission() == 0);
}

} // namespace hal_esp32

#endif // ARDUINO || ESP32
