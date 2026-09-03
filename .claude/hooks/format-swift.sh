#!/bin/sh
# Formats and lint-fixes a Swift file the moment an agent edits it, so formatting never shows
# up in a diff and CI never fails on style. Measured at well under a second per file.
#
# Claude Code passes the tool payload as JSON on stdin.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

file=$(python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))
except Exception:
    print("")
')

case "$file" in
    *.swift) ;;
    *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

cd "$ROOT"
command -v swiftformat > /dev/null && swiftformat --quiet "$file" || true

# SwiftLint exit codes: 0 clean, 2 violations remain, anything else is a tooling problem
# (1 = nothing lintable, 133 = toolchain crash) and must not block the agent.
# --force-exclude honors the config's excluded paths even when a file is passed explicitly.
if command -v swiftlint > /dev/null; then
    set +e
    output=$(swiftlint lint --fix --quiet --force-exclude "$file" 2>&1)
    swiftlint lint --strict --quiet --force-exclude "$file" > /dev/null 2>&1
    code=$?
    set -e
    if [ "$code" -eq 2 ]; then
        swiftlint lint --strict --quiet --force-exclude "$file" >&2 || true
        # Exit 2 surfaces the remaining violations to the agent as something to fix now.
        exit 2
    fi
fi

exit 0
