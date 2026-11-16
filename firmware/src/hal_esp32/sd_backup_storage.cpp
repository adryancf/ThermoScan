#include "sd_backup_storage.h"

#if defined(ARDUINO) || defined(ESP32)

#include "diagnostics/web_diagnostics.h"
#define Serial diagnostics::getGlobalDualSerial()

namespace hal_esp32 {

SdBackupStorage::SdBackupStorage(uint8_t cs_pin,
                                 int8_t sck_pin,
                                 int8_t miso_pin,
                                 int8_t mosi_pin)
    : cs_pin_(cs_pin),
      sck_pin_(sck_pin),
      miso_pin_(miso_pin),
      mosi_pin_(mosi_pin) {}

SdBackupStorage::~SdBackupStorage() {
    closeActiveFile();
}

std::string SdBackupStorage::makeTempPath(const std::string& inspection_id) const {
    return std::string(BACKUP_DIR) + "/" + inspection_id + ".tmp";
}

std::string SdBackupStorage::makeBinPath(const std::string& inspection_id) const {
    return std::string(BACKUP_DIR) + "/" + inspection_id + ".bin";
}

void SdBackupStorage::closeActiveFile() {
    if (active_file_) {
        active_file_.flush();
        active_file_.close();
    }
    active_inspection_id_.clear();
}

bool SdBackupStorage::init() {
    closeActiveFile();
    available_ = false;

    SPI.begin(sck_pin_, miso_pin_, mosi_pin_, cs_pin_);
    if (!SD.begin(cs_pin_, SPI)) {
        Serial.println(F("[SD] Card mount failed or no SD card present; continuing with NVS-only fallback."));
        return false;
    }

    if (!SD.exists(BACKUP_DIR)) {
        if (!SD.mkdir(BACKUP_DIR)) {
            Serial.println(F("[SD] Failed to create /backups directory; disabling SD backup."));
            SD.end();
            return false;
        }
    }

    available_ = true;
    Serial.println(F("[SD] MicroSD backup storage initialized."));
    return true;
}

bool SdBackupStorage::isAvailable() const {
    return available_;
}

bool SdBackupStorage::beginScanBackup(const std::string& inspection_id) {
    if (!available_ || inspection_id.empty()) {
        return false;
    }

    closeActiveFile();

    const std::string tmp_path = makeTempPath(inspection_id);
    if (SD.exists(tmp_path.c_str())) {
        SD.remove(tmp_path.c_str());
    }

    active_file_ = SD.open(tmp_path.c_str(), FILE_WRITE);
    if (!active_file_) {
        Serial.printf("[SD] Failed to open temp backup file: %s\n", tmp_path.c_str());
        return false;
    }

    active_inspection_id_ = inspection_id;
    return true;
}

bool SdBackupStorage::appendRawFrame(float scan_x_cm, const float* temps_768) {
    if (!available_ || !active_file_ || temps_768 == nullptr) {
        return false;
    }

    const size_t x_written = active_file_.write(reinterpret_cast<const uint8_t*>(&scan_x_cm), sizeof(float));
    const size_t pixels_bytes = FRAME_PIXEL_COUNT * sizeof(float);
    const size_t pixels_written = active_file_.write(reinterpret_cast<const uint8_t*>(temps_768), pixels_bytes);

    if (x_written != sizeof(float) || pixels_written != pixels_bytes) {
        Serial.println(F("[SD] Failed to write raw thermal frame to temp backup."));
        return false;
    }

    active_file_.flush();
    return true;
}

bool SdBackupStorage::commitScanBackup(const std::string& inspection_id) {
    if (!available_ || inspection_id.empty()) {
        return false;
    }

    if (active_inspection_id_ == inspection_id) {
        closeActiveFile();
    }

    const std::string tmp_path = makeTempPath(inspection_id);
    const std::string bin_path = makeBinPath(inspection_id);

    if (!SD.exists(tmp_path.c_str())) {
        return SD.exists(bin_path.c_str());
    }

    if (SD.exists(bin_path.c_str())) {
        SD.remove(bin_path.c_str());
    }

    if (!SD.rename(tmp_path.c_str(), bin_path.c_str())) {
        Serial.printf("[SD] Failed to commit backup %s -> %s\n", tmp_path.c_str(), bin_path.c_str());
        return false;
    }

    return true;
}

bool SdBackupStorage::hasScanBackup(const std::string& inspection_id) {
    if (!available_ || inspection_id.empty()) {
        return false;
    }
    return SD.exists(makeBinPath(inspection_id).c_str());
}

bool SdBackupStorage::removeScanBackup(const std::string& inspection_id) {
    if (!available_ || inspection_id.empty()) {
        return false;
    }

    const std::string bin_path = makeBinPath(inspection_id);
    if (!SD.exists(bin_path.c_str())) {
        return true;
    }
    return SD.remove(bin_path.c_str());
}

bool SdBackupStorage::purgeTempFiles() {
    if (!available_) {
        return false;
    }

    closeActiveFile();

    File dir = SD.open(BACKUP_DIR);
    if (!dir || !dir.isDirectory()) {
        if (dir) {
            dir.close();
        }
        return false;
    }

    File entry = dir.openNextFile();
    while (entry) {
        const std::string name = entry.name();
        const bool is_dir = entry.isDirectory();
        entry.close();

        if (!is_dir && name.size() >= 4 && name.compare(name.size() - 4, 4, ".tmp") == 0) {
            std::string full_path = name;
            if (full_path.front() != '/') {
                full_path = std::string(BACKUP_DIR) + "/" + full_path;
            }
            SD.remove(full_path.c_str());
        }
        entry = dir.openNextFile();
    }

    dir.close();
    return true;
}

} // namespace hal_esp32

#endif // ARDUINO || ESP32
