#!/bin/sh
# The night's guard, a PreToolUse hook every session's calls pass through. It hands
# `scripts/nightly-tooling.py hook` only a call whose input holds the id of the night's session,
# which `nightly-tooling.py begin` writes to the newest night's folder, .build/retro/<date>/session
# in the main checkout, whichever worktree the session runs in; every other call leaves here with
# exit 0 and no output, having started no Python. No `set -e` and no jq, so nothing here can fail a
# daytime session's call.

input=$(cat)
# The main checkout is the parent of git's common folder, from the main checkout or any worktree.
common=$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || exit 0
main=$(dirname "$common")
night=""
for folder in "$main"/.build/retro/20*/; do
    [ -d "$folder" ] && night=${folder%/}
done
[ -n "$night" ] && [ -f "$night/session" ] || exit 0
id=$(cat "$night/session")
[ -n "$id" ] || exit 0
case "$input" in
    *"$id"*) ;;
    *) exit 0 ;;
esac
# The night's call: only the guard's own allow (exit 0) lets it run. Python that can't start
# exits 126 or 127, which Claude Code would treat as no objection, so anything but 0 denies.
printf '%s' "$input" | /usr/bin/env python3 "$CLAUDE_PROJECT_DIR/scripts/nightly-tooling.py" hook "$night" || exit 2
