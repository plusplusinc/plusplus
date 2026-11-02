#!/bin/bash
# Shared setup for the scripts in this directory. Source it; do not run it.
#
# Builds funnel through a fixed derived-data path (.build/DerivedData for the simulator,
# .build/device for scripts/device.sh) so incremental builds stay warm across invocations, and
# through xcbeautify (when installed) so a reader gets a few hundred bytes of diagnostics instead
# of kilobytes of compiler invocations.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT="$ROOT/PlusPlus.xcodeproj"
SCHEME="PlusPlus"
PACKAGE="$ROOT/Packages"
DERIVED_DATA="$ROOT/.build/DerivedData"
RESULTS="$ROOT/.build/results"
# Each linked worktree, whose .git is a file, is an agent's, and builds and tests on a simulator
# of its own, "PlusPlus <worktree>", so two worktrees never share an app, its data, or its
# settings. ensure_simulator creates it on first use and records it in the clone's shared git
# directory, and scripts/tidy.sh deletes it with the worktree, or after one removed by hand. The main checkout defaults to iPhone 17, the maintainer's. scripts/test.sh resets, and
# scripts/sim.sh erases, only the worktree's own simulator, so an agent that leaves out
# PLUSPLUS_SIMULATOR never reaches a person's.

#   worktree_simulator <worktree path>
worktree_simulator() {
    echo "PlusPlus $(basename "$1")"
}

if [ -f "$ROOT/.git" ]; then
    OWN_SIMULATOR=$(worktree_simulator "$ROOT")
    SIMULATOR_NAME="${PLUSPLUS_SIMULATOR:-$OWN_SIMULATOR}"
else
    OWN_SIMULATOR=""
    SIMULATOR_NAME="${PLUSPLUS_SIMULATOR:-iPhone 17}"
fi
DESTINATION="platform=iOS Simulator,name=$SIMULATOR_NAME"

mkdir -p "$DERIVED_DATA" "$RESULTS"

# simctl passes SIMCTL_CHILD_* variables to the app it launches. InjectionNext, when linked by
# Config/Local.xcconfig, watches this directory for edits to hot-reload; otherwise it is unused.
export SIMCTL_CHILD_INJECTION_PROJECT_ROOT="$ROOT"

beautify() {
    if command -v xcbeautify > /dev/null; then
        xcbeautify --quieter --disable-colored-output --disable-logging
    else
        cat
    fi
}

# Prints "<udid> <state>" of the one simulator with this name, nothing when there is none, and
# fails when the name matches more than one, since acting on the wrong one could hit a person's.
#
#   simulator_udid <name>
simulator_udid() {
    xcrun simctl list devices --json | python3 -c '
import json, sys
matches = [d for ds in json.load(sys.stdin)["devices"].values() for d in ds
           if d["name"] == sys.argv[1]]
if len(matches) > 1:
    sys.exit(f"{len(matches)} simulators are named {sys.argv[1]!r}; delete or rename the extras with xcrun simctl")
for d in matches:
    print(d["udid"], d["state"])
' "$1"
}

# Whether the scripts are pointed at the worktree's own simulator, the only one they reset or
# erase; false in the main checkout and when PLUSPLUS_SIMULATOR names another.
is_own_simulator() {
    [ -n "$OWN_SIMULATOR" ] && [ "$SIMULATOR_NAME" = "$OWN_SIMULATOR" ]
}

# Each worktree simulator has a record, "<git common dir>/plusplus-simulators/<worktree>", whose
# modification time is the last time a script used it: `scripts/sim.sh list` reads it as idle
# time, and scripts/tidy.sh shuts down one idle too long.
simulator_records() {
    echo "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)/plusplus-simulators"
}

mark_simulator_used() {
    is_own_simulator || return 0
    local records
    records=$(simulator_records)
    mkdir -p "$records" && touch "$records/$(basename "$ROOT")"
}

# How many worktree simulators may be booted at once. Each takes about 2 GB and some 250
# processes; four at once filled a 48 GB Mac and most of its swap (2026-11-01). The maintainer's
# simulator never counts and never waits. Override with PLUSPLUS_MAX_BOOTED_SIMS in the
# environment (`env` in .claude/settings.local.json reaches every agent).
MAX_BOOTED_SIMS="${PLUSPLUS_MAX_BOOTED_SIMS:-2}"
# How long a boot waits for a free place before it gives up, short enough to finish inside an
# agent's 10-minute command limit with a build before it.
BOOT_WAIT_SECONDS="${PLUSPLUS_SIM_WAIT_SECONDS:-300}"

