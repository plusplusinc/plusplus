#!/bin/sh
# Formats a Swift file immediately after it is edited, so formatting never shows up in a diff
# and `swift format lint --strict` in CI never fails on whitespace.
#
# Claude Code passes the tool payload as JSON on stdin.
set -eu

file=$(python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))
except Exception:
    print("")
')

case "$file" in
    *.swift) [ -f "$file" ] && swift format --in-place "$file" ;;
esac

exit 0
