#ifndef THERMOSCAN_HAL_ESP32_SD_BACKUP_STORAGE_H
#define THERMOSCAN_HAL_ESP32_SD_BACKUP_STORAGE_H

#if defined(ARDUINO) || defined(ESP32)

#include <Arduino.h>
#include <SD.h>
#include <SPI.h>
#include <cstdint>
#include <string>

#include "hal/i_backup_storage.h"
#include "pinout.h"

namespace hal_esp32 {

/**
 * @brief ESP32 MicroSD backup storage driver implementing IBackupStorage via SD.h / SPI.h.
 * Provides automatic fallback (isAvailable() == false) when SD.begin fails or no card is inserted.
 */
class SdBackupStorage : public IBackupStorage {
public:
#ifdef PIN_SD_CS
    static constexpr uint8_t DEFAULT_CS_PIN = PIN_SD_CS;
#else
    static constexpr uint8_t DEFAULT_CS_PIN = 5;
#endif

#ifdef PIN_SD_SCK
    static constexpr int8_t DEFAULT_SCK_PIN = PIN_SD_SCK;
#else
    static constexpr int8_t DEFAULT_SCK_PIN = 18;
#endif

#ifdef PIN_SD_MISO
    static constexpr int8_t DEFAULT_MISO_PIN = PIN_SD_MISO;
#else
    static constexpr int8_t DEFAULT_MISO_PIN = 19;
#endif

#ifdef PIN_SD_MOSI
    static constexpr int8_t DEFAULT_MOSI_PIN = PIN_SD_MOSI;
#else
    static constexpr int8_t DEFAULT_MOSI_PIN = 23;
#endif

    explicit SdBackupStorage(uint8_t cs_pin = DEFAULT_CS_PIN,
                             int8_t sck_pin = DEFAULT_SCK_PIN,
                             int8_t miso_pin = DEFAULT_MISO_PIN,
                             int8_t mosi_pin = DEFAULT_MOSI_PIN);
    ~SdBackupStorage() override;

    bool init() override;
    bool isAvailable() const override;

    bool beginScanBackup(const std::string& inspection_id) override;
    bool appendRawFrame(float scan_x_cm, const float* temps_768) override;
    bool commitScanBackup(const std::string& inspection_id) override;

    bool hasScanBackup(const std::string& inspection_id) override;
    bool removeScanBackup(const std::string& inspection_id) override;
    bool purgeTempFiles() override;

private:
    static constexpr const char* BACKUP_DIR = "/backups";

    uint8_t cs_pin_;
    int8_t sck_pin_;
    int8_t miso_pin_;
    int8_t mosi_pin_;
    bool available_{false};
    File active_file_;
    std::string active_inspection_id_;

    std::string makeTempPath(const std::string& inspection_id) const;
    std::string makeBinPath(const std::string& inspection_id) const;
    void closeActiveFile();
};

} // namespace hal_esp32

#endif // ARDUINO || ESP32

#endif // THERMOSCAN_HAL_ESP32_SD_BACKUP_STORAGE_H
