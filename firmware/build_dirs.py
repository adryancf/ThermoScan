Import("env")
import os

build_dir = env.subst("$BUILD_DIR")
os.makedirs(build_dir, exist_ok=True)
for sub in ["app", "diagnostics", "domain", "hal_esp32", "utils"]:
    p = os.path.join(build_dir, "src", sub)
    os.makedirs(p, exist_ok=True)

for lib in [
    "lib597/Wire",
    "lib699/SPI",
    "lib09e/Adafruit BusIO",
    "lib925/WiFi",
    "lib9d1/ESPmDNS",
    "lib9a4/FS",
    "lib6ab/WebServer",
    "lib5cc/WiFiClientSecure",
    "lib6e5/HTTPClient",
    "lib10f/Preferences",
    "FrameworkArduino",
    "FrameworkArduino/libb64"
]:
    p = os.path.join(build_dir, lib)
    os.makedirs(p, exist_ok=True)


