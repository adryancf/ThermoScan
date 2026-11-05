Import("env")
import os

build_dir = env.subst("$BUILD_DIR")
os.makedirs(build_dir, exist_ok=True)
for sub in ["app", "diagnostics", "domain", "hal_esp32", "utils"]:
    p = os.path.join(build_dir, "src", sub)
    os.makedirs(p, exist_ok=True)


