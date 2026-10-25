#!/bin/bash
# The "PR check" job's logic (.github/workflows/pr-check.yml), runnable locally against any PR or
# commit. docs/pr-check.md explains the check.
#
#   scripts/pr-check.sh run <pr> <sha>       # what CI runs: lint a docs-only PR, else wait
#   scripts/pr-check.sh files <pr>           # the PR's changed paths, renames' old paths too
#   scripts/pr-check.sh classify < paths     # "docs", or "app: <first path that is app code>"
#   scripts/pr-check.sh wait <sha> [minutes] # Xcode Cloud's result on a commit; default 40 min
#   scripts/pr-check.sh xcode-cloud          # .github/no-code-paths as Xcode Cloud's rule, JSON
#
# Needs `gh` signed in (GH_TOKEN in CI). Polls about once a minute.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LIST="$ROOT/.github/no-code-paths"
# The commit status Xcode Cloud's PR workflow posts; its actions post check runs besides.
XCODE_CLOUD_STATUS="PlusPlus Workout Tracker | PR"
POLL_SECONDS=${PR_CHECK_POLL_SECONDS:-60}

usage() {
    sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

repo() {
    echo "${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
}

# Prints a message as an error annotation in Actions, plainly elsewhere.
fail() {
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "::error title=PR check::$1"
    else
        echo "$1" >&2
    fi
    exit 1
}

entries() {
    grep -v -e '^#' -e '^[[:space:]]*$' "$LIST"
}

# True when a path matches an entry, with Xcode Cloud's meaning (see the list's header).
is_no_code() {
    local path=$1 entry
    while IFS= read -r entry; do
        case "$entry" in
            */) [[ "$path" == "$entry"* ]] && return 0 ;;
            */*) [[ "$path" == "$entry" ]] && return 0 ;;
            *) [[ "$(basename "$path")" == "$entry" ]] && return 0 ;;
        esac
    done < <(entries)
    return 1
}

files() {
    gh api --paginate "repos/$(repo)/pulls/$1/files" \
        --jq '.[] | .filename, (.previous_filename // empty)'
}

classify() {
    local path
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        is_no_code "$path" || { echo "app: $path"; return; }
    done
    echo docs
}

xcode_cloud_status() {
    gh api "repos/$(repo)/commits/$1/status" --jq \
        ".statuses[] | select(.context == \"$XCODE_CLOUD_STATUS\") | [.state, .description, .target_url] | @tsv"
}

xcode_cloud_actions() {
    gh api "repos/$(repo)/commits/$1/check-runs" --jq \
        '.check_runs[] | select(.app.slug == "xcode-cloud") | "\(.name): \(.output.title // .conclusion)"'
}

wait_for() {
    local sha=$1 minutes=${2:-40} state="" description="" url="" line
    local deadline=$((SECONDS + minutes * 60))
    echo "waiting for \"$XCODE_CLOUD_STATUS\" on $sha"
    while :; do
        line=$(xcode_cloud_status "$sha")
        if [ -n "$line" ]; then
            IFS=$'\t' read -r state description url <<< "$line"
            [ "$state" = pending ] || break
        fi
        [ "$SECONDS" -lt "$deadline" ] || fail "No result from Xcode Cloud on $sha after $minutes min \
(${state:-no status yet}). If it never started, the PR changed only paths Xcode Cloud's start \
condition skips but .github/no-code-paths does not list: compare the two (docs/pr-check.md)."
        sleep "$POLL_SECONDS"
    done

    local actions
    actions=$(xcode_cloud_actions "$sha")
    [ -n "$actions" ] && echo "$actions"
    case "$state" in
        success) echo "Xcode Cloud passed: $url" ;;
        *)
            if [ "$description" = cancelled ] && [ -z "$actions" ]; then
                fail "Xcode Cloud cancelled the run before any action started, which usually means \
this month's Xcode Cloud compute hours are spent (App Store Connect, Xcode Cloud, Usage). Once \
they are back, start the run again and re-run this check. $url"
            fi
            fail "Xcode Cloud ${description:-$state}: $url"
            ;;
    esac
}

run() {
    local pr=$1 sha=$2 paths verdict
    paths=$(files "$pr")
    verdict=$(classify <<< "$paths")
    if [ "$verdict" = docs ]; then
        echo "docs-only: every changed path is in .github/no-code-paths, so Xcode Cloud skips it"
        local existing=()
        while IFS= read -r path; do
            [ -f "$ROOT/$path" ] && existing+=("$path")
        done <<< "$paths"
        if [ "${#existing[@]}" -eq 0 ]; then
            echo "nothing left to lint: the PR only deletes files"
            return
        fi
        cd "$ROOT"
        scripts/lint.sh "${existing[@]}"
    else
        echo "changes the app (${verdict#app: }), so Xcode Cloud's result decides"
        wait_for "$sha" "${PR_CHECK_MINUTES:-40}"
    fi
}

xcode_cloud_rule() {
    entries | python3 -I -c '
import json, sys
matchers = []
for entry in sys.stdin.read().split():
    if entry.endswith("/"):
        matchers.append({"directory": entry.rstrip("/")})
    elif "/" in entry:
        folder, name = entry.rsplit("/", 1)
        matchers.append({"directory": folder, "fileName": name})
    else:
        matchers.append({"fileName": entry})
print(json.dumps({"mode": "DO_NOT_START_IF_ALL_FILES_MATCH", "matchers": matchers}, indent=2))
'
}

case "${1:-}" in
    run) [ "$#" -eq 3 ] || usage; run "$2" "$3" ;;
    files) [ "$#" -eq 2 ] || usage; files "$2" ;;
    classify) classify ;;
    wait) [ "$#" -ge 2 ] || usage; wait_for "$2" "${3:-40}" ;;
    xcode-cloud) xcode_cloud_rule ;;
    *) usage ;;
esac
