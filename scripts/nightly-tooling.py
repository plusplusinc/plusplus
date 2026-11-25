#!/usr/bin/env python3
"""The night's steps (.claude/skills/night/SKILL.md), each a command its scheduled session runs.

    scripts/nightly-tooling.py night                         # tonight's folder, then the script to run
    scripts/nightly-tooling.py begin <night-dir>             # record the session; park and undo what a dead run left
    scripts/nightly-tooling.py usage <night-dir> [<file>]    # exits 1 when a weekly window is at 97%
    scripts/nightly-tooling.py tally <night-dir>             # the agents' tallies, for the retro and the review
    scripts/nightly-tooling.py outcome <night-dir> ran | failed <step> <why>
    scripts/nightly-tooling.py review <night-dir>            # exits 0 when a setup review is due, opening it
    scripts/nightly-tooling.py review-end <night-dir>        # carry the review's report; keep its last line
    scripts/nightly-tooling.py next <night-dir> [--dry-run]  # exits 0 with the card to take, 1 when none may start
    scripts/nightly-tooling.py decide <night-dir> <card>     # exits 3 while armed
    scripts/nightly-tooling.py digest [<night-dir>]          # a night's digest, written; bare, the last night's, printed
    scripts/nightly-tooling.py hook <night-dir>              # the guard, behind .claude/hooks/night-guard.sh
    scripts/nightly-tooling.py pre-push <night-dir>          # a card's git pre-push hook

The night's folder, .build/retro/<date>/ in the main checkout, which `night` prints with the main
checkout's copy of this script from any worktree, holds the night's state, so each
command reads what the last one wrote: `session` (the night's session id, which `begin` takes
from CLAUDE_CODE_SESSION_ID), state.json (the night's start, this month's Xcode Cloud hours,
main's test counts, and the open phase: a card, the setup review, or none), cards.json (each
card taken and what was decided), notes.json (what the digest says besides the cards),
guard-seen (each phase and caller the guard judged a call for), starts (the Xcode Cloud runs the
hooks let start), and pushed (the branches a card's worktree pushed).

`usage` reads the usage.json the night saved from the app's usage tool, copied first from <file>
when given, and prints one line; it
exits 1 when a window whose label names a week is at 97% or more, and 0 when the file can't be
read, which the digest then says. `outcome` writes outcome.txt. `digest <night-dir>` makes the
closing reads (Xcode Cloud, main's tests, PRs behind main, tonight's merges), each failure a "Not
checked:" line, then writes the night's digest.md and prints it; bare, it only prints the newest
night's, from its files. Its first line is "Night <date>: ran" or "Night <date>: failed: <step>,
<why>", and "no outcome recorded: still running, or it stopped early" when none was.

`next` holds the night's gates, so no agent can forget one. It starts no card from 5 am to
midnight, while a phase is open, after a merge that skipped the gates, when this session isn't
the one `begin` recorded, or when guard-seen holds no line for the session's own calls (the guard
isn't installed). It reads usage.json, which must be under 15 minutes old: no card when any
window is at 90%; three a night, unless every weekly window resets by 7 am; and on that night a
window still open past 7 am keeps half of it free. The night's first `next` puts a card, "Update
<tool> to <version>", at the top of Definitely for each lint tool `scripts/lint-tools.sh
outdated` names, unless the board has one by that title or an open one for that tool, and moves
to Done the cards a night parked or left waiting whose PR has merged since. Then it takes the
first eligible card that names no file an open PR changes (a retro PR's Markdown under .claude/
and docs/ holds none back, and a card held back tops the digest) and, when it may change the
app, fits this month's 70 Xcode Cloud PR hours and leaves room for EXPECTED_RUNS of the night's
four runs. A card is built in the session's own folder, since Claude Code refuses a subagent's
edits in another worktree: never the main checkout, whose copies of this script and the guard
judge the card, and never with uncommitted changes there. `next` makes the card's branch from
main, switches the session's folder to it with the night's pre-push hook in that worktree's own
git config, moves the card to In Progress, opens its phase, and prints the card, title,
worktree, branch, handoff, and last-line file. --dry-run prints the same, or why not, and
changes nothing. What the night keeps outside that folder (a handoff, the review's report) is
written in it and carried across by `decide` and `review-end`.

`decide` first turns auto-merge off on every open PR from the night's branches, the ones `next`
made or a card's worktree pushed, then reads the PR on the card's branch. It arms auto-merge only after a passing verifier
record by this account, on a commit of the PR with only tests after it, no test count dropped
unexplained, and a line in guard-seen from one of the card's subagents; a PR touching a protected
path or only .claude/ and docs/ waits for the maintainer, and a failed card's PR goes back to
draft. Armed, it waits for the merge until eight minutes after it started and exits 3 when it hasn't come, so the
session runs it again; a failed PR check, or an hour armed, parks the card. A PR from the night's
branches merged that the night didn't arm, or a list of tonight's merges it can't read, ends the
cards and tops the digest. Every outcome closes the phase, carries the handoff to the main
checkout's .slices/, unsets the hook, and switches the folder back (when it can't, no more cards
start). A card decided before is left as it is, and exits 0. The lead's last line comes from the
last-line file `next` printed, which the lead Writes, since a line on the command line may hold
what the guard won't pass, and a pipe into the main checkout's script is no closing step.

`review` is due from midnight to 5 am, on the first night of a month with no setup review's
report in .slices/review-setup/ yet, or on a newer major Xcode installed since the last report,
on at most two nights a month that started one. Due, and with the guard able to hold the
session's calls (as for a card), it opens the review's phase, for 90 minutes or until 5 am, and
exits 0; the session then
runs /review-setup nightly, and `review-end` carries its report, closes the phase, and keeps the
last line the lead Wrote to .build/last-line.txt in its folder for the digest; a `begin` after a
session that died first carries the report. It exits 1 when the review isn't due or can't run guarded, and 2 when it failed.

The night calls `tally` before the retro, so neither agent runs
scripts/agent-record.py, which their skills' allowed tools don't hold. It writes the retro's agents'
tally, over the PRs merged in the last 30 days, to agent-tally.txt in the night's folder, and, when
the setup review runs tonight, the review's, since its last report and since each trial's start
(docs/agent-tooling.md's "Models by task"), to agent-tally-review.txt, all from one fetch. The
fetch's requests are cut off after three minutes together; a tally that fails or runs past that
writes "No tally tonight: <why>" in its file instead, and the night goes on. `review` writes the
review's file itself when the night's `tally` didn't.

`hook` is the guard. The main checkout's .claude/hooks/night-guard.sh, once .claude/settings.json
runs it (HOOK_COMMAND) as a PreToolUse hook on every session's calls, hands it only the calls
whose input holds the session id of a night's folder; such a hook runs before the permission
rules, and its deny wins over their allow. With no phase open it allows everything,
so the retro runs unguarded. During a card it reads each Bash command as the shell would split
it, `bash -c`, `eval`, and `$(...)` included, and denies a merge of a PR (`gh pr merge`, `gh api`
on a merge path, a GraphQL mutation), any `asc xcode-cloud` command that starts or changes a
build or workflow and any `asc api` call but a GET, a gh alias being defined, turning off git's
hooks, moving a card on the board, a shell or interpreter run on inline or piped code (`python3 -c`, `| sh`, a heredoc into a
shell), a push or PR that would start an Xcode Cloud run once tonight's runs reach four or this
month's PR hours pass 70, and, from 7 am, any new agent, edit but the handoff, or command but
reading and committing; from 7:45 it denies everything but the lead's own `decide`, `review-end`,
`digest`, and `outcome`, run as one command, and the lead's Write of its last-line file. It keeps
a card's writes in its worktree (not its .git file), denies git config writes, a plainly
spelled copy of this script run with one of the night's steps, and a command naming the night's
own files: the main checkout, read from every folder a `cd` in the command may leave the shell
in, the night's folder, or a dotfile in the home folder. During the setup review it denies Edit,
commits, pushes, PR writes, brew, and asc, and a Write outside the session's
.slices/review-setup/; past the review's deadline, all but that Write and the lead's closing
commands. Once it knows a call is the night's, any error in it denies the call.

Where the guard can't tell a call is the night's, it passes it, so no day session is ever held:
when CLAUDE_PROJECT_DIR names no checkout with a guard, it never runs. That holds for every call
of that session, so the guard never judges a call of the night's, and `next` and `review` refuse.

The guard is a net for an agent's mistakes: it reads only what the command line shows and
denies the plain spellings, and a path or step spelled through an expansion, a glob, or a
script the card writes is past it. What holds against a card's branch is elsewhere: the files
that judge the card run from the main checkout, found from the session folder's path, which
the app sets, which `next` takes no card outside; `decide`'s own gates, with its checks before
arming that the main checkout's scripts/, .claude/hooks/, and .git/hooks/ are as `next` hashed
them (else it parks the card and ends the cards) and that the pre-push hook is on in the card's
folder (on now, not at every push); `begin` closing no phase
of a session the guard heard lately; and main's ruleset and protected paths. The pre-push hook
(core.hooksPath in the session folder's own config) refuses a push past the budget, with
tonight's runs counted from Xcode Cloud itself, and records the branch; `decide` turns
auto-merge off on the night's PRs before it decides and lists the PRs from the night's branches
merged to main that it didn't arm. Other merges, the maintainer's sessions', get one plain line.
A deadline holds to within one tool call: a call already running isn't stopped.

Tests: python3 scripts/nightly-tooling-test.py, against fixtures, with no network.
"""
import fnmatch
import importlib.util
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from xcresult import PR_WORKFLOW, ROOT, when  # noqa: E402

CUTOFF_HOUR = 5  # no card starts at or after this hour
STOP_HOUR = 7  # nothing new starts at all; a running builder writes its handoff
LAST_CALL = timedelta(minutes=45)  # past STOP_HOUR, only the lead's closing commands run
CAPPED_CARDS = 3
USAGE_STOP = 90  # percent of any usage window at which no card starts
# On the uncapped night, a window still open past STOP_HOUR keeps this percent free.
MORNING_RESERVE = 50
USAGE_FRESH = timedelta(minutes=15)  # usage.json older than this is usage unknown
HOURS_LIMIT = 70  # this month's Xcode Cloud PR hours, of the plan's 100
RUN_LIMIT = 4  # Xcode Cloud PR runs a night's cards may start
EXPECTED_RUNS = 2  # the runs a card that may change the app needs: its PR's, and one more push
MERGE_POLL = timedelta(minutes=8)  # `decide` polls an armed PR this long, inside a ten-minute Bash call
MERGE_WAIT = timedelta(hours=1)  # an armed PR not merged by then is parked
STARTED = time.monotonic()  # each command is its own process
# A read the hooks wait on gives up after this, well inside the hook's own timeout, so a slow
# service denies the call rather than letting Claude Code run it when the hook times out.
READ_TIMEOUT = 60

# A PR touching one of these is never merged at night (fnmatch, where * also matches /). The
# night's own files are here too, so no night can loosen its gates.
PROTECTED = [
    # What decides the PR check, and what Xcode Cloud runs: the project and its schemes (which
    # tests the test action runs), the test plan, the scripts ci_post_clone.sh runs, the tools it
    # installs, and the resolved packages.
    ".github/*", "scripts/pr-check.sh", "ci_scripts/*", "*.xcodeproj/*", "*.xcworkspace/*",
    "*.xctestplan", "Config/*.xcconfig", "*.entitlements", "Packages/Package.swift",
    "*Package.resolved", "Brewfile", "Brewfile.lock.json", "scripts/lint.sh", "scripts/lint-tools.sh",
    "scripts/check-us-english.sh", "scripts/common.sh", ".swiftlint.yml", "*/.swiftlint.yml",
    ".swiftformat", "*/.swiftformat",
    # What steers the night's agents and their gates: this script and its helpers, everything in
    # .claude/ (agents, skills, rules, hooks, permissions), the instructions every session loads,
    # and the tools.
    "scripts/nightly-tooling.py", "scripts/nightly-tooling-test.py", "scripts/nightly-retro.sh",
    "scripts/xcresult.py", "scripts/tidy.sh", "scripts/board.sh", "scripts/models.py",
    "scripts/models-test.py", "scripts/board-test.py", ".claude/*", "CLAUDE.md",
    "AGENTS.md", ".mcp.json",
]
# The CI half repeats what .github/no-code-paths's header and scripts/pr-check.sh's GATE_PATTERN
# name; a file added to either belongs here too.
DAY_ONLY = (".claude/", "docs/")  # a PR entirely under these waits for the day
RETRO_TITLE = "Retro of"  # how every retro PR's title starts (.claude/skills/retro/SKILL.md)
REVIEW_REPORTS = ".slices/review-setup"  # in the main checkout (.claude/skills/review-setup/)
REVIEW_LIMIT = timedelta(minutes=90)  # a setup review's phase closes after this, or at the 5 am cutoff
TALLY = "agent-tally.txt"  # the retro's agents' tally, in the night's folder (.claude/skills/retro/)
REVIEW_TALLY = "agent-tally-review.txt"  # the setup review's (.claude/skills/review-setup/)
TALLY_DAYS = 30  # the retro's tally covers the PRs merged in these last days
TALLY_LIMIT = 180  # seconds the night waits for a tally's GitHub requests, all of them together
REVIEW_TRIES = 2  # nights a month that may start a setup review, so a failing one doesn't eat every night's cards
TEST_DIRS = ("Packages/Tests", "PlusPlusUITests")
TEST_PATTERN = r"@Test([^A-Za-z]|$)|func test[A-Z_]"
FEWER_TESTS = "Fewer tests:"  # the PR body's line that explains a drop, naming its target
FAILURES = (RuntimeError, OSError, ValueError, KeyError, subprocess.SubprocessError)
# The lines a verifier record may hold after its header (.claude/agents/verifier.md).
RECORD_LINE = re.compile(r"- (criterion|test|design|crash|other), (new|known): \S")

