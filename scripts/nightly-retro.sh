#!/bin/bash
# Runs the nightly retro (the retro skill's "How it runs") in a detached GNU screen session named
# nightly-retro, in the main checkout. Unlike a terminal tab, it starts while the Mac is locked
# and outlives the terminal app.
#
#   scripts/nightly-retro.sh start   # start it, from any checkout; refuses when one is running
#   scripts/nightly-retro.sh show    # print what its window shows now, without attaching
#
# Attach with `screen -r nightly-retro`, detach with Ctrl-a d. When Claude Code quits, a shell
# takes its place in the window, so its last screen stays readable.
#
# `start` passes on only what a login sets: a Claude Code session's shell carries variables of
# its own (CLAUDECODE, CLAUDE_CODE_*, and others), which must not reach the retro's claude. It
# runs claude in an interactive login zsh, since claude is on the PATH only through ~/.zshrc.
#
# macOS ships screen 4.00, and this works around its quirks: `screen -ls` exits 1 even when it
# lists sessions; -S matches a name prefix; -dm and -X return before the session acts; a detached
# window is 80 by 24; and a hardcopy keeps only the low byte of each character. Claude Code
# redraws its window in place, so nothing reaches screen's scrollback and the window is all
# `show` can read; `start` makes it 120 by 50.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCREEN=/usr/bin/screen
SESSION=nightly-retro
# The title scripts/conversations.py leaves out, so a run never reads the last run's digest.
NAME="Nightly retro"
COMMAND="caffeinate -s claude --name \"$NAME\" --permission-mode auto \"/retro nightly\""
# The retro's claude process, wherever it runs, and not the caffeinate that started it.
RETRO_PROCESS="(^|/)claude --name $NAME( |\$)"
HINT="Read it with scripts/nightly-retro.sh show, or attach with screen -r $SESSION (Ctrl-a d detaches)."
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

# The session's "<pid>.nightly-retro" id when it is running, else nothing. It matches the whole
# name, so a session named nightly-retro-2 doesn't count.
session_id() {
    { "$SCREEN" -ls 2> /dev/null || true; } | awk -v name="$SESSION" '
        { id = $1; sub(/^[0-9]+\./, "", id) }
        id == name && /tached\)/ { print $1; exit }'
}

is_running() {
    [ -n "$(session_id)" ]
}

start() {
    local id pid common main name
    id=$(session_id)
    pid=$(pgrep -of "$RETRO_PROCESS" || true)
    [ -z "$id" ] || [ -n "$pid" ] || die "$SESSION is open ($id), but its claude has quit. Read" \
        "why with scripts/nightly-retro.sh show, then close it with screen -S $id -X quit and start again."
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
        is_running
    id=$(session_id)
    "$SCREEN" -S "$id" -p 0 -X width -w 120 50
    wait_for "$SESSION started ($id), but its claude didn't. Read why with scripts/nightly-retro.sh show." \
        pgrep -qf "$RETRO_PROCESS"
    echo "Started $SESSION ($id) in $main."
    echo "$HINT"
}

show() {
    local id dir
    id=$(session_id)
    [ -n "$id" ] || die "No $SESSION session is running. Start one with scripts/nightly-retro.sh start."
    dir=$(mktemp -d)
    # Expanded now: the trap runs after this function returns, when $dir is gone.
    trap "rm -rf '$dir'" EXIT
    # The session runs commands in order, so the second file appearing means the first is whole.
    "$SCREEN" -S "$id" -p 0 -X hardcopy "$dir/screen"
    "$SCREEN" -S "$id" -p 0 -X hardcopy "$dir/done"
    wait_for "$SESSION did not answer within $WAIT_SECONDS seconds. Attach with screen -r $SESSION to see why." \
        test -e "$dir/done"
    # A NUL is a character whose low byte is 0, such as the box line U+2500; it becomes a space,
    # keeping the columns. Other bytes outside printable ASCII become U+FFFD; a character whose
    # low byte is printable ASCII can't be told apart from it (Claude Code's prompt arrow,
    # U+276F, prints as "o"). Trailing spaces and blank lines at either end go; inner runs of
    # blank lines become one.
    LC_ALL=C tr '\000' ' ' < "$dir/screen" | LC_ALL=C awk '
        { gsub(/[^[:print:]]/, "\357\277\275"); sub(/ +$/, "") }
        NF { if (gap && seen) print ""; print; seen = 1; gap = 0; next }
        { gap = 1 }'
}

case "${1:-}" in
    start) start ;;
    show) show ;;
    *)
        sed -n '2,10s/^# \{0,1\}//p' "${BASH_SOURCE[0]}" >&2
        exit 64
        ;;
esac
