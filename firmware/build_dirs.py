Import("env")
import os

build_dir = env.subst("$BUILD_DIR")
print(">>> PRE-SCRIPT BUILD_DIR IS:", build_dir)
for sub in ["app", "diagnostics", "domain", "hal_esp32", "utils"]:
    p = os.path.join(build_dir, "src", sub)
    os.makedirs(p, exist_ok=True)
    print("Created:", p, os.path.exists(p))

