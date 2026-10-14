#!/bin/bash
# Drives the app that scripts/run.sh installed, without rebuilding.
#
#   scripts/sim.sh screenshot [name]        # .build/screenshots/<name>.png; prints the path
#   scripts/sim.sh shots [name]             # <name>.light.png, .dark.png, .xxxl.png; ends light, large
#   scripts/sim.sh appearance light|dark
#   scripts/sim.sh content-size <category>  # large (the default), extra-extra-extra-large,
#                                           # accessibility-extra-extra-extra-large, ...
#   scripts/sim.sh reset                    # light, large, software keyboard; scripts/test.sh sim
#                                           # runs it first
#   scripts/sim.sh relaunch                 # terminate and launch the installed build
#   scripts/sim.sh log [minutes]            # the app's own log lines, plus errors and faults
#   scripts/sim.sh erase-team               # erase "PlusPlus Team", then reset it; when its state
#                                           # is suspect or a UI test fails with nothing wrong in
#                                           # the app. About a minute, and the app is gone after.
#
# Appearance, content size, and the keyboard are simulator settings, so they survive relaunches
# and reboots: whatever the last session left behind is what the next screenshot or UI test
# sees. `reset` puts the device back to the defaults, and `shots` always ends with appearance and
# content size back.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SHOTS="$ROOT/.build/screenshots"
SUBSYSTEM="com.plusplusinc.plusplus"
# The only simulator `erase-team` will erase: the feature agents' own, never a person's.
TEAM_SIMULATOR="PlusPlus Team"

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

# The device's `defaults`, run inside the simulator. Like `log`, it prints one spurious
# "getpwuid_r did not find a match" line on stderr per invocation; drop only that.
device_defaults() {
    xcrun simctl spawn "$SIMULATOR_NAME" defaults "$@" 2> >(grep -v getpwuid_r >&2)
}

# Sets a boolean in the device's keyboard preferences, writing only when it differs. Prints the
# key when it wrote, so the caller knows whether anything changed.
keyboard_setting() {
    local domain="com.apple.keyboard.preferences" current want=0
    [ "$2" = true ] && want=1
    current=$(device_defaults read "$domain" "$1" 2> /dev/null || true)
    if [ "$current" != "$want" ]; then
        device_defaults write "$domain" "$1" -bool "$2"
        echo "$1"
    fi
}

# The keyboard settings a UI test needs: the software keyboard, full size. After hardware key
# events (`axe type` sends them), the device remembers a hardware keyboard and keeps its software
# keyboard minimized, which a reboot alone does not clear. What brought it back in #47 was
# writing these and rebooting, so `reset` reboots too, but only when it wrote something.
reset_keyboard() {
    local changed
    changed=$(
        keyboard_setting AutomaticMinimizationEnabled false
        keyboard_setting HardwareKeyboardLastSeen false
    )
    if [ -n "$changed" ]; then
        echo "keyboard settings changed (${changed//$'\n'/, }); rebooting $SIMULATOR_NAME" >&2
        xcrun simctl shutdown "$SIMULATOR_NAME"
        xcrun simctl bootstatus "$SIMULATOR_NAME" -b > /dev/null
    fi
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
        xcrun simctl bootstatus "$SIMULATOR_NAME" -b > /dev/null
        reset_keyboard
        ui appearance light
        ui content_size large
        settle
        ;;
    erase-team)
        # Raw `simctl erase` is denied to agents: it takes any device, or `all`, and a wrong
        # argument would wipe a person's simulators. This erases one device, by the team's name
        # and by nothing else, so the permission boundary lives here.
        if [ "$SIMULATOR_NAME" != "$TEAM_SIMULATOR" ]; then
            echo "erase-team erases only \"$TEAM_SIMULATOR\", not \"$SIMULATOR_NAME\";" \
                "run it as PLUSPLUS_SIMULATOR=\"$TEAM_SIMULATOR\" scripts/sim.sh erase-team" >&2
            exit 64
        fi
        # A name can match more than one device; erase only when it names exactly one.
        matches=$(xcrun simctl list devices --json | python3 -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["name"] == sys.argv[1]:
            print(device["udid"], device["state"])
' "$TEAM_SIMULATOR")
        if [ "$(grep -c . <<< "$matches")" -ne 1 ]; then
            echo "expected one simulator named \"$TEAM_SIMULATOR\", found:" \
                "${matches:-none}; create or rename it with xcrun simctl" >&2
            exit 1
        fi
        read -r udid state <<< "$matches"
        if [ "$state" != Shutdown ]; then
            xcrun simctl shutdown "$udid"
        fi
        xcrun simctl erase "$udid"
        "${BASH_SOURCE[0]}" reset
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
        sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
        exit 64
        ;;
esac
