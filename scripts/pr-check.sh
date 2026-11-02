#!/bin/bash
# The "PR check" job's logic (.github/workflows/pr-check.yml), runnable locally against any PR or
# commit. docs/pr-check.md explains the check.
#
#   scripts/pr-check.sh route <pr>           # docs, or xcode-cloud for a PR that changes the app
#   scripts/pr-check.sh lint <pr>            # the docs-only path: scripts/lint.sh on its files
#   scripts/pr-check.sh wait <sha> [minutes] # Xcode Cloud's result on a commit; default 40 min
#   scripts/pr-check.sh files <pr>           # the PR's changed paths, renames' old paths too
#   scripts/pr-check.sh classify < paths     # "docs", or "app: <first path that is app code>"
#   scripts/pr-check.sh xcode-cloud          # .github/no-code-paths as Xcode Cloud's rule, JSON
#   scripts/pr-check.sh reverts <base> <head> # fails if head's diff undoes a recent commit on base
#
# Needs `gh` signed in (GH_TOKEN in CI). Polls about once a minute. Run it inside a checkout.
# It reads the no-code list from PR_CHECK_BASE (default origin/main), never the working tree,
# so a PR cannot widen the list it is checked against; CI runs main's copy of this script too.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
BASE=${PR_CHECK_BASE:-origin/main}
LIST=".github/no-code-paths"
# They decide the check, so a PR that changes them waits for Xcode Cloud, whatever the list says.
GATE_PATTERN='^(\.github/no-code-paths|scripts/pr-check\.sh|\.github/workflows/.*)$'
# The commit status Xcode Cloud's PR workflow posts; its actions post check runs besides.
XCODE_CLOUD_STATUS="PlusPlus Workout Tracker | PR"
POLL_SECONDS=${PR_CHECK_POLL_SECONDS:-60}
# Below the workflow's timeout-minutes, so the check fails with a message rather than a kill.
MINUTES=40
# Xcode Cloud posts a pending status within a minute of the PR event; none by then means no run.
START_MINUTES=10

usage() {
    sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 2
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
    local path
    ENTRIES=()
    while IFS= read -r path; do ENTRIES+=("$path"); done < <(entries)
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [[ "$path" =~ $GATE_PATTERN ]] || ! is_no_code "$path"; then
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

# Fails when the diff from base and head's merge base to head undoes, in some file, every line one
# of the merge base's last REVERT_WINDOW commits changed there: a line it added is gone, a line it
# removed is back, a binary file is back to the copy before it. A squash onto a newer main with
# `git reset --soft origin/main` does that, recording the branch's stale copies of whatever main
# changed meanwhile (#136 undid #134 so). A revert made with `git revert`, whose message says
# "This reverts commit <sha>" (a short sha too), is meant, and passes.
REVERT_WINDOW=30
reverts() {
    git -C "$ROOT" rev-parse --quiet --verify "$1^{commit}" > /dev/null &&
        git -C "$ROOT" rev-parse --quiet --verify "$2^{commit}" > /dev/null ||
        fail "reverts needs commits $1 and $2 here, with their history: fetch them"
    local found
    found=$(cd "$ROOT" && python3 -I - "$1" "$2" "$REVERT_WINDOW" <<'PY'
import collections, re, subprocess, sys

base, head, window = sys.argv[1:]

def git(*args):
    return subprocess.run(["git", *args], capture_output=True, check=True).stdout

def blob(commit, path):
    found = subprocess.run(["git", "rev-parse", "--quiet", "--verify", f"{commit}:{path}"],
                           capture_output=True)
    return found.stdout.strip() or None

def lines(sha):
    if sha is None:
        return collections.Counter()
    return collections.Counter(line for line in git("cat-file", "blob", sha).splitlines()
                               if line.strip())

def sign(n):
    return (n > 0) - (n < 0)

def undone(path, parent, commit, merge_base, binary):
    before, after, now, then = (blob(c, path) for c in (parent, commit, head, merge_base))
    if binary:
        return now == before and then != before
    before, after, now, then = map(lines, (before, after, now, then))
    standing = [line for line in before.keys() | after.keys()
                if after[line] != before[line] and sign(then[line] - before[line]) == sign(after[line] - before[line])]
    return bool(standing) and all((now[line] - before[line]) * sign(after[line] - before[line]) <= 0
                                  for line in standing)

merge_base = git("merge-base", base, head).decode().strip()
changed = set(git("diff", "--name-only", "-z", "--no-renames", merge_base, head).split(b"\0")) - {b""}
messages = git("log", "--format=%B", f"{merge_base}..{head}").decode()
meant = re.findall(r"This reverts commit ([0-9a-f]{7,40})", messages)
for commit in git("rev-list", "--first-parent", "-n", window, merge_base).decode().split():
    parents = git("rev-list", "--parents", "-n", "1", commit).decode().split()[1:]
    if not parents or any(commit.startswith(sha) for sha in meant):
        continue
    stat = git("diff", "--numstat", "-z", "--no-renames", parents[0], commit).split(b"\0")
    paths = []
    for entry in stat:
        if not entry:
            continue
        added, _, path = entry.split(b"\t", 2)
        if path in changed and undone(path.decode(), parents[0], commit, merge_base, added == b"-"):
            paths.append(path.decode())
    if paths:
        subject = git("log", "-1", "--format=%h %s", commit).decode().strip()
        listed = ", ".join(paths[:5]) + (f", and {len(paths) - 5} more" if len(paths) > 5 else "")
        print(f"{subject}: undone in {listed}")
PY
    )
    if [ -n "$found" ]; then
        echo "$found" >&2
        fail "this diff undoes what the commits above added to main. A squash onto a newer main \
(git reset --soft origin/main) does that: merge origin/main into the branch instead, and squash, \
if at all, onto git merge-base HEAD origin/main (/pr). A revert that is meant is made with git \
revert, whose \"This reverts commit <sha>\" line passes this check."
    fi
    echo "reverts nothing main added in its last $REVERT_WINDOW commits"
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
        echo "changes the app (${verdict#app: }), so Xcode Cloud's result decides" >&2
        echo xcode-cloud
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

case "${1:-}" in
    route) [ "$#" -eq 2 ] || usage; route "$2" ;;
    lint) [ "$#" -eq 2 ] || usage; lint "$2" ;;
    files) [ "$#" -eq 2 ] || usage; files "$2" ;;
    classify) require_base; classify ;;
    wait) [ "$#" -ge 2 ] || usage; wait_for "$2" "${3:-}" ;;
    xcode-cloud) require_base; xcode_cloud_rule ;;
    reverts) [ "$#" -eq 3 ] || usage; reverts "$2" "$3" ;;
    *) usage ;;
esac
