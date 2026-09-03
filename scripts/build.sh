#!/bin/bash
# Builds the app for the simulator. Prints compact diagnostics and exits non-zero on failure.
#
#   scripts/build.sh            # Debug
#   scripts/build.sh Release
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CONFIGURATION="${1:-Debug}"
BUNDLE="$RESULTS/build.xcresult"
rm -rf "$BUNDLE"

set +e
xcodebuild build "${COMMON_XCODEBUILD_FLAGS[@]}" \
    -configuration "$CONFIGURATION" \
    -resultBundlePath "$BUNDLE" \
    2>&1 | beautify
status=${PIPESTATUS[0]}
set -e

if [ "$status" -ne 0 ]; then
    echo "--- build failed (exit $status) ---"
    print_build_issues "$BUNDLE"
    exit "$status"
fi
echo "build ok ($CONFIGURATION, $SIMULATOR_NAME)"
