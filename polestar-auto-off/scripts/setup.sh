#!/usr/bin/env bash
# One-time install over adb. Usage: scripts/setup.sh path/to/app-debug.apk [adb-serial]
set -euo pipefail

APK=${1:?usage: setup.sh app-debug.apk [adb-serial]}
ADB=(adb)
[ -n "${2:-}" ] && ADB=(adb -s "$2")
PKG=com.wildflow.polestarautooff

"${ADB[@]}" install -r "$APK"
# Lets the app re-enable its own accessibility service after every boot/update.
"${ADB[@]}" shell pm grant "$PKG" android.permission.WRITE_SECURE_SETTINGS
"${ADB[@]}" shell settings put secure enabled_accessibility_services "$PKG/$PKG.AutoOffService"
"${ADB[@]}" shell settings put secure accessibility_enabled 1
"${ADB[@]}" shell am start -n "$PKG/.MainActivity"
echo "installed; open the app and press 'run now' to test"
