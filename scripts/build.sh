#!/bin/bash
# Build for the simulator. Prints only warnings/errors and the final status.
set -o pipefail
source "$(dirname "$0")/env.sh"
cd "$PROJECT_ROOT"
xcodebuild -project Blockey.xcodeproj -scheme "$SCHEME" -configuration Debug \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | grep -E "(error|warning|BUILD SUCCEEDED|BUILD FAILED|Testing failed)" | sort -u