# Prints "<name>\t<udid>\t<idle seconds>\t<worktree path or ->" for each booted worktree
# simulator: one with a record, so the maintainer's and any other person's never show.
booted_worktree_simulators() {
    local records
    records=$(simulator_records)
    xcrun simctl list devices booted --json | python3 -c '
import json, os, subprocess, sys, time
records, root = sys.argv[1], sys.argv[2]
worktrees = {}
out = subprocess.run(["git", "-C", root, "worktree", "list", "--porcelain"],
                     capture_output=True, text=True).stdout
for line in out.splitlines():
    if line.startswith("worktree "):
        path = line[len("worktree "):]
        worktrees[os.path.basename(path)] = path
names = set(os.listdir(records)) if os.path.isdir(records) else set()
for ds in json.load(sys.stdin)["devices"].values():
    for d in ds:
        owner = d["name"].removeprefix("PlusPlus ")
        if d["state"] != "Booted" or owner == d["name"] or owner not in names:
            continue
        idle = int(time.time() - os.path.getmtime(os.path.join(records, owner)))
        print(d["name"], d["udid"], idle, worktrees.get(owner, "-"), sep="\t")
' "$records" "$ROOT"
}

# Boots the simulator the scripts point at and waits until it is ready. The worktree's own boots
# only while fewer than $MAX_BOOTED_SIMS worktree simulators are booted, else it waits for one to
# shut down, and after $BOOT_WAIT_SECONDS fails, naming the holders. It never shuts down another
# worktree's simulator: that one's agent may be mid-run. A lock makes the count and the boot one
# step, so two worktrees starting together cannot both take the last place.
boot_simulator() {
    if ! is_own_simulator; then
        xcrun simctl bootstatus "$SIMULATOR_NAME" -b > /dev/null
        return
    fi
    ensure_simulator
    mark_simulator_used
    local udid state
    read -r udid state < <(simulator_udid "$SIMULATOR_NAME")
    [ "$state" = Booted ] && return 0
    local lock deadline=$((SECONDS + BOOT_WAIT_SECONDS)) told=0 holders
    lock="$(simulator_records)/.boot.lock"
    while :; do
        # lockf holds a kernel lock that dies with the process, so a killed boot leaves none.
        if lockf -k "$lock" bash -c '
            source "$1/scripts/common.sh"
            [ "$(booted_worktree_simulators | grep -c .)" -lt "$MAX_BOOTED_SIMS" ] || exit 75
            xcrun simctl boot "$2" 2> /dev/null || [ "$(simulator_udid "$3" | cut -d" " -f2)" = Booted ]
        ' _ "$ROOT" "$udid" "$SIMULATOR_NAME"; then
            break
        elif [ $? -ne 75 ]; then
            echo "could not boot \"$SIMULATOR_NAME\" ($udid)" >&2
            return 1
        fi
        # A leftover past its idle limit makes way; a simulator in use never does.
        local name idle_udid freed=0
        while IFS=$'\t' read -r name idle_udid; do
            echo "shutting down \"$name\", idle over $((IDLE_SHUTDOWN_SECONDS / 60))m" >&2
            xcrun simctl shutdown "$idle_udid" && freed=1
        done < <(idle_worktree_simulators)
        [ "$freed" -eq 1 ] && continue
        holders=$(booted_worktree_simulators | awk -F'\t' '{ printf "  %s, idle %dm\n", $1, $3 / 60 }')
        if [ "$SECONDS" -ge "$deadline" ]; then
            printf '%s\n%s\n%s\n' \
                "$MAX_BOOTED_SIMS worktree simulators are still booted after ${BOOT_WAIT_SECONDS}s:" \
                "$holders" \
                "Run this command again later; never shut down another worktree's simulator. scripts/sim.sh list shows them." >&2
            return 75
        fi
        if [ "$told" -eq 0 ]; then
            printf '%s\n%s\n' "waiting for a free simulator place (limit $MAX_BOOTED_SIMS, PLUSPLUS_MAX_BOOTED_SIMS):" "$holders" >&2
            told=1
        fi
        # Waiting on another agent's simulator, which only that agent's own shutdown frees; no
        # event announces it, so look again every 15 seconds.
        sleep 15
    done
    xcrun simctl bootstatus "$udid" > /dev/null
}

