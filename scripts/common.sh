#!/bin/bash
# Shared setup for the scripts in this directory. Source it; do not run it.
#
# Everything funnels through one derived-data path so incremental builds stay warm across
# invocations, and through xcbeautify (when installed) so an agent reads 500 bytes of
# diagnostics instead of 8KB of compiler invocations.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT="$ROOT/PlusPlus.xcodeproj"
SCHEME="PlusPlus"
DERIVED_DATA="$ROOT/.build/DerivedData"
RESULTS="$ROOT/.build/results"
SIMULATOR_NAME="${PLUSPLUS_SIMULATOR:-iPhone 17}"
DESTINATION="platform=iOS Simulator,name=$SIMULATOR_NAME"
BUNDLE_ID="com.plusplusinc.plusplus"

mkdir -p "$DERIVED_DATA" "$RESULTS"

# Prettifies xcodebuild output if xcbeautify is installed; passes it through otherwise.
beautify() {
    if command -v xcbeautify > /dev/null; then
        xcbeautify --quieter --disable-colored-output --disable-logging
    else
        cat
    fi
}

# Compact diagnostics from a result bundle; see scripts/xcresult.py.
print_build_issues() {
    [ -d "$1" ] && python3 "$ROOT/scripts/xcresult.py" build "$1" || true
}

print_test_summary() {
    [ -d "$1" ] && python3 "$ROOT/scripts/xcresult.py" tests "$1" || true
}

COMMON_XCODEBUILD_FLAGS=(
    -project "$PROJECT"
    -scheme "$SCHEME"
    -destination "$DESTINATION"
    -derivedDataPath "$DERIVED_DATA"
    -skipPackagePluginValidation
    -skipMacroValidation
    -disableAutomaticPackageResolution
    -onlyUsePackageVersionsFromResolvedFile
)
