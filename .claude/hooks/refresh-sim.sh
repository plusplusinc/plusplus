#!/bin/bash
# Keeps the app on the simulator matching the checkout. Runs in the background after every edit
# an agent makes and again when its turn ends: if the app's code differs from what is installed
# (an edit, a branch switch, a pull), rebuild, reinstall, and relaunch. A no-op otherwise.
#
# When InjectionNext is linked (Config/Local.xcconfig) and the app this script launched is still
# running, edits that only change code inside existing Swift files are hot-reloaded by the app
# itself, so this leaves the app alone and keeps its state. Anything injection cannot apply (a new
# or deleted file, a stored property or enum case, a resource, settings, another commit) still
# rebuilds and relaunches. Known gaps: members of nested types are not checked, and the first
# save or two after a launch only warm InjectionNext up; `scripts/run.sh` relaunches by hand.
#
# At the end of a turn it also reports app crashes since the last turn, once each.
#
#   refresh-sim.sh          # after an edit: a failed build is expected mid-change, stay quiet
#   refresh-sim.sh --report # end of turn: exit 2 so a failed build or a crash wakes the agent
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STAMP="$ROOT/.build/installed-source.tree"
LAUNCHED="$ROOT/.build/launched-app.pid"
BUILT="$ROOT/.build/built-source.tree"
LOCK="$ROOT/.build/installed-source.lock"
LOG="$ROOT/.build/installed-source.log"
CRASH_MARK="$ROOT/.build/crashes-reported"
SOURCES=(App Packages Config PlusPlus.xcodeproj)

# Only the main checkout drives the maintainer's simulator. A linked worktree is an agent's, and
# an agent runs its build on its own simulator by hand, so here the hook does nothing.
[ "$(git -C "$ROOT" rev-parse --absolute-git-dir)" \
    = "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)" ] || exit 0

# One refresh at a time. lockf holds a kernel lock that dies with the process, so a refresh
# killed mid-build (by the hook timeout, or the session ending) cannot leave a stale lock behind.
# Whoever holds it keeps going until the code stops changing, so an edit that lands mid-build is
# picked up by the loop below instead of a second build. The end-of-turn report waits its turn
# instead: the refresh it would defer to stays quiet about a failed build.
if [ -z "${REFRESH_SIM_LOCKED:-}" ]; then
    mkdir -p "$ROOT/.build"
    wait=0
    [ "${1:-}" = "--report" ] && wait=600
    status=0
    REFRESH_SIM_LOCKED=1 lockf -s -t "$wait" "$LOCK" "$0" "$@" || status=$?
    # 75 is lockf's "already locked": another refresh is running and will pick this change up.
    [ "$status" -eq 75 ] && exit 0
    exit "$status"
fi

source "$ROOT/scripts/common.sh"
REPORT=""
[ "${1:-}" = "--report" ] && REPORT=1

# The app's sources as a git tree, untracked files included, so two states can be diffed. The
# temporary index starts as a copy of the real one, so git rehashes only files that changed.
source_tree() {
    local index
    index=$(mktemp)
    cp "$(git -C "$ROOT" rev-parse --absolute-git-dir)/index" "$index"
    (
        cd "$ROOT"
        export GIT_INDEX_FILE="$index"
        git add -A -- "${SOURCES[@]}"
        git write-tree
    )
    rm -f "$index"
}

# The app's process id on the simulator, empty when it is not running. Output is captured before
# it is searched: under pipefail, a reader exiting early fails the pipeline with SIGPIPE.
app_pid() {
    local bundle_id running
    bundle_id=$(app_bundle_id 2> /dev/null) || return 0
    running=$(xcrun simctl spawn "$SIMULATOR_NAME" launchctl list 2> /dev/null) || return 0
    awk -v label="UIKitApplication:$bundle_id" 'index($3, label) == 1 { print $1 }' <<< "$running"
}

# True when the running app can take the change from the installed tree to $2 as a hot reload:
# every change edits an existing Swift file, no changed line declares a type-level `let`, `var`,
# or `case` (that changes the type's layout, and injecting it corrupts live instances),
# InjectionNext is linked, and the app is still the process this script launched, so the hot
# reloads since then are in it. Cheapest checks first.
injectable() {
    local installed=$1 current=$2 diff pid
    diff=$(git -C "$ROOT" diff-tree -r --raw -p -U0 "$installed" "$current")
    awk '/^:/ && ($5 != "M" || $6 !~ /^(App|Packages\/Sources)\/.*\.swift$/) { bad = 1 }
        END { exit bad }' <<< "$diff" || return 1
    ! grep -Eq '^[-+]    (@[A-Za-z]+(\([^)]*\))? )*([a-z]+(\([a-z]+\))? )*(let|var|case) ' \
        <<< "$diff" || return 1
    grep -q -- "-interposable" "$ROOT/Config/Local.xcconfig" 2> /dev/null || return 1
    pid=$(app_pid)
    [ -n "$pid" ] && [ "$pid" = "$(cat "$LAUNCHED" 2> /dev/null || true)" ]
}

crashes=""
report_crashes() {
    [ -z "$crashes" ] && return 0
    echo "The app crashed since the last turn:" >&2
    echo "$crashes" >&2
}

build_failed() {
    echo "The app no longer builds; the simulator still runs the last code that did." >&2
    tail -n 20 "$LOG" >&2
    report_crashes
    exit 2
}

if [ -n "$REPORT" ] && bundle_id=$(app_bundle_id 2> /dev/null); then
    # Reported once: the mark moves forward on every check that could read the reports. The
    # first check only sets the mark.
    next_mark=$(mktemp)
    if [ -f "$CRASH_MARK" ]; then
        crashes=$(find "$HOME/Library/Logs/DiagnosticReports" -name '*.ips' -newer "$CRASH_MARK" \
            -print0 2> /dev/null \
            | xargs -0 python3 "$ROOT/.claude/hooks/crash-summary.py" "$bundle_id" || true)
    fi
    mv "$next_mark" "$CRASH_MARK"
fi

while current=$(source_tree) && installed=$(cat "$STAMP" 2> /dev/null || true) \
    && [ "$current" != "$installed" ]; do
    if [ -n "$installed" ] && injectable "$installed" "$current"; then
        # The app hot-reloads these itself. The stamp stays at what is installed, so the next
        # change injection cannot apply still rebuilds everything since then. At the end of a
        # turn, compile once per tree: a hot reload that fails to compile only logs in the app.
        if [ -n "$REPORT" ] && [ "$current" != "$(cat "$BUILT" 2> /dev/null || true)" ]; then
            "$ROOT/scripts/build.sh" > "$LOG" 2>&1 || build_failed
            echo "$current" > "$BUILT"
        fi
        break
    fi
    if "$ROOT/scripts/run.sh" > "$LOG" 2>&1; then
        echo "$current" > "$STAMP"
        app_pid > "$LAUNCHED"
    elif [ -n "$REPORT" ]; then
        build_failed
    else
        exit 0
    fi
done

if [ -n "$crashes" ]; then
    report_crashes
    exit 2
fi
