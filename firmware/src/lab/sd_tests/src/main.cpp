#include <Arduino.h>
#include <FS.h>
#include <SD.h>
#include <SPI.h>

#include "pinout.h"

namespace {

constexpr const char* kTmpPath = "/sd_test.tmp";
constexpr const char* kBinPath = "/sd_test.bin";
constexpr const char* kTestPayload = "ThermoScan SD card hardware test payload\n";

const char* cardTypeToString(uint8_t card_type) {
    switch (card_type) {
        case CARD_NONE: return "NONE";
        case CARD_MMC:  return "MMC";
        case CARD_SD:   return "SDSC";
        case CARD_SDHC: return "SDHC";
        default:        return "UNKNOWN";
    }
}

void printCardInfo() {
    uint8_t card_type = SD.cardType();
    Serial.printf("Card Type : %s\n", cardTypeToString(card_type));

    uint64_t card_size_mb = SD.cardSize() / (1024ULL * 1024ULL);
    uint64_t total_bytes  = SD.totalBytes();
    uint64_t used_bytes   = SD.usedBytes();
    uint64_t free_bytes   = (total_bytes >= used_bytes) ? (total_bytes - used_bytes) : 0;

    Serial.printf("Card Size : %llu MB\n", static_cast<unsigned long long>(card_size_mb));
    Serial.printf("Total     : %llu bytes\n", static_cast<unsigned long long>(total_bytes));
    Serial.printf("Used      : %llu bytes\n", static_cast<unsigned long long>(used_bytes));
    Serial.printf("Free      : %llu bytes\n", static_cast<unsigned long long>(free_bytes));
}

bool testWriteFile(const char* path, const char* data) {
    Serial.printf("[1/4] Write test (%s)... ", path);
    File file = SD.open(path, FILE_WRITE);
    if (!file) {
        Serial.println("FAIL (open for write failed)");
        return false;
    }

    size_t expected = strlen(data);
    size_t written = file.print(data);
    file.close();

    if (written != expected) {
        Serial.printf("FAIL (wrote %u/%u bytes)\n",
                      static_cast<unsigned>(written),
                      static_cast<unsigned>(expected));
        return false;
    }
    Serial.println("PASS");
    return true;
}

bool testReadFile(const char* path, const char* expected) {
    Serial.printf("[2/4] Read test (%s)... ", path);
    File file = SD.open(path, FILE_READ);
    if (!file) {
        Serial.println("FAIL (open for read failed)");
        return false;
    }

    String content;
    while (file.available()) {
        content += static_cast<char>(file.read());
    }
    file.close();

    if (content != expected) {
        Serial.printf("FAIL (content mismatch: got \"%s\")\n", content.c_str());
        return false;
    }
    Serial.println("PASS");
    return true;
}

bool testRenameFile(const char* from_path, const char* to_path) {
    Serial.printf("[3/4] Rename test (%s -> %s)... ", from_path, to_path);
    if (SD.exists(to_path)) {
        SD.remove(to_path);
    }

    if (!SD.rename(from_path, to_path)) {
        Serial.println("FAIL (SD.rename returned false)");
        return false;
    }
    if (SD.exists(from_path) || !SD.exists(to_path)) {
        Serial.println("FAIL (post-rename file state invalid)");
        return false;
    }
    Serial.println("PASS");
    return true;
}

bool testDeleteFile(const char* path) {
    Serial.printf("[4/4] Delete test (%s)... ", path);
    if (!SD.remove(path)) {
        Serial.println("FAIL (SD.remove returned false)");
        return false;
    }
    if (SD.exists(path)) {
        Serial.println("FAIL (file still exists after remove)");
        return false;
    }
    Serial.println("PASS");
    return true;
}

}  // namespace

void setup() {
    Serial.begin(115200);
    delay(1000);

    Serial.println("\n=== ThermoScan SD Card Hardware Test ===");
    Serial.printf("SPI Pins -> CS:%u MOSI:%u MISO:%u SCK:%u\n",
                  SD_CS_PIN, SD_MOSI_PIN, SD_MISO_PIN, SD_SCK_PIN);

    SPI.begin(SD_SCK_PIN, SD_MISO_PIN, SD_MOSI_PIN, SD_CS_PIN);

    if (!SD.begin(PIN_SD_CS)) {
        Serial.println("ERROR: SD.begin(PIN_SD_CS) failed. Check wiring and SD card.");
        return;
    }

    if (SD.cardType() == CARD_NONE) {
        Serial.println("ERROR: No SD card detected.");
        return;
    }

    printCardInfo();

    // Clean up any leftover test files from previous runs.
    if (SD.exists(kTmpPath)) SD.remove(kTmpPath);
    if (SD.exists(kBinPath)) SD.remove(kBinPath);

    bool ok = true;
    ok = ok && testWriteFile(kTmpPath, kTestPayload);
    ok = ok && testReadFile(kTmpPath, kTestPayload);
    ok = ok && testRenameFile(kTmpPath, kBinPath);
    ok = ok && testDeleteFile(kBinPath);

    Serial.printf("Overall SD Test Result: %s\n", ok ? "ALL PASSED" : "FAILED");
}

void loop() {
    delay(5000);
}
