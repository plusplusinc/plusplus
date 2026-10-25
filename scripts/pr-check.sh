#!/bin/bash
# The "PR check" job's logic (.github/workflows/pr-check.yml), runnable locally against any PR or
# commit. docs/pr-check.md explains the check.
#
#   scripts/pr-check.sh route <pr>           # docs, xcode-cloud, or github: where the PR is checked
#   scripts/pr-check.sh lint <pr>            # the docs-only path: scripts/lint.sh on its files
#   scripts/pr-check.sh wait <sha> [minutes] # Xcode Cloud's result on a commit; default 40 min
#   scripts/pr-check.sh files <pr>           # the PR's changed paths, renames' old paths too
#   scripts/pr-check.sh classify < paths     # "docs", or "app: <first path that is app code>"
#   scripts/pr-check.sh xcode-cloud          # .github/no-code-paths as Xcode Cloud's rule, JSON
#
# Needs `gh` signed in (GH_TOKEN in CI). Polls about once a minute. Run it inside a checkout.
# PR_TESTS_ON, the repository variable CI passes in, says where an app PR's tests run:
# xcode-cloud (also when unset) or github, GitHub's xcode-27 runner.
# It reads the no-code list from PR_CHECK_BASE (default origin/main), never the working tree,
# so a PR cannot widen the list it is checked against; CI runs main's copy of this script too.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
BASE=${PR_CHECK_BASE:-origin/main}
LIST=".github/no-code-paths"
# They decide the check, so a PR that changes them waits for Xcode Cloud, whatever the list says.
GATE_PATTERN='^(\.github/no-code-paths|scripts/pr-check\.sh|\.github/workflows/.*)$'
# The GitHub runner's tests run them, so with PR_TESTS_ON=github they count as app code too.
GITHUB_TEST_PATTERN='^(scripts/test\.sh|scripts/xcresult\.py)$'
# The commit status Xcode Cloud's PR workflow posts; its actions post check runs besides.
XCODE_CLOUD_STATUS="PlusPlus Workout Tracker | PR"
POLL_SECONDS=${PR_CHECK_POLL_SECONDS:-60}
# Below the workflow's timeout-minutes, so the check fails with a message rather than a kill.
MINUTES=40
# Xcode Cloud posts a pending status within a minute of the PR event; none by then means no run.
START_MINUTES=10

usage() {
    sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

# Where an app PR's tests run, from PR_TESTS_ON; unset means Xcode Cloud.
tests_on() {
    case "${PR_TESTS_ON:-xcode-cloud}" in
        xcode-cloud | github) echo "${PR_TESTS_ON:-xcode-cloud}" ;;
        *) fail "PR_TESTS_ON is \"$PR_TESTS_ON\"; set the repository variable to xcode-cloud or github" ;;
    esac
}

repo() {
    echo "${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
}

# Prints a message as an error annotation in Actions, plainly elsewhere. Always on stderr, which
# the runner reads commands from too, so a caller capturing stdout (route) still shows it.
fail() {
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "::error title=PR check::$1" >&2
    else
        echo "$1" >&2
    fi
    exit 1
}

require_base() {
    git -C "$ROOT" rev-parse --quiet --verify "$BASE^{commit}" > /dev/null ||
        fail "no commit $BASE here to read $LIST from: fetch it, or set PR_CHECK_BASE"
}

entries() {
    local list
    if list=$(git -C "$ROOT" show "$BASE:$LIST" 2> /dev/null); then
        :
    else
        # Only before the check first merges: main has no list yet.
        echo "no $LIST on $BASE; reading the working tree's" >&2
        list=$(cat "$ROOT/$LIST")
    fi
    grep -v -e '^#' -e '^[[:space:]]*$' <<< "$list"
}

# True when a path matches an entry, with Xcode Cloud's meaning (see the list's header).
is_no_code() {
    local path=$1 entry
    for entry in "${ENTRIES[@]}"; do
        case "$entry" in
            */) [[ "$path" == "$entry"* ]] && return 0 ;;
            */*) [[ "$path" == "$entry" ]] && return 0 ;;
            *) [[ "${path##*/}" == "$entry" ]] && return 0 ;;
        esac
    done
    return 1
}

files() {
    gh api --paginate "repos/$(repo)/pulls/$1/files" \
        --jq '.[] | .filename, (.previous_filename // empty)'
}