# The night's files, in its folder.
SESSION = "session"
STATE = "state.json"
CARDS = "cards.json"
NOTES = "notes.json"
SEEN = "guard-seen"
PUSHED = "pushed"  # the branches a card's worktree pushed, which its pre-push hook records
HEARD = "heard"  # touched by the guard at each of the night's calls
HEARD_LATELY = timedelta(minutes=5)  # a session heard this lately is alive, and `begin` leaves its phase open
# The main checkout's folders whose files judge a card: `next` records their hashes in the
# card's entry, after the night's catch-up has moved them, and `decide` compares them before arming.
JUDGES = ("scripts", ".claude/hooks", ".git/hooks")
SCRIPT = "scripts/nightly-tooling.py"  # this script, in the main checkout, which runs the night's steps
WEEKLY_STOP = 97  # percent of a weekly window at which the night skips the retro
USAGE = "usage.json"  # what the app's usage tool returned, which the night saves
OUTCOME = "outcome.txt"  # "ran" or "failed: <step>, <why>", which `outcome` writes
# In the session's own folder: the lead's last line for `decide` or `review-end`, which the lead
# Writes there, since a line given on the command line may hold what the guard won't pass.
LAST_LINE = ".build/last-line.txt"
# The night's steps, which only its lead runs, from the main checkout's script.
NIGHT_STEPS = {"night", "begin", "usage", "tally", "outcome", "review", "review-end", "next", "decide",
               "digest", "hook", "pre-push"}
# .claude/settings.json's PreToolUse command: the main checkout's guard, found from the text of
# the session's folder alone, which the app sets: the main checkout itself, or a worktree the app
# made at <main>/.claude/worktrees/<name>. It reads no file in that folder, which a card could
# write, and runs no program that could fail. With no guard there, it passes the call silently.
HOOK_COMMAND = ('d=${CLAUDE_PROJECT_DIR%%/.claude/worktrees/*}/.claude/hooks/night-guard.sh; '
                '[ -f "$d" ] || exit 0; exec /bin/sh "$d"')


def checkout_note(folder):
    """The digest's line when scripts/nightly-retro.sh catch-up couldn't bring the main checkout up
    to origin/main, from main-checkout.txt, which it writes only then: the night ran older scripts."""
    try:
        text = (Path(folder) / "main-checkout.txt").read_text(errors="replace").strip()
    except OSError:
        return []
    return [f"Not checked: {text}"] if text else []


def start_count(folder):
    """The Xcode Cloud runs the hooks let tonight's cards start, which Xcode Cloud may not list yet."""
    path = Path(folder) / "starts"
    return len(path.read_text().splitlines()) if path.exists() else 0


# The gates. Each takes what it decides on and returns the decision, so the tests drive it with
# fixtures.

def night_window(now):
    """(cutoff, stop) for a night whose cards start at `now`, or None from 5 am to midnight."""
    if now.hour >= CUTOFF_HOUR:
        return None
    day = now.replace(minute=0, second=0, microsecond=0)
    return day.replace(hour=CUTOFF_HOUR), day.replace(hour=STOP_HOUR)


def usage_gate(rows, age, now, stop, taken):
    """None when usage leaves room for one more card, else why not. rows are plan_windows()'s, age
    how old usage.json is, and taken the cards started tonight.

    Every window counts, whatever its label; one whose reset has passed counts as fresh. The
    night is uncapped when every weekly window resets after now and by `stop`: the night before
    the weekly reset. A weekly reset already past starts a new week, which a night doesn't spend.
    """
    if isinstance(rows, str):
        return f"usage is unknown: {rows}"
    if age is None or age > USAGE_FRESH:
        return f"usage is unknown: {USAGE} is over {USAGE_FRESH.seconds // 60} minutes old"
    read = []
    for label, used, resets in rows:
        try:
            # To the minute: the tool's reset times carry stray milliseconds (07:00:00.066).
            read.append((label, used, when(resets).astimezone().replace(second=0, microsecond=0)))
        except (TypeError, ValueError, AttributeError):
            return f"usage is unknown: the window {label} has no reset time ({resets!r})"
    weekly = [resets for label, _, resets in read if "week" in label.lower()]
    uncapped = bool(weekly) and all(now < resets <= stop for resets in weekly)
    for label, used, resets in read:
        if resets <= now:
            continue
        state = f"{label} at {used:g}%, resetting {resets:%a %H:%M}"
        if used >= USAGE_STOP:
            return state
        if uncapped and "week" not in label.lower() and resets > stop and used >= MORNING_RESERVE:
            return f"{state}; keeping {MORNING_RESERVE}% of it for the morning"
    if not uncapped and taken >= CAPPED_CARDS:
        return f"{taken} cards tonight, the limit on a night the weekly limit doesn't reset"
    return None


def xcode_major(text):
    """The major version of the first "Xcode <version>" in text ("Xcode 27.1" gives "27"), or None."""
    match = re.search(r"Xcode (\d+)", text or "")
    return match.group(1) if match else None


def last_review(folder):
    """(month, Xcode major) of the newest setup review's report in folder, or None. The report's
    name holds its date and its first line the Xcode it ran on (.claude/skills/review-setup/), so a
    review run by hand counts too."""
    reports = sorted(Path(folder).glob("report-20[0-9][0-9]-[0-9][0-9]-[0-9][0-9].md"))
    if not reports:
        return None
    first = reports[-1].read_text(errors="replace").split("\n", 1)[0]
    return reports[-1].stem.removeprefix("report-")[:7], xcode_major(first)


def review_tries(retro, now):
    """How many nights this month started a setup review: the night folders in .build/retro/ whose
    notes say its phase opened (a due review that couldn't run guarded is "review_blocked")."""
    tries = 0
    for path in Path(retro).glob(f"{now:%Y-%m}-[0-9][0-9]/{NOTES}"):
        try:
            tries += "review" in json.loads(path.read_text())
        except (OSError, ValueError, TypeError):
            continue
    return tries


def review_due(last, now, xcode, tries=0):
    """Why the setup review runs tonight, or None: once a month, at the first night with none
    yet, and again once a newer major Xcode is installed. Only at night, like the cards. A review
    that wrote no report (a usage limit, the time cap) is tried once more, the next night."""
    if not night_window(now) or tries >= REVIEW_TRIES:
        return None
    if last is None:
        return "no review has run yet"
    month, major = last
    if month != f"{now:%Y-%m}":
        return f"none has run in {now:%B %Y} yet"
    # Newer only: switching to a beta and back starts one review, not two.
    if xcode and major and int(xcode) > int(major):
        return f"Xcode {xcode} is installed since the last review, on Xcode {major}"
    return None


def last_review_date(folder):
    """The date of the newest setup review's report in folder, YYYY-MM-DD, or None: the review's
    tally starts there, as the skill's "Collect" does."""
    reports = sorted(Path(folder).glob("report-20[0-9][0-9]-[0-9][0-9]-[0-9][0-9].md"))
    return reports[-1].stem.removeprefix("report-") if reports else None


def review_parts(last, now, trials):
    """The setup review's tally as (heading, since) parts: since its last report, else over the last
    TALLY_DAYS (the skill looks back a month with none), then one per row on trial, since its date.
    trials is [(role, model, set)], or a string saying why the table wasn't read."""
    since = last or f"{now - timedelta(days=TALLY_DAYS):%Y-%m-%d}"
    parts = [(f"Since the last setup review, {last}:" if last else
              f"No setup review's report yet, so over the last {TALLY_DAYS} days:", since)]
    if isinstance(trials, str):
        return parts + [(f"Trials not read: {trials}", None)]
    return parts + [(f"Trial: {role} on {model}, {set_}; since its start:", set_[:10]) for role, model, set_ in trials]


def write_tallies(folder, wanted, fetch, tally):
    """Writes each file in wanted ({name: [(heading, since)]}) to the night's folder, from one fetch
    since the earliest date (scripts/agent-record.py's fetch and tally), so the night spends one set
    of GitHub requests. A part whose since is None is its heading alone. Any failure writes one line
    to each file, "No tally tonight: <why>", never an empty file, and never stops the night."""
    dates = [since for parts in wanted.values() for _, since in parts if since]
    try:
        prs, cost, remaining = fetch(min(dates))
        texts = {}
        for name, parts in wanted.items():
            blocks = ["\n".join(filter(None, [heading, since and tally(
                [p for p in prs if (p.get("mergedAt") or "")[:10] >= since], since)])) for heading, since in parts]
            texts[name] = "\n\n".join(blocks) + (f"\n\nOne fetch, since {min(dates)}, cost {cost} GraphQL "
                                                 f"points; {remaining} left this hour.\n")
    except Exception as error:  # noqa: BLE001 - a tally must never stop the night, whatever went wrong
        why = f"{type(error).__name__}: {error}"
        if isinstance(error, subprocess.CalledProcessError):
            said = (error.stderr or "").strip().splitlines()
            why = f"{' '.join(error.cmd[:3])} failed: {said[-1] if said else 'no output'}"
        elif isinstance(error, subprocess.TimeoutExpired):  # its text holds the whole query
            why = f"GitHub's answers took over {error.timeout:.0f} s"
        texts = dict.fromkeys(wanted, f"No tally tonight: {why}\n")
    for name, text in texts.items():
        (Path(folder) / name).write_text(text)
    return texts


