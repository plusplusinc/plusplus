#!/bin/bash
# Runs the nightly retro (the retro skill's "How it runs"): a launchd agent starts one Claude Code
# run in print mode at midnight in the main checkout, and the run exits when its report is done.
# Then scripts/nightly-tooling.py runs the monthly setup review when one is due, and the night's
# tooling cards, if any may run.
# launchd needs no session to stay open, so a restart of the Mac changes nothing.
#
#   scripts/nightly-retro.sh install   # run it every midnight; replaces an earlier install
#   scripts/nightly-retro.sh run       # run it once now, as launchd does; refuses when one runs
#   scripts/nightly-retro.sh show      # whether it's installed and running, its last reply and digest
#
# install writes ~/Library/LaunchAgents/$LABEL.plist with this checkout's main checkout's paths,
# so nothing personal is tracked. launchd runs a midnight it missed while the Mac slept once it
# wakes, but not one it missed while the Mac was off; the next run covers that night too. A run's
# output and errors go to .build/retro/nightly.log in the main checkout, and each claude's
# stream-json to the night's folder, .build/retro/<date>/, where the tooling runner reads its
# usage limits from.
#
# run passes on only what a login sets: a Claude Code session's shell carries variables of its
# own (CLAUDECODE, CLAUDE_CODE_*, and others), which must not reach the retro's claude. It runs
# claude in an interactive login zsh, since claude is on the PATH only through ~/.zshrc.
#
# run first fast-forwards the main checkout to origin/main (catch_up, below), then goes on in the
# script's new copy. Before the retro, run updates Claude Code (`claude update`, bounded, and never fatal: a failed one
# runs the night on the installed version), and writes one line saying what happened to the night's
# claude-update.txt, which the tooling runner's digest reads. A running session keeps its version
# until it exits, so this never breaks one in flight; the desktop app's copy updates with the app.
# Then `scripts/nightly-tooling.py tally` writes the agents' tallies the retro and the setup review
# read to the night's folder (its header says which), never stopping the night.
#
# show reads the reply from the run's transcript (scripts/conversations.py --retro-reply), which
# holds it whole, including while a run is still going, then the tooling runner's last digest.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LABEL=inc.plusplus.nightly-retro
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
# The title scripts/conversations.py leaves out, so a run never reads the last run's digest.
NAME="Nightly retro"
# The retro's claude process, wherever it runs, and not the caffeinate that started it.
RETRO_PROCESS="(^|/)claude --name $NAME( |\$)"
# The tooling runner, which starts after the retro: the monthly setup review, then the cards.
TOOLING_PROCESS="nightly-tooling\.py (review|run) |nightly-retro\.sh update "

# The retro's model and effort, from docs/agent-tooling.md's "Models by task", passed explicitly so
# the night never follows the interactive default; scripts/lint.sh fails when they disagree.
RETRO_MODEL=claude-fable-5-2
RETRO_EFFORT=high

# The longest `claude update` may take; a hung one must not hold the night.
UPDATE_LIMIT=180

die() {
    echo "$*" >&2
    exit 1
}

# The main checkout, which holds the scripts launchd runs and the retro's .build/retro.
main_checkout() {
    local common
    # Two steps, so a git failure stops the script rather than leaving dirname with "".
    common=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)
    dirname "$common"
}

# The nightly run's pid, the retro's claude or the tooling runner, else nothing. -a, since pgrep
# otherwise skips its own ancestors, which the retro's claude is when this runs inside it.
nightly_pid() {
    pgrep -aof "$RETRO_PROCESS" || pgrep -aof "$TOOLING_PROCESS" || true
}

installed() {
    launchctl print "$DOMAIN/$LABEL" > /dev/null 2>&1
}

install() {
    local main
    main=$(main_checkout)
    mkdir -p "$(dirname "$PLIST")" "$main/.build/retro"
    cat > "$PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$main/scripts/nightly-retro.sh</string>
        <string>run</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>0</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$main/.build/retro/nightly.log</string>
    <key>StandardErrorPath</key>
    <string>$main/.build/retro/nightly.log</string>
</dict>
</plist>
PLIST
    plutil -lint -s "$PLIST" || die "launchd wouldn't read $PLIST; it was left there to look at."
    # bootout fails when it isn't loaded yet, which is fine.
    launchctl bootout "$DOMAIN/$LABEL" 2> /dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "Installed $LABEL: the retro runs every midnight from $main."
    echo "Its output goes to $main/.build/retro/nightly.log; read its report with scripts/nightly-retro.sh show."
}

