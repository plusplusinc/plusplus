#!/bin/bash
# Builds the app for the simulator. Prints compact diagnostics and exits non-zero on failure.
#
#   scripts/build.sh            # Debug
#   scripts/build.sh Release
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CONFIGURATION="${1:-Debug}"
run_xcodebuild build build -configuration "$CONFIGURATION"
echo "build ok ($CONFIGURATION, $SIMULATOR_NAME)"
