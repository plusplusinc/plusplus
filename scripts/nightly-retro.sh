#!/bin/bash
# Runs the nightly retro (the retro skill's "How it runs"): a launchd agent starts one Claude Code
# run in print mode at midnight in the main checkout, and the run exits when its report is done.
# Then scripts/nightly-tooling.py runs the night's tooling cards, if any may run.
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
# The tooling runner, which starts after the retro.
TOOLING_PROCESS="nightly-tooling\.py run "

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

# The retro's claude pid, else nothing. -a, since pgrep otherwise skips its own ancestors, which
# the retro's claude is when this runs inside it.
retro_pid() {
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
    pid=$(retro_pid)
    [ -z "$pid" ] || die "A nightly run, the retro or its tooling cards, is already going (pid $pid); two would cover the same night."

    local vars=(SHELL=/bin/zsh TERM=xterm-256color PATH=/usr/bin:/bin:/usr/sbin:/sbin)
    for name in HOME USER LOGNAME LANG TMPDIR SSH_AUTH_SOCK __CF_USER_TEXT_ENCODING COMMAND_MODE; do
        [ -z "${!name:-}" ] || vars+=("$name=${!name}")
    done
    main=$(main_checkout)
    cd "$main"
    night="$main/.build/retro/$(date +%F)"
    mkdir -p "$night"
    echo "== $(date '+%Y-%m-%d %H:%M %Z') nightly retro in $main"
    # The retro's stream goes to the night's folder: show reads its reply from the transcript, and
    # the tooling runner reads the usage limits from the stream. The runner runs after it whether
    # or not it succeeded; its own gates decide whether any card starts.
    env -i "${vars[@]}" /bin/zsh -lic "caffeinate -s claude --name \"$NAME\" -p --permission-mode auto \
        --output-format stream-json --verbose \"/retro nightly\" >> \"$night/retro.jsonl\";
        caffeinate -s \"$main/scripts/nightly-tooling.py\" run \"$night\""
}

show() {
    local pid
    pid=$(retro_pid)
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
    run) run ;;
    show) show ;;
    *)
        sed -n '2,9s/^# \{0,1\}//p' "${BASH_SOURCE[0]}" >&2
        exit 64
        ;;
esac
