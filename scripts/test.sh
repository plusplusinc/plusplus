#!/bin/bash
# Runs tests.
#
#   scripts/test.sh          # fast: the package on macOS, no simulator, then the scripts' own
#                            # tests. Seconds.
#   scripts/test.sh sim      # the app scheme on the simulator: package, snapshot, and UI tests;
#                            # in a worktree, on its own simulator after scripts/sim.sh reset
#   scripts/test.sh sim WorkoutStoreTests/WorkoutStoreContainerTests   # -only-testing filter
#   scripts/test.sh sim PlusPlusUITests/WorkoutUITests PlusPlusUITests/RowDragUITests  # several
#
# The package declares a macOS platform so its tests run with `swift test` and no simulator.
# Tests that need UIKit are compiled out there and run in the simulator tier, whose test
# plan includes the package test targets, so `sim` covers the package tests `fast` runs.
#
# Each run prints its times against the budgets in scripts/xcresult.py, and never fails on them.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MODE="${1:-fast}"
ONLY=("${@:2}")

case "$MODE" in
    fast)
        if [ "${#ONLY[@]}" -gt 0 ]; then
            echo "fast runs the whole package; a test filter is for sim: scripts/test.sh sim ${ONLY[*]}" >&2
            exit 64
        fi
        log="$RESULTS/fast.log"
        status=0
        swift test --package-path "$PACKAGE" --disable-xctest --quiet 2>&1 | tee "$log" ||
            status=$?
        xcresult package "$log"
        [ "$status" -eq 0 ] || exit "$status"
        # The scripts' own tests: the night runner's gates, the PR check's revert guard, the
        # models check and hook, board.sh's readme, and the times' parsing. Nothing else runs them, CI included, and they need no simulator or
        # network (about 7 s).
        python3 -I "$ROOT/scripts/nightly-tooling-test.py" > "$RESULTS/scripts.log" 2>&1 &&
            python3 -I "$ROOT/scripts/pr-check-test.py" >> "$RESULTS/scripts.log" 2>&1 &&
            python3 -I "$ROOT/scripts/models-test.py" >> "$RESULTS/scripts.log" 2>&1 &&
            python3 -I "$ROOT/scripts/board-test.py" >> "$RESULTS/scripts.log" 2>&1 &&
            python3 -I -m doctest "$ROOT/scripts/xcresult.py" >> "$RESULTS/scripts.log" 2>&1 ||
            { cat "$RESULTS/scripts.log"; echo "script tests failed" >&2; exit 1; }
        ;;
    sim)
        # zsh leaves an unquoted $VAR whole, so a list of filters can arrive as one argument
        # with spaces, which matches no test.
        for identifier in ${ONLY[@]+"${ONLY[@]}"}; do
            if [[ "$identifier" =~ [[:space:]] ]]; then
                echo "\"$identifier\" has a space: pass each filter as its own argument (zsh doesn't split an unquoted \$VAR; use \${=VAR} or an array)" >&2
                exit 64
            fi
        done
        # Whatever the last session left on the simulator (dark mode, a minimized keyboard) is
        # what the UI tests would see. Only the checkout's own simulator is reset: the reset can
        # reboot, and any other simulator is a person's. The reset creates it on first use.
        if is_own_simulator; then
            "$ROOT/scripts/sim.sh" reset
        else
            echo "not resetting \"$SIMULATOR_NAME\": only the checkout's own simulator is reset" >&2
        fi
        only=()
        for identifier in ${ONLY[@]+"${ONLY[@]}"}; do
            only+=(-only-testing:"$identifier")
        done
        status=0
        run_xcodebuild test test ${only[@]+"${only[@]}"} || status=$?
        # The summary also fails a run that executed no tests; xcodebuild's own failure wins.
        if ! xcresult tests "$RESULTS/test.xcresult" && [ "$status" -eq 0 ]; then status=1; fi
        xcresult times "$RESULTS/test.xcresult"
        [ "$status" -eq 0 ] || exit "$status"
        ;;
    *)
        echo "usage: scripts/test.sh [fast|sim] [only-testing-identifier...]" >&2
        exit 64
        ;;
esac
echo "tests ok ($MODE)"
