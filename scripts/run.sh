#!/bin/bash
# Boot the simulator, install, grant calendar access, launch, and screenshot.
# Everything here touches the SIMULATOR only - never the host Mac's Calendar.
set -e
source "$(dirname "$0")/env.sh"
SHOT="${1:-/tmp/blockey.png}"
xcrun simctl boot "$SIM_NAME" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_NAME" -b >/dev/null 2>&1 || true
xcrun simctl uninstall "$SIM_NAME" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIM_NAME" "$APP_PATH"
xcrun simctl privacy "$SIM_NAME" grant calendar "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$SIM_NAME" "$BUNDLE_ID" >/dev/null
sleep 3
xcrun simctl io "$SIM_NAME" screenshot "$SHOT" >/dev/null 2>&1
echo "launched; screenshot -> $SHOT"
