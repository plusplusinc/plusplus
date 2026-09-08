#!/bin/bash
# Drives the app that scripts/run.sh installed, without rebuilding.
#
#   scripts/sim.sh screenshot [name]        # .build/screenshots/<name>.png; prints the path
#   scripts/sim.sh shots [name]             # <name>.light.png, .dark.png, .xxxl.png, then reset
#   scripts/sim.sh appearance light|dark
#   scripts/sim.sh content-size <category>  # large (the default), extra-extra-extra-large,
#                                           # accessibility-extra-extra-extra-large, ...
#   scripts/sim.sh reset                    # appearance light, content size large
#   scripts/sim.sh relaunch                 # terminate and launch the installed build
#   scripts/sim.sh log [minutes]            # the app's own log lines, plus errors and faults
#
# Appearance and content size are simulator settings, so they survive relaunches and reboots:
# whatever the last session left behind is what the next screenshot shows. `reset` puts the
# device back to the defaults, and `shots` always ends with it.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SHOTS="$ROOT/.build/screenshots"
SUBSYSTEM="com.plusplusinc.plusplus"

# UIKit crossfades an appearance change and re-lays out for a content size change after
# `simctl ui` has already returned, and nothing outside the process signals when that is done.
# A capture taken immediately after the change shows the old state; one second later it is
# reliably the new one.
settle() {
    sleep 1
}

ui() {
    xcrun simctl ui "$SIMULATOR_NAME" "$@"
}

screenshot() {
    mkdir -p "$SHOTS"
    local path="$SHOTS/$1.png"
    # simctl narrates the capture on stderr; keep it for the failure case only.
    local output
    if ! output=$(xcrun simctl io "$SIMULATOR_NAME" screenshot --type=png -- "$path" 2>&1); then
        echo "$output" >&2
        return 1
    fi
    echo "$path"
}

case "${1:-}" in
    screenshot)
        screenshot "${2:-app}"
        ;;
    shots)
        name="${2:-app}"
        ui appearance light
        ui content_size large
        settle
        screenshot "$name.light"
        ui appearance dark
        settle
        screenshot "$name.dark"
        ui appearance light
        ui content_size accessibility-extra-extra-extra-large
        settle
        screenshot "$name.xxxl"
        ui content_size large
        ;;
    appearance)
        ui appearance "${2:?usage: scripts/sim.sh appearance light|dark}"
        settle
        ;;
    content-size)
        ui content_size "${2:?usage: scripts/sim.sh content-size <category>}"
        settle
        ;;
    reset)
        ui appearance light
        ui content_size large
        settle
        ;;
    relaunch)
        xcrun simctl bootstatus "$SIMULATOR_NAME" -b > /dev/null
        bundle_id=$(app_bundle_id)
        xcrun simctl terminate "$SIMULATOR_NAME" "$bundle_id" 2> /dev/null || true
        xcrun simctl launch "$SIMULATOR_NAME" "$bundle_id" > /dev/null
        ;;
    log)
        # The device's `log show`, run inside the simulator. It prints one spurious
        # "getpwuid_r did not find a match" line on stderr per invocation; drop only that,
        # so a real failure (the device is shut down, say) still explains itself.
        xcrun simctl spawn "$SIMULATOR_NAME" log show --last "${2:-5}m" --style compact \
            --predicate "process == \"$SCHEME\" AND (subsystem == \"$SUBSYSTEM\" OR messageType >= 16)" \
            2> >(grep -v getpwuid_r >&2)
        ;;
    *)
        sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
        exit 64
        ;;
esac
