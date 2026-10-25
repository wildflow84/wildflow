#!/usr/bin/env bash
# Pull the current screen's UI tree over adb (open the target settings screen on the car first).
# Usage: scripts/dump_ui.sh [adb-serial]  -> ui.xml in the current directory
set -euo pipefail

ADB=(adb)
[ -n "${1:-}" ] && ADB=(adb -s "$1")

"${ADB[@]}" shell uiautomator dump /sdcard/ui.xml
"${ADB[@]}" pull /sdcard/ui.xml ./ui.xml
