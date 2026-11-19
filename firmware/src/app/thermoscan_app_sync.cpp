#include "thermoscan_app.h"
#include <cmath>
#include <algorithm>
#include <ArduinoJson.h>

#if defined(ARDUINO) || defined(ESP32)
#include <Arduino.h>
#include "diagnostics/web_diagnostics.h"
#define Serial diagnostics::getGlobalDualSerial()
#else
#include "hal/native_net_compat.h"
#endif

namespace app {

void ThermoscanApp::handleSyncing() {
    if (cloud_ != nullptr && cloud_->isResetPending()) {
        executeFullReset();
        return;
    }

    // Only fetch configuration if a pending update was marked
    if (!config_update_pending_) {
        if (!pending_sync_backup_id_.empty()) {
            if (backup_storage_ != nullptr && backup_storage_->isAvailable()) {
                backup_storage_->removeScanBackup(pending_sync_backup_id_);
            }
            pending_sync_backup_id_.clear();
            inspection_source_event_id_.clear();
            inspection_crash_retries_ = 0;
            if (storage_ != nullptr) {
                storage_->clearInspectionProgress();
            }
            saveCurrentStateToNvs();
        }
        transitionTo(AppState::IDLE);
        return;
    }

    if (cloud_ == nullptr || !cloud_->isConnected()) {
        config_sync_failed_waiting_ping_ = true;
        transitionTo(AppState::IDLE);
        return;
    }

    std::string cfg_json;
    if (!cloud_->getConfiguration(cfg_json)) {
        // getConfiguration failed: keep pending flag true, return to IDLE, retry on next ping
        config_sync_failed_waiting_ping_ = true;
        transitionTo(AppState::IDLE);
        return;
    }

    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, cfg_json.c_str());
    if (err) {
        last_config_error_ = "json_parse_error";
        config_sync_failed_waiting_ping_ = true;
        transitionTo(AppState::IDLE);
        return;
    }

    // 1. Version validation
    uint32_t ver = doc["config_version"] | 0;
    if (ver == 0) {
        last_config_error_ = "invalid_version";
        config_sync_failed_waiting_ping_ = true;
        transitionTo(AppState::IDLE);
        return;
    }

    // 2. Geometry validation
    if (!doc["geometry"].is<JsonObject>()) {
        last_config_error_ = "missing_geometry";
        config_sync_failed_waiting_ping_ = true;
        transitionTo(AppState::IDLE);
        return;
    }

    float len = doc["geometry"]["panel_length_cm"] | 0.0f;
    float width = doc["geometry"]["panel_width_cm"] | 0.0f;
    int32_t count = doc["geometry"]["panel_count"] | 0;
    float space = doc["geometry"]["panel_spacing_cm"] | -1.0f;

    if (len <= 0.0f || width <= 0.0f || count < 1 || space < 0.0f) {
        last_config_error_ = "invalid_geometry";
        config_sync_failed_waiting_ping_ = true;
        transitionTo(AppState::IDLE);
        return;
    }

    // 3. Solar angle validation (0 to 90 degrees)
    float min_solar = doc["min_solar_angle"] | -1.0f;
    if (min_solar < 0.0f || min_solar > 90.0f) {
        last_config_error_ = "invalid_solar_angle";
        config_sync_failed_waiting_ping_ = true;
        transitionTo(AppState::IDLE);
        return;
    }

    // 4. Interval validation (>= 1 day)
    int32_t interval_d = doc["interval_days"] | 0;
    if (interval_d < 1) {
        last_config_error_ = "invalid_interval";
        config_sync_failed_waiting_ping_ = true;
        transitionTo(AppState::IDLE);
        return;
    }

    // 5. Ping interval validation (>= 5 seconds)
    int32_t ping_s = doc["ping_interval_seconds"] | 0;
    if (ping_s < 5) {
        last_config_error_ = "invalid_ping_interval";
        config_sync_failed_waiting_ping_ = true;
        transitionTo(AppState::IDLE);
        return;
    }

    // 6. Coordinates validation (optional latitude -90..90, longitude -180..180)
    float lat = config_.latitude;
    if (doc["latitude"].is<float>()) {
        lat = doc["latitude"].as<float>();
        if (lat < -90.0f || lat > 90.0f) {
            last_config_error_ = "invalid_latitude";
            config_sync_failed_waiting_ping_ = true;
            transitionTo(AppState::IDLE);
            return;
        }
    }

