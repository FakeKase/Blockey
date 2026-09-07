#!/bin/bash
# Run the unit test suite on the simulator.
set -o pipefail
source "$(dirname "$0")/env.sh"
cd "$PROJECT_ROOT"
xcodebuild -project Blockey.xcodeproj -scheme "$SCHEME" -configuration Debug \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO test 2>&1 \
  | grep -E "(error:|failed|passed|Executed|TEST SUCCEEDED|TEST FAILED)" | sort -u
