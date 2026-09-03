#!/bin/bash
# Runs tests, cheapest tier first.
#
#   scripts/test.sh              # fast: every package that can run on macOS, no simulator
#   scripts/test.sh all          # fast tier, then the full app scheme on the simulator
#   scripts/test.sh sim          # only the app scheme on the simulator (snapshots, UI, app)
#   scripts/test.sh sim WorkoutStoreTests/WorkoutStoreContainerTests   # -only-testing filter
#
# Package tests run with `swift test` on macOS because every package declares a macOS platform
# for exactly this reason. Anything that needs UIKit is compiled out there and runs on the
# simulator via the app scheme, whose test action includes the package test targets.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MODE="${1:-fast}"
ONLY="${2:-}"

# Packages whose test targets can run on macOS. Add a package here when it grows a test target.
FAST_PACKAGES=(WorkoutStore DesignSystem)

run_fast() {
    for package in "${FAST_PACKAGES[@]}"; do
        echo "--- swift test: $package ---"
        set +e
        swift test --package-path "$ROOT/Packages/$package" --quiet 2>&1 \
            | grep -Ev '^\s*$|^(Fetch|Comput|Creating working|Working copy)|Executed 0 tests|Test Suite .All tests'
        local status=${PIPESTATUS[0]}
        set -e
        [ "$status" -eq 0 ] || return 1
    done
}

run_sim() {
    local bundle="$RESULTS/test.xcresult"
    rm -rf "$bundle"
    local extra=()
    [ -n "$ONLY" ] && extra+=(-only-testing:"$ONLY")

    set +e
    xcodebuild test "${COMMON_XCODEBUILD_FLAGS[@]}" \
        -resultBundlePath "$bundle" \
        -enableCodeCoverage YES \
        ${extra[@]+"${extra[@]}"} \
        2>&1 | beautify
    local status=${PIPESTATUS[0]}
    set -e

    print_test_summary "$bundle"
    if [ "$status" -ne 0 ]; then
        echo "--- tests failed (exit $status) ---"
        print_build_issues "$bundle"
        return "$status"
    fi
}

case "$MODE" in
    fast) run_fast ;;
    sim) run_sim ;;
    all) run_fast && run_sim ;;
    *) echo "usage: scripts/test.sh [fast|sim|all] [only-testing-identifier]" >&2; exit 64 ;;
esac
echo "tests ok ($MODE)"
