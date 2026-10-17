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
# settings. ensure_simulator creates it on first use, and scripts/tidy.sh deletes it with the
# worktree. The main checkout defaults to iPhone 17, the maintainer's. scripts/test.sh resets, and
# scripts/sim.sh erases, only the worktree's own simulator, so an agent that leaves out
# PLUSPLUS_SIMULATOR never reaches a person's.
TEMPLATE_SIMULATOR="PlusPlus Team"

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

# Creates the worktree's own simulator when it does not exist yet: the device type of
# $TEMPLATE_SIMULATOR (an iPhone 17 when there is none) on the newest installed iOS runtime that
# runs it (a beta runtime can carry only a new device).
# Does nothing in the main checkout or when PLUSPLUS_SIMULATOR names another simulator.
ensure_simulator() {
    [ "$SIMULATOR_NAME" = "$OWN_SIMULATOR" ] || return 0
    local found
    found=$(simulator_udid "$SIMULATOR_NAME") || return 1
    [ -z "$found" ] || return 0
    local device_type runtime
    read -r device_type runtime < <(xcrun simctl list --json devices runtimes | python3 -c '
import json, sys
data = json.load(sys.stdin)
types = [d["deviceTypeIdentifier"] for ds in data["devices"].values() for d in ds
         if d["name"] == sys.argv[1]]
device_type = types[0] if types else "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
runtimes = [r for r in data["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]
            and any(t["identifier"] == device_type for t in r["supportedDeviceTypes"])]
if not runtimes:
    sys.exit(f"no installed iOS runtime runs {device_type}; install one in Xcode > Settings > Components")
newest = max(runtimes, key=lambda r: [int(p) for p in r["version"].split(".")])
print(device_type, newest["identifier"])
' "$TEMPLATE_SIMULATOR") || return 1
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
