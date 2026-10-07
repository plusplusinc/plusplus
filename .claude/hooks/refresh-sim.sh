#!/bin/bash
# Keeps the app on the simulator matching the checkout. Runs in the background after every edit
# an agent makes and again when its turn ends: if the app's code differs from what is installed
# (an edit, a branch switch, a pull), rebuild, reinstall, and relaunch. A no-op otherwise.
#
#   refresh-sim.sh          # after an edit: a failed build is expected mid-change, stay quiet
#   refresh-sim.sh --report # end of turn: a failed build is reported back to the agent
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STAMP="$ROOT/.build/installed-source.sha"
LOCK="$ROOT/.build/installed-source.lock"
LOG="$ROOT/.build/installed-source.log"
SOURCES=(App Packages Config PlusPlus.xcodeproj)

fingerprint() {
    cd "$ROOT"
    {
        git rev-parse HEAD
        git diff HEAD -- "${SOURCES[@]}"
        git ls-files -z --others --exclude-standard -- "${SOURCES[@]}" | xargs -0 shasum 2> /dev/null
    } | shasum | cut -d' ' -f1
}

mkdir -p "$ROOT/.build"
# One rebuild at a time. Whoever holds the lock keeps going until the code stops changing, so an
# edit that lands mid-build is picked up without a second build racing the first.
mkdir "$LOCK" 2> /dev/null || exit 0
trap 'rmdir "$LOCK"' EXIT

while current=$(fingerprint) && [ "$current" != "$(cat "$STAMP" 2> /dev/null || true)" ]; do
    if "$ROOT/scripts/run.sh" > "$LOG" 2>&1; then
        echo "$current" > "$STAMP"
    elif [ "${1:-}" = "--report" ]; then
        echo "Simulator refresh failed; see .build/installed-source.log" >&2
        exit 1
    else
        exit 0
    fi
done
