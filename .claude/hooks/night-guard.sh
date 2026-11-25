#!/bin/sh
# The night's guard, a PreToolUse hook every session's calls pass through. .claude/settings.json
# runs the main checkout's copy from any worktree (scripts/nightly-tooling.py's HOOK_COMMAND),
# found from the session folder's path alone, and this copy runs the main checkout's script. It hands
# `nightly-tooling.py hook` only a call whose input holds the id of a night's session, which
# `nightly-tooling.py begin` writes to that night's folder, .build/retro/<date>/session in the main
# checkout; every other call leaves here with exit 0 and no output, having started no Python. No
# git, no `set -e`, and no jq, so nothing here can fail a daytime session's call; it needs only
# /bin/sh and cat.

input=$(cat)
# This file is <main>/.claude/hooks/night-guard.sh.
main=$(cd "${0%/*}/../.." 2> /dev/null && pwd -P) || exit 0
night=""
# The folder whose session file names this call's session, not merely the newest folder.
for file in "$main"/.build/retro/20*/session; do
    [ -f "$file" ] || continue
    id=""
    IFS= read -r id < "$file"
    [ -n "$id" ] || continue
    case "$input" in
        *"$id"*) night=${file%/session} ;;
    esac
done
[ -n "$night" ] || exit 0
# A night's call: only the guard's own allow (exit 0) lets it run. Python that can't start
# exits 126 or 127, which Claude Code would treat as no objection, so anything but 0 denies.
printf '%s' "$input" | /usr/bin/env python3 "$main/scripts/nightly-tooling.py" hook "$night" || exit 2
