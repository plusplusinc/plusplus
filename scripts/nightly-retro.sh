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
# `start` runs Claude Code from a clean environment: a Claude Code session's shell carries
# CLAUDECODE and CLAUDE_CODE_* variables, which must not reach the retro's claude. It runs in an
# interactive login zsh, since claude is on the PATH only through ~/.zshrc.
#
# macOS ships screen 4.00, and this works around its quirks: `screen -ls` exits 1 even when it
# lists sessions; `-X` returns before the session runs the command; and a detached window is 80
# by 24. Claude Code redraws its window in place, so nothing reaches screen's scrollback and the
# window is all `show` can read; `start` makes it 120 by 50. A hardcopy keeps only the low byte
# of each character, so `show` prints a character outside ASCII as U+FFFD, or as the letter its
# low byte happens to be (Claude Code's prompt arrow comes out as "o").
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCREEN=/usr/bin/screen
SESSION=nightly-retro
COMMAND='caffeinate -s claude --name "Nightly retro" --permission-mode auto "/retro nightly"'
# The retro's claude process, wherever it runs, and not the caffeinate that started it.
RETRO_PROCESS='(^|/)claude --name Nightly retro( |$)'
WAIT_SECONDS=10

die() {
    echo "$*" >&2
    exit 1
}

# The session's "<pid>.nightly-retro" id when it is running, else nothing. Matching the whole
# name matters: screen's -S matches a prefix, so it would also take nightly-retro-2.
session_id() {
    { "$SCREEN" -ls 2> /dev/null || true; } | awk -v name="$SESSION" '
        { id = $1; sub(/^[0-9]+\./, "", id) }
        id == name && /tached\)/ { print $1; exit }'
}

start() {
    local id pid main name started
    id=$(session_id)
    [ -z "$id" ] || die "$SESSION is already running ($id). Read it with scripts/nightly-retro.sh" \
        "show, or attach with screen -r $SESSION (Ctrl-a d detaches)."
    pid=$(pgrep -f "$RETRO_PROCESS" | head -1 || true)
    [ -z "$pid" ] || die "A nightly retro is already running outside screen (pid $pid). Quit it" \
        "first: two would both run at midnight."

    # What a login on this Mac sets, and nothing a Claude Code session adds.
    local vars=(SHELL=/bin/zsh TERM=xterm-256color PATH=/usr/bin:/bin:/usr/sbin:/sbin)
    for name in HOME USER LOGNAME LANG TMPDIR SSH_AUTH_SOCK __CF_USER_TEXT_ENCODING COMMAND_MODE; do
        [ -z "${!name:-}" ] || vars+=("$name=${!name}")
    done
    main=$(dirname "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)")
    cd "$main"
    # -U: the window is UTF-8 whatever the caller's locale.
    env -i "${vars[@]}" "$SCREEN" -U -dmS "$SESSION" /bin/zsh -lic "$COMMAND; exec /bin/zsh -l"

    started=$SECONDS
    until id=$(session_id) && [ -n "$id" ]; do
        [ $((SECONDS - started)) -lt "$WAIT_SECONDS" ] || die "screen started no $SESSION session" \
            "within $WAIT_SECONDS seconds. Run the command in a terminal to see why: cd $main && $COMMAND"
        sleep 0.1
    done
    "$SCREEN" -S "$id" -p 0 -X width -w 120 50
    echo "Started $SESSION ($id) in $main."
    echo "Read it with scripts/nightly-retro.sh show, or attach with screen -r $SESSION (Ctrl-a d detaches)."
}

show() {
    local id dir started
    id=$(session_id)
    [ -n "$id" ] || die "No $SESSION session is running. Start one with scripts/nightly-retro.sh start."
    dir=$(mktemp -d)
    # Expanded now: the trap runs after this function returns, when $dir is gone.
    trap "rm -rf '$dir'" EXIT
    # The session runs commands in order, so the second file appearing means the first is whole.
    "$SCREEN" -S "$id" -p 0 -X hardcopy "$dir/screen"
    "$SCREEN" -S "$id" -p 0 -X hardcopy "$dir/done"
    started=$SECONDS
    until [ -e "$dir/done" ]; do
        [ $((SECONDS - started)) -lt "$WAIT_SECONDS" ] || die "$SESSION did not answer within" \
            "$WAIT_SECONDS seconds. Attach with screen -r $SESSION to see why."
        sleep 0.1
    done
    # NULs are blank cells and box lines (U+2500's low byte is 0); other bytes outside printable
    # ASCII become U+FFFD. Trailing spaces and blank lines at either end go; inner runs of blank
    # lines become one.
    LC_ALL=C tr -d '\000' < "$dir/screen" | LC_ALL=C awk '
        { gsub(/[^[:print:]]/, "\357\277\275"); sub(/ +$/, "") }
        NF { if (gap && seen) print ""; print; seen = 1; gap = 0; next }
        { gap = 1 }'
}

case "${1:-}" in
    start) start ;;
    show) show ;;
    *)
        sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
        exit 64
        ;;
esac
