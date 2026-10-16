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
# The feature agents' own simulator. The main checkout's default, iPhone 17, is the
# maintainer's, so scripts/test.sh resets, and scripts/sim.sh erases, only this one.
TEAM_SIMULATOR="PlusPlus Team"
# A linked worktree, whose .git is a file, is an agent's, so it defaults to the team's simulator
# and an agent that leaves out PLUSPLUS_SIMULATOR cannot reach the maintainer's.
if [ -f "$ROOT/.git" ]; then
    SIMULATOR_NAME="${PLUSPLUS_SIMULATOR:-$TEAM_SIMULATOR}"
else
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
