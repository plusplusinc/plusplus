#!/bin/bash
# Formatting, lint, and spelling, the same way CI runs them.
#
#   scripts/lint.sh          # check only; non-zero on any finding
#   scripts/lint.sh --fix    # apply SwiftFormat and SwiftLint autocorrections first
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

cd "$ROOT"
for tool in swiftformat swiftlint; do
    command -v "$tool" > /dev/null || { echo "$tool is not installed: brew install $tool" >&2; exit 1; }
done

if [ "${1:-}" = "--fix" ]; then
    swiftformat App Packages
    swiftlint lint --fix --quiet App Packages
fi

status=0
swiftformat App Packages --lint || status=1
swiftlint lint --strict --quiet App Packages || status=1
scripts/check-us-english.sh || status=1

[ "$status" -eq 0 ] && echo "lint ok"
exit "$status"
