#!/bin/bash
# Create an AVD matching the Zebra MC330M: Android 8.1, 4.0" WVGA 480x800 (240 dpi),
# 2 GB RAM, physical keypad + d-pad. Runs on the host, using the exported SDKs.
set -euo pipefail

: "${SDK_PATH:?SDK_PATH is not set}"
AVD="${AVD:-Zebra_MC330M}"
export JAVA_HOME="$SDK_PATH/java" ANDROID_HOME="$SDK_PATH/android" ANDROID_SDK_ROOT="$SDK_PATH/android"

echo no | "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd --force \
    -n "$AVD" -k "system-images;android-27;google_apis;x86" -d "Nexus S"

python3 - "$HOME/.android/avd/$AVD.avd/config.ini" <<'PY'
import sys
path = sys.argv[1]
cfg = dict(l.rstrip('\n').split('=', 1) for l in open(path) if '=' in l)
cfg.update({
    'avd.ini.displayname': 'Zebra MC330M (Android 8.1)',
    'hw.lcd.width': '480', 'hw.lcd.height': '800', 'hw.lcd.density': '240',
    'hw.ramSize': '2048', 'vm.heapSize': '256', 'disk.dataPartition.size': '4G',
    'hw.keyboard': 'yes', 'hw.dPad': 'yes', 'hw.mainKeys': 'yes',
    'hw.camera.back': 'emulated', 'hw.camera.front': 'none',
    'hw.gps': 'yes', 'hw.battery': 'yes', 'hw.sdCard': 'yes', 'sdcard.size': '512M',
    'hw.initialOrientation': 'portrait', 'showDeviceFrame': 'no', 'skin.dynamic': 'yes',
    'hw.gpu.enabled': 'yes', 'hw.gpu.mode': 'auto',
})
cfg.pop('skin.name', None)
cfg.pop('skin.path', None)
open(path, 'w').write(''.join(f'{k}={v}\n' for k, v in sorted(cfg.items())))
PY
echo "Created AVD $AVD - start it with: make emulator"
