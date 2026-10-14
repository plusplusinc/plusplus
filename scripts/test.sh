#!/bin/bash
# Runs tests.
#
#   scripts/test.sh          # fast: the package on macOS, no simulator. Seconds.
#   scripts/test.sh sim      # the app scheme on the simulator: package, snapshot, and UI tests,
#                            # after scripts/sim.sh reset
#   scripts/test.sh sim WorkoutStoreTests/WorkoutStoreContainerTests   # -only-testing filter
#
# The package declares a macOS platform so its tests run with `swift test` and no simulator.
# Tests that need UIKit are compiled out there and run in the simulator tier, whose test
# plan includes the package test targets, so `sim` is a superset of `fast`.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MODE="${1:-fast}"
ONLY="${2:-}"

case "$MODE" in
    fast)
        swift test --package-path "$PACKAGE" --disable-xctest --quiet
        ;;
    sim)
        # Whatever the last session left on the simulator (dark mode, a minimized keyboard) is
        # what the UI tests would see.
        "$ROOT/scripts/sim.sh" reset
        only=()
        [ -n "$ONLY" ] && only=(-only-testing:"$ONLY")
        status=0
        run_xcodebuild test test ${only[@]+"${only[@]}"} || status=$?
        # The summary also fails a run that executed no tests; xcodebuild's own failure wins.
        if ! xcresult tests "$RESULTS/test.xcresult" && [ "$status" -eq 0 ]; then status=1; fi
        [ "$status" -eq 0 ] || exit "$status"
        ;;
    *)
        echo "usage: scripts/test.sh [fast|sim] [only-testing-identifier]" >&2
        exit 64
        ;;
esac
echo "tests ok ($MODE)"