run() {
    local pid main name night
    pid=$(nightly_pid)
    [ -z "$pid" ] || die "A nightly run, the retro or its tooling cards, is already going (pid $pid); two would cover the same night."

    local vars=(SHELL=/bin/zsh TERM=xterm-256color PATH=/usr/bin:/bin:/usr/sbin:/sbin)
    for name in HOME USER LOGNAME LANG TMPDIR SSH_AUTH_SOCK __CF_USER_TEXT_ENCODING COMMAND_MODE; do
        [ -z "${!name:-}" ] || vars+=("$name=${!name}")
    done
    main=$(main_checkout)
    cd "$main"
    night="$main/.build/retro/$(date +%F)"
    mkdir -p "$night"
    if [ -z "${NIGHTLY_CAUGHT_UP:-}" ]; then
        catch_up "$main" "$night"
        # The fast-forward may have changed this file: the night goes on in its new copy.
        NIGHTLY_CAUGHT_UP=1 exec /bin/bash "$main/scripts/nightly-retro.sh" run
    fi
    echo "== $(date '+%Y-%m-%d %H:%M %Z') nightly retro in $main"
    # The retro's stream goes to the night's folder: show reads its reply from the transcript, and
    # the tooling runner reads the usage limits from the stream. The runner runs after it whether
    # or not it succeeded; its own gates decide whether any card starts.
    env -i "${vars[@]}" /bin/zsh -lic "\"$main/scripts/nightly-retro.sh\" update \"$night\";
        \"$main/scripts/nightly-tooling.py\" tally \"$night\";
        caffeinate -s claude --name \"$NAME\" -p --permission-mode auto \
        --model \"$RETRO_MODEL\" --effort \"$RETRO_EFFORT\" \
        --output-format stream-json --verbose \"/retro nightly\" >> \"$night/retro.jsonl\";
        caffeinate -s \"$main/scripts/nightly-tooling.py\" review \"$night\";
        caffeinate -s \"$main/scripts/nightly-tooling.py\" run \"$night\""
}

# Brings the main checkout's main to origin/main, since the night runs that checkout's scripts and
# skills and nothing else moves it: only a fast-forward, only of a checkout on main with no tracked
# changes. Otherwise it leaves the checkout as it is and writes why to the night's
# main-checkout.txt, which the tooling runner's digest puts at its top. It always returns 0.
catch_up() {
    local main=$1 night=$2 branch why=""
    branch=$(git -C "$main" symbolic-ref --quiet --short HEAD || true)
    if [ "$branch" != main ]; then
        why="it is on ${branch:-a detached HEAD}, not main"
    elif [ -n "$(git -C "$main" status --porcelain --untracked-files=no)" ]; then
        why="it has uncommitted changes"
    elif ! git -C "$main" fetch --quiet origin main 2> /dev/null; then
        why="fetching origin failed"
    elif ! git -C "$main" merge --ff-only --quiet origin/main > /dev/null 2>&1; then
        why="its main has commits origin/main doesn't"
    fi
    if [ -n "$why" ]; then
        echo "Main checkout not brought up to date: $why; the night runs $(git -C "$main" rev-parse --short HEAD)" |
            tee "$night/main-checkout.txt"
    else
        rm -f "$night/main-checkout.txt"
        echo "Main checkout at $(git -C "$main" log -1 --format='%h %s')"
    fi
}

# Runs a command for at most $1 seconds; a killed one returns 143.
bounded() {
    local limit=$1 pid dog status=0
    shift
    "$@" &
    pid=$!
    (sleep "$limit"; kill "$pid" 2> /dev/null; sleep 5; kill -9 "$pid" 2> /dev/null) &
    dog=$!
    wait "$pid" || status=$?
    kill "$dog" 2> /dev/null || true
    return "$status"
}

# Updates Claude Code before the retro starts, and records one line in the night's folder and log.
# Called inside the login zsh run builds, where claude is on the PATH. It always returns 0.
update() {
    local night=$1 before after output status=0 line why
    before=$(claude --version 2> /dev/null | awk '{print $1}')
    output=$(mktemp)
    bounded "$UPDATE_LIMIT" claude update > "$output" 2>&1 < /dev/null || status=$?
    after=$(claude --version 2> /dev/null | awk '{print $1}')
    if [ "$status" -eq 0 ] && [ -z "$after" ]; then
        status=1
        echo "claude --version failed after the update" > "$output"
    fi
    if [ "$status" -ne 0 ]; then
        why=$(tail -n 1 "$output" | cut -c1-120)
        [ "$status" -ne 143 ] || why="timed out after ${UPDATE_LIMIT}s"
        line="Claude Code update failed: ${why:-no output} (exit $status); running ${after:-$before}"
    elif [ "$before" != "$after" ]; then
        line="Claude Code $before → $after"
    else
        line="Claude Code $after, already the latest"
    fi
    rm -f "$output"
    echo "$line" | tee "$night/claude-update.txt"
}

show() {
    local pid
    pid=$(nightly_pid)
    if [ -n "$pid" ]; then
        echo "The nightly run is going (pid $pid), the retro or its tooling cards. The retro's reply so far follows."
    elif installed; then
        echo "The retro isn't running; launchd starts it at midnight. Its last reply follows."
    else
        echo "The retro isn't installed, so nothing starts it. Install it with scripts/nightly-retro.sh install."
    fi
    "$ROOT/scripts/conversations.py" --retro-reply
    echo
    "$ROOT/scripts/nightly-tooling.py" digest
}

case "${1:-}" in
    install) install ;;
    # Each arm that can change this file exits before bash reads past the case.
    run)
        run
        exit
        ;;
    update) update "${2:?usage: nightly-retro.sh update <night-dir>}" ;;
    catch-up)
        catch_up "$(main_checkout)" "${2:?usage: nightly-retro.sh catch-up <night-dir>}"
        exit
        ;;
    show) show ;;
    *)
        sed -n '2,10s/^# \{0,1\}//p' "${BASH_SOURCE[0]}" >&2
        exit 64
        ;;
esac