classify() {
    local path on
    on=$(tests_on)
    ENTRIES=()
    while IFS= read -r path; do ENTRIES+=("$path"); done < <(entries)
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [[ "$path" =~ $GATE_PATTERN ]] || ! is_no_code "$path" ||
            { [ "$on" = github ] && [[ "$path" =~ $GITHUB_TEST_PATTERN ]]; }; then
            echo "app: $path"
            return
        fi
    done
    echo docs
}

# state, description, and link, separated by \x1f, which unlike a tab keeps an empty field.
xcode_cloud_status() {
    gh api "repos/$(repo)/commits/$1/status" --jq \
        ".statuses[] | select(.context == \"$XCODE_CLOUD_STATUS\")
            | [.state, .description // \"\", .target_url // \"\"] | join(\"\\u001f\")"
}

xcode_cloud_actions() {
    gh api "repos/$(repo)/commits/$1/check-runs" --jq \
        '.check_runs[] | select(.app.slug == "xcode-cloud") | "\(.name): \(.output.title // .conclusion)"'
}

wait_for() {
    local sha=$1 minutes=${2:-$MINUTES} state="" description="" url="" line
    local deadline=$((SECONDS + minutes * 60)) start_deadline=$((SECONDS + START_MINUTES * 60))
    echo "waiting for \"$XCODE_CLOUD_STATUS\" on $sha"
    while :; do
        # A failed request is a poll with no answer, not a failed check.
        line=$(xcode_cloud_status "$sha") || line=""
        if [ -n "$line" ]; then
            IFS=$'\x1f' read -r state description url <<< "$line"
            [ "$state" = pending ] || break
        elif [ -z "$state" ] && [ "$SECONDS" -ge "$start_deadline" ]; then
            fail "Xcode Cloud has not started on $sha after $START_MINUTES min. Either GitHub's \
event never reached it (push an empty commit, as /pr says), or the PR changed only paths Xcode \
Cloud's start condition skips but .github/no-code-paths does not list (docs/pr-check.md)."
        fi
        [ "$SECONDS" -lt "$deadline" ] || fail "Xcode Cloud has not finished on $sha after \
$minutes min: $url"
        sleep "$POLL_SECONDS"
    done

    local actions
    actions=$(xcode_cloud_actions "$sha") || actions=
    [ -n "$actions" ] && echo "$actions"
    case "$state" in
        success) echo "Xcode Cloud passed: $url" ;;
        *)
            if [[ "$description" == [Cc]ancel* ]] && [ -z "$actions" ]; then
                fail "Xcode Cloud cancelled the run before any action started, which usually means \
this month's Xcode Cloud compute hours are spent (App Store Connect, Xcode Cloud, Usage). Once \
they are back, start the run again and re-run this check. $url"
            fi
            fail "Xcode Cloud ${description:-$state}: $url"
            ;;
    esac
}

route() {
    local paths verdict
    require_base
    # Not a pipe: classify stops at the first app path, which would end files with SIGPIPE.
    paths=$(files "$1")
    verdict=$(classify <<< "$paths")
    if [ "$verdict" = docs ]; then
        echo "docs-only: every changed path is in $BASE's $LIST" >&2
        echo docs
    else
        echo "changes the app (${verdict#app: }), so its tests run on $(tests_on)" >&2
        tests_on
    fi
}

lint() {
    local paths path existing=()
    paths=$(files "$1")
    while IFS= read -r path; do
        [ -f "$ROOT/$path" ] && existing+=("$path")
    done <<< "$paths"
    if [ "${#existing[@]}" -eq 0 ]; then
        echo "nothing left to lint: the PR only deletes files"
        return
    fi
    cd "$ROOT"
    scripts/lint.sh "${existing[@]}"
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

# Here, not only where it is read, since bash ignores a failure inside $(...).
tests_on > /dev/null

case "${1:-}" in
    route) [ "$#" -eq 2 ] || usage; route "$2" ;;
    lint) [ "$#" -eq 2 ] || usage; lint "$2" ;;
    files) [ "$#" -eq 2 ] || usage; files "$2" ;;
    classify) require_base; classify ;;
    wait) [ "$#" -ge 2 ] || usage; wait_for "$2" "${3:-}" ;;
    xcode-cloud) require_base; xcode_cloud_rule ;;
    *) usage ;;
esac
