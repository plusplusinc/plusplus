#!/bin/bash
# Runs the nightly retro (the retro skill's "How it runs") in a detached GNU screen session named
# nightly-retro, in the main checkout. Unlike a terminal tab, it starts while the Mac is locked
# and outlives the terminal app.
#
#   scripts/nightly-retro.sh start   # start it, from any checkout; refuses when one is running
#   scripts/nightly-retro.sh show    # whether its claude is running, and its last reply, whole
#
# Attach with `screen -d -r nightly-retro` (-d detaches any other terminal first), detach with
# Ctrl-a d. When Claude Code quits, a shell takes its place, so its last screen stays readable.
#
# `start` passes on only what a login sets: a Claude Code session's shell carries variables of
# its own (CLAUDECODE, CLAUDE_CODE_*, and others), which must not reach the retro's claude. It
# runs claude in an interactive login zsh, since claude is on the PATH only through ~/.zshrc.
#
# `show` reads the reply from the session's transcript (scripts/conversations.py --retro-reply),
# which holds it whole: the window holds only what fits, and a hardcopy of it keeps nothing
# outside ASCII.
#
# macOS ships screen 4.00, and this works around its quirks: `screen -ls` exits 1 even when it
# lists sessions; -S matches a name prefix; and -dm returns before the session exists.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCREEN=/usr/bin/screen
SESSION=nightly-retro
# The title scripts/conversations.py leaves out, so a run never reads the last run's digest.
NAME="Nightly retro"
COMMAND="caffeinate -s claude --name \"$NAME\" --permission-mode auto \"/retro nightly\""
# The retro's claude process, wherever it runs, and not the caffeinate that started it.
RETRO_PROCESS="(^|/)claude --name $NAME( |\$)"
HINT="Read it with scripts/nightly-retro.sh show, or attach with screen -d -r $SESSION (Ctrl-a d detaches)."
WAIT_SECONDS=10

die() {
    echo "$*" >&2
    exit 1
}

# Runs the command until it succeeds, for up to WAIT_SECONDS, else stops with the message.
wait_for() {
    local message=$1 deadline=$((SECONDS + WAIT_SECONDS))
    shift
    until "$@"; do
        [ "$SECONDS" -lt "$deadline" ] || die "$message"
        sleep 0.1
    done
}

# The session's "<pid>.nightly-retro" id when it is open, else nothing. It matches the whole
# name, so a session named nightly-retro-2 doesn't count.
session_id() {
    { "$SCREEN" -ls 2> /dev/null || true; } | awk -v name="$SESSION" '
        { id = $1; sub(/^[0-9]+\./, "", id) }
        id == name && /tached\)/ { print $1; exit }'
}

has_session() {
    [ -n "$(session_id)" ]
}

# The retro's claude pid, else nothing. -a, since pgrep otherwise skips its own ancestors, which
# the retro's claude is when this runs inside it.
retro_pid() {
    pgrep -aof "$RETRO_PROCESS" || true
}

has_retro() {
    [ -n "$(retro_pid)" ]
}

start() {
    local id pid common main name
    id=$(session_id)
    pid=$(retro_pid)
    [ -z "$id" ] || [ -n "$pid" ] || die "$SESSION is open ($id), but its claude has quit. See" \
        "why with screen -d -r $id, then close it with screen -S $id -X quit and start again."
    [ -z "$id" ] || die "$SESSION is already running ($id). $HINT"
    [ -z "$pid" ] || die "A nightly retro is already running outside screen (pid $pid). Quit it" \
        "first: two would both run at midnight."

    local vars=(SHELL=/bin/zsh TERM=xterm-256color PATH=/usr/bin:/bin:/usr/sbin:/sbin)
    for name in HOME USER LOGNAME LANG TMPDIR SSH_AUTH_SOCK __CF_USER_TEXT_ENCODING COMMAND_MODE; do
        [ -z "${!name:-}" ] || vars+=("$name=${!name}")
    done
    # Two steps, so a git failure stops the script rather than leaving dirname with "".
    common=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)
    main=$(dirname "$common")
    cd "$main"
    # -U: the window is UTF-8 whatever the caller's locale.
    env -i "${vars[@]}" "$SCREEN" -U -dmS "$SESSION" /bin/zsh -lic "$COMMAND; exec /bin/zsh -l"

    wait_for "screen started no $SESSION session within $WAIT_SECONDS seconds. Run the command in a terminal to see why: cd $main && $COMMAND" \
        has_session
    id=$(session_id)
    wait_for "$SESSION started ($id), but its claude didn't. See why with screen -d -r $id." \
        has_retro
    echo "Started $SESSION ($id) in $main."
    echo "$HINT"
}

show() {
    local pid
    pid=$(retro_pid)
    if [ -n "$pid" ]; then
        echo "The retro's claude is running (pid $pid)."
    elif has_session; then
        echo "The retro's claude has quit, and its $SESSION session is open: see why with screen -d -r $SESSION."
    else
        echo "The retro's claude is not running. Start it with scripts/nightly-retro.sh start."
    fi
    "$ROOT/scripts/conversations.py" --retro-reply
}

case "${1:-}" in
    start) start ;;
    show) show ;;
    *)
        sed -n '2,10s/^# \{0,1\}//p' "${BASH_SOURCE[0]}" >&2
        exit 64
        ;;
esac
