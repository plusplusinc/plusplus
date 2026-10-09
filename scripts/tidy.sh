#!/bin/bash
# Removes finished work from this clone: linked worktrees and local branches whose work already
# landed. Runs in the background at the start of every session in the main checkout, and by hand.
#
# Finished means the branch tip is in origin/main, or is the head (or an ancestor of the head) of
# a merged PR. Merges are squashed, so a merged branch's own commits never reach main and git
# alone cannot tell it is done; the PR can. Kept: a worktree with uncommitted changes, a branch
# with commits no merged PR contains, and a worktree touched in the last day whose branch has no
# merged PR (an agent's fresh worktree starts at main with nothing committed yet). Closed but
# unmerged PRs are never cleaned up; their work may still be wanted.
#
#   scripts/tidy.sh            # remove, and print each thing removed
#   scripts/tidy.sh --dry-run  # print what would be removed
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
# Only the main checkout tidies. A linked worktree, whose .git is a file, may be the thing to remove.
[ -d .git ] || exit 0

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
FRESH_SECONDS=$((24 * 60 * 60))

git fetch --quiet --prune origin
# "<branch> <head sha> <number>" for every merged PR.
MERGED=$(gh pr list --state merged --limit 500 --json headRefName,headRefOid,number \
    --jq '.[] | "\(.headRefName) \(.headRefOid) \(.number)"')

run() {
    echo "tidy: $*"
    [ "$DRY_RUN" -eq 1 ] || "$@" > /dev/null
}

# Whether a merged PR contains this tip. Fetches the PR's head when the commit is not local.
in_merged_pr() {
    local branch="$1" tip="$2" name head number
    while read -r name head number; do
        [ "$name" = "$branch" ] || continue
        [ "$tip" = "$head" ] && return 0
        git cat-file -e "$head^{commit}" 2> /dev/null ||
            git fetch --quiet origin "pull/$number/head" 2> /dev/null || continue
        git merge-base --is-ancestor "$tip" "$head" && return 0
    done <<< "$MERGED"
    return 1
}

in_main() {
    git merge-base --is-ancestor "$1" origin/main
}

# Seconds since anything in a worktree's git state changed (index, HEAD, a commit).
idle_seconds() {
    local git_dir newest
    git_dir=$(git -C "$1" rev-parse --absolute-git-dir)
    newest=$(stat -f %m "$git_dir/HEAD" "$git_dir/index" "$git_dir/logs/HEAD" 2> /dev/null | sort -n | tail -1)
    echo $(($(date +%s) - ${newest:-0}))
}

# Worktrees first: a branch cannot be deleted while one has it checked out.
freed=()
while IFS=$'\t' read -r path branch; do
    [ "$path" = "$ROOT" ] && continue
    [ -z "$(git -C "$path" status --porcelain)" ] || continue
    tip=$(git -C "$path" rev-parse HEAD)
    if { [ -n "$branch" ] && in_merged_pr "$branch" "$tip"; } ||
        { in_main "$tip" && [ "$(idle_seconds "$path")" -gt "$FRESH_SECONDS" ]; }; then
        run git worktree remove "$path"
        freed+=("$branch")
    fi
done < <(git worktree list --porcelain |
    awk '/^worktree /{path=substr($0,10)} /^branch /{print path "\t" substr($0,19)} /^detached/{print path "\t"}')

checked_out=$(git worktree list --porcelain | awk '/^branch /{print substr($0,19)}')
while read -r branch; do
    [ "$branch" = main ] && continue
    if grep -qxF "$branch" <<< "$checked_out" &&
        ! printf '%s\n' "${freed[@]+"${freed[@]}"}" | grep -qxF "$branch"; then
        continue
    fi
    tip=$(git rev-parse "refs/heads/$branch")
    if in_main "$tip" || in_merged_pr "$branch" "$tip"; then
        run git branch -D "$branch"
    fi
done < <(git for-each-ref --format='%(refname:short)' refs/heads)
