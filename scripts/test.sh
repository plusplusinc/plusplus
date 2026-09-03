#!/bin/bash
# Runs tests.
#
#   scripts/test.sh          # fast: the package on macOS, no simulator. Seconds.
#   scripts/test.sh sim      # the app scheme on the simulator: package, snapshot, and UI tests
#   scripts/test.sh sim WorkoutStoreTests/WorkoutStoreContainerTests   # -only-testing filter
#
# The package declares a macOS platform so its tests run with `swift test` and no simulator.
# Tests that need UIKit are compiled out there and run in the simulator tier, whose scheme
# includes the package test targets, so `sim` is a superset of `fast`.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MODE="${1:-fast}"
ONLY="${2:-}"

case "$MODE" in
    fast)
        swift test --package-path "$PACKAGE" --disable-xctest --quiet
        ;;
    sim)
        only=()
        [ -n "$ONLY" ] && only=(-only-testing:"$ONLY")
        status=0
        run_xcodebuild test test ${only[@]+"${only[@]}"} || status=$?
        xcresult tests "$RESULTS/test.xcresult"
        [ "$status" -eq 0 ] || exit "$status"
        ;;
    *)
        echo "usage: scripts/test.sh [fast|sim] [only-testing-identifier]" >&2
        exit 64
        ;;
esac
echo "tests ok ($MODE)"
