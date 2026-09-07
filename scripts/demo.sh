#!/bin/bash
# Launch into the populated demo state (simulator only) and screenshot.
set -e
source "$(dirname "$0")/env.sh"
SHOT="${1:-/tmp/blockey-demo.png}"
xcrun simctl boot "$SIM_NAME" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_NAME" -b >/dev/null 2>&1 || true
xcrun simctl uninstall "$SIM_NAME" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIM_NAME" "$APP_PATH"
xcrun simctl privacy "$SIM_NAME" grant calendar "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$SIM_NAME" "$BUNDLE_ID" -blockeyDemo -blockeyNow "${BLOCKEY_NOW:-10:20}" ${BLOCKEY_STAMP:+-blockeyStamp} >/dev/null
sleep 6
xcrun simctl io "$SIM_NAME" screenshot "$SHOT" >/dev/null 2>&1
echo "demo launched; screenshot -> $SHOT"
