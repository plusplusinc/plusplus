#!/bin/bash
# Builds, installs, and launches the app on the simulator, then takes a screenshot.
#
#   scripts/run.sh                    # screenshot to .build/screenshots/app.png
#   scripts/run.sh set-logging        # ...to .build/screenshots/set-logging.png
#   PLUSPLUS_SIMULATOR="iPhone 17 Pro" scripts/run.sh
#
# The screenshot path is printed last so an agent can Read it. Once the app is up,
# scripts/sim.sh drives it (appearance, Dynamic Type, more screenshots, log) without rebuilding.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

NAME="${1:-app}"

"$ROOT/scripts/build.sh" Debug

APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/$SCHEME.app"
BUNDLE_ID=$(app_bundle_id)

xcrun simctl bootstatus "$SIMULATOR_NAME" -b > /dev/null
open -a Simulator > /dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_NAME" "$APP"
xcrun simctl terminate "$SIMULATOR_NAME" "$BUNDLE_ID" 2> /dev/null || true
xcrun simctl launch "$SIMULATOR_NAME" "$BUNDLE_ID" > /dev/null

# Give the first frame a moment to settle before capturing.
sleep 2
"$ROOT/scripts/sim.sh" screenshot "$NAME"
