#!/bin/bash
# Drives the simulator, and the app scripts/run.sh installed on it, without rebuilding.
#
#   scripts/sim.sh screenshot [name]        # .build/screenshots/<name>.png; prints the path
#   scripts/sim.sh shots [name]             # <name>.light.png, .dark.png, .xxxl.png; ends light, large
#   scripts/sim.sh appearance light|dark
#   scripts/sim.sh content-size <category>  # large (the default), extra-extra-extra-large,
#                                           # accessibility-extra-extra-extra-large, ...
#   scripts/sim.sh reset                    # light, large, keyboard not minimized
#   scripts/sim.sh relaunch                 # terminate and launch the installed build
#   scripts/sim.sh log [minutes]            # the app's own log lines, plus errors and faults
#   scripts/sim.sh erase                    # in a worktree, erase its own simulator and reset it;
#                                           # about 25 s, and scripts/run.sh reinstalls the app
#   scripts/sim.sh motion <recording.mov>   # each move in a recording, frame by frame, and its
#                                           # pauses; reads the file, touches no simulator
#
# Appearance, content size, and the keyboard are simulator settings, so they survive relaunches
# and reboots: whatever the last session left behind is what the next screenshot or UI test
# sees. `reset` puts the device back to the defaults, and `shots` always ends with appearance and
# content size back.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SHOTS="$ROOT/.build/screenshots"
SUBSYSTEM="com.plusplusinc.plusplus"
# `erase` erases only the worktree's own simulator, $OWN_SIMULATOR. Raw `simctl erase` and
# `simctl delete` are denied to agents, since they take any device, or `all`, and a wrong argument
# would wipe a person's simulators; this script is the permission boundary.

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

# Runs a command inside the simulator. Each invocation prints one spurious "getpwuid_r did not
# find a match" line on stderr; drop only that, so a real failure (the device is shut down, say)
# still explains itself.
device() {
    xcrun simctl spawn "$SIMULATOR_NAME" "$@" 2> >(grep -v getpwuid_r >&2)
}

# After hardware key events (`axe type` sends them), the device keeps its software keyboard
# minimized, and a reboot alone does not bring it back. Turning off automatic minimization and
# rebooting did, in #47, so `reset` does the same, rebooting only when it wrote the setting.
reset_keyboard() {
    local domain="com.apple.keyboard.preferences" key="AutomaticMinimizationEnabled"
    if [ "$(device defaults read "$domain" "$key" 2> /dev/null)" != 0 ]; then
        device defaults write "$domain" "$key" -bool false
        echo "turned off keyboard minimization; rebooting $SIMULATOR_NAME" >&2
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

# Each frame's change from the last different one (mpdecimate drops a recording's repeated
# frames, which simctl writes out of order), as the mean brightness of their difference, 0 to
# 255. A move runs from a frame changing by 0.5 or more to the last such frame before half a
# second with none; a pause is 0.04 s or more inside it (two frames at 60 fps) with no frame
# changing by 0.05, the level a pulsing dot stays under. Tuned on two recordings of one move
# between rows (2026-10-28): the first reads 0.95 s with a 0.133 s pause at 0.158 s, the stall
# that looking at its frames missed and tracking each row's position found; its rework, 0.75 s
# and none.
motion() {
    ffmpeg -hide_banner -nostats -i "$1" -vf \
        "mpdecimate,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG" \
        -f null - 2>&1 |
        awk '/pts_time:/ { sub(/.*pts_time:/, ""); t = $1 } /YAVG=/ { sub(/.*YAVG=/, ""); print t, $1 }' |
        sort -n |
        awk -v moving=0.5 -v still=0.05 '
            { t[NR] = $1; c[NR] = $2 }
            END {
                i = 1
                while (i <= NR) {
                    while (i <= NR && c[i] < moving) i++
                    if (i > NR) break
                    s = i; e = i
                    for (j = i + 1; j <= NR && t[j] - t[e] < 0.5; j++) if (c[j] >= moving) e = j
                    printf "move at %.3f s, %.2f s long (time from its start, change, bar)\n", t[s], t[e] - t[s]
                    last = s; pauses = ""
                    for (k = s; k <= e; k++) {
                        bar = ""
                        for (b = 0.125; b <= c[k] && b < 40; b += 0.25) bar = bar "#"
                        printf "  %6.3f %5.2f %s\n", t[k] - t[s], c[k], bar
                        if (c[k] < still) continue
                        if (t[k] - t[last] > 0.04)
                            pauses = pauses sprintf("  pause of %.3f s at %.3f s\n", t[k] - t[last], t[last] - t[s])
                        last = k
                    }
                    printf "%s", pauses
                    i = e + 1
                }
                if (NR == 0) print "no frames read" > "/dev/stderr"
            }'
}

case "${1:-}" in
    motion)
        [ -f "${2:-}" ] || { echo "usage: scripts/sim.sh motion <recording.mov>" >&2; exit 64; }
        motion "$2"
        ;;
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
        ensure_simulator
        xcrun simctl bootstatus "$SIMULATOR_NAME" -b > /dev/null
        reset_keyboard
        ui appearance light
        ui content_size large
        settle
        ;;
    erase)
        if ! is_own_simulator; then
            echo "erase acts only on a worktree's own simulator, not \"$SIMULATOR_NAME\"" >&2
            exit 1
        fi
        ensure_simulator
        read -r udid state < <(simulator_udid "$OWN_SIMULATOR")
        if [ "$state" = Booted ]; then
            xcrun simctl shutdown "$udid"
        fi
        xcrun simctl erase "$udid"
        "${BASH_SOURCE[0]}" reset
        ;;
    relaunch)
        ensure_simulator
        xcrun simctl bootstatus "$SIMULATOR_NAME" -b > /dev/null
        bundle_id=$(app_bundle_id)
        xcrun simctl terminate "$SIMULATOR_NAME" "$bundle_id" 2> /dev/null || true
        xcrun simctl launch "$SIMULATOR_NAME" "$bundle_id" > /dev/null
        ;;
    log)
        device log show --last "${2:-5}m" --style compact \
            --predicate "process == \"$SCHEME\" AND (subsystem == \"$SUBSYSTEM\" OR messageType >= 16)"
        ;;
    *)
        sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
        exit 64
        ;;
esac