    float lon = config_.longitude;
    if (doc["longitude"].is<float>()) {
        lon = doc["longitude"].as<float>();
        if (lon < -180.0f || lon > 180.0f) {
            last_config_error_ = "invalid_longitude";
            config_sync_failed_waiting_ping_ = true;
            transitionTo(AppState::IDLE);
            return;
        }
    }

    // 7. Orientation validation (optional azimuth 0..360, tilt 0..90)
    float azimuth = config_.azimuth;
    if (doc["azimuth_deg"].is<float>()) {
        azimuth = doc["azimuth_deg"].as<float>();
    } else if (doc["azimuth"].is<float>()) {
        azimuth = doc["azimuth"].as<float>();
    }
    if (azimuth < 0.0f || azimuth >= 360.0f) {
        last_config_error_ = "invalid_azimuth";
        config_sync_failed_waiting_ping_ = true;
        transitionTo(AppState::IDLE);
        return;
    }

    float tilt = config_.tilt;
    if (doc["tilt_deg"].is<float>()) {
        tilt = doc["tilt_deg"].as<float>();
    } else if (doc["tilt"].is<float>()) {
        tilt = doc["tilt"].as<float>();
    }
    if (tilt < 0.0f || tilt > 90.0f) {
        last_config_error_ = "invalid_tilt";
        config_sync_failed_waiting_ping_ = true;
        transitionTo(AppState::IDLE);
        return;
    }

    // 8. Hotspot threshold delta validation (optional > 0..50 °C)
    float hs_delta = config_.hotspot_threshold_delta_c;
    if (doc["hotspot_threshold_delta_c"].is<float>()) {
        hs_delta = doc["hotspot_threshold_delta_c"].as<float>();
        if (hs_delta <= 0.0f || hs_delta > 50.0f) {
            last_config_error_ = "invalid_hotspot_threshold";
            config_sync_failed_waiting_ping_ = true;
            transitionTo(AppState::IDLE);
            return;
        }
    }

    // All parameters validated successfully!
    last_config_error_.clear();
    const bool interval_changed = (interval_d != config_.interval_days);

    // Apply to RAM
    config_.config_version = ver;
    config_.panel_length_cm = len;
    config_.panel_width_cm = width;
    config_.panel_count = count;
    config_.panel_spacing_cm = space;
    config_.min_solar_angle = min_solar;
    config_.interval_days = interval_d;
    config_.ping_interval_seconds = ping_s;
    config_.latitude = lat;
    config_.longitude = lon;
    config_.azimuth = azimuth;
    config_.tilt = tilt;
    config_.hotspot_threshold_delta_c = hs_delta;
    thermal_analyzer_.setHotspotThresholdDeltaC(hs_delta);

    // Apply to NVS Flash
    if (storage_ != nullptr) {
        storage_->saveConfigVersion(ver);
        storage_->saveGeometry(len, width, count, space);
        storage_->saveMinSolarAngle(min_solar);
        storage_->saveIntervalDays(interval_d);
        storage_->savePingIntervalSeconds(ping_s);
        storage_->saveLocationAndOrientation(lat, lon, azimuth, tilt);
        storage_->saveHotspotThresholdDeltaC(hs_delta);
    }

    // Recalculate scheduled inspection timestamp if interval changed or if first provisioned
    if (interval_changed || next_inspection_time_ == 0) {
        const uint32_t now = getCurrentTime();
        if (now > 0) {
            next_inspection_time_ = now + static_cast<uint32_t>(config_.interval_days * 86400);
            if (storage_ != nullptr) {
                storage_->saveNextInspectionTimestamp(next_inspection_time_);
            }
        }
    }

    // Send acknowledgment only after successful RAM & NVS persistence
    const bool ack_ok = cloud_->ackConfiguration(config_.config_version);
    cloud_->clearConfigurationPending();

    if (ack_ok && !pending_sync_backup_id_.empty()) {
        if (backup_storage_ != nullptr && backup_storage_->isAvailable()) {
            backup_storage_->removeScanBackup(pending_sync_backup_id_);
        }
        pending_sync_backup_id_.clear();
        inspection_source_event_id_.clear();
        inspection_crash_retries_ = 0;
        if (storage_ != nullptr) {
            storage_->clearInspectionProgress();
        }
        saveCurrentStateToNvs();
    }

    config_update_pending_ = false;
    config_sync_failed_waiting_ping_ = false;
    transitionTo(AppState::IDLE);
}

} // namespace app
