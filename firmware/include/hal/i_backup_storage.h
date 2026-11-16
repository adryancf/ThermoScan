#ifndef THERMOSCAN_HAL_I_BACKUP_STORAGE_H
#define THERMOSCAN_HAL_I_BACKUP_STORAGE_H

#include <cstddef>
#include <cstdint>
#include <string>

/**
 * @brief Hardware Abstraction Layer for optional raw thermal scan backup storage (e.g. MicroSD).
 * All methods must fail-safe gracefully when no storage medium is present (isAvailable() == false).
 */
class IBackupStorage {
public:
    static constexpr size_t FRAME_PIXEL_COUNT = 768; // MLX90640 32x24 pixels

    virtual ~IBackupStorage() = default;

    virtual bool init() = 0;
    virtual bool isAvailable() const = 0;

    virtual bool beginScanBackup(const std::string& inspection_id) = 0;
    virtual bool appendRawFrame(float scan_x_cm, const float* temps_768) = 0;
    virtual bool commitScanBackup(const std::string& inspection_id) = 0;

    virtual bool hasScanBackup(const std::string& inspection_id) = 0;
    virtual bool removeScanBackup(const std::string& inspection_id) = 0;
    virtual bool purgeTempFiles() = 0;
};

#endif // THERMOSCAN_HAL_I_BACKUP_STORAGE_H
