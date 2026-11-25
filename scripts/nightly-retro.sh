#!/bin/bash
# The night's helpers (.claude/skills/night/SKILL.md, which a scheduled task in the Claude app
# runs at midnight in a worktree of its own), and the removal of the launchd agent that ran it before.
#
#   scripts/nightly-retro.sh catch-up <night-dir>  # bring the main checkout up to origin/main
#   scripts/nightly-retro.sh show                  # the night's retro reply and digest
#   scripts/nightly-retro.sh uninstall             # remove the old launchd agent and its plist
#
# show reads the reply from the night's transcript (scripts/conversations.py --retro-reply),
# which holds it whole, including while a night is still going, then the night's digest
# (scripts/nightly-tooling.py digest). It says so first when the old launchd agent is still
# installed. uninstall succeeds when the agent is already gone; NIGHTLY_RETRO_LABEL and
# NIGHTLY_RETRO_PLIST stand in for its label and plist in the tests.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LABEL=${NIGHTLY_RETRO_LABEL:-inc.plusplus.nightly-retro}
PLIST=${NIGHTLY_RETRO_PLIST:-$HOME/Library/LaunchAgents/$LABEL.plist}
DOMAIN="gui/$(id -u)"

# The main checkout, which holds the night's .build/retro.
main_checkout() {
    local common
    # Two steps, so a git failure stops the script rather than leaving dirname with "".
    common=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)
    dirname "$common"
}

installed() {
    launchctl print "$DOMAIN/$LABEL" > /dev/null 2>&1
}

uninstall() {
    if installed; then
        launchctl bootout "$DOMAIN/$LABEL"
        echo "Stopped the launchd agent $LABEL."
    fi
    if [ -e "$PLIST" ]; then
        rm "$PLIST"
        echo "Deleted $PLIST."
    fi
    echo "The launchd agent $LABEL is gone; the scheduled task in the Claude app runs the night."
}

# Brings the main checkout's main to origin/main, since the night runs that checkout's
# nightly-tooling.py, the next night's worktree is cut from its main, and nothing else moves it: only a fast-forward, only of a checkout on main. An uncommitted
# change stays as it is and stops the fast-forward only when origin/main changed the same file,
# which git refuses. Otherwise it leaves the checkout as it is and writes why to the night's
# main-checkout.txt, which the night's digest puts at its top. It always returns 0.
catch_up() {
    local main=$1 night=$2 branch why=""
    branch=$(git -C "$main" symbolic-ref --quiet --short HEAD || true)
    if [ "$branch" != main ]; then
        why="it is on ${branch:-a detached HEAD}, not main"
    elif ! git -C "$main" fetch --quiet origin main 2> /dev/null; then
        why="fetching origin failed"
    elif ! git -C "$main" merge --ff-only --quiet origin/main > /dev/null 2>&1; then
        if git -C "$main" merge-base --is-ancestor HEAD origin/main; then
            why="it has uncommitted changes to files origin/main changed"
        else
            why="its main has commits origin/main doesn't"
        fi
    fi
    if [ -n "$why" ]; then
        echo "Main checkout not brought up to date: $why; the night runs $(git -C "$main" rev-parse --short HEAD)" |
            tee "$night/main-checkout.txt"
    else
        rm -f "$night/main-checkout.txt"
        echo "Main checkout at $(git -C "$main" log -1 --format='%h %s')"
    fi
}

show() {
    if installed; then
        echo "The old launchd agent $LABEL is still installed: remove it with scripts/nightly-retro.sh uninstall."
    fi
    "$ROOT/scripts/conversations.py" --retro-reply || true
    echo
    "$ROOT/scripts/nightly-tooling.py" digest
}

case "${1:-}" in
    uninstall) uninstall ;;
    # The fast-forward may change this file: exit before bash reads past the case.
    catch-up)
        mkdir -p "${2:?usage: nightly-retro.sh catch-up <night-dir>}"
        catch_up "$(main_checkout)" "$2"
        exit
        ;;
    show) show ;;
    *)
        sed -n '2,7s/^# \{0,1\}//p' "${BASH_SOURCE[0]}" >&2
        exit 64
        ;;
esac
