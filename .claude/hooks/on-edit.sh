#!/bin/sh
# Runs after every file an agent edits: format, lint-fix, and spell-check that one file with
# the same script CI uses, so nothing the hook accepts can fail later. Remaining findings are
# returned to the agent to fix now (exit 2). Well under a second per file.
#
# Claude Code passes the tool payload as JSON on stdin.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
file=$(jq -r '.tool_input.file_path // empty' 2> /dev/null || true)
[ -n "$file" ] && [ -f "$file" ] || exit 0

if ! output=$("$ROOT/scripts/lint.sh" --fix "$file" 2>&1); then
    printf '%s\n' "$output" >&2
    exit 2
fi
