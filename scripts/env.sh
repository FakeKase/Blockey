#!/bin/bash
# Shared config for all Blockey dev scripts.
# Uses DEVELOPER_DIR so no `sudo xcode-select` is ever required.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCHEME=Blockey
export BUNDLE_ID=com.kase.blockey
export SIM_NAME="iPhone 17 Pro"
export DERIVED="$PROJECT_ROOT/build"
export APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/Blockey.app"
