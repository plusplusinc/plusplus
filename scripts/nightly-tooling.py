#!/usr/bin/env python3
"""After the nightly retro, runs eligible tooling cards one at a time, each with its own lead.

    scripts/nightly-tooling.py run <night-dir> [--dry-run] [--now 2026-10-29T01:30]
    scripts/nightly-tooling.py hook <night-dir> <worktree>   # a card's PreToolUse hook
    scripts/nightly-tooling.py pre-push <night-dir>          # a card's git pre-push hook
    scripts/nightly-tooling.py digest [<night-dir>]          # a night's digest; the last by default

scripts/nightly-retro.sh run calls `run` after the retro, with the night's folder in
.build/retro/, where the retro's stream-json log already is. `run` holds the night's gates, so
no agent can forget one: it starts cards only from midnight to 5 am, up to three a night, or,
on the night before the weekly usage limit resets (its reset at or before 7 am), until a
usage window reaches 0.9 or 5 am. Before each card it reads the last rate_limit_event in the
night's logs (no probe calls), this month's Xcode Cloud PR hours, and the open PRs' files. It
makes the card's worktree from main, runs one `claude -p` lead with the nightly-card skill,
then decides on the PR itself: auto-merge is armed only after a passing verifier record, never
for a PR touching a protected path or only .claude/ and docs/, which wait for the maintainer;
a failed card's PR goes back to draft. It ends with a private digest, saved in the night's
folder, which `scripts/nightly-retro.sh show` prints. --dry-run reads everything and prints the
card it would take and the command it would run, then stops before changing anything.

`hook` is the PreToolUse hook `run` gives each card's claude through --settings. It runs before
the permission rules, and its deny wins over their allow. It reads each Bash command as the shell
would split it, `bash -c`, `eval`, and `$(...)` included, and denies a merge of a PR (`gh pr
merge`, `gh api` on a merge path, a GraphQL mutation), any `asc xcode-cloud` command that starts
or changes a build or workflow, a gh alias being defined, turning off git's hooks, a push or PR
that would start an Xcode Cloud run once tonight's runs reach four or this month's PR hours pass
70, and, from 7 am, any new agent or anything but reading and committing. Any error in it denies
the call. It reads only what the command line shows, so two checks back it whatever a command
hides: git runs the night's `pre-push` hook (through GIT_CONFIG_* in the card's environment) on
every push, refusing one past the budget, with tonight's runs counted from Xcode Cloud itself;
and the runner ends the night when a card's PR was merged by anyone but itself.

Tests: python3 scripts/nightly-tooling-test.py, against fixtures, with no network.
"""
import fnmatch
import json
import os
import re
import shlex
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from xcresult import PR_WORKFLOW, ROOT, when  # noqa: E402

CUTOFF_HOUR = 5  # no card starts at or after this hour
STOP_HOUR = 7  # nothing new starts at all; a running builder writes its handoff
KILL_GRACE = timedelta(minutes=45)  # past STOP_HOUR, a card's claude is stopped
CAPPED_CARDS = 3
USAGE_STOP = 0.9
# On the uncapped night, a five-hour window still open in the morning keeps this much free.
MORNING_RESERVE = 0.5
HOURS_LIMIT = 70  # this month's Xcode Cloud PR hours, of the plan's 100
RUN_LIMIT = 4  # Xcode Cloud PR runs a night's cards may start

# A PR touching one of these is never merged at night (fnmatch, where * also matches /). The
# runner's own files are here too, so no night can loosen its gates.
PROTECTED = [
    # What decides the PR check, and what Xcode Cloud runs: the project and its schemes (which
    # tests the test action runs), the test plan, the scripts ci_post_clone.sh runs, the tools it
    # installs, and the resolved packages.
    ".github/*", "scripts/pr-check.sh", "ci_scripts/*", "*.xcodeproj/*", "*.xcworkspace/*",
    "*.xctestplan", "Config/*.xcconfig", "*.entitlements", "Packages/Package.swift",
    "*Package.resolved", "Brewfile", "Brewfile.lock.json", "scripts/lint.sh",
    "scripts/check-us-english.sh", "scripts/common.sh", ".swiftlint.yml", "*/.swiftlint.yml",
    ".swiftformat", "*/.swiftformat",
    # What steers the night's agents and their gates: the runner and its helpers, everything in
    # .claude/ (agents, skills, rules, hooks, permissions), the instructions every session loads,
    # and the tools.
    "scripts/nightly-tooling.py", "scripts/nightly-tooling-test.py", "scripts/nightly-retro.sh",
    "scripts/xcresult.py", "scripts/tidy.sh", "scripts/board.sh", ".claude/*", "CLAUDE.md",
    "AGENTS.md", ".mcp.json",
]
# The CI half repeats what .github/no-code-paths's header and scripts/pr-check.sh's GATE_PATTERN
# name; a file added to either belongs here too.
DAY_ONLY = (".claude/", "docs/")  # a PR entirely under these waits for the day
TEST_DIRS = ("Packages/Tests", "PlusPlusUITests")
TEST_PATTERN = r"@Test([^A-Za-z]|$)|func test[A-Z_]"
FEWER_TESTS = "Fewer tests:"  # the PR body's line that explains a drop, naming its target
FAILURES = (RuntimeError, OSError, ValueError, KeyError, subprocess.SubprocessError)
# The lines a verifier record may hold after its header (.claude/agents/verifier.md).
RECORD_LINE = re.compile(r"- (criterion|test|design|crash), (new|known): \S")