def agent_record():
    """scripts/agent-record.py as a module, whose name has a dash."""
    spec = importlib.util.spec_from_file_location("agent_record", ROOT / "scripts/agent-record.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def trial_rows(record):
    """[(role, model, set)] of the "Models by task" rows on trial, or why the table wasn't read."""
    try:
        models = record.models()
        rows = models.table((ROOT / models.TABLE).read_text())
    except FAILURES as error:
        return f"{type(error).__name__}: {error}"
    return [(row["Role"], row["Model"], row["Set"]) for row in rows if "trial" in row["Set"]]


def protected(files):
    return [f for f in files if any(fnmatch.fnmatch(f, p) for p in PROTECTED)]


def day_only(files):
    return bool(files) and all(f.startswith(DAY_ONLY) for f in files)


def section(body, heading):
    match = re.search(rf"^## {re.escape(heading)}\s*\n(.*?)(?=^## |\Z)", body, re.M | re.S)
    return match[1].strip() if match else ""


def eligibility(status, feature, body):
    """None when a night may take the card, else why not."""
    if status != "Definitely":
        return f"it is in {status}"
    if feature != "-":
        return "it is a slice of a feature"
    if not re.search(r"^Nightly:\s*\S", body, re.M):
        return "it has no Nightly: line"
    if not (section(body, "Acceptance criteria") or section(body, "Success")):
        return "it has no check for the verifier"
    return None


def likely_files(body, repo_files):
    """The repo's files and folders the card names in backticks."""
    names = set()
    for token in re.findall(r"`([^`\n]+)`", body):
        path = token.split()[0].lstrip("(").rstrip(".,:;)/") if token.split() else ""
        if path in repo_files:
            names.add(path)
        elif path and any(f.startswith(path + "/") for f in repo_files):
            names.add(path + "/")
    return names


def clash_files(pr):
    """The files of an open PR a card may collide with: all of them, but a retro PR's Markdown
    under .claude/ and docs/. The retro's PR stays open until a day session merges it, often a
    day, and edits the rules there, so counting them would hold back every card naming one."""
    files = [f["path"] for f in pr["files"]]
    if pr["title"].startswith(RETRO_TITLE):
        return [f for f in files if not (f.endswith(".md") and f.startswith(DAY_ONLY))]
    return files


def overlap(likely, files):
    return sorted(f for f in files for name in likely
                  if f == name or (name.endswith("/") and f.startswith(name)))


def update_cards(outdated, rows):
    """[(title, body)] of the card for each tool `scripts/lint-tools.sh outdated` names, "<tool>
    <pinned> <latest>" a line, that the board has none for: none by its title, in any status, and
    no other "Update <tool> to" card still open. rows are board_rows()'s."""
    cards = []
    for line in outdated.splitlines():
        tool, pinned, latest = line.split()
        title = f"Update {tool} to {latest}"
        if any(t == title or (t.startswith(f"Update {tool} to ") and status != "Done")
               for _, status, _, t in rows):
            continue
        cards.append((title, UPDATE_CARD.format(tool=tool, pinned=pinned, latest=latest)))
    return cards


UPDATE_CARD = """## Problem
`scripts/lint-tools.sh` pins {tool} {pinned}, and {latest} is its latest release. Dependabot can't
read that pin, so the nightly run made this card from `scripts/lint-tools.sh outdated`.

## Acceptance criteria
- `scripts/lint-tools.sh` pins {tool}'s latest release ({latest} when this card was made) with its
  release asset's SHA-256, and `scripts/lint-tools.sh outdated` no longer names {tool}.
- `scripts/lint.sh` passes on the whole repo: what the new version finds is fixed, or its rule is
  turned off in `.swiftformat` or `.swiftlint.yml` with a comment saying why.

Nightly: lint runs the tool's latest release; `scripts/lint-tools.sh outdated` stops naming it

## Plan
Standalone tooling. Raise the pin as the header of `scripts/lint-tools.sh` says, run
`scripts/lint.sh --fix`, and fix what is left. The PR touches a protected path, so it waits for
the maintainer.
"""


def xcode_cloud_gate(month_hours, runs, needed=1):
    """None, or why `needed` more Xcode Cloud runs can't start tonight: one for a push or a new
    PR, EXPECTED_RUNS for a card that may change the app, so it isn't built only to be refused
    its push."""
    if month_hours > HOURS_LIMIT:
        return f"{month_hours:.1f} Xcode Cloud hours this month, above {HOURS_LIMIT}"
    if runs + needed > RUN_LIMIT:
        return (f"{runs} Xcode Cloud runs tonight, the night's limit" if needed == 1 else
                f"{runs} Xcode Cloud runs tonight, and a card that may change the app needs room for "
                f"{needed} of the night's {RUN_LIMIT}")
    return None


def month_hours(runs, now):
    """Hours of this calendar month's (UTC) PR runs, a run still going counted up to now."""
    start = now.astimezone(timezone.utc).replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    total = timedelta()
    for run in runs:
        attributes = run["attributes"]
        if not attributes.get("startedDate") or when(attributes["startedDate"]) < start:
            continue
        end = when(attributes["finishedDate"]) if attributes.get("finishedDate") else now
        total += end - when(attributes["startedDate"])
    return total.total_seconds() / 3600


def runs_since(runs, since):
    return [r for r in runs if when(r["attributes"]["createdDate"]) >= since]


def runs_tonight(runs, since, folder):
    """Tonight's Xcode Cloud runs: those it lists, or the starts the hooks allowed, which it may
    not list yet, whichever is more."""
    return max(len(runs_since(runs, since)), start_count(folder))


def verifier_record(comments):
    """(hash, failures, unread) of the newest "Verifier record" comment, or None when there is none.

    Strict, so a misspelled failure never reads as a pass: unread holds every line that is
    neither `- <kind>, <new|known>: ...` nor `- No findings`, and a record with no lines.
    """
    records = [c for c in comments if c.startswith("Verifier record")]
    if not records:
        return None
    header, *lines = records[-1].strip().splitlines()
    match = re.fullmatch(r"Verifier record, ([0-9a-f]{7,40})", header.strip())
    lines = [line.rstrip() for line in lines if line.strip()]
    kinds = [(line, RECORD_LINE.match(line)) for line in lines]
    failures = [line for line, match in kinds if match and match[1] in ("criterion", "crash")]
    unread = [line for line, match in kinds if not match and line != "- No findings"]
    return (match[1] if match else None), failures, unread or ([] if lines else ["(no lines)"])


def only_tests(files):
    """Whether these files are all in the test targets, where a verifier adds tests after its build."""
    return all(f.startswith(tuple(d + "/" for d in TEST_DIRS)) for f in files)


def test_drops(before, after):
    return [(t, before[t], after.get(t, 0)) for t in sorted(before) if after.get(t, 0) < before[t]]


def unexplained_drops(drops, body):
    """The drops no line of the PR body explains: one starting "Fewer tests:" that names the target."""
    lines = [line for line in body.splitlines() if line.startswith(FEWER_TESTS)]
    return [d for d in drops if not any(re.search(rf"\b{re.escape(d[0])}\b", line) for line in lines)]


# Comments and string literals, in one pass so that whichever starts first wins: `//` in a string
# is no comment, and a quote in a comment starts no string.
SWIFT_NOISE = re.compile(r'//[^\n]*|/\*.*?\*/|"""(?:.|\n)*?"""|"(?:\\.|[^"\\\n])*"', re.S)


DISABLED = re.compile(r"\.disabled\b|\.enabled\(\s*if:\s*false\s*\)")


def block(code, start):
    """(open, end) of the first { } block at or after start, braces nested."""
    first, depth = code.find("{", start), 0
    if first < 0:
        return len(code), len(code)
    for i in range(first, len(code)):
        depth += {"{": 1, "}": -1}.get(code[i], 0)
        if depth == 0:
            return first, i + 1
    return first, len(code)


def without_dead_code(code):
    """The code without `#if false` (or `0`) blocks, an `#else` branch kept."""
    kept, depth = [], 0
    for line in code.split("\n"):
        directive = line.strip()
        if depth:
            if directive.startswith("#if"):
                depth += 1
            elif directive.startswith("#endif"):
                depth -= 1
            elif directive.startswith(("#else", "#elseif")) and depth == 1:
                depth = 0
            continue
        if re.fullmatch(r"#if\s+(false|0)\b.*", directive):
            depth = 1
        else:
            kept.append(line)
    return "\n".join(kept)


def count_tests(source):
    """The tests in a Swift file that run, so a test commented out or disabled counts as dropped:
    one in a comment or `#if false`, an `@Test` or `@Suite` with `.disabled` or `.enabled(if:
    false)`, and an XCTest that throws XCTSkip (XCTSkipIf too, whose condition a reader can't
    know). A heuristic: a nested block comment, a raw string, or a condition only known at run
    time (`#if SOME_FLAG`, `.enabled(if: x)`) can fool it, which a reviewer of the PR sees."""
    code = without_dead_code(SWIFT_NOISE.sub("", source))
    for suite in reversed(list(re.finditer(r"@Suite\b", code))):
        first, end = block(code, suite.end())
        if DISABLED.search(code[suite.end():first]):
            code = code[:suite.start()] + code[end:]
    count = 0
    for test in re.finditer(TEST_PATTERN, code):
        if test[0].startswith("@Test"):
            declared = re.compile(r"\bfunc\b").search(code, test.end())
            disabled = DISABLED.search(code[test.end():declared.start() if declared else len(code)])
        else:
            disabled = "XCTSkip" in code[slice(*block(code, test.end()))]
        count += not disabled
    return count


# What a card may still run past 7 am: reading, and committing what builds.
SAFE_LATE = {"cd", "ls", "cat", "head", "tail", "grep"}
SAFE_LATE_GIT = {"add", "commit", "status", "diff", "log", "show", "rev-parse"}
# shlex keeps a run of punctuation as one token (`$(cat x); y` ends `cat` with ");", `(a)>f`
# with ")>"): each such token is read as its separators and redirections.
PUNCTUATION = re.compile(r"&?\d?[<>]+&?|[;&|()]")
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
INTERPRETERS = re.compile(r"python[\d.]*|node|perl|ruby|osascript")
# Interpreter options whose value is the next word, not a script file.
INTERPRETER_VALUES = {"python": {"-W", "-X", "-Q"}, "node": {"-r", "--require", "--import", "--loader"},
                      "perl": {"-I", "-M", "-m"}, "ruby": {"-I", "-r", "-C"}, "osascript": {"-l", "-i"}}
WRAPPERS = {"env", "command", "exec", "nohup", "time", "xargs", "nice", "timeout", "caffeinate"}
WRAPPER_VALUES = {"-u", "-n", "-I", "-L", "-P", "-S", "-C", "-s"}  # wrapper options that take a value
GIT_VALUE_OPTIONS = {"-c", "-C", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
# asc xcode-cloud words that start a build or change a workflow or product.
ASC_CHANGES = {"run", "create", "update", "duplicate", "delete"}
MERGE_PATH = re.compile(r"(^|/)merges?($|[/?])")
PR_PATH = re.compile(r"(^|/)(pulls|git/refs)($|[/?])")  # opening a PR, or moving a branch, through the API
API_WRITES = {"-f", "-F", "--field", "--raw-field", "--input", "-X", "--method"}


def without_heredocs(command):
    """The command line without its heredocs' bodies, which are text, not commands."""
    kept, end = [], None
    for line in command.split("\n"):
        if end is not None:
            if line.strip() == end:
                end = None
            continue
        kept.append(line)
        match = re.search(r"(?<!<)<<(?!<)-?\s*(['\"]?)(\w+)\1", line)
        end = match[2] if match else None
    return "\n".join(kept)


def commands(command, depth=0, targets=False):
    """Each simple command in a shell command line, as its words, with those `bash -c`, `eval`,
    `$(...)`, and backticks run. A line shlex can't split is read again without its quotes, which
    finds more commands, never fewer. With targets, a redirection's file is kept as a word, after
    its direction: `>file` or `<file`."""
    # A newline ends a command; inside quotes the added ";" changes only this reading of the text.
    text = without_heredocs(command).replace("\n", " ; ")
    lexer = shlex.shlex(text, posix=True, punctuation_chars=";&|()<>")
    lexer.whitespace_split, lexer.commenters = True, ""
    try:
        tokens = list(lexer)
    except ValueError:
        return (commands(re.sub(r"[\"'\\]", " ", text), depth + 1, targets) if depth < 3
                else [text.split()])
    found, words, redirect = [], [], None
    pieces = [p for t in [*tokens, ";"] for p in (
        PUNCTUATION.findall(t) if re.fullmatch(f"(?:{PUNCTUATION.pattern})+", t) else [t])]
    for token in pieces:
        if redirect:
            # `>&` and `2>&` duplicate a descriptor: what follows is a number, not a file.
            if targets and not redirect.endswith("&"):
                words.append((">" if ">" in redirect else "<") + token)
            redirect = None
        elif token in {";", "&", "|", "(", ")"}:
            if words:
                found.append(words)
            words = []
        elif PUNCTUATION.fullmatch(token):
            redirect = token
        else:
            words.append(token)
    if depth >= 3:
        return found
    # Substitutions anywhere in the line, quoted or not; shlex keeps an unquoted backtick in its word.
    inner = [a or b for a, b in re.findall(r"\$\(([^()]*)\)|`([^`]*)`", text)]
    for words in found:
        for i, word in enumerate(words):
            after = words[i + 1:]
            code = shell_code(after) if word.rsplit("/", 1)[-1] in SHELLS else None
            if code is not None:
                inner.append(code)
            if word == "eval":
                inner.append(" ".join(after))
    return found + [words for text in inner for words in commands(text, depth + 1, targets)]


def shell_code(args):
    """The code a shell runs with -c, its options before it whatever they are, or None."""
    i = 0
    while i < len(args) and args[i][:1] in ("-", "+"):
        if re.fullmatch(r"-\w*c\w*", args[i]):
            return args[i + 1] if i + 1 < len(args) else ""
        i += 2 if args[i] in ("-o", "+o", "-O", "+O") else 1  # set -o takes the option's name
    return None


def program(words):
    """(name, args) of the program a simple command runs, past assignments and wrappers such as
    env, xargs, and timeout, with their options."""
    i = 0
    while i < len(words):
        word, name = words[i], words[i].rsplit("/", 1)[-1]
        if name == "command" and words[i + 1:i + 2] in (["-v"], ["-V"]):
            return name, words[i + 1:]  # only looks a program up
        if re.fullmatch(r"\w+=.*", word) or name in WRAPPERS:
            i += 1
        elif i and (word.startswith("-") or re.fullmatch(r"[\d.]+[smhd]?", word)):
            i += 2 if word in WRAPPER_VALUES else 1
        else:
            return name, words[i + 1:]
    return "", []


def runs_inline_code(words):
    """Whether a simple command runs a shell or an interpreter on code that isn't a file: `python3
    -c`, `node -e`, `perl -e`, or code read from stdin (a pipe, a heredoc, a here-string). A
    shell's `-c` is allowed, since commands() reads its code."""
    name, args = program(words)
    if name in SHELLS:
        if shell_code(args) is not None:
            return False
        return "-s" in args or not [a for a in args if not a.startswith("-")]
    if not INTERPRETERS.fullmatch(name):
        return False
    inline = r"-[a-zA-Z]*c" if name.startswith("python") else r"-[a-zA-Z]*[eE]|-p"
    takes_value = INTERPRETER_VALUES["python" if name.startswith("python") else name]
    skip = False
    for arg in args:
        if skip:
            skip = False
            continue
        if arg in takes_value:
            skip = True
            continue
        if arg == "-" or re.match(inline, arg) or arg.split("=")[0] in ("--eval", "--print"):
            return True
        if arg == "-m" and name.startswith("python"):
            return False
        if not arg.startswith("-"):
            return False  # a script file
    return True  # no script file: it reads stdin


def tool_args(words, name):
    """The words after the first one that runs `name`, wherever it sits (after env, time, xargs,
    an assignment, as a path), or None when none does."""
    for i, word in enumerate(words):
        if word.rsplit("/", 1)[-1] == name:
            return words[i + 1:]
    return None


def git_call(args):
    """(options, subcommand, rest) of git's arguments."""
    i = 0
    while i < len(args) and args[i].startswith("-"):
        i += 2 if args[i] in GIT_VALUE_OPTIONS else 1
    return args[:i], (args[i] if i < len(args) else ""), args[i + 1:]


def positionals(args):
    """gh's words that aren't flags, past its -R/--repo and their values."""
    words, i = [], 0
    while i < len(args):
        if args[i] in ("-R", "--repo"):
            i += 2
            continue
        if not args[i].startswith("-"):
            words.append(args[i])
        i += 1
    return words


def call_risks(command):
    """(never, starts): why a command is never allowed at night, else None, and what in it may
    start an Xcode Cloud run: "push", "pr" (a PR opened, reopened, or made ready, or a branch
    moved through the API), or None.

    It reads what the command line shows. A push from a script or another program still meets
    the pre-push hook in the card worktree's git config, and a merge `decide`'s check of the PR.
    """
    starts = None
    for words in commands(command):
        if hooks_off(words):
            return ("The night's git hooks stay on: no --no-verify, core.hooksPath, extensions.worktreeConfig, "
                    "git config written, GIT_CONFIG_* changed, or environment cleared."), None
        if runs_inline_code(words):
            return ("At night no shell or interpreter runs inline or piped code (python3 -c, node -e, "
                    "perl -e, | sh, a heredoc or here-string into a shell): write the script to a file "
                    "in the worktree and run that."), None
        git = tool_args(words, "git")
        if git is not None and git_call(git)[1] == "push":
            starts = starts or "push"
        gh = tool_args(words, "gh")
        if gh is not None:
            group, *rest = positionals(gh) or [""]
            # gh's command words are written out, so the checks below read what gh will run.
            spelled = [group] + (rest[:1] if group != "api" else [])
            if group and not all(re.fullmatch(r"[a-z][a-z-]*", w) for w in spelled):
                return "At night gh's command words are written out in full: no variables or globs.", None
            if group == "pr" and rest[:1] == ["merge"]:
                return "The night arms auto-merge itself, once the verifier has passed. Never merge.", None
            # A query read from a file or stdin can't be checked, so it counts as a mutation.
            mutation = "graphql" in rest and ("--input" in gh or any(
                re.search(r"mutation|=@|^@", w, re.I) for w in gh))
            if group == "api" and (mutation or any(MERGE_PATH.search(w) for w in rest)):
                return ("Never merge, and no GraphQL mutation or merge endpoint through gh api: the "
                        "night arms auto-merge itself."), None
            if group == "alias" and rest[:1] in (["set"], ["import"]):
                return "The night defines no gh aliases.", None
            if (group == "pr" and rest[:1] in (["create"], ["ready"], ["reopen"])) or (
                    group == "api" and API_WRITES & set(gh) and any(PR_PATH.search(w) for w in rest)):
                starts = "pr"
        if (tool_args(words, "board.sh") or [""])[0] in ("status", "move"):
            return "The night moves its card itself, once `decide` has decided it: no board status or move.", None
        asc = tool_args(words, "asc")
        if asc is not None and "xcode-cloud" in asc:
            after = asc[asc.index("xcode-cloud") + 1:]
            if ASC_CHANGES & {w for w in after if not w.startswith("-")}:
                return ("No Xcode Cloud run is started, and no workflow or product changed, at night: "
                        "a push to the PR starts its run."), None
        # asc's raw API: anything but a GET writes to App Store Connect.
        asc_words = [w for w in asc or [] if not w.startswith("-")]
        if "api" in asc_words and [w.upper() for w in asc_words[asc_words.index("api") + 1:][:1]] != ["GET"]:
            return "At night asc api only reads: GET, never POST, PATCH, or DELETE.", None
    return None, starts


def hooks_off(words):
    """Whether a simple command may turn off the night's pre-push hook: git's --no-verify,
    core.hooksPath or extensions.worktreeConfig (which git needs to read the hook from the
    worktree's config), any `git config` that writes, a GIT_CONFIG_* variable set or removed, or
    the environment cleared. A card's work changes no git config."""
    if any(re.search(r"--no-ver", w) for w in words):
        return True
    git = tool_args(words, "git")
    if git is not None and (any(re.search("hookspath|worktreeconfig", w, re.I) for w in words)
                            or config_write(git)):
        return True
    if any(re.match(r"GIT_CONFIG\w*=", w) for w in words):
        return True
    return words[0].rsplit("/", 1)[-1] in ("env", "unset", "export", "declare", "typeset") and bool(
        any(w.startswith("GIT_CONFIG") for w in words) or {"-i", "-", "--ignore-environment"} & set(words))


CONFIG_READS = {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "--get-color", "--get-colorbool",
                "--list", "-l"}


def config_write(git):
    """Whether git's arguments are a `git config` that may write: any but one marked a read by
    its options (--get, --list) or its first word (get, list). A key alone, a read too, is
    denied with the rest: a net, not a parser of git's options."""
    _, sub, args = git_call(git)
    words = [a for a in args if not a.startswith("-")]
    return sub == "config" and not (CONFIG_READS & set(args) or words[:1] in (["get"], ["list"]))


def script_call(words):
    """(script, args) of the file a simple command runs, directly or through an interpreter past
    its options and their values; ("", []) when it runs none."""
    name, args = program(words)
    if not INTERPRETERS.fullmatch(name):
        return next((w for w in words if w.rsplit("/", 1)[-1] == name), ""), args
    takes_value, i = INTERPRETER_VALUES["python" if name.startswith("python") else name], 0
    while i < len(args) and args[i].startswith("-"):
        i += 2 if args[i] in takes_value else 1
    return (args[i], args[i + 1:]) if i < len(args) else ("", [])


def night_step(words):
    """Whether a simple command runs a copy of this script with one of the night's steps."""
    script, args = script_call(words)
    return script.rsplit("/", 1)[-1] == "nightly-tooling.py" and args[:1] != [] and args[0] in NIGHT_STEPS


def safe_late(words):
    if words[0] in SAFE_LATE:
        return True
    return tool_args(words[:1], "git") is not None and git_call(words[1:])[1] in SAFE_LATE_GIT


class Fence:
    """Where a card's agents may write: its worktree, the session's own folder on the card's
    branch, but not its Claude Code settings, which the running session reloads, or its .git
    file. What a command
    names may not be the night's own files: the main checkout (the scripts and guard that judge
    the card, the night's folder, git's config), this script's own checkout, or a dotfile in the
    home folder (gh's, git's, Claude Code's, and asc's config)."""

    def __init__(self, worktree, main, night, cwd=None):
        self.cwd = self.real(cwd or worktree)
        worktree = self.real(worktree)
        self.main = self.real(main)
        self.writable = [worktree]
        # And not its .git file, which ties the folder to its git config and the pre-push hook there.
        self.live = [worktree / ".claude/settings*.json", worktree / ".mcp.json", worktree / ".git"]
        self.home = self.real("~")
        self.guarded_roots = [self.main, self.real(ROOT), self.real(night), self.home / "Library/LaunchAgents"]

    @staticmethod
    def real(path, cwd=None):
        path = re.sub(r"^(\$HOME|\$\{HOME\})(?=/|$)", "~", str(path))
        path = Path(os.path.expanduser(path))
        return Path(os.path.realpath(path if path.is_absolute() or cwd is None else cwd / path))

    def resolve(self, path, cwd=None):
        return self.real(path, cwd or self.cwd)

    def may_write(self, path, cwd=None):
        path = self.resolve(path, cwd)
        return (any(path == root or root in path.parents for root in self.writable)
                and not any(fnmatch.fnmatch(str(path), str(live)) for live in self.live))

    def guarded(self, path, cwd=None):
        """Whether a path a command names is one of the night's own files."""
        if self.may_write(path, cwd):
            return False
        path = self.resolve(path, cwd)
        if any(path == root or root in path.parents for root in self.guarded_roots):
            return True
        return self.home in path.parents and path.relative_to(self.home).parts[0].startswith(".")

    def named(self, parsed):
        """The night's own files a Bash command names, in a word, an option's value, or a
        redirection; parsed is commands(command, targets=True). A word is read from every folder
        the shell may be in when it runs: the call's own, and each `cd` or `pushd` before it,
        since one in a subshell, a pipe, or `bash -c` moves nothing after it. A folder a reader
        can't know (a variable, a substitution, a glob, `cd -`) adds the main checkout, where
        the night's own files are."""
        found, folders = [], [self.cwd]
        for words in parsed:
            for word in words:
                for part in {word.lstrip("<>@"), word.split("=", 1)[-1].lstrip("<>@")}:
                    if (part.startswith(("/", "~", ".", "$HOME", "${HOME}")) or "/" in part) and any(
                            self.guarded(part, cwd) for cwd in folders):
                        found.append(part)
            if words[0] in ("cd", "pushd"):
                target = next((w for w in words[1:] if not w.startswith("-")), "~")
                unknown = words[1:2] == ["-"] or re.search(r"[`*?\[]|\$(?!HOME\b|\{HOME\})", target)
                moved = [self.main] if unknown else [self.real(target, cwd) for cwd in folders]
                folders = list(dict.fromkeys(folders + moved))
        return sorted(set(found))


def strings(value):
    """Every string in a tool call's input, however deep."""
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)


def hook_decision(tool, command, now, stop, handoff, run_gate, fence, path="", inputs=()):
    """None to allow a card's tool call, else the reason it's denied. `command` is a Bash call's,
    `path` an edit's file, `inputs` the strings in any other tool's input. run_gate(starts) is
    None when one more Xcode Cloud run fits tonight, else why not; it is called only for a call
    that may start one."""
    late = now >= stop
    late_reason = (f"It is past {STOP_HOUR} am, so the night starts nothing new. Commit what builds, "
                   f"write the handoff note to {handoff}, and end your turn.")
    fenced = ("At night a card writes only in its worktree, the session's own folder (its handoff and "
              "scratch files in .slices/ there), and no command names the night's own files (the main "
              "checkout, its scripts, the night's folder, git's, gh's, asc's, or Claude Code's config): ")
    if tool in ("Edit", "Write", "NotebookEdit"):
        if not fence.may_write(path):
            return fenced + path
        return late_reason if late and fence.resolve(path) != fence.resolve(handoff) else None
    if tool != "Bash":
        named = [s for s in inputs if s.startswith(("/", "~")) and fence.guarded(s)]
        if named:
            return fenced + ", ".join(named)
        return late_reason if late else None
    never, starts = call_risks(command)
    if never:
        return never
    parsed = commands(command, targets=True)
    if any(night_step(words) for words in parsed):
        return ("During a card only the night's lead runs the night's steps, from the main checkout's "
                "script, never a worktree's copy.")
    named = fence.named(parsed)
    if named:
        return fenced + ", ".join(named)
    writes = [w for words in parsed for w in words if w.startswith(">") and w != ">/dev/null"]
    if late and (starts or writes or not all(safe_late(words) for words in parsed)):
        return late_reason
    if starts:
        why = run_gate(starts)
        if why:
            return (f"This would start an Xcode Cloud run, and {why}. Don't push or open the PR: park "
                    "the card, saying so in your last line.")
    return None


CLOSING = {"decide", "review-end", "digest", "outcome"}  # the lead's own steps, run whatever the hour


def closing(command, cwd, main):
    """Whether a Bash command is one of the lead's closing steps: one simple command, with no
    substitution or redirection, running the main checkout's scripts/nightly-tooling.py with one
    of CLOSING."""
    parsed = commands(command, targets=True)
    if len(parsed) != 1 or any(w[:1] in "<>" for w in parsed[0]) or hooks_off(parsed[0]):
        return False
    script, args = script_call(parsed[0])
    where = Fence.real(script, Path(cwd or main))
    return where == Fence.real(Path(main) / SCRIPT) and args[:1] != [] and args[0] in CLOSING


def review_decision(tool, command, path, now, deadline, reports, cwd):
    """None to allow a call during the setup review, else why not: it writes its report and cards
    only (.claude/skills/review-setup/), and past its deadline only the report."""
    report = tool == "Write" and Fence.real(reports) in Fence.real(path, Path(cwd or reports)).parents
    if now >= deadline:
        return None if report else (f"The setup review's time is up: write the report in {reports}/ "
                                    "now, or end your turn.")
    if tool in ("Edit", "NotebookEdit"):
        return "The setup review edits nothing: it writes its report and cards only."
    if tool == "Write" and not report:
        return f"The setup review writes only its report, in {reports}/."
    if tool != "Bash":
        return None
    for words in commands(command):
        git, gh = tool_args(words, "git"), tool_args(words, "gh")
        if git is not None and git_call(git)[1] in ("push", "commit"):
            return "The setup review never commits or pushes: it cards each change."
        if gh is not None and positionals(gh)[:1] == ["pr"] and positionals(gh)[1:2] in (
                ["merge"], ["create"], ["edit"], ["close"]):
            return "The setup review opens, edits, and merges no PR: it cards each change."
        if tool_args(words, "brew") is not None or tool_args(words, "asc") is not None:
            return "The setup review runs no brew or asc: it reads release notes and cards each change."
    return None


def digest_block(pr, sha, files, proof):
    areas = sorted({"/".join(f.split("/")[:2]) if f.startswith("Packages/") else f.split("/")[0]
                    for f in files})
    return f"#{pr['number']} {pr['title']} — {sha[:7]} — {', '.join(areas)} — {proof} — undo: git revert {sha[:7]}"


# The world: git, gh, asc, and the board.

def sh(*args, cwd=ROOT, stdin=None, check=True, timeout=None):
    result = subprocess.run(args, cwd=cwd, input=stdin, capture_output=True, text=True, timeout=timeout)
    if check and result.returncode != 0:
        raise RuntimeError(f"{' '.join(args)}: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout


def gh_json(*args):
    return json.loads(sh("gh", *args))


def disable_auto(n):
    """Turns a PR's auto-merge off, and makes sure: gh fails on a PR that has none to turn off,
    so the check reads the PR again rather than trusting gh's exit."""
    sh("gh", "pr", "merge", str(n), "--disable-auto", check=False)
    if sh("gh", "pr", "view", str(n), "--json", "autoMergeRequest", "--jq", ".autoMergeRequest != null").strip() == "true":
        raise RuntimeError(f"auto-merge is still on for #{n}")


def board_rows():
    """[(id, status, feature, title)] of every item, in board order: one list request."""
    rows = []
    for line in sh(str(ROOT / "scripts/board.sh"), "list").splitlines():
        head, feature, title = line.split("\t", 2)
        item, status = head.split(None, 1)
        rows.append((item, status.strip(), feature, title))
    return rows


def board_bodies(rows):
    """[(id, status, feature, title, body)] of rows: one show request."""
    if not rows:
        return []
    shown = sh(str(ROOT / "scripts/board.sh"), "show", *[r[0] for r in rows][:100])
    # show prints a "==> id <==" header before each card only when it shows more than one.
    bodies = (dict(re.findall(r"^==> (\S+) <==\n(.*?)(?=^==> |\Z)", shown, re.M | re.S))
              if len(rows) > 1 else {rows[0][0]: shown})
    return [(*r, bodies.get(r[0], "")) for r in rows]


def board_cards(rows):
    """[(id, status, feature, title, body)] of the standalone Definitely cards in rows: one show request."""
    return board_bodies([r for r in rows if r[1] == "Definitely" and r[2] == "-"])


def left_pr(body):
    """The PR a night parked or left waiting, as the card's State names it, else None."""
    match = re.search(r"PR #(\d+) (?:is a draft with auto-merge off|waits for the maintainer)",
                      section(body, "State"))
    return int(match[1]) if match else None


def board(*args, stdin=None):
    return sh(str(ROOT / "scripts/board.sh"), *args, stdin=stdin)


def classify(files):
    return sh(str(ROOT / "scripts/pr-check.sh"), "classify", stdin="\n".join(files) + "\n",
              timeout=READ_TIMEOUT).strip()


def outdated_tools():
    """`scripts/lint-tools.sh outdated`, which asks GitHub for each lint tool's latest release.
    A tool whose release can't be read fails the command; the others' lines still print."""
    return subprocess.run([str(ROOT / "scripts/lint-tools.sh"), "outdated"], cwd=ROOT,
                          capture_output=True, text=True, timeout=READ_TIMEOUT)


def xcode_cloud_runs(limit=200):
    out = sh("asc", "xcode-cloud", "build-runs", "--workflow-id", PR_WORKFLOW, "--sort", "-number",
             "--limit", str(limit), timeout=READ_TIMEOUT)
    return json.loads(out)["data"]


def test_counts(rev):
    """Tests per test target at a revision, read from one archive of its Swift test files."""
    swift = [p for p in sh("git", "ls-tree", "-r", "--name-only", rev, "--", *TEST_DIRS).splitlines()
             if p.endswith(".swift")]
    if not swift:
        return {}
    import io
    import tarfile

    tar = subprocess.run(["git", "archive", "--format=tar", rev, "--", *swift], cwd=ROOT,
                         capture_output=True, check=True).stdout
    counts = {}
    with tarfile.open(fileobj=io.BytesIO(tar)) as archive:
        for member in archive.getmembers():
            if member.isfile():
                parts = member.name.split("/")
                target = parts[2] if parts[0] == "Packages" else parts[0]
                source = archive.extractfile(member).read().decode(errors="replace")
                counts[target] = counts.get(target, 0) + count_tests(source)
    return counts


def main_checkout():
    """The main checkout, where .slices/, .build/retro/, and the worktrees live, from any worktree."""
    return Path(sh("git", "rev-parse", "--path-format=absolute", "--git-common-dir").strip()).parent


def night_dir(now):
    """Tonight's folder, the main checkout's, wherever the session runs: the app may start it in a
    worktree of its own."""
    return main_checkout() / ".build/retro" / f"{now:%Y-%m-%d}"


def slug(title):
    words = re.findall(r"[a-z0-9]+", title.lower())
    return "night-" + "-".join(words[:6])


def branch_name(title):
    """A branch whose name no branch or PR has used, so an earlier card's PR can never be read as
    this one's."""
    name = slug(title)
    used = set(sh("git", "for-each-ref", "--format=%(refname:lstrip=-1)", "refs/heads",
                  "refs/remotes/origin").split())
    used |= {pr["headRefName"] for pr in gh_json("pr", "list", "--state", "all", "--search",
                                                 f"head:{name}", "--json", "headRefName")}
    branch, n = name, 2
    while branch in used:
        branch, n = f"{name}-{n}", n + 1
    return branch


def session_folder():
    """The checkout the night's session runs in: its shell's, where the lead runs each step."""
    return Path(sh("git", "rev-parse", "--show-toplevel", cwd=Path.cwd()).strip()).resolve()


def git_status(folder):
    return sh("git", "-C", str(folder), "status", "--porcelain").strip()


class NoCard(Exception):
    """Why no card, or no setup review, starts, found partway through starting it."""


class Night:
    """A night, kept in its folder, so each command the night's session runs reads what the last
    one wrote. A JSON file is replaced whole, so a reader never sees half of one."""

    def __init__(self, folder):
        self.dir = Path(folder).resolve()

    @property
    def main(self):
        """The main checkout, whose .build/retro/<date>/ this night's folder is."""
        return self.dir.parents[2]

    @property
    def script(self):
        return self.main / SCRIPT

    def read(self, name, empty):
        try:
            return json.loads((self.dir / name).read_text())
        except FileNotFoundError:
            return empty

    def write(self, name, value):
        self.dir.mkdir(parents=True, exist_ok=True)
        temporary = self.dir / f".{name}.tmp"
        temporary.write_text(json.dumps(value, indent=1) + "\n")
        os.replace(temporary, self.dir / name)

    def state(self):
        return self.read(STATE, {})

    def cards(self):
        return self.read(CARDS, [])

    def notes(self):
        return self.read(NOTES, {})

    def note(self, key, value):
        """Sets a note, or adds one to a list note when it isn't there yet."""
        notes = self.notes()
        if isinstance(value, list):
            notes[key] = notes.get(key, []) + [v for v in value if v not in notes.get(key, [])]
        else:
            notes[key] = value
        self.write(NOTES, notes)

    def set_state(self, **fields):
        self.write(STATE, {**self.state(), **fields})

    def start(self):
        return datetime.fromisoformat(self.state()["start"])

    def since(self):
        """The night's start, as GitHub's search reads a time."""
        return self.start().astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    def entry(self, item):
        found = [c for c in self.cards() if c["item"] == item]
        return found[-1] if found else None

    def update(self, item, **fields):
        cards = self.cards()
        for card in reversed(cards):
            if card["item"] == item:
                card.update(fields)
                break
        self.write(CARDS, cards)
        return self.entry(item)

    def branches(self):
        """The night's branches: the ones `next` made for its cards, and any other a card's
        worktree pushed, which its pre-push hook records. The maintainer's sessions use the same
        account, so a branch pushed tonight from elsewhere is no sign of the night's."""
        try:
            pushed = set((self.dir / PUSHED).read_text().split())
        except FileNotFoundError:
            pushed = set()
        return {c["branch"] for c in self.cards()} | pushed

    def seen(self):
        try:
            return [line.split("\t") for line in (self.dir / SEEN).read_text().splitlines()]
        except FileNotFoundError:
            return []

    def session(self):
        try:
            return (self.dir / SESSION).read_text().strip() or None
        except FileNotFoundError:
            return None


def phase_label(phase):
    if not phase:
        return "none"
    return f"card {phase['item']}" if phase["kind"] == "card" else "review"


class StillOpen(Exception):
    """Why `begin` closes no phase: one a live session opened, which its own closing step closes."""


def still_open(folder, now, session):
    """Why `begin` leaves `folder`'s open phase alone, else None: the phase is this session's (by
    its id), or the guard heard a call of the night's session lately, as it does just before a
    card's agent runs a copy of `begin`, however spelled. Only a session that ended leaves a
    phase for `begin` to close. An earlier night's folder it can't read holds no live phase."""
    age = file_age(folder.dir / HEARD, now)
    if not (age is not None and age < HEARD_LATELY) and not (session and folder.session() == session):
        return None
    try:
        phase = folder.state().get("phase")
    except FAILURES:
        if session:
            raise
        return None
    if not phase:
        return None
    return (f"The {phase_label(phase)} phase of {folder.dir.name} is still open in a live session, so begin "
            f"changes nothing. Close it with {closing_step(folder, phase)}; a session that ended leaves it "
            f"to the next begin, once the guard has heard none of its calls for {HEARD_LATELY.seconds // 60} "
            "minutes.")


def closing_step(night, phase):
    """The lead's command that closes `phase`: decide for a card, review-end for the review."""
    step = f"decide {night.dir} {phase['item']}" if phase["kind"] == "card" else f"review-end {night.dir}"
    return f"{night.script} {step}"


def begin(night, now, session):
    """The night's first step: its folder, its session, and a phase a run that died left open
    closed. Returns the lines to print; raises StillOpen, changing nothing, when a live
    session's phase is open, here or on an earlier night."""
    earlier = sorted(f for f in night.dir.parent.glob("20*") if f.name < night.dir.name)
    for folder in [night] + [Night(f) for f in earlier]:
        why = still_open(folder, now, session if folder is night else None)
        if why:
            raise StillOpen(why)
    night.dir.mkdir(parents=True, exist_ok=True)
    for name in (OUTCOME, USAGE):
        (night.dir / name).unlink(missing_ok=True)
    lines = [f"Night {night.dir.name}: begun"]
    if session:
        (night.dir / SESSION).write_text(session + "\n")
    else:
        (night.dir / SESSION).unlink(missing_ok=True)
        lines.append("No session id: no card will start tonight.")
    try:
        lines += [f"Unset the night's pre-push hook a stopped night left in {tree}."
                  for tree in clear_night_hooks(night.main)]
    except FAILURES as error:
        night.note("unchecked", [f"the pre-push hooks a stopped night may have left ({error})"])
    # The night before's session may have died mid-card too, and no later begin of its own runs.
    for folder in earlier:  # an ended night's session: the guard, which reads each, reads one
        (folder / SESSION).unlink(missing_ok=True)
    for folder in ([Night(earlier[-1])] if earlier else []) + [night]:
        try:
            line = park_left_open(folder, night, now if folder is night else None)
        except FAILURES as error:
            if folder is night:
                raise
            night.note("unchecked", [f"a card {folder.dir.name} may have left open ({error})"])
            continue
        if line:
            lines.append(line)
            if folder is not night:
                night.note("earlier", [line])
    return lines


def judge_hashes(main):
    """Each file in the main checkout's JUDGES folders, by path, as sha256. The guard reads only
    plain spellings of a path, so `decide` compares these before arming."""
    import hashlib  # here, not at the top: the guard, which runs on every call, never hashes

    main = Path(main)
    return {str(f.relative_to(main)): hashlib.sha256(f.read_bytes()).hexdigest()
            for folder in JUDGES for f in sorted((main / folder).glob("*")) if f.is_file()}


def clear_night_hooks(main):
    """Unsets core.hooksPath in each worktree whose own config points it into a night's folder, as
    a night that ended before its `decide` leaves it, so no day's push meets the night's hook.
    Returns the worktrees it was unset in."""
    retro, cleared = (Path(main) / ".build/retro").resolve(), []
    for line in sh("git", "-C", str(main), "worktree", "list", "--porcelain").splitlines():
        tree = line.removeprefix("worktree ")
        if tree == line:
            continue
        hooks = sh("git", "-C", tree, "config", "--worktree", "--get", "core.hooksPath", check=False).strip()
        if hooks and retro in Path(hooks).resolve().parents:
            sh("git", "-C", tree, "config", "--worktree", "--unset", "core.hooksPath")
            cleared.append(tree)
    return cleared


def handoff_path(folder, branch):
    """A night card's handoff note, in the session's folder, which `decide` carries to the main checkout's."""
    return Path(folder) / ".slices" / f"{branch}-handoff.md"


def carry(files, to):
    """Copies those of `files` that exist from the session's folder into the main checkout's `to`,
    the record a day session reads: Claude Code refuses the session's Write there."""
    for file in files:
        if file.is_file() and file.resolve() != (to / file.name).resolve():
            to.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(file, to / file.name)


def leave_card(night, entry):
    """Leaves the session's folder as `next` found it, once a card is decided: the card's handoff
    carried to the main checkout's .slices/, the night's pre-push hook unset, and the branch it was
    on switched back to. Returns why it couldn't, or None; the folder then stays on the card's
    branch, and no more cards start."""
    folder, branch = Path(entry["worktree"]), entry["branch"]
    carry([handoff_path(folder, branch)], night.main / ".slices")
    sh("git", "-C", str(folder), "config", "--worktree", "--unset", "core.hooksPath", check=False)
    back = entry.get("back")
    if not back:
        return None  # `next` never switched it
    if git_status(folder):
        return f"the session's folder has uncommitted changes on {branch}, so it stays there"
    sh("git", "-C", str(folder), "switch", *(["--detach", back["commit"]] if back.get("commit") else [back["branch"]]))
    return None


def park_left_open(folder, tonight, now):
    """Closes `folder`'s open phase, parking a card a session that ended left open, and returns
    the line saying so; failures go to `tonight`'s notes. `now` given, it is tonight's own folder,
    whose start a run earlier the same date keeps, so tonight's runs count from the first."""
    state = folder.state()
    phase = state.get("phase")
    if now:
        folder.write(STATE, {**state, "start": state.get("start") or now.isoformat(), "phase": None})
    elif phase:
        folder.set_state(phase=None)
    if phase and phase["kind"] == "review":
        # A review whose session ended before `review-end`: its reports still reach the record.
        try:
            carry(Path(phase["reports"]).glob("report-*.md"), folder.main / REVIEW_REPORTS)
        except FAILURES as error:
            tonight.note("unchecked", [f"the setup review's report, left by a run that ended ({error})"])
    if not phase or phase["kind"] != "card":
        return None
    why = "the night's session ended before deciding on it"
    folder.update(phase["item"], decision="parked", why=why, where="its PR, if any, as the card's run left it")
    try:
        disarm(folder)
        board("state", phase["item"], stdin=f"- The nightly run of {folder.dir.name} ended while taking "
              "this card, so it is still In Progress and its PR, if any, is as the card's run left it.\n"
              "- Next: a daytime /onward reads the PR and the handoff in `.slices/`.\n")
    except FAILURES as error:
        tonight.note("unchecked", [f"parking \"{phase['title']}\", left open by a run that ended ({error})"])
    entry = folder.entry(phase["item"])
    if entry:
        put_back(folder, entry, tonight)
    return f"Parked \"{phase['title']}\" of {folder.dir.name}: {why}."


def close_merged(rows, dry_run):
    """Moves to Done each In Progress card of the board's rows whose PR a night parked or left
    waiting and a day session has merged since, which nothing in that session does. Returns
    (closed, unchecked)."""
    closed = []
    try:
        rows = [r for r in rows if r[1] == "In Progress" and r[2] == "-"]
        for item, _, _, title, body in board_bodies(rows):
            n = left_pr(body)
            if not n or gh_json("pr", "view", str(n), "--json", "state")["state"] != "MERGED":
                continue
            if not dry_run:
                board("status", item, "Done")
            closed.append(f"{title}, since #{n} merged")
    except FAILURES as error:
        return closed, [f"moving cards whose PR merged to Done ({error})"]
    return closed, []


def add_update_cards(rows, dry_run):
    """A card at the top of Definitely for each lint tool with a newer release that has none yet,
    in `outdated`'s order. Returns (titles added, unchecked). The board's list lags a card just
    added, so the night takes it once the list shows it."""
    added, unchecked = [], []
    try:
        result = outdated_tools()
        if result.returncode != 0:
            unchecked.append(f"which lint tools have a newer release ({result.stderr.strip()})")
        cards = update_cards(result.stdout, rows) if result.stdout.strip() else []
        for title, body in reversed(cards):  # each goes on top, so the first goes last
            if not dry_run:
                board("move", board("add", title, stdin=body).strip(), "top")
            added.append(title)
    except FAILURES as error:
        unchecked.append(f"adding the lint tools' update cards ({error})")
    return added, unchecked


def file_age(path, now):
    """How long ago a file was last written, or None when it can't be read."""
    try:
        return now - datetime.fromtimestamp(Path(path).stat().st_mtime).astimezone()
    except OSError:
        return None


def unguarded(night, session):
    """Why the guard can't hold this session's calls, or None: a card or the review starts only
    when it can."""
    recorded = night.session()
    if not recorded:
        return "no session id was recorded at the night's start, so the guard can't tell the night's calls."
    if recorded != session:
        return "this session isn't the one the night's start recorded."
    if not any(caller == "lead" for _, caller in night.seen()):
        return ("the guard never judged this session's calls, so it isn't installed in "
                ".claude/settings.json; nothing runs unguarded.")
    return None


def refusal(night, now, session):
    """Why no card may start before any card is read, or None."""
    window = night_window(now)
    if not window:
        return f"cards start only from midnight to {CUTOFF_HOUR} am."
    state = night.state()
    if state.get("phase"):
        return f"the {phase_label(state['phase'])} is still open, so run decide or review-end first."
    if state.get("stopped"):
        return state["stopped"]
    return unguarded(night, session) or usage_gate(plan_windows(night.dir), file_age(night.dir / USAGE, now), now, window[1], len(night.cards()))


def choose(night, now, tried):
    """((item, title, body), month hours, held) of the first card that may start, or (None, why
    not, held). held are the cards an open PR holds back."""
    runs = xcode_cloud_runs()
    hours, tonight = month_hours(runs, now), runs_tonight(runs, night.start(), night.dir)
    open_files = {pr["number"]: clash_files(pr) for pr in
                  gh_json("pr", "list", "--state", "open", "--json", "number,files,title")}
    repo_files = set(sh("git", "ls-tree", "-r", "--name-only", "origin/main").split())
    held, skipped = [], []
    for item, status, feature, title, body in board_cards(board_rows()):
        if item in tried:
            continue
        why = eligibility(status, feature, body)
        likely = likely_files(body, repo_files)
        if not why:
            clashes = {n: f for n, f in ((n, overlap(likely, files)) for n, files in open_files.items()) if f}
            if clashes:
                touch = "may touch what " + ", ".join(f"#{n} ({', '.join(f)})" for n, f in clashes.items()) + " changes"
                why = "it " + touch
                held.append(f"\"{title}\" {touch}; merge or close "
                            + " and ".join(f"#{n}" for n in clashes) + " so a night can take it")
        if not why:
            # A card that names no files may change the app, so the budget applies to it too.
            app = not likely or classify(sorted(likely)) != "docs"
            why = app and xcode_cloud_gate(hours, tonight, EXPECTED_RUNS)
        if why:
            if re.search(r"^Nightly:", body, re.M):
                skipped.append(f"\"{title}\": {why}")
            continue
        return (item, title, body), hours, held
    if skipped:
        return None, "no card in Definitely may start tonight: " + "; ".join(skipped) + ".", held
    return None, "no eligible tooling card left in Definitely.", held


def install_pre_push(night, worktree):
    """The night's pre-push hook, the main checkout's script, in the card worktree's own git
    config, so every push from it meets the hook however it starts, and no other checkout's does.
    `decide` unsets it, and `begin` one a stopped night left."""
    hooks = git_hooks(night)
    hooks.mkdir(exist_ok=True)
    (hooks / "pre-push").write_text(pre_push_text(night))
    (hooks / "pre-push").chmod(0o755)
    sh("git", "-C", str(worktree), "config", "--worktree", "core.hooksPath", str(hooks))


def git_hooks(night):
    """The folder the night's pre-push hook is in, which a card's worktree's core.hooksPath names."""
    return night.dir / "git-hooks"


def pre_push_text(night):
    return (f"#!/bin/sh\nexec /usr/bin/env python3 {shlex.quote(str(night.script))} "
            f"pre-push {shlex.quote(str(night.dir))}\n")


def tampered(night, entry):
    """Why a card that passed its gates still isn't armed, else None: the main checkout's files that
    judge it, or the night's pre-push hook, changed since `next` took it, which also ends the
    cards; or the hook is off in its folder now, so a push may have passed the run budget
    unchecked."""
    pre_push = git_hooks(night) / "pre-push"
    if judge_hashes(night.main) != entry.get("judges"):
        why = "the main checkout's guard, scripts, or git hooks changed while the card ran"
    elif not pre_push.is_file() or pre_push.read_text() != pre_push_text(night):
        why = "the night's pre-push hook changed after next wrote it"
    else:
        hooks = sh("git", "-C", entry["worktree"], "config", "--get", "core.hooksPath", check=False).strip()
        return None if hooks == str(git_hooks(night)) else (
            "the night's pre-push hook was off in the card's folder, so its pushes may have gone unchecked")
    night.set_state(stopped=why + ".")
    return why


def where_it_was(folder):
    """The branch the session's folder is on, or its commit when detached, for `decide` to go back to."""
    branch = sh("git", "-C", str(folder), "symbolic-ref", "-q", "--short", "HEAD", check=False).strip()
    return {"branch": branch} if branch else {"commit": sh("git", "-C", str(folder), "rev-parse", "HEAD").strip()}


def next_card(night, now, session, dry_run):
    """(the lines that name the card taken, None), or (None, why no card starts)."""
    why = refusal(night, now, session)
    if why:
        return None, why
    # A card is built in the session's own folder, switched to the card's branch: Claude Code
    # refuses a subagent's edits in a worktree its session doesn't sit in. Never the main
    # checkout, whose scripts and guard judge the card.
    folder = session_folder()
    if folder == night.main:
        return None, ("the night's session runs in the main checkout, whose scripts judge a card; "
                      "cards are built only in a worktree of the session's own.")
    if folder.parent != night.main / ".claude/worktrees":
        # HOOK_COMMAND finds the main checkout's guard from this path alone.
        return None, (f"the night's session runs in {folder}, outside the main checkout's .claude/worktrees/, "
                      "where the guard can't find the main checkout's copy.")
    if git_status(folder):
        return None, "the session's folder has uncommitted changes, so no card's branch is switched in."
    sh("git", "fetch", "--quiet", "origin", "main")
    if not night.state().get("night_read"):
        # Once a night: main's tests, the cards whose PR merged by day, and the update cards.
        tests = test_counts("origin/main")
        rows = board_rows()
        closed, unchecked = close_merged(rows, dry_run)
        added, more = add_update_cards(rows, dry_run)
        if dry_run:
            for line in [f"would move to Done: {c}" for c in closed] + [f"would add: {a}" for a in added]:
                print(f"Dry run: {line}", file=sys.stderr)
        else:
            night.set_state(night_read=True, tests_before=tests)
            for key, value in (("closed", closed), ("added", added), ("unchecked", unchecked + more)):
                night.note(key, value)
    card, detail, held = choose(night, now, {c["item"] for c in night.cards()})
    if not dry_run:
        night.note("held", held)
    if not card:
        return None, detail
    item, title, _ = card
    branch = branch_name(title)
    handoff, last_line = handoff_path(folder, branch), folder / LAST_LINE
    lines = [f"card {item}", f"title {title}", f"worktree {folder}", f"branch {branch}", f"handoff {handoff}",
             f"last-line {last_line}"]
    if dry_run:
        return lines, None
    back = where_it_was(folder)
    sh("git", "-C", str(folder), "switch", "--no-track", "-c", branch, "origin/main")
    try:
        install_pre_push(night, folder)
    except FAILURES as error:
        leave_card(night, {"worktree": str(folder), "branch": branch, "back": back})
        sh("git", "-C", str(folder), "branch", "-D", branch, check=False)
        raise NoCard(f"the session's folder couldn't take the night's pre-push hook ({error}), "
                     "and no card runs without it.") from error
    last_line.unlink(missing_ok=True)
    rows = plan_windows(night.dir)
    night.write(CARDS, night.cards() + [{"item": item, "title": title, "branch": branch, "worktree": str(folder),
                                         "back": back, "usage": plan_usage_line(rows) if not isinstance(rows, str) else rows,
                                         "judges": judge_hashes(night.main), "decision": "open"}])
    night.set_state(hours=detail, phase={"kind": "card", "item": item, "title": title, "worktree": str(folder),
                                         "branch": branch, "handoff": str(handoff), "last_line": str(last_line),
                                         "stop": night_window(now)[1].isoformat()})
    board("status", item, "In Progress")
    board("state", item, stdin=f"- Nightly run of {night.dir.name}: led by the night's session, on branch "
          f"`{branch}`; handoff `.slices/{branch}-handoff.md` in the main checkout.\n")
    return lines, None


def disarm(night):
    """Turns auto-merge off on every open PR from the night's branches. A failure raises."""
    branches = night.branches()
    if not branches:
        return
    for pr in gh_json("pr", "list", "--state", "open", "--author", "@me", "--search", f"created:>={night.since()}",
                      "--json", "number,autoMergeRequest,headRefName"):
        if pr["headRefName"] in branches and pr.get("autoMergeRequest"):
            disable_auto(pr["number"])


def close_phase(night):
    night.set_state(phase=None)


def park(night, entry, pr, why):
    where = f"PR #{pr['number']} is a draft with auto-merge off" if pr else "no PR"
    night.update(entry["item"], decision="parked", why=why, where=where, pr=pr and pr["number"])
    close_phase(night)
    if pr:
        disable_auto(pr["number"])
        sh("gh", "pr", "ready", str(pr["number"]), "--undo", check=False)
    board("state", entry["item"], stdin=f"- Parked by the nightly run: {why}. {where}.\n- Next: "
          "a daytime /onward reads the PR and the handoff in `.slices/`.\n")
    return "parked", f"Parked \"{entry['title']}\": {why} ({where})."


def gates(pr, me):
    """("park", why), ("wait", why, files), or ("arm", files, built) for a card's open PR, from
    its verifier record by `me`, its commits, its test counts, and the paths it touches."""
    n, sha = pr["number"], pr["headRefOid"]
    sh("git", "fetch", "--quiet", "origin", f"pull/{n}/head", check=False)
    # Only a record the verifier posted counts: it comments as the account this runs as, and a
    # public repo's comments can come from anyone.
    record = verifier_record([c["body"] for c in pr["comments"] if (c.get("author") or {}).get("login") == me])
    if not record:
        return "park", "no verifier record on the PR"
    built, failures, unread = record
    if failures:
        return "park", "the verifier found " + "; ".join(f[2:] for f in failures)
    if unread:
        return "park", "its verifier record has lines the night can't read: " + "; ".join(unread)
    if not built:
        return "park", "its verifier record names no commit"
    if subprocess.run(["git", "merge-base", "--is-ancestor", built, sha], cwd=ROOT).returncode != 0:
        return "park", f"its verifier record names {built}, which isn't on the PR"
    if not only_tests(sh("git", "diff", "--name-only", f"{built}..{sha}").split()):
        return "park", "changes after the verifier's build that it never saw"
    base = sh("git", "merge-base", "origin/main", sha).strip()
    drops = unexplained_drops(test_drops(test_counts(base), test_counts(sha)), pr["body"] or "")
    if drops:
        return "park", ("fewer tests (" + ", ".join(f"{t} {b} → {a}" for t, b, a in drops)
                        + f") and no line in its body starting \"{FEWER_TESTS}\" that names the target")
    # Without rename detection a renamed file lists its old path too.
    files = sh("git", "diff", "--name-only", "--no-renames", base, sha).split()
    touched = protected(files)
    if touched or day_only(files):
        return "wait", (f"it touches {', '.join(touched)}, which a night never merges" if touched
                        else "it changes only .claude/ and docs/, which waits for the day"), files
    return "arm", files, built


def settle(night, entry, pr, now):
    """What `decide` does with a card's open PR: park it, leave it for the maintainer, or arm
    auto-merge at its head and wait for the merge. Returns (decision, line)."""
    me = sh("gh", "api", "user", "--jq", ".login").strip()
    verdict = gates(pr, me)
    if verdict[0] == "park":
        return park(night, entry, pr, verdict[1])
    n = pr["number"]
    if verdict[0] == "wait":
        why = verdict[1]
        night.update(entry["item"], decision="waiting", why=why, pr=n, pr_title=pr["title"])
        close_phase(night)
        disable_auto(n)
        board("state", entry["item"], stdin=f"- PR #{n} waits for the maintainer, unmerged: {why}.\n")
        return "waiting", f"#{n} waits for the maintainer: {why}."
    if not any(label == f"card {entry['item']}" and caller != "lead" for label, caller in night.seen()):
        return park(night, entry, pr, "the guard never judged a subagent's call for this card, so it ran unguarded")
    why = tampered(night, entry)
    if why:
        return park(night, entry, pr, why)
    _, files, built = verdict
    # Recorded before arming, so a session that ends here leaves a PR `begin` disarms.
    night.update(entry["item"], decision="armed", pr=n, pr_title=pr["title"], head=pr["headRefOid"],
                 built=built, files=files, armed_at=now.isoformat())
    sh("gh", "pr", "merge", str(n), "--auto", "--squash", "--match-head-commit", pr["headRefOid"])
    return wait_merge(night, night.entry(entry["item"]))


def proof(entry):
    """How the digest says a merged card was checked."""
    check = "PR check passed, lint only"
    try:
        if classify(entry["files"]) != "docs":
            run = next((r for r in xcode_cloud_runs(limit=20)
                        if (r["attributes"].get("sourceCommit") or {}).get("commitSha") == entry["head"]), None)
            check = f"PR check passed on Xcode Cloud run {run['attributes']['number']}" if run else "PR check passed"
    except FAILURES:
        check = "PR check passed"
    return f"verifier record at {entry['built']}, {check}"


def wait_merge(night, entry):
    """Polls an armed PR once a minute for up to MERGE_POLL, since a check may not exist yet when
    auto-merge is armed: merged, parked when the required check, "PR check", failed or an hour has
    passed since arming, else still armed."""
    # From the process's start, so the gates `decide` ran before arming count too.
    deadline = STARTED + MERGE_POLL.total_seconds()
    n = entry["pr"]
    while True:
        pr = gh_json("pr", "view", str(n), "--json", "state,mergeCommit,statusCheckRollup")
        if pr["state"] == "MERGED":
            merge = pr["mergeCommit"]["oid"]
            night.update(entry["item"], decision="merged", merge=merge, proof=proof(entry))
            close_phase(night)
            board("status", entry["item"], "Done")
            return "merged", f"#{n} merged as {merge[:7]}."
        failed = any(c.get("name") == "PR check" and c.get("conclusion") in ("FAILURE", "CANCELLED", "TIMED_OUT")
                     for c in pr["statusCheckRollup"])
        if failed or datetime.now().astimezone() - datetime.fromisoformat(entry["armed_at"]) > MERGE_WAIT:
            return park(night, entry, {"number": n}, "its PR check failed, or didn't finish within the hour")
        if time.monotonic() >= deadline:
            return "armed", "armed: run decide again"
        time.sleep(60)


def audit(night):
    """Every PR from the night's branches merged to main that the night didn't arm, kept in the
    notes for the top of the digest, and the other merges since the night started, the maintainer's
    sessions', for one plain line. Any of the first kind ends the cards: something got past the
    gates."""
    merged = gh_json("pr", "list", "--state", "merged", "--base", "main", "--search", f"merged:>={night.since()}",
                     "--json", "number,title,mergedBy,mergeCommit,headRefName")
    cards, branches = night.cards(), night.branches()
    armed = {c["pr"] for c in cards if c.get("armed_at")}
    found = {pr["number"] for pr in merged}
    # A merge GitHub's search may not list yet: the PR `decide` found merged.
    during = [{"number": c["pr"], "title": c["pr_title"]} for c in cards
              if c["decision"] == "unarmed" and c["pr"] not in found]
    unarmed = [pr for pr in merged if pr["headRefName"] in branches and pr["number"] not in armed] + during
    night.note("unarmed", unarmed)
    night.note("others", [pr for pr in merged if pr["headRefName"] not in branches])
    if unarmed:
        night.set_state(stopped="merged to main tonight without the night's gates: "
                        + ", ".join(f"#{pr['number']}" for pr in unarmed) + ".")


def decide(night, item, now):
    """(decision, line) for the open card `item`: merged, parked, waiting, unarmed, armed (run
    decide again), or already, for a card decided before, which it leaves as it is. A parked
    card's reason is its lead's last line, which the lead Wrote in the session's folder."""
    entry = night.entry(item)
    if not entry:
        raise ValueError(f"no card {item} was taken tonight")
    if entry["decision"] not in ("open", "armed"):
        return "already", f"\"{entry['title']}\" was already decided: {entry['decision']}."
    if entry["decision"] == "armed":
        return wait_merge(night, entry)
    # Whatever happens next, no PR the card opened merges unless `decide` arms it below.
    disarm(night)
    prs = gh_json("pr", "list", "--head", entry["branch"], "--state", "all",
                  "--json", "number,title,state,headRefOid,body,comments")
    pr = prs[0] if prs else None
    last = last_line(Path(entry["worktree"]) / LAST_LINE)
    if not pr:
        return park(night, entry, None, f"no PR; its lead ended with: {last}")
    if pr["state"] == "CLOSED":
        return park(night, entry, pr, f"its PR was closed; its lead ended with: {last}")
    if pr["state"] == "MERGED":
        night.update(item, decision="unarmed", pr=pr["number"], pr_title=pr["title"])
        close_phase(night)
        board("state", item, stdin=f"- The nightly run found PR #{pr['number']} merged during the card's run, "
              "not by the night, so none of its gates ran; review it, and undo with git revert.\n")
        return "unarmed", f"#{pr['number']} merged without the night's gates."
    return settle(night, entry, pr, now)


def closing_reads(night, now):
    """The digest's reads of the world, made once the cards are done, saved in the notes; a read
    that fails is a "Not checked:" line. Nothing to read on a night no `next` got to its cards."""
    if not night.state().get("night_read"):
        return
    closing, unchecked = {}, []
    try:
        runs = xcode_cloud_runs()
        closing.update(runs=runs_tonight(runs, night.start(), night.dir), hours=month_hours(runs, now))
    except FAILURES as error:
        unchecked.append(f"Xcode Cloud's runs ({error})")
    try:
        sh("git", "fetch", "--quiet", "origin", "main")
        closing["tests"] = test_counts("origin/main")
    except FAILURES as error:
        unchecked.append(f"main's test counts ({error})")
    try:
        closing["behind"] = [{"number": pr["number"], "title": pr["title"]} for pr in gh_json(
            "pr", "list", "--state", "open", "--json", "number,title,mergeStateStatus")
            if pr["mergeStateStatus"] == "BEHIND"]
    except FAILURES as error:
        unchecked.append(f"the open PRs behind main ({error})")
    try:
        audit(night)
    except FAILURES as error:
        unchecked.append(f"tonight's merges ({error})")
    night.note("closing", closing)
    night.note("unchecked", unchecked)


def review_reason(now):
    """(why the setup review runs tonight or None, the main checkout)."""
    try:
        xcode = xcode_major(sh("xcodebuild", "-version", check=False))
    except FAILURES:
        xcode = None
    main = main_checkout()
    return review_due(last_review(main / REVIEW_REPORTS), now, xcode, review_tries(main / ".build/retro", now)), main


def tallies(folder, now, review_only=False):
    """Writes the agents' tallies to the night's folder before the agents that read them start: the
    retro's over the last TALLY_DAYS, and, when the setup review runs tonight, the review's, both
    from one fetch. review_only writes the review's alone, when it has none yet."""
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    wanted = {} if review_only else {TALLY: [("", f"{now - timedelta(days=TALLY_DAYS):%Y-%m-%d}")]}
    try:
        why, main = review_reason(now)
        record = agent_record()
        if why:
            wanted[REVIEW_TALLY] = review_parts(last_review_date(main / REVIEW_REPORTS), now, trial_rows(record))
        texts = write_tallies(folder, wanted, lambda since: record.fetch(since, limit=TALLY_LIMIT),
                              record.tally) if wanted else {}
    except Exception as error:  # noqa: BLE001 - before the fetch: still one line saying why, never fatal
        texts = {REVIEW_TALLY if review_only else TALLY: f"No tally tonight: {type(error).__name__}: {error}\n"}
        for name, text in texts.items():
            (folder / name).write_text(text)
    for name, text in texts.items():
        print(f"{name}: {text.splitlines()[0][:160]}")


def open_review(night, now, session):
    """Why the setup review is due tonight, its phase now open for at most REVIEW_LIMIT or until
    the cutoff, or None when it isn't due. A due review that can't run guarded raises NoCard,
    kept for the digest. The night's `tally` wrote the review's tally before the retro; one it
    didn't is written here."""
    why, main = review_reason(now)
    if not why:
        return None
    blocked = unguarded(night, session)
    if blocked:
        # Not "review": only a review that started counts as one of the month's tries.
        night.note("review_blocked", f"due ({why}), not run: {blocked}")
        raise NoCard(blocked)
    if night.state().get("phase"):
        raise ValueError(f"the {phase_label(night.state()['phase'])} is still open")
    if not (night.dir / REVIEW_TALLY).exists():
        tallies(night.dir, now, review_only=True)
    deadline = min(night_window(now)[0], now + REVIEW_LIMIT)
    # The report is written in the session's own folder, which `review-end` carries to the main
    # checkout's: Claude Code refuses a Write outside the folder a session sits in.
    folder = session_folder()
    night.set_state(phase={"kind": "review", "deadline": deadline.isoformat(), "reports": str(folder / REVIEW_REPORTS),
                           "last_line": str(folder / LAST_LINE)})
    (folder / LAST_LINE).unlink(missing_ok=True)
    night.note("review", None)
    return why


def end_review(night):
    """`review-end`: the review's reports carried from the session's folder to the main
    checkout's, its phase closed, and the last line the lead Wrote kept for the digest. Returns
    that line."""
    phase = night.state().get("phase") or {}
    if phase.get("kind") != "review":
        return night.notes().get("review") or "nothing"  # run again: what the first run kept
    carry(Path(phase["reports"]).glob("report-*.md"), night.main / REVIEW_REPORTS)
    close_phase(night)
    line = last_line(phase["last_line"])
    night.note("review", line)
    return line


def hook(folder):
    """The guard: exit 2 with the reason on stderr denies the call. Once it knows the call is the
    night's, it fails closed: any error denies the call, since Claude Code runs a call whose hook
    exits with anything else."""
    try:
        why = hook_check(Path(folder), sys.stdin.read())
    except Exception as error:  # noqa: BLE001 - an error must deny, whatever it is
        why = (f"The night's guard failed ({type(error).__name__}: {error}), so it denies this call. "
               "Park the card, saying so in your last line.")
    if why:
        print(why, file=sys.stderr)
        sys.exit(2)


def hook_check(folder, text):
    call = json.loads(text)
    if not isinstance(call, dict):
        raise ValueError("the hook's input is not a JSON object")
    night = Night(folder)
    if call.get("session_id") != night.session():
        return None  # the night's id was only in the call's text
    state = json.loads((night.dir / STATE).read_text())  # not night.state(): a missing file must deny
    phase = state.get("phase")
    caller = (call.get("agent_type") or "subagent") if call.get("agent_id") else "lead"
    line = [phase_label(phase), caller]
    if line not in night.seen():
        with (night.dir / SEEN).open("a") as out:
            out.write("\t".join(line) + "\n")
    (night.dir / HEARD).touch()
    if not phase:
        return None
    tool, tool_input = call["tool_name"], call.get("tool_input") or {}
    command = tool_input.get("command") or ""
    path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    main, now = night.main, datetime.now().astimezone()
    if caller == "lead" and tool == "Bash" and closing(command, call.get("cwd"), main):
        return None
    if (caller == "lead" and tool == "Write" and phase.get("last_line")
            and Fence.real(path, Path(call.get("cwd") or main)) == Fence.real(phase["last_line"])):
        return None  # the line for decide or review-end, at any hour
    if phase["kind"] == "review":
        return review_decision(tool, command, path, now, datetime.fromisoformat(phase["deadline"]),
                               phase["reports"], call.get("cwd"))
    stop = datetime.fromisoformat(phase["stop"])
    if now >= stop + LAST_CALL:
        late = f"It is past {(stop + LAST_CALL):%H:%M}, so only the night's own {', '.join(sorted(CLOSING))} run."
        if caller != "lead":
            return f"{late} End your turn with your last line."
        return (f"{late} Write your last line to {phase.get('last_line') or LAST_LINE}, then close the card "
                f"with {closing_step(night, phase)}, run as one command.")
    # A push's start is recorded by the pre-push hook it then meets; a PR's here.
    return hook_decision(tool, command, now, stop, phase["handoff"],
                         lambda starts: run_budget(night.dir, phase["worktree"], state, record=starts != "push"),
                         Fence(phase["worktree"], main, night.dir, call.get("cwd")), path, list(strings(tool_input)))


def run_budget(folder, worktree, state, record, revs=("HEAD",)):
    """None when the changes of the commits about to be pushed or opened (revs) are docs, or one
    more Xcode Cloud run fits tonight, else why not. Tonight's runs are counted from Xcode Cloud
    itself, so a run counts however it started; this month's hours are `next`'s reading at the
    card's start."""
    files = {f for rev in revs for f in sh("git", "diff", "--name-only", f"origin/main...{rev}", cwd=worktree).split()}
    if not files or classify(sorted(files)) == "docs":
        return None
    # The night's runs are among the newest few; a cap of four needs no more.
    runs = xcode_cloud_runs(limit=20)
    why = xcode_cloud_gate(state["hours"], runs_tonight(runs, datetime.fromisoformat(state["start"]), folder))
    if not why and record:
        with (folder / "starts").open("a") as out:
            out.write(f"{datetime.now().astimezone().isoformat()} {worktree}\n")
    return why


def pre_push(folder):
    """The git pre-push hook of a card's worktree, run in it: exit 1 refuses the push. It fails
    closed, like the guard."""
    folder = Path(folder)
    try:
        state = json.loads((folder / STATE).read_text())
        # git gives the hook a line per ref it pushes: local ref, local commit, remote ref, remote
        # commit. A deleted ref's local commit is all zeros. `scripts/pr-media.sh` pushes to
        # pr-media, which shares no history with main and has no PR, so it starts no run.
        refs = [ref for ref in (line.split() for line in sys.stdin.read().splitlines())
                if len(ref) == 4 and ref[1].strip("0") and ref[2] != "refs/heads/pr-media"]
        # Only a card's worktree runs this hook, so a branch pushed here is the night's.
        with (folder / PUSHED).open("a") as out:
            out.writelines(ref[2].removeprefix("refs/heads/") + "\n" for ref in refs)
        why = run_budget(folder, os.getcwd(), state, record=True, revs=[ref[1] for ref in refs])
    except Exception as error:  # noqa: BLE001 - an error must refuse, whatever it is
        why = f"the nightly pre-push hook failed ({type(error).__name__}: {error})"
    if why:
        print(f"The night's pre-push hook: this push would start an Xcode Cloud run, and {why}. Don't push: "
              "park the card, saying so in your last line.", file=sys.stderr)
        sys.exit(1)


def plan_windows(folder):
    """The plan's usage windows from the night's usage.json, as (label, percent used, resets at),
    or a string saying why they can't be read."""
    try:
        data = json.loads((Path(folder) / USAGE).read_text())
        found = data["plan"]["windows"]
        rows = [(str(w["label"]), float(w["percentUsed"]), w.get("resetsAt")) for w in found]
    except OSError:
        return f"{USAGE} is missing"
    except (ValueError, KeyError, TypeError) as error:
        return f"{USAGE} isn't the usage tool's plan.windows ({type(error).__name__}: {error})"
    return rows or f"{USAGE} lists no windows"


def usage_check(folder):
    """(go on, the line to print): the night stops only when a weekly window is at WEEKLY_STOP or
    more, and goes on when usage.json can't be read."""
    rows = plan_windows(folder)
    if isinstance(rows, str):
        return True, f"Usage unreadable: {rows}"
    full = [f"{label} at {used:g}%, resetting {resets or 'at an unknown time'}"
            for label, used, resets in rows if "week" in label.lower() and used >= WEEKLY_STOP]
    if full:
        return False, "; ".join(full)
    return True, plan_usage_line(rows)


def plan_usage_line(rows):
    return "Usage: " + ", ".join(f"{label} {used:g}%" for label, used, _ in rows)


def card_lines(folder, state, cards, notes):
    """The digest's lines on the night's cards, from its files alone."""
    closing = notes.get("closing") or {}
    merged = [c for c in cards if c["decision"] == "merged"]
    lines = [f"Nightly tooling {folder.name}: {len(merged)} merged, "
             f"{sum(c['decision'] == 'parked' for c in cards)} parked, "
             f"{sum(c['decision'] == 'waiting' for c in cards)} waiting for the maintainer"]
    lines += [digest_block({"number": c["pr"], "title": c["pr_title"]}, c["merge"], c["files"], c["proof"])
              for c in merged]
    if "runs" in closing:
        lines.append(f"Xcode Cloud: {closing['runs']} runs tonight, {closing['hours']:.1f} h this month")
    before, after = state.get("tests_before") or {}, closing.get("tests")
    if after is not None:
        lines.append("Tests: " + ", ".join(f"{t} {before.get(t, 0)} → {after.get(t, 0)}"
                                           for t in sorted(set(before) | set(after))))
    lines += [f"Added: {title}, at the top of Definitely" for title in notes.get("added", [])]
    lines += [f"Done: {c}" for c in notes.get("closed", [])]
    if notes.get("others"):
        lines.append("Also merged tonight, not by a card: "
                     + ", ".join(f"#{pr['number']} {pr['title']}" for pr in notes["others"]))
    lines += [f"Parked: {c['title']}: {c['why']} ({c['where']})" for c in cards if c["decision"] == "parked"]
    lines += [f"Waiting: #{c['pr']} {c['pr_title']}: {c['why']}" for c in cards if c["decision"] == "waiting"]
    lines += [f"Undecided: {c['title']} was still {c['decision']} when the digest was written"
              for c in cards if c["decision"] in ("open", "armed")]
    lines += [f"Behind main: #{pr['number']} {pr['title']}" for pr in closing.get("behind", [])]
    lines += [f"Usage: {c['title']}: at its start, {c['usage'].removeprefix('Usage: ')}" for c in cards]
    return lines


def night_digest(folder):
    """The night's digest, from its files alone: its outcome first, then merges that skipped the
    gates, a main checkout the night couldn't bring up to date, what went unchecked, and the cards
    an open PR held back, so a day session merges or closes that PR first; then its usage, its
    cards, the setup review, and why no more cards started."""
    folder = Path(folder)
    try:
        outcome = (folder / OUTCOME).read_text().strip()
    except OSError:
        outcome = ""
    lines = [f"Night {folder.name}: {outcome or 'no outcome recorded: still running, or it stopped early'}"]
    night = Night(folder)
    try:
        state, cards, notes = night.state(), night.cards(), night.notes()
    except (OSError, ValueError) as error:
        state, cards, notes = {}, [], {"unchecked": [f"the night's files ({error})"]}
    lines += [f"Merged without the night's gates: #{pr['number']} {pr['title']}, by "
              f"{(pr.get('mergedBy') or {}).get('login', 'unknown')}; none of the night's gates ran on it. "
              f"Review it; undo: git revert {((pr.get('mergeCommit') or {}).get('oid') or '?')[:7]}"
              for pr in notes.get("unarmed", [])]
    lines += checkout_note(folder)
    lines += notes.get("earlier", [])
    lines += [f"Not checked: {u}" for u in dict.fromkeys(notes.get("unchecked", []))]
    lines += [f"Waits on an open PR: {h}" for h in notes.get("held", [])]
    rows = plan_windows(folder)
    lines.append(f"Not checked: usage, {rows}" if isinstance(rows, str) else plan_usage_line(rows))
    if state.get("night_read") or cards:
        lines += card_lines(folder, state, cards, notes)
    if "review" in notes or notes.get("review_blocked"):
        lines.append(f"Setup review: {notes.get('review') or notes.get('review_blocked') or 'no reply'}")
    if notes.get("ended"):
        lines.append(f"{'Ended' if cards else 'No card started'}: {notes['ended']}")
    return lines


def record_outcome(folder, args):
    """Writes outcome.txt from `ran` or `failed <step> <why>` and returns its text, or None when
    args are neither."""
    if args == ["ran"]:
        text = "ran"
    elif len(args) >= 3 and args[0] == "failed":
        text = f"failed: {args[1]}, {' '.join(args[2:])}"
    else:
        return None
    Path(folder).mkdir(parents=True, exist_ok=True)
    (Path(folder) / OUTCOME).write_text(text + "\n")
    return text


def usage_exit(code):
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    sys.exit(code)


def exit_with(status, text):
    print(text, file=sys.stderr if status == 2 else sys.stdout)
    sys.exit(status)


def run_review(night, now, session):
    """`review`'s (exit status, text): 0 when the review is due and its phase open, 1 when it
    isn't due or can't run guarded, kept for the digest, and 2 when opening it failed."""
    try:
        why = open_review(night, now, session)
    except NoCard as error:
        return 1, f"No setup review tonight: {error}"
    except Exception as error:  # noqa: BLE001 - the session records the step as failed
        return 2, f"review failed: {type(error).__name__}: {error}"
    return (0, f"Setup review due: {why}.") if why else (1, "No setup review tonight.")


def run_next(night, now, session, dry_run):
    """`next`'s (exit status, text): 0 and the card's lines, 1 and why no card starts, kept for
    the digest, or 2 and the error, which leaves a phase it opened for begin or decide to park."""
    try:
        lines, why = next_card(night, now, session, dry_run)
    except NoCard as error:
        lines, why = None, str(error)
    except Exception as error:  # noqa: BLE001 - whatever failed, the session is told and stops taking cards
        return 2, f"next failed: {type(error).__name__}: {error}"
    if lines:
        return 0, "\n".join(lines)
    if not dry_run:
        night.note("ended", why)
    return 1, f"No card: {why}"


def last_line(path):
    """The lead's last line, from the file it Wrote in the session's folder, which the phase's
    opening cleared; "nothing" when there is none."""
    try:
        return " ".join(Path(path).read_text(errors="replace").split()) or "nothing"
    except OSError:
        return "nothing"


def put_back(night, entry, tonight=None):
    """leave_card for a decided card, a failure noted in tonight's notes (the night's own when
    not given). Tonight's own card's folder that can't be put back starts no more cards."""
    try:
        why = leave_card(night, entry)
    except FAILURES as error:
        why = f"putting the session's folder back failed ({error})"
    if why:
        (tonight or night).note("unchecked", [f"\"{entry['title']}\": {why}"])
        if not tonight:
            night.set_state(stopped=why + ".")


def run_decide(night, item, now):
    """`decide`'s (exit status, text): 0 when decided, or decided before, 3 while armed, and 2 when
    deciding failed, which parks the card and turns auto-merge off on the night's PRs. Decided,
    the session's folder goes back as `next` found it."""
    try:
        decision, line = decide(night, item, now)
        if decision == "already":
            return 0, line
        if decision != "armed":
            put_back(night, night.entry(item))
            try:
                audit(night)
            except FAILURES as error:
                # As when gates were skipped: what the night can't see, it doesn't build on.
                night.note("unchecked", [f"tonight's merges after \"{item}\" ({error})"])
                night.set_state(stopped=f"reading tonight's merges after \"{item}\" failed ({error}).")
        return (3 if decision == "armed" else 0), line
    except Exception as error:  # noqa: BLE001 - whatever failed, the card is parked and its PR disarmed
        why = f"deciding failed: {type(error).__name__}: {error}"
        entry = night.entry(item)
        if entry and entry["decision"] in ("open", "armed"):
            night.update(item, decision="parked", why=why, where="its PR, if any, with auto-merge off")
        if entry:
            put_back(night, entry)
        if (night.state().get("phase") or {}).get("item") == item:
            close_phase(night)
        try:
            disarm(night)
        except Exception as again:  # noqa: BLE001 - the digest says so, at the top
            night.note("unchecked", [f"turning auto-merge off on tonight's PRs ({again})"])
        return 2, why


def main(args):
    now = datetime.now().astimezone()
    command, rest = (args[0], args[1:]) if args else ("", [])
    session = os.environ.get("CLAUDE_CODE_SESSION_ID")
    if command == "night" and not rest:
        print(f"{night_dir(now)}\n{main_checkout() / SCRIPT}")
    elif command == "usage" and len(rest) in (1, 2):
        if rest[1:]:  # a Python write, which a session in a worktree of its own may make here
            (Path(rest[0]) / USAGE).write_bytes(Path(rest[1]).read_bytes())
        go_on, line = usage_check(rest[0])
        print(line)
        sys.exit(0 if go_on else 1)
    elif command == "outcome" and len(rest) >= 2 and (text := record_outcome(rest[0], rest[1:])):
        print(f"Night {Path(rest[0]).name}: {text}")
    elif command == "begin" and len(rest) == 1:
        try:
            print("\n".join(begin(Night(rest[0]), now, session)))
        except StillOpen as error:
            exit_with(1, str(error))
    elif command == "next" and len(rest) in (1, 2) and rest[1:] in ([], ["--dry-run"]):
        exit_with(*run_next(Night(rest[0]), now, session, rest[1:] == ["--dry-run"]))
    elif command == "decide" and len(rest) == 2:
        exit_with(*run_decide(Night(rest[0]), rest[1], now))
    elif command == "review" and len(rest) == 1:
        exit_with(*run_review(Night(rest[0]), now, session))
    elif command == "review-end" and len(rest) == 1:
        night = Night(rest[0])
        if "review" not in night.notes():
            print("No setup review opened tonight.", file=sys.stderr)
            sys.exit(1)
        print(f"Setup review: {end_review(night)}")
    elif command == "tally" and len(rest) == 1:
        tallies(rest[0], now)
    elif command == "hook" and len(rest) == 1:
        hook(rest[0])
    elif command == "pre-push" and len(rest) == 1:
        pre_push(rest[0])
    elif command == "digest" and len(rest) <= 1:
        # The newest night's, never an earlier one, which would read as this one's.
        folders = [Path(rest[0])] if rest else sorted((main_checkout() / ".build/retro").glob("20*"))
        if not folders:
            print("No night yet: .build/retro/ holds no night's folder.")
            return
        if rest:  # the night's own step; bare, it only reads
            # A night whose first step failed has no folder yet, and still gets its digest.
            folders[-1].mkdir(parents=True, exist_ok=True)
            closing_reads(Night(folders[-1]), now)
        text = "\n".join(night_digest(folders[-1]))
        if rest:
            (folders[-1] / "digest.md").write_text(text + "\n")
        print(text)
    else:
        usage_exit(64)


if __name__ == "__main__":
    main(sys.argv[1:])