# A worktree simulator no script has used for this long is left over from an agent that ended
# without `scripts/sim.sh shutdown`.
IDLE_SHUTDOWN_SECONDS=$((${PLUSPLUS_SIM_IDLE_MINUTES:-30} * 60))

# Prints the name and udid of each booted worktree simulator idle longer than that, with no
# xcodebuild running in its worktree (a long test run touches the record only as it starts).
idle_worktree_simulators() {
    local name udid idle path
    while IFS=$'\t' read -r name udid idle path; do
        [ "$idle" -gt "$IDLE_SHUTDOWN_SECONDS" ] || continue
        [ "$path" != - ] && pgrep -qf "xcodebuild.*$path/" && continue
        printf '%s\t%s\n' "$name" "$udid"
    done < <(booted_worktree_simulators)
}

# Shuts down the worktree's own simulator, if it is booted. Never any other: another worktree's
# agent may be mid-run, and the maintainer's is theirs.
shutdown_own_simulator() {
    if ! is_own_simulator; then
        echo "shutdown acts only on a worktree's own simulator, not \"$SIMULATOR_NAME\"" >&2
        return 1
    fi
    local udid state
    read -r udid state < <(simulator_udid "$OWN_SIMULATOR") || return 0
    [ "$state" = Booted ] || return 0
    xcrun simctl shutdown "$udid"
    echo "shut down \"$OWN_SIMULATOR\""
}

# Creates the worktree's own simulator when it does not exist yet: an iPhone 17 on the newest
# installed iOS runtime that runs it (a beta runtime can carry only a new device). Does nothing
# for any other simulator.
ensure_simulator() {
    is_own_simulator || return 0
    # The record outlives the worktree, so scripts/tidy.sh can delete the simulator of a worktree
    # removed with `git worktree remove`.
    mark_simulator_used
    local plan
    plan=$(xcrun simctl list --json devices runtimes | python3 -c '
import json, sys
own = sys.argv[1]
device_type = "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
data = json.load(sys.stdin)
if any(d["name"] == own for ds in data["devices"].values() for d in ds):
    sys.exit()
runtimes = [r for r in data["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]
            and any(t["identifier"] == device_type for t in r["supportedDeviceTypes"])]
if not runtimes:
    sys.exit(f"no installed iOS runtime runs {device_type}; install one in Xcode > Settings > Components")
newest = max(runtimes, key=lambda r: [int(p) for p in r["version"].split(".")])
print(device_type, newest["identifier"])
' "$SIMULATOR_NAME") || return 1
    [ -n "$plan" ] || return 0
    local device_type runtime
    read -r device_type runtime <<< "$plan"
    echo "creating simulator \"$SIMULATOR_NAME\" ($device_type, $runtime)" >&2
    xcrun simctl create "$SIMULATOR_NAME" "$device_type" "$runtime" > /dev/null
}

# Compact summaries of a result bundle; see scripts/xcresult.py.
xcresult() {
    python3 "$ROOT/scripts/xcresult.py" "$@"
}

# Runs xcodebuild with the shared flags and a result bundle at .build/results/<name>.xcresult.
# On failure, prints one line per diagnostic from the bundle and returns xcodebuild's status.
#
#   run_xcodebuild <name> <action> [xcodebuild args...]
run_xcodebuild() {
    local bundle="$RESULTS/$1.xcresult"
    shift
    rm -rf "$bundle"
    local status=0
    xcodebuild "$@" \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "$DESTINATION" \
        -derivedDataPath "$DERIVED_DATA" \
        -resultBundlePath "$bundle" \
        -skipPackagePluginValidation \
        -skipMacroValidation \
        -disableAutomaticPackageResolution \
        -onlyUsePackageVersionsFromResolvedFile \
        2>&1 | beautify || status=$?
    if [ "$status" -ne 0 ]; then
        echo "--- xcodebuild $1 failed (exit $status) ---"
        xcresult build "$bundle"
    fi
    return "$status"
}

# The bundle identifier of a built app, by default the last Debug simulator build, read from the
# built product so the scripts never hard-code it. Fails when nothing has been built yet.
#
#   app_bundle_id [path/to/PlusPlus.app]
app_bundle_id() {
    local plist="${1:-$DERIVED_DATA/Build/Products/Debug-iphonesimulator/$SCHEME.app}/Info.plist"
    if [ ! -f "$plist" ]; then
        echo "no built app at $plist; build it first, as scripts/run.sh does" >&2
        return 1
    fi
    plutil -extract CFBundleIdentifier raw -o - "$plist"
}