def log(message):
    print(f"{datetime.now().strftime('%H:%M')} {message}", flush=True)
    return message


def local(stamp):
    """A unix time as a local datetime."""
    return datetime.fromtimestamp(stamp).astimezone()


def windows(info):
    """A rate_limit_info's windows by name: five_hour, seven_day, and any other. A window may be
    malformed; window() reads one."""
    found = info.get("unifiedWindows") if isinstance(info, dict) else None
    return found if isinstance(found, dict) else {}


def window(w):
    """(utilization, resetsAt, status) of a window, or None when it isn't one the gates can read."""
    if not isinstance(w, dict):
        return None
    used, resets = w.get("utilization", 0), w.get("resetsAt")
    if not all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in (used, resets)):
        return None
    return used, resets, w.get("status")


def events(lines):
    """The JSON objects among a stream-json log's lines; stderr and anything else are skipped."""
    for line in lines:
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if isinstance(event, dict):
            yield event


def start_count(folder):
    """The Xcode Cloud runs the hook let tonight's cards start, which Xcode Cloud may not list yet."""
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


def is_uncapped(info, stop):
    """Whether every limit but the five-hour one resets by `stop`: the night before the weekly reset."""
    weekly = [window(w) for name, w in windows(info).items() if name != "five_hour"]
    return bool(weekly) and all(w and w[1] <= stop.timestamp() for w in weekly)


def usage_gate(info, now, cutoff, stop, uncapped):
    """("go", None), ("wait", until), or ("stop", why), from a rate_limit_event's rate_limit_info.

    Every window counts, whatever its name; one whose reset has passed counts as fresh. A full
    five-hour window waits for its reset only when that lands before the cutoff.
    """
    if not windows(info):
        return "stop", "no rate_limit_event in tonight's logs, so usage is unknown"
    wait = None
    for name, w in sorted(windows(info).items()):
        read = window(w)
        if not read:
            return "stop", f"the usage window {name} can't be read ({json.dumps(w)[:200]})"
        used, resets, status = read
        resets = local(resets)
        if resets <= now:
            continue
        state = f"{name} at {used:.2f} ({status}), resets {resets:%a %H:%M}"
        if status != "allowed" or used >= USAGE_STOP:
            if name == "five_hour" and resets < cutoff:
                wait = max(wait or resets, resets)
                continue
            return "stop", state
        if uncapped and name == "five_hour" and resets > stop and used >= 1 - MORNING_RESERVE:
            return "stop", f"{state}; keeping {MORNING_RESERVE:.0%} of it for the morning"
    return ("wait", wait) if wait else ("go", None)


def cards_left(count, uncapped):
    return uncapped or count < CAPPED_CARDS


def last_rate_limit(paths):
    """The rate_limit_info of the last rate_limit_event in these stream-json logs, oldest first."""
    found = None
    for path in paths:
        lines = [line for line in Path(path).read_text(errors="replace").splitlines()
                 if '"rate_limit_event"' in line]
        for event in events(lines):
            if event.get("type") == "rate_limit_event":
                found = event.get("rate_limit_info")
    return found


def limit_hit(lines):
    """Whether a claude run's stream-json lines end in a usage limit."""
    for event in events(lines):
        # Top-level fields only: a tool's output that mentions a limit is no limit.
        if "usage_limit_reached" in (event.get("error"), event.get("apiError")):
            return True
        if event.get("type") == "rate_limit_event":
            if (event.get("rate_limit_info") or {}).get("status") == "rejected":
                return True
        if event.get("type") == "result" and event.get("is_error"):
            text = str(event.get("result") or "")
            if event.get("api_error_status") == 429 or re.search(r"hit your .*limit", text):
                return True
    return False


def protected(files):
    return [f for f in files if any(fnmatch.fnmatch(f, p) for p in PROTECTED)]


def day_only(files):
    return bool(files) and all(f.startswith(DAY_ONLY) for f in files)


def section(body, heading):
    match = re.search(rf"^## {re.escape(heading)}\s*\n(.*?)(?=^## |\Z)", body, re.M | re.S)
    return match[1].strip() if match else ""


def eligibility(status, feature, body):
    """None when a night may take the card, else why not."""
    if status != "Todo":
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


def overlap(likely, files):
    return sorted(f for f in files for name in likely
                  if f == name or (name.endswith("/") and f.startswith(name)))


