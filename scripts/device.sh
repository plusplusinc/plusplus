#!/bin/bash
# Builds the app for a physical iPhone, installs it, and launches it.
#
#   scripts/device.sh                                  # the one available iPhone
#   PLUSPLUS_DEVICE="<name or UDID>" scripts/device.sh
#
# The phone is looked up each time, never stored, since the repo is public. It must be paired
# with this Mac and reachable: devicectl drops it when it is locked, away, or off the Mac's
# Wi-Fi. The build is incremental in the worktree's .build/device, apart from the simulator's
# derived data so both can build at once.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# One line per available iPhone, UDID then name, tab-separated, narrowed to PLUSPLUS_DEVICE
# when it is set. devicectl also lists simulators, watches, and devices it cannot reach.
available_iphones() {
    xcrun devicectl list devices --quiet --json-output - | python3 -c '
import json, sys

wanted = sys.argv[1]
for device in json.load(sys.stdin)["result"]["devices"]:
    properties = device["properties"]
    hardware, connection = properties["hardware"], properties["connection"]
    name = properties["state"]["name"]
    if (
        hardware["reality"] == "physical"
        and hardware["deviceType"] == "iPhone"
        and connection["pairingState"] == "paired"
        and connection["state"] != "unavailable"
        and wanted in ("", hardware["udid"], name)
    ):
        print(hardware["udid"], name, sep="\t")
' "${PLUSPLUS_DEVICE:-}"
}

IPHONES=$(available_iphones)
COUNT=$(grep -c . <<< "$IPHONES" || true)

if [ "$COUNT" -eq 0 ]; then
    echo "no iPhone available${PLUSPLUS_DEVICE:+ matching PLUSPLUS_DEVICE=$PLUSPLUS_DEVICE}:" \
        "unlock it and put it on this Mac's Wi-Fi; xcrun devicectl list devices shows what it sees" >&2
    exit 69
fi
if [ "$COUNT" -gt 1 ]; then
    echo "more than one iPhone available; choose one with PLUSPLUS_DEVICE=\"<name or UDID>\":" >&2
    cut -f2 <<< "$IPHONES" | sed 's/^/  /' >&2
    exit 64
fi
IFS=$'\t' read -r UDID NAME <<< "$IPHONES"

DESTINATION="id=$UDID"
DERIVED_DATA="$ROOT/.build/device"
run_xcodebuild device build -configuration Debug -allowProvisioningUpdates

APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/$SCHEME.app"
BUNDLE_ID=$(app_bundle_id "$APP")
xcrun devicectl device install app --quiet --device "$UDID" "$APP"
xcrun devicectl device process launch --quiet --terminate-existing --device "$UDID" "$BUNDLE_ID"
echo "launched on $NAME"
