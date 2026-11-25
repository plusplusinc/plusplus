#!/bin/sh
# The night's guard, a PreToolUse hook every session's calls pass through. It hands
# `scripts/nightly-tooling.py hook` only a call whose input holds the id of the night's session,
# which `nightly-tooling.py begin` writes to the newest night's folder, .build/retro/<date>/session;
# every other call leaves here with exit 0 and no output, having started no Python. A session in a
# worktree has no .build/retro/ and leaves at the folder; one in the main checkout, at the id.
# No `set -e` and no jq, so nothing here can fail a daytime session's call.

input=$(cat)
night=""
for folder in "$CLAUDE_PROJECT_DIR"/.build/retro/20*/; do
    [ -d "$folder" ] && night=${folder%/}
done
[ -n "$night" ] && [ -f "$night/session" ] || exit 0
id=$(cat "$night/session")
[ -n "$id" ] || exit 0
case "$input" in
    *"$id"*) ;;
    *) exit 0 ;;
esac
printf '%s' "$input" | exec /usr/bin/env python3 "$CLAUDE_PROJECT_DIR/scripts/nightly-tooling.py" hook "$night"