def xcode_cloud_gate(month_hours, runs):
    """None, or why a card, or a call, that would start an Xcode Cloud run can't tonight."""
    if month_hours > HOURS_LIMIT:
        return f"{month_hours:.1f} Xcode Cloud hours this month, above {HOURS_LIMIT}"
    if runs >= RUN_LIMIT:
        return f"{runs} Xcode Cloud runs tonight, the night's limit"
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


def count_tests(source):
    """The tests in a Swift file, leaving out any in a comment, such as a test commented out. A
    heuristic: a nested block comment or a raw string can fool it, which a reviewer of the PR sees."""
    return len(re.findall(TEST_PATTERN, SWIFT_NOISE.sub("", source)))


# What a card may still run past 7 am: reading, and committing what builds.
SAFE_LATE = {"cd", "ls", "cat", "head", "tail", "grep"}
SAFE_LATE_GIT = {"add", "commit", "status", "diff", "log", "show", "rev-parse"}
SEPARATORS = {";", "&", "&&", "|", "||", "|&", "(", ")"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
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


def commands(command, depth=0):
    """Each simple command in a shell command line, as its words, with those `bash -c`, `eval`,
    `$(...)`, and backticks run. A line shlex can't split is read again without its quotes, which
    finds more commands, never fewer."""
    # A newline ends a command; inside quotes the added ";" changes only this reading of the text.
    text = without_heredocs(command).replace("\n", " ; ")
    lexer = shlex.shlex(text, posix=True, punctuation_chars=";&|()<>")
    lexer.whitespace_split, lexer.commenters = True, ""
    try:
        tokens = list(lexer)
    except ValueError:
        return commands(re.sub(r"[\"'\\]", " ", text), depth + 1) if depth < 3 else [text.split()]
    found, words, skip = [], [], False
    for token in [*tokens, ";"]:
        if skip:
            skip = False
        elif token in SEPARATORS:
            if words:
                found.append(words)
            words = []
        elif set(token) <= set("<>&") or re.fullmatch(r"\d?[<>]+&?", token):
            skip = True  # a redirection and its target
        else:
            words.append(token)
    if depth >= 3:
        return found
    # Substitutions anywhere in the line, quoted or not; shlex keeps an unquoted backtick in its word.
    inner = [a or b for a, b in re.findall(r"\$\(([^()]*)\)|`([^`]*)`", text)]
    for words in found:
        for i, word in enumerate(words):
            after = words[i + 1:]
            if word.rsplit("/", 1)[-1] in SHELLS and len(after) > 1 and re.fullmatch(r"-\w*c\w*", after[0]):
                inner.append(after[1])
            if word == "eval":
                inner.append(" ".join(after))
    return found + [words for text in inner for words in commands(text, depth + 1)]


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
    the pre-push hook the runner gives each card's git, and a merge the runner's check of the PR.
    """
    starts = None
    for words in commands(command):
        if re.search(r"hookspath|GIT_CONFIG|--no-verify", " ".join(words), re.I):
            return "The night's git hooks stay on: no --no-verify, core.hooksPath, or GIT_CONFIG_*.", None
        git = tool_args(words, "git")
        if git is not None and git_call(git)[1] == "push":
            starts = starts or "push"
        gh = tool_args(words, "gh")
        if gh is not None:
            group, *rest = positionals(gh) or [""]
            if group == "pr" and rest[:1] == ["merge"]:
                return "The nightly runner arms auto-merge itself, once the verifier has passed. Never merge.", None
            # A query read from a file or stdin can't be checked, so it counts as a mutation.
            mutation = "graphql" in rest and ("--input" in gh or any(
                re.search(r"mutation|=@|^@", w, re.I) for w in gh))
            if group == "api" and (mutation or any(MERGE_PATH.search(w) for w in rest)):
                return ("Never merge, and no GraphQL mutation or merge endpoint through gh api: the "
                        "nightly runner arms auto-merge itself."), None
            if group == "alias" and rest[:1] in (["set"], ["import"]):
                return "The night defines no gh aliases.", None
            if (group == "pr" and rest[:1] in (["create"], ["ready"], ["reopen"])) or (
                    group == "api" and API_WRITES & set(gh) and any(PR_PATH.search(w) for w in rest)):
                starts = "pr"
        asc = tool_args(words, "asc")
        if asc is not None and "xcode-cloud" in asc:
            after = asc[asc.index("xcode-cloud") + 1:]
            if ASC_CHANGES & {w for w in after if not w.startswith("-")}:
                return ("No Xcode Cloud run is started, and no workflow or product changed, at night: "
                        "a push to the PR starts its run."), None
    return None, starts


def safe_late(words):
    if words[0] in SAFE_LATE:
        return True
    return tool_args(words[:1], "git") is not None and git_call(words[1:])[1] in SAFE_LATE_GIT


def hook_decision(tool, command, now, stop, handoff, run_gate):
    """None to allow a card's tool call, else the reason it's denied. run_gate(starts) is None when
    one more Xcode Cloud run fits tonight, else why not; it is called only for a call that may
    start one."""
    late = now >= stop
    late_reason = (f"It is past {STOP_HOUR} am, so the night starts nothing new. Commit what builds, "
                   f"write the handoff note to {handoff}, and end your turn.")
    if tool in ("Agent", "Task"):
        return late_reason if late else None
    if tool != "Bash":
        return None
    never, starts = call_risks(command)
    if never:
        return never
    if late and (starts or not all(safe_late(words) for words in commands(command))):
        return late_reason
    if starts:
        why = run_gate(starts)
        if why:
            return (f"This would start an Xcode Cloud run, and {why}. Don't push or open the PR: park "
                    "the card, saying so in your last line.")
    return None


def digest_block(pr, sha, files, proof):
    areas = sorted({"/".join(f.split("/")[:2]) if f.startswith("Packages/") else f.split("/")[0]
                    for f in files})
    return f"#{pr['number']} {pr['title']} — {sha[:7]} — {', '.join(areas)} — {proof} — undo: git revert {sha[:7]}"


# The world: git, gh, asc, the board, and claude.

def sh(*args, cwd=ROOT, stdin=None, check=True):
    result = subprocess.run(args, cwd=cwd, input=stdin, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(f"{' '.join(args)}: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout


def gh_json(*args):
    return json.loads(sh("gh", *args))


def board_cards():
    """[(id, status, feature, title, body)] in board order: one list and one show request."""
    rows = []
    for line in sh(str(ROOT / "scripts/board.sh"), "list").splitlines():
        head, feature, title = line.split("\t", 2)
        item, status = head.split(None, 1)
        rows.append((item, status.strip(), feature, title))
    todo = [r for r in rows if r[1] == "Todo" and r[2] == "-"]
    if not todo:
        return []
    shown = sh(str(ROOT / "scripts/board.sh"), "show", *[r[0] for r in todo][:100])
    # show prints a "==> id <==" header before each card only when it shows more than one.
    bodies = (dict(re.findall(r"^==> (\S+) <==\n(.*?)(?=^==> |\Z)", shown, re.M | re.S))
              if len(todo) > 1 else {todo[0][0]: shown})
    return [(*r, bodies.get(r[0], "")) for r in todo]


def board(*args, stdin=None):
    sh(str(ROOT / "scripts/board.sh"), *args, stdin=stdin)


def classify(files):
    return sh(str(ROOT / "scripts/pr-check.sh"), "classify", stdin="\n".join(files) + "\n").strip()


def xcode_cloud_runs(limit=200):
    out = sh("asc", "xcode-cloud", "build-runs", "--workflow-id", PR_WORKFLOW, "--sort", "-number",
             "--limit", str(limit))
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


def tidy():
    subprocess.run([str(ROOT / "scripts/tidy.sh")], cwd=ROOT, check=False)


def slug(title):
    words = re.findall(r"[a-z0-9]+", title.lower())
    return "night-" + "-".join(words[:6])


class Night:
    def __init__(self, folder, now, dry_run):
        self.dir = Path(folder).resolve()
        self.now = now
        self.dry_run = dry_run
        self.window = night_window(now)
        self.merged = []  # (pr, merge commit, files, head, verifier's commit)
        self.parked = []
        self.waiting = []
        self.usage = []
        self.tried = set()
        self.cards = 0
        self.me = None  # the account the verifier comments as, read once a night
        self.ended = "no card was eligible"

    def logs(self):
        return sorted(self.dir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime)


    def run(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        self.start = datetime.now().astimezone()
        self.tests_before = {}
        self.current = None  # the card being taken, which a failure leaves In Progress
        try:
            self.loop()
        except Exception as error:  # noqa: BLE001 - whatever failed, the night ends with a digest saying so
            # Nothing after a failure is trusted: end the night.
            self.ended = log(f"No more cards: the runner failed: {type(error).__name__}: {error}")
            if self.current:
                self.left_in_progress(self.current, error)
        return self.finish()

    def loop(self):
        sh("git", "fetch", "--quiet", "origin", "main")
        self.tests_before = test_counts("origin/main")
        if not self.window:
            self.ended = log(f"No tooling cards: they start only from midnight to {CUTOFF_HOUR} am.")
            return
        cutoff, stop = self.window
        while True:
            info = last_rate_limit(self.logs())
            uncapped = is_uncapped(info, stop)
            now = self.clock()
            if now >= cutoff:
                self.ended = log(f"No more cards: it is past {CUTOFF_HOUR} am.")
                return
            if not cards_left(self.cards, uncapped):
                self.ended = log(f"No more cards: {self.cards} tonight, the limit on a night the weekly "
                                 "limit doesn't reset.")
                return
            decision, detail = usage_gate(info, now, cutoff, stop, uncapped)
            if decision == "stop":
                self.ended = log(f"No more cards: {detail}.")
                return
            if decision == "wait":
                log(f"Waiting for the five-hour window to reset at {detail:%H:%M}.")
                if self.dry_run:
                    return
                time.sleep(max(0, (detail - datetime.now().astimezone()).total_seconds()) + 60)
                continue
            card = self.next_card()
            if not card:
                return
            if self.dry_run:
                self.show_plan(card, info, uncapped)
                return
            self.cards += 1
            self.current = card
            if self.take(card, info) == "stop":
                return
            self.current = None

    def left_in_progress(self, card, error):
        """Says on the card, and in the digest, that the runner failed while taking it."""
        item, title, _ = card
        self.parked.append(f"{title}: the runner failed ({error}); it is still In Progress, so check "
                           "its card, worktree, and PR")
        try:
            board("state", item, stdin=f"- The nightly run of {self.start:%Y-%m-%d} failed while taking this "
                  f"card ({type(error).__name__}: {error}), so it is still In Progress and its PR, if any, is "
                  "as the card's run left it.\n- Next: a daytime /onward reads the PR and the handoff in "
                  "`.slices/`.\n")
        except Exception as again:  # noqa: BLE001 - the digest still says so
            self.parked[-1] += f"; writing its State failed too ({again})"

    def clock(self):
        return self.now if self.dry_run else datetime.now().astimezone()

    def next_card(self):
        """The first eligible card that won't collide with an open PR or the Xcode Cloud budget."""
        runs = xcode_cloud_runs()
        self.hours = month_hours(runs, self.clock())
        self.runs_tonight = runs_tonight(runs, self.start, self.dir)
        open_prs = gh_json("pr", "list", "--state", "open", "--json", "number,files")
        open_files = {pr["number"]: [f["path"] for f in pr["files"]] for pr in open_prs}
        # The cards and main's files, read once a night: the runner's own moves are in self.tried.
        if not hasattr(self, "cards_tonight"):
            self.cards_tonight = board_cards()
            self.repo_files = set(sh("git", "ls-tree", "-r", "--name-only", "origin/main").split())
        repo_files = self.repo_files
        for item, status, feature, title, body in self.cards_tonight:
            if item in self.tried:
                continue
            why = eligibility(status, feature, body)
            likely = likely_files(body, repo_files)
            if not why:
                clashes = {n: overlap(likely, files) for n, files in open_files.items()}
                clashes = {n: f for n, f in clashes.items() if f}
                if clashes:
                    why = "it may touch what " + ", ".join(f"#{n} ({', '.join(f)})" for n, f in clashes.items()) + " changes"
            if not why:
                # A card that names no files may change the app, so the budget applies to it too.
                app = not likely or classify(sorted(likely)) != "docs"
                why = app and xcode_cloud_gate(self.hours, self.runs_tonight)
            if why:
                if re.search(r"^Nightly:", body, re.M):
                    log(f"Skipped \"{title}\": {why}.")
                    self.tried.add(item)
                continue
            return item, title, body
        self.ended = log("No eligible tooling card left in Todo.")
        return None

    def command(self, item, worktree, branch, settings):
        return ["claude", "--name", "Nightly card", "-p", "--permission-mode", "auto",
                "--output-format", "stream-json", "--verbose", "--settings", str(settings),
                f"/nightly-card {item} {worktree} {branch}"]

    def paths(self, title):
        name = slug(title)
        main = Path(sh("git", "rev-parse", "--path-format=absolute", "--git-common-dir").strip()).parent
        worktree = main / ".claude/worktrees" / name
        n = 2
        while worktree.exists():
            worktree = main / ".claude/worktrees" / f"{name}-{n}"
            n += 1
        return worktree, worktree.name

    def settings(self, worktree, path):
        hook = f"/usr/bin/env python3 {ROOT / 'scripts/nightly-tooling.py'} hook {self.dir} {worktree}"
        path.write_text(json.dumps({
            "hooks": {"PreToolUse": [{"matcher": "Bash|Agent|Task",
                                      "hooks": [{"type": "command", "command": hook, "timeout": 60}]}]},
        }, indent=2))

    def git_env(self):
        """The environment for a card's claude: its git runs this night's pre-push hook, which
        refuses a push past the night's Xcode Cloud runs however the push was started."""
        hooks = self.dir / "git-hooks"
        hooks.mkdir(exist_ok=True)
        pre_push = hooks / "pre-push"
        pre_push.write_text(f"#!/bin/sh\nexec /usr/bin/env python3 {shlex.quote(str(ROOT / 'scripts/nightly-tooling.py'))} "
                            f"pre-push {shlex.quote(str(self.dir))}\n")
        pre_push.chmod(0o755)
        return {**os.environ, "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.hooksPath",
                "GIT_CONFIG_VALUE_0": str(hooks)}

    def show_plan(self, card, info, uncapped):
        item, title, _ = card
        worktree, branch = self.paths(title)
        log(f"Dry run: would take \"{title}\" ({item}).")
        log(f"  usage: {usage_line(info)}; {'uncapped' if uncapped else f'capped at {CAPPED_CARDS}'}")
        log(f"  Xcode Cloud: {self.hours:.1f} h this month, {self.runs_tonight} runs tonight")
        log(f"  worktree {worktree} on branch {branch}, from origin/main")
        log("  " + " ".join(self.command(item, worktree, branch, self.dir / "card-1-settings.json")))
        log("Stopped before changing anything.")

    def take(self, card, info):
        item, title, body = card
        self.tried.add(item)
        n = self.cards
        worktree, branch = self.paths(title)
        handoff = f".slices/{branch}-handoff.md"  # in the main checkout, the worktrees' parent
        sh("git", "fetch", "--quiet", "origin", "main")
        sh("git", "worktree", "add", "--no-track", str(worktree), "-b", branch, "origin/main")
        stop = self.window[1]
        (self.dir / "state.json").write_text(json.dumps(
            {"start": self.start.isoformat(), "stop": stop.isoformat(), "hours": self.hours,
             "handoff": str(worktree.parents[2] / handoff)}))
        settings = self.dir / f"card-{n}-settings.json"
        self.settings(worktree, settings)
        board("status", item, "In Progress")
        board("state", item, stdin=f"- Nightly run of {self.start:%Y-%m-%d}, card {n}: led by "
              f"scripts/nightly-tooling.py, not a session.\n- Worktree: `.claude/worktrees/{branch}`, "
              f"branch `{branch}`; handoff `{handoff}`.\n")
        log(f"Card {n}: \"{title}\" in {worktree}; usage before: {usage_line(info)}.")
        stream = self.dir / f"card-{n}.jsonl"
        deadline = stop + KILL_GRACE
        with stream.open("w") as out:
            process = subprocess.Popen(self.command(item, worktree, branch, settings), cwd=worktree,
                                       env=self.git_env(), stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT,
                                       text=True)
            try:
                process.wait(timeout=max(60, (deadline - datetime.now().astimezone()).total_seconds()))
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait()
        lines = stream.read_text(errors="replace").splitlines()
        after = last_rate_limit([stream])
        self.usage.append(f"{title}: {usage_line(info)} → {usage_line(after)}")
        reply = last_reply(lines)
        prs = gh_json("pr", "list", "--head", branch, "--state", "all",
                      "--json", "number,title,state,headRefOid,body,comments")
        pr = prs[0] if prs else None
        if limit_hit(lines):
            self.park(item, title, pr, "the usage limit stopped its run")
            self.ended = "A usage limit stopped a card's run."
            return "stop"
        if pr and pr["state"] == "MERGED":
            # Only the runner arms auto-merge, after every gate; a PR merged during the run skipped them.
            why = (f"PR #{pr['number']} was merged during the card's run, not by the runner, so none of "
                   f"its gates ran; review it, and undo with git revert")
            self.parked.append(f"{title}: {why}")
            board("state", item, stdin=f"- The nightly run found {why}.\n")
            self.ended = log(f"No more cards: {why}.")
            return "stop"
        if not pr:
            return self.park(item, title, None, f"no PR; its lead ended with: {reply or 'nothing'}")
        return self.decide(item, title, pr)

    def decide(self, item, title, pr):
        n, sha = pr["number"], pr["headRefOid"]
        sh("git", "fetch", "--quiet", "origin", f"pull/{n}/head", check=False)
        # Only a record the verifier posted counts: it comments as the account this runs as, and a
        # public repo's comments can come from anyone.
        self.me = self.me or sh("gh", "api", "user", "--jq", ".login").strip()
        record = verifier_record([c["body"] for c in pr["comments"]
                                  if (c.get("author") or {}).get("login") == self.me])
        if not record:
            return self.park(item, title, pr, "no verifier record on the PR")
        built, failures, unread = record
        if failures:
            return self.park(item, title, pr, "the verifier found " + "; ".join(f[2:] for f in failures))
        if unread:
            return self.park(item, title, pr, "its verifier record has lines the runner can't read: "
                             + "; ".join(unread))
        if not built:
            return self.park(item, title, pr, "its verifier record names no commit")
        if subprocess.run(["git", "merge-base", "--is-ancestor", built, sha], cwd=ROOT).returncode != 0:
            return self.park(item, title, pr, f"its verifier record names {built}, which isn't on the PR")
        later = sh("git", "diff", "--name-only", f"{built}..{sha}").split()
        if not only_tests(later):
            return self.park(item, title, pr, "changes after the verifier's build that it never saw")
        base = sh("git", "merge-base", "origin/main", sha).strip()
        drops = unexplained_drops(test_drops(test_counts(base), test_counts(sha)), pr["body"] or "")
        if drops:
            return self.park(item, title, pr, "fewer tests (" + ", ".join(f"{t} {b} → {a}" for t, b, a in drops)
                             + f") and no line in its body starting \"{FEWER_TESTS}\" that names the target")
        # Without rename detection a renamed file lists its old path too.
        files = sh("git", "diff", "--name-only", "--no-renames", base, sha).split()
        touched = protected(files)
        if touched or day_only(files):
            why = (f"it touches {', '.join(touched)}, which a night never merges" if touched
                   else "it changes only .claude/ and docs/, which waits for the day")
            self.waiting.append(f"#{n} {pr['title']}: {why}")
            board("state", item, stdin=f"- PR #{n} waits for the maintainer, unmerged: {why}.\n")
            log(f"#{n} waits for the maintainer: {why}.")
            return "waiting"
        sh("gh", "pr", "merge", str(n), "--auto", "--squash", "--match-head-commit", sha)
        log(f"#{n}: verifier passed; auto-merge armed at {sha[:7]}.")
        merged = self.wait_merge(n)
        if not merged:
            return self.park(item, title, pr, "its PR check failed, or didn't finish within the hour")
        board("status", item, "Done")
        self.merged.append((pr, merged, files, sha, built))
        log(f"#{n} merged as {merged[:7]}.")
        return "merged"

    def wait_merge(self, n):
        """The merge commit, or None when the checks failed or the hour ran out."""
        try:
            subprocess.run(["gh", "pr", "checks", str(n), "--watch", "--interval", "60", "--required"],
                           cwd=ROOT, capture_output=True, timeout=3600, check=False)
        except subprocess.TimeoutExpired:
            pass
        for _ in range(10):
            pr = gh_json("pr", "view", str(n), "--json", "state,mergeCommit,statusCheckRollup")
            if pr["state"] == "MERGED":
                return pr["mergeCommit"]["oid"]
            # A check run has a conclusion; a commit status, such as Xcode Cloud's, a state.
            if any(c.get("conclusion") in ("FAILURE", "CANCELLED", "TIMED_OUT")
                   or c.get("state") in ("FAILURE", "ERROR") for c in pr["statusCheckRollup"]):
                return None
            time.sleep(60)
        return None

    def proof(self, runs, sha, built, files):
        check = "PR check passed, lint only"
        if classify(files) != "docs":
            run = next((r for r in runs
                        if (r["attributes"].get("sourceCommit") or {}).get("commitSha") == sha), None)
            check = f"PR check passed on Xcode Cloud run {run['attributes']['number']}" if run else "PR check passed"
        return f"verifier record at {built}, {check}"

    def park(self, item, title, pr, why):
        if pr:
            n = str(pr["number"])
            sh("gh", "pr", "merge", n, "--disable-auto", check=False)
            sh("gh", "pr", "ready", n, "--undo", check=False)
        where = f"PR #{pr['number']} is a draft with auto-merge off" if pr else "no PR"
        board("state", item, stdin=f"- Parked by the nightly run: {why}. {where}.\n- Next: "
              "a daytime /onward reads the PR and the handoff in `.slices/`.\n")
        self.parked.append(f"{title}: {why} ({where})")
        log(f"Parked \"{title}\": {why}.")
        return "parked"

    def finish(self):
        if self.dry_run:
            return
        try:
            lines = self.digest()
        except Exception as error:  # noqa: BLE001 - the digest is written whatever fails
            lines = [f"Nightly tooling {self.start:%Y-%m-%d}: the digest failed ({type(error).__name__}: {error})",
                     *[f"Parked: {p}" for p in self.parked], *[f"Waiting: {w}" for w in self.waiting],
                     f"Ended: {self.ended}"]
        text = "\n".join(lines)
        (self.dir / "digest.md").write_text(text + "\n")
        print(text)
        tidy()

    def digest(self):
        now = datetime.now().astimezone()
        # A read that fails says so in the Ended line, and the rest of the digest is still written.
        try:
            runs = xcode_cloud_runs()
        except FAILURES as error:
            runs, self.ended = [], f"{self.ended} Reading Xcode Cloud's runs failed: {error}"
        try:
            sh("git", "fetch", "--quiet", "origin", "main")
            after = test_counts("origin/main")
        except FAILURES as error:
            after, self.ended = {}, f"{self.ended} Counting main's tests failed: {error}"
        try:
            behind = [pr for pr in gh_json("pr", "list", "--state", "open",
                                           "--json", "number,title,mergeStateStatus")
                      if pr["mergeStateStatus"] == "BEHIND"]
        except FAILURES as error:
            behind, self.ended = [], f"{self.ended} Reading the open PRs failed: {error}"
        lines = [f"Nightly tooling {self.start:%Y-%m-%d}: {len(self.merged)} merged, "
                 f"{len(self.parked)} parked, {len(self.waiting)} waiting for the maintainer"]
        lines += [digest_block(pr, merged, files, self.proof(runs, sha, built, files))
                  for pr, merged, files, sha, built in self.merged]
        lines.append(f"Xcode Cloud: {runs_tonight(runs, self.start, self.dir)} runs tonight, "
                     f"{month_hours(runs, now):.1f} h this month")
        lines.append("Tests: " + ", ".join(f"{t} {self.tests_before.get(t, 0)} → {after.get(t, 0)}"
                                           for t in sorted(set(self.tests_before) | set(after))))
        lines += [f"Parked: {p}" for p in self.parked]
        lines += [f"Waiting: {w}" for w in self.waiting]
        lines += [f"Behind main: #{pr['number']} {pr['title']}" for pr in behind]
        lines += [f"Usage: {u}" for u in self.usage]
        lines.append(f"Ended: {self.ended}")
        return lines


def usage_line(info):
    parts = []
    for name, w in sorted(windows(info).items()):
        read = window(w)
        parts.append(f"{name} {read[0]:.2f}" if read else f"{name} unreadable")
    return ", ".join(parts) or "unknown"


def last_reply(lines):
    for event in reversed(list(events(lines))):
        if event.get("type") == "result":
            reply = str(event.get("result") or "").strip().splitlines()
            return reply[-1] if reply else ""
    return ""


def hook(folder, worktree):
    """The PreToolUse hook: exit 2 with the reason on stderr denies the call. It fails closed: any
    error denies the call, since Claude Code runs a call whose hook exits with anything else."""
    try:
        why = hook_check(Path(folder), worktree)
    except Exception as error:  # noqa: BLE001 - an error must deny, whatever it is
        why = (f"The nightly hook failed ({type(error).__name__}: {error}), so it denies this call. "
               "Park the card, saying so in your last line.")
    if why:
        print(why, file=sys.stderr)
        sys.exit(2)


def hook_check(folder, worktree):
    call = json.load(sys.stdin)
    state = json.loads((folder / "state.json").read_text())
    now = datetime.now().astimezone()
    # A push's start is recorded by the pre-push hook it then meets; a PR's here.
    return hook_decision(call["tool_name"], (call.get("tool_input") or {}).get("command") or "", now,
                         datetime.fromisoformat(state["stop"]), state["handoff"],
                         lambda starts: run_budget(folder, worktree, state, record=starts != "push"))


def run_budget(folder, worktree, state, record):
    """None when the branch's changes are docs, or one more Xcode Cloud run fits tonight, else why
    not. Tonight's runs are counted from Xcode Cloud itself, so a run counts however it started;
    this month's hours are the runner's reading at the card's start."""
    files = sh("git", "diff", "--name-only", "origin/main...HEAD", cwd=worktree).split()
    if not files or classify(files) == "docs":
        return None
    # The night's runs are among the newest few; a cap of four needs no more.
    runs = xcode_cloud_runs(limit=20)
    why = xcode_cloud_gate(state["hours"], runs_tonight(runs, datetime.fromisoformat(state["start"]), folder))
    if not why and record:
        with (folder / "starts").open("a") as out:
            out.write(f"{datetime.now().astimezone().isoformat()} {worktree}\n")
    return why


def pre_push(folder):
    """The git pre-push hook of a card's claude, run in the worktree: exit 1 refuses the push. It
    fails closed, like the PreToolUse hook."""
    folder = Path(folder)
    try:
        state = json.loads((folder / "state.json").read_text())
        why = run_budget(folder, os.getcwd(), state, record=True)
    except Exception as error:  # noqa: BLE001 - an error must refuse, whatever it is
        why = f"the nightly pre-push hook failed ({type(error).__name__}: {error})"
    if why:
        print(f"Nightly runner: this push would start an Xcode Cloud run, and {why}. Don't push: park "
              "the card, saying so in your last line.", file=sys.stderr)
        sys.exit(1)


def main(args):
    if args[:1] == ["run"] and len(args) >= 2:
        now = datetime.now().astimezone()
        if "--now" in args:
            now = datetime.fromisoformat(args[args.index("--now") + 1]).astimezone()
        Night(args[1], now, "--dry-run" in args).run()
    elif args[:1] == ["hook"] and len(args) == 3:
        hook(args[1], args[2])
    elif args[:1] == ["pre-push"] and len(args) == 2:
        pre_push(args[1])
    elif args[:1] == ["digest"]:
        folders = [Path(args[1])] if len(args) > 1 else sorted((ROOT / ".build/retro").glob("20*"))
        if not folders:
            print("No nightly tooling digest yet.")
        elif (folders[-1] / "digest.md").exists():
            print((folders[-1] / "digest.md").read_text().rstrip())
        else:
            # Never an earlier night's digest, which would read as this one's.
            print(f"No tooling digest for {folders[-1].name}: the runner is still going, or ended "
                  "without one; its output is in .build/retro/nightly.log.")
    else:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        sys.exit(64)


if __name__ == "__main__":
    main(sys.argv[1:])
