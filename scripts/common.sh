#!/bin/bash
# Shared setup for the scripts in this directory. Source it; do not run it.
#
# Everything funnels through one derived-data path so incremental builds stay warm across
# invocations, and through xcbeautify (when installed) so a reader gets a few hundred bytes of
# diagnostics instead of kilobytes of compiler invocations.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT="$ROOT/PlusPlus.xcodeproj"
SCHEME="PlusPlus"
PACKAGE="$ROOT/Packages"
DERIVED_DATA="$ROOT/.build/DerivedData"
RESULTS="$ROOT/.build/results"
SIMULATOR_NAME="${PLUSPLUS_SIMULATOR:-iPhone 17}"

mkdir -p "$DERIVED_DATA" "$RESULTS"

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
        -destination "platform=iOS Simulator,name=$SIMULATOR_NAME" \
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
