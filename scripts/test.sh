#!/bin/bash
# Runs tests.
#
#   scripts/test.sh          # fast: the package on macOS, no simulator. Seconds.
#   scripts/test.sh sim      # the app scheme on the simulator: package, snapshot, and UI tests;
#                            # in a worktree, on its own simulator after scripts/sim.sh reset
#   scripts/test.sh sim WorkoutStoreTests/WorkoutStoreContainerTests   # -only-testing filter
#
# For a slower machine, two variables change `sim` from the test plan's settings:
#   PLUSPLUS_TEST_ALLOWANCE=<seconds>   each test's execution-time allowance, instead of the
#                                       plan's 180; XCTest rounds it up to whole minutes
#   PLUSPLUS_TEST_SERIAL=1              one simulator, no parallel clones, whatever the plan says
# The PR check sets both on GitHub's runner (docs/pr-check.md); local runs and Xcode Cloud don't.
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
        # what the UI tests would see. Only a worktree's own simulator is reset: the reset can
        # reboot, and any other simulator is a person's. The reset creates it on first use.
        if is_own_simulator; then
            "$ROOT/scripts/sim.sh" reset
        else
            echo "not resetting \"$SIMULATOR_NAME\": only a worktree's own simulator is reset" >&2
        fi
        args=()
        [ -n "$ONLY" ] && args=(-only-testing:"$ONLY")
        if [ -n "${PLUSPLUS_TEST_ALLOWANCE:-}" ]; then
            args+=(-test-timeouts-enabled YES
                -default-test-execution-time-allowance "$PLUSPLUS_TEST_ALLOWANCE"
                -maximum-test-execution-time-allowance "$PLUSPLUS_TEST_ALLOWANCE")
        fi
        [ "${PLUSPLUS_TEST_SERIAL:-}" = 1 ] && args+=(-parallel-testing-enabled NO)
        # Probe only: repeat the run.
        [ -n "${PLUSPLUS_TEST_ITERATIONS:-}" ] && args+=(-test-iterations "$PLUSPLUS_TEST_ITERATIONS")
        status=0
        run_xcodebuild test test ${args[@]+"${args[@]}"} || status=$?
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
