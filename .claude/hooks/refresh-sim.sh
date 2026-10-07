#!/bin/bash
# Keeps the app on the simulator matching the checkout. Runs in the background after every edit
# an agent makes and again when its turn ends: if the app's code differs from what is installed
# (an edit, a branch switch, a pull), rebuild, reinstall, and relaunch. A no-op otherwise.
#
#   refresh-sim.sh          # after an edit: a failed build is expected mid-change, stay quiet
#   refresh-sim.sh --report # end of turn: exit 2 so a failed build wakes the agent to fix it
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STAMP="$ROOT/.build/installed-source.sha"
LOCK="$ROOT/.build/installed-source.lock"
LOG="$ROOT/.build/installed-source.log"
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

fingerprint() {
    cd "$ROOT"
    {
        git rev-parse HEAD
        git diff HEAD -- "${SOURCES[@]}"
        git ls-files -z --others --exclude-standard -- "${SOURCES[@]}" | xargs -0 shasum 2> /dev/null
    } | shasum | cut -d' ' -f1
}

while current=$(fingerprint) && [ "$current" != "$(cat "$STAMP" 2> /dev/null || true)" ]; do
    if "$ROOT/scripts/run.sh" > "$LOG" 2>&1; then
        echo "$current" > "$STAMP"
    elif [ "${1:-}" = "--report" ]; then
        echo "The app no longer builds, so the simulator still runs the previous build." >&2
        tail -n 20 "$LOG" >&2
        exit 2
    else
        exit 0
    fi
done
