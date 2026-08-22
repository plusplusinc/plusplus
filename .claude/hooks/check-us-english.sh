#!/bin/sh
# Flags British spellings in a file the moment it is edited, so they never reach
# a commit or a CI failure. Shares its wordlist with scripts/check-us-english.sh,
# which is what CI runs — there is one list, not two that drift.
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

[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0

case "$file" in
    *.swift | *.md | *.yml | *.yaml | *.json | *.xcconfig | *.sh | *.plist) ;;
    *) exit 0 ;;
esac

if ! output=$("$ROOT/scripts/check-us-english.sh" "$file" 2>&1); then
    printf '%s\n' "$output" >&2
    # Exit 2 surfaces this back to the agent as something to fix.
    exit 2
fi

exit 0
