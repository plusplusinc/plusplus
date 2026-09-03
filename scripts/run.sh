#!/bin/bash
# Builds, installs, and launches the app on the simulator, then takes a screenshot.
#
#   scripts/run.sh                    # screenshot to .build/screenshots/app.png
#   scripts/run.sh set-logging        # ...to .build/screenshots/set-logging.png
#   PLUSPLUS_SIMULATOR="iPhone 17 Pro" scripts/run.sh
#
# The screenshot path is printed last so an agent can Read it. Deep links skip navigation:
# `xcrun simctl openurl booted "plusplus://..."` once the app registers a URL scheme.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

NAME="${1:-app}"
SHOTS="$ROOT/.build/screenshots"
mkdir -p "$SHOTS"

"$ROOT/scripts/build.sh" Debug

UDID=$(xcrun simctl list devices available -j \
    | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
for runtime, items in devices.items():
    if 'iOS' not in runtime: continue
    for d in items:
        if d['name'] == '$SIMULATOR_NAME':
            print(d['udid']); sys.exit(0)
sys.exit(1)")

xcrun simctl bootstatus "$UDID" -b > /dev/null
open -a Simulator --args -CurrentDeviceUDID "$UDID" > /dev/null 2>&1 || true

APP=$(find "$DERIVED_DATA/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "PlusPlus.app" | head -1)
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2> /dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" > /dev/null

# Give the first frame a moment to settle before capturing.
sleep 2
xcrun simctl io "$UDID" screenshot --type=png -- "$SHOTS/$NAME.png" > /dev/null
echo "$SHOTS/$NAME.png"
