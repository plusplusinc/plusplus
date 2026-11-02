#!/bin/bash
# Removes finished work from this clone: linked worktrees and local branches whose work already
# landed. Runs in the background at the start of every session in the main checkout, and by hand.
#
# Finished means the branch tip is in origin/main, or is the head (or an ancestor of the head) of
# a merged PR, or every one of its commits' patches is in a merged PR's head (the PR was rebased
# on GitHub). Merges are squashed, so a merged branch's own commits never reach main and git
# alone cannot tell it is done; the PR can. Kept: a worktree with uncommitted changes, a branch
# with commits no merged PR contains, and a worktree touched in the last day whose branch has no
# merged PR (an agent's fresh worktree starts at main with nothing committed yet). Closed but
# unmerged PRs are never cleaned up; their work may still be wanted. A removed worktree's own
# simulator, "PlusPlus <worktree>" (see scripts/common.sh), is shut down and deleted with it, and
# so is the recorded simulator of a worktree removed by hand; this is the only script that deletes
# a simulator. A worktree simulator booted but unused for 30 minutes (PLUSPLUS_SIM_IDLE_MINUTES)
# is shut down, not deleted. A file or folder in .slices/ goes too once every board card it names
# (by item id, PVTI_...) is Done, unless it is named after a live worktree or branch; one that names none, or a
# card the board doesn't have, is kept. Last, it keeps the simulator runtimes on the newest iOS,
# Xcode's SDK: it downloads that runtime when missing, then deletes older ones (see the end).
#
#   scripts/tidy.sh            # remove, and print each thing removed
#   scripts/tidy.sh --dry-run  # print what would be removed
set -euo pipefail

DRY_RUN=0
case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    *)
        echo "usage: scripts/tidy.sh [--dry-run]" >&2
        exit 64
        ;;
esac

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
# Only the main checkout tidies. A linked worktree, whose .git is a file, may be the thing to remove,
# so from one this does nothing and says where to run it.
if [ ! -d .git ]; then
    main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
    echo "tidy: nothing tidied from a worktree; run $main/scripts/tidy.sh" >&2
    exit 0
fi
source "$ROOT/scripts/common.sh"

FRESH_SECONDS=$((24 * 60 * 60))

git fetch --quiet --prune origin
# "<branch> <head sha> <number>" for every merged PR.
MERGED=$(gh pr list --state merged --limit 500 --json headRefName,headRefOid,number \
    --jq '.[] | "\(.headRefName) \(.headRefOid) \(.number)"')

run() {
    echo "tidy: $*"
    [ "$DRY_RUN" -eq 1 ] || "$@" > /dev/null
}

# Shuts down and deletes a worktree's own simulator, when it has one. Fails only when it could not
# delete one.
delete_simulator() {
    local name udid state
    name=$(worktree_simulator "$1")
    read -r udid state < <(simulator_udid "$name") || return 0
    echo "tidy: delete simulator \"$name\""
    [ "$DRY_RUN" -eq 1 ] && return 0
    # The worktree is already gone, so a failure here says so and lets the rest of the run go on.
    if ! { [ "$state" != Booted ] || xcrun simctl shutdown "$udid"; } || ! xcrun simctl delete "$udid"; then
        echo "tidy: could not delete simulator \"$name\" ($udid); agents are denied simctl delete, so ask the maintainer to delete it" >&2
        return 1
    fi
}

