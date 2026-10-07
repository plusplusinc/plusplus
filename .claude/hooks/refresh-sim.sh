#!/bin/bash
# Keeps the app on the simulator matching the checkout. Runs in the background after every edit
# an agent makes and again when its turn ends: if the app's code differs from what is installed
# (an edit, a branch switch, a pull), rebuild, reinstall, and relaunch. A no-op otherwise.
#
# When InjectionNext is linked (Config/Local.xcconfig) and the app is running, edits that only
# change code inside existing Swift files are hot-reloaded by the app itself, so this leaves the
# app alone and keeps its state. Anything injection cannot apply (a new or deleted file, a stored
# property, a resource, settings, another commit) still rebuilds and relaunches.
#
# At the end of a turn it also reports app crashes since the last turn, once each.
#
#   refresh-sim.sh          # after an edit: a failed build is expected mid-change, stay quiet
#   refresh-sim.sh --report # end of turn: exit 2 so a failed build or a crash wakes the agent
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STAMP="$ROOT/.build/installed-source.tree"
LOCK="$ROOT/.build/installed-source.lock"
LOG="$ROOT/.build/installed-source.log"
CRASH_MARK="$ROOT/.build/crashes-reported"
SOURCES=(App Packages Config PlusPlus.xcodeproj)

# One refresh at a time. lockf holds a kernel lock that dies with the process, so a refresh
# killed mid-build (by the hook timeout, or the session ending) cannot leave a stale lock behind.
# Whoever holds it keeps going until the code stops changing, so an edit that lands mid-build is
# picked up by the loop below instead of a second build.
if [ -z "${REFRESH_SIM_LOCKED:-}" ]; then
    mkdir -p "$ROOT/.build"
    status=0
    REFRESH_SIM_LOCKED=1 lockf -s -t 0 "$LOCK" "$0" "$@" || status=$?
    # 75 is lockf's "already locked": another refresh is running and will pick this change up.
    [ "$status" -eq 75 ] && exit 0
    exit "$status"
fi

source "$ROOT/scripts/common.sh"
REPORT=$([ "${1:-}" = "--report" ] && echo 1 || true)

# The app's sources as a git tree, untracked files included, so two states can be diffed.
source_tree() {
    local index
    index=$(mktemp)
    (
        cd "$ROOT"
        export GIT_INDEX_FILE="$index"
        git read-tree HEAD
        git add -A -- "${SOURCES[@]}"
        git write-tree
    )
    rm -f "$index"
}

# True when the running app can take the change from the installed tree to $1 as a hot reload:
# InjectionNext is linked, the app is running, and every change edits code inside an existing
# Swift file. A changed line declaring a type-level `let` or `var` without a body is a stored
# property, which changes the type's layout; injecting that corrupts live instances.
injectable() {
    local installed=$1 current=$2
    grep -q -- "-interposable" "$ROOT/Config/Local.xcconfig" 2> /dev/null || return 1
    # Each command's output is captured before it is searched: under pipefail, `grep -q` exiting
    # at the first match fails the pipeline with the writer's SIGPIPE.
    local bundle_id running changes patch
    bundle_id=$(app_bundle_id 2> /dev/null) || return 1
    running=$(xcrun simctl spawn "$SIMULATOR_NAME" launchctl list 2> /dev/null) || return 1
    grep -q "UIKitApplication:$bundle_id" <<< "$running" || return 1
    changes=$(git -C "$ROOT" diff-tree -r --name-status "$installed" "$current")
    awk '$1 != "M" || $2 !~ /^(App|Packages\/Sources)\/.*\.swift$/ { bad = 1 } END { exit bad }' \
        <<< "$changes" || return 1
    patch=$(git -C "$ROOT" diff-tree -r -p -U0 "$installed" "$current")
    ! grep -Eq '^[-+]    (@[A-Za-z]+(\([^)]*\))? )*((private|fileprivate|internal|public)(\(set\))? )*(let|var) [^{]*$' \
        <<< "$patch"
}

crashes=""
if [ -n "$REPORT" ]; then
    # Reported once: the mark moves forward on every check. The first check only sets the mark.
    next_mark=$(mktemp)
    if [ -f "$CRASH_MARK" ]; then
        crashes=$(find "$HOME/Library/Logs/DiagnosticReports" -name '*.ips' -newer "$CRASH_MARK" \
            -print0 2> /dev/null | xargs -0 python3 "$ROOT/.claude/hooks/crash-summary.py" || true)
    fi
    mv "$next_mark" "$CRASH_MARK"
fi

while current=$(source_tree) && installed=$(cat "$STAMP" 2> /dev/null || true) \
    && [ "$current" != "$installed" ]; do
    if [ -n "$installed" ] && injectable "$installed" "$current"; then
        # The app hot-reloads these itself. The stamp stays at what is installed, so the next
        # change injection cannot apply still rebuilds everything since then. At the end of a
        # turn, compile anyway: a hot reload that fails to compile only logs inside the app.
        if [ -n "$REPORT" ] && ! "$ROOT/scripts/build.sh" > "$LOG" 2>&1; then
            echo "The app no longer builds; the simulator keeps the last code that did." >&2
            tail -n 20 "$LOG" >&2
            exit 2
        fi
        break
    fi
    if "$ROOT/scripts/run.sh" > "$LOG" 2>&1; then
        echo "$current" > "$STAMP"
    elif [ -n "$REPORT" ]; then
        echo "The app no longer builds, so the simulator still runs the previous build." >&2
        tail -n 20 "$LOG" >&2
        exit 2
    else
        exit 0
    fi
done

if [ -n "$crashes" ]; then
    echo "The app crashed since the last turn:" >&2
    echo "$crashes" >&2
    exit 2
fi
