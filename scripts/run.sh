#!/bin/bash
# Builds, installs, and launches the app on the simulator, then takes a screenshot.
#
#   scripts/run.sh                    # screenshot to .build/screenshots/app.png
#   scripts/run.sh set-logging        # ...to .build/screenshots/set-logging.png
#   PLUSPLUS_SIMULATOR="iPhone 17 Pro" scripts/run.sh
#
# The screenshot path is printed last so an agent can Read it.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

NAME="${1:-app}"
SHOTS="$ROOT/.build/screenshots"
mkdir -p "$SHOTS"

"$ROOT/scripts/build.sh" Debug

APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/$SCHEME.app"
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw -o - "$APP/Info.plist")

xcrun simctl bootstatus "$SIMULATOR_NAME" -b > /dev/null
open -a Simulator > /dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_NAME" "$APP"
xcrun simctl terminate "$SIMULATOR_NAME" "$BUNDLE_ID" 2> /dev/null || true
xcrun simctl launch "$SIMULATOR_NAME" "$BUNDLE_ID" > /dev/null

# Give the first frame a moment to settle before capturing.
sleep 2
xcrun simctl io "$SIMULATOR_NAME" screenshot --type=png -- "$SHOTS/$NAME.png" > /dev/null
echo "$SHOTS/$NAME.png"