# Whether a merged PR contains this tip. Fetches the PR's head when the commit is not local.
in_merged_pr() {
    local branch="$1" tip="$2" name head number base own
    while read -r name head number; do
        [ "$name" = "$branch" ] || continue
        [ "$tip" = "$head" ] && return 0
        git cat-file -e "$head^{commit}" 2> /dev/null ||
            git fetch --quiet origin "pull/$number/head" 2> /dev/null || continue
        git merge-base --is-ancestor "$tip" "$head" && return 0
        # `gh pr update-branch --rebase` rewrites a PR's commits, so a worktree's older tip is no
        # ancestor of the merged head; it is still merged when each of its commits has its patch
        # there. A failed git command, or a tip with no commits of its own, never counts.
        base=$(git merge-base "$tip" origin/main) || continue
        own=$(git cherry "$head" "$tip" "$base") || continue
        [ -n "$own" ] && ! grep -q '^+' <<< "$own" && return 0
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
        delete_simulator "$path" || true
        freed+=("$branch")
    elif prs=$(awk -v b="$branch" '$1 == b { print "#" $3 }' <<< "$MERGED" | paste -sd, -) &&
        [ -n "$prs" ]; then
        # A conflict resolved while GitHub rebased the PR changes a patch, so nothing here can
        # prove the work landed. Say so rather than keep it silently.
        echo "tidy: kept $path: $prs merged, but its head lacks a patch from here;" \
            "compare them, then remove it by hand"
    fi
done < <(git worktree list --porcelain |
    awk '/^worktree /{path=substr($0,10)} /^branch /{print path "\t" substr($0,19)} /^detached/{print path "\t"}')

# A worktree removed with `git worktree remove`, such as one of main added to compare with, leaves
# its simulator. scripts/common.sh records each worktree simulator it uses; delete the recorded
# ones whose worktree is gone, and drop their records.
RECORDS="$ROOT/.git/plusplus-simulators"
if [ -d "$RECORDS" ]; then
    live=$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' |
        while read -r path; do basename "$path"; done)
    for record in "$RECORDS"/*; do
        [ -e "$record" ] || continue
        name=$(basename "$record")
        grep -qxF "$name" <<< "$live" && continue
        if delete_simulator "$name" && [ "$DRY_RUN" -eq 0 ]; then
            rm "$record"
        fi
    done
fi

# A worktree simulator left booted and idle by an agent that ended without shutting it down.
while IFS=$'\t' read -r name udid; do
    echo "tidy: shut down simulator \"$name\", idle over $((IDLE_SHUTDOWN_SECONDS / 60))m"
    [ "$DRY_RUN" -eq 1 ] || xcrun simctl shutdown "$udid" || true
done < <(idle_worktree_simulators)

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

# .slices/ entries of finished cards. One named after a live worktree or local branch (`<name>`,
# `<name>-plan.md`, `<name>.json`), or touched in the last day, is work still going and stays,
# whatever cards it cites. Any other goes once every card it names is Done, read in one `board.sh list` request, made only when
# such an entry names a card. One naming a card the board doesn't have stays, and says so.
SLICES="$ROOT/.slices"
if [ -d "$SLICES" ]; then
    live=$({
        git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' |
            while read -r path; do basename "$path"; done
        git for-each-ref --format='%(refname:short)' refs/heads
    } | sort -u)
    candidates=()
    for entry in "$SLICES"/* "$SLICES"/.[!.]*; do
        [ -e "$entry" ] || continue
        name=$(basename "$entry")
        owned=false
        while read -r prefix; do
            case "$name" in "$prefix" | "$prefix"-* | "$prefix".*) owned=true && break ;; esac
        done <<< "$live"
        [ -n "$(find "$entry" -newermt "-$FRESH_SECONDS seconds" -print -quit)" ] && owned=true
        $owned || candidates+=("$entry")
    done
    if [ "${#candidates[@]}" -gt 0 ] && grep -rqE 'PVTI_' "${candidates[@]}" 2> /dev/null; then
        if rows=$("$ROOT/scripts/board.sh" list 2>&1); then
            # A row is "<id>  <status>\t<feature>\t<title>".
            known=$(awk '{ print $1 }' <<< "$rows" | sort -u)
            done_ids=$(awk -F'\t' '$1 ~ /  Done$/ { split($1, f, " "); print f[1] }' <<< "$rows" | sort -u)
            for entry in "${candidates[@]}"; do
                named=$(grep -rhoE 'PVTI_[A-Za-z0-9_-]+' "$entry" 2> /dev/null | sort -u || true)
                [ -n "$named" ] || continue
                unknown=$(comm -23 <(echo "$named") <(echo "$known") | paste -sd, -)
                if [ -n "$unknown" ]; then
                    echo "tidy: kept $entry: it names $unknown, which the board doesn't have"
                elif [ -z "$(comm -23 <(echo "$named") <(echo "$done_ids"))" ]; then
                    run rm -r "$entry"
                fi
            done
        else
            # A spent quota, or any other board error, leaves everything in place.
            echo "tidy: kept .slices/: reading the board failed: $(tail -1 <<< "$rows")"
        fi
    fi
fi

# Simulator runtimes: the newest iOS is the one Xcode's SDK targets. When no runtime of it runs
# the iPhone 17 the scripts use (a runtime can carry only a new device), download Xcode's (several
# GB); once one does, delete every older iOS runtime and the simulators left without one, so old
# runtimes never fill the disk. To test an older iOS on purpose, download it by hand; the next
# session's tidy deletes it again.
sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)
# "ready" or "missing", then "<image id> <version>" for each older iOS runtime.
plan=$(python3 -I -c '
import json, subprocess, sys
def simctl(*args):
    return json.loads(subprocess.run(["xcrun", "simctl", *args], capture_output=True, check=True).stdout)
version = lambda v: [int(p) for p in v.split(".")][:2]
sdk = version(sys.argv[1])
iphone = "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
runs = any(r["platform"] == "iOS" and r["isAvailable"] and version(r["version"]) == sdk
           and any(t["identifier"] == iphone for t in r["supportedDeviceTypes"])
           for r in simctl("list", "--json", "runtimes")["runtimes"])
print("ready" if runs else "missing")
for image in simctl("runtime", "list", "-j").values():
    if image["platformIdentifier"] == "com.apple.platform.iphonesimulator" and version(image["version"]) < sdk:
        print(image["identifier"], image["version"])
' "$sdk")
read -r current <<< "$plan"
if [ "$current" = missing ]; then
    echo "tidy: download the iOS $sdk simulator runtime, logging to .build/runtime-download.log"
    # The session hook stops tidy after two minutes, so the download runs in a session of its
    # own, which outlives it. lockf skips it while another is running; its lock dies with it.
    [ "$DRY_RUN" -eq 1 ] || python3 -I -c '
import subprocess, sys
log = open(sys.argv[1], "a")
subprocess.Popen(sys.argv[2:], start_new_session=True, stdin=subprocess.DEVNULL, stdout=log, stderr=log)
' "$ROOT/.build/runtime-download.log" lockf -t 0 "$ROOT/.build/runtime-download.lock" \
        xcodebuild -downloadPlatform iOS
else
    while read -r id version; do
        [ -n "$id" ] || continue
        echo "tidy: delete the iOS $version simulator runtime"
        [ "$DRY_RUN" -eq 1 ] || xcrun simctl runtime delete "$id" || true
    done < <(tail -n +2 <<< "$plan")
    run xcrun simctl delete unavailable
fi
