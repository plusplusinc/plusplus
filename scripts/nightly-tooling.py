#!/usr/bin/env python3
"""After the nightly retro, runs eligible tooling cards one at a time, each with its own lead.

    scripts/nightly-tooling.py run <night-dir> [--dry-run] [--now 2026-10-29T01:30]
    scripts/nightly-tooling.py hook <night-dir> <worktree>   # a card's PreToolUse hook
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

`hook` is the PreToolUse hook `run` gives each card's claude through --settings: it denies
`gh pr merge`, a push that would start an Xcode Cloud run past the night's four or past 70
hours this month, and, from 7 am, any new agent or anything but writing the handoff.

Tests: python3 scripts/nightly-tooling-test.py, against fixtures, with no network.
"""
import fnmatch
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# The main checkout, under which cards get their worktrees, whichever checkout this runs from.
MAIN = Path(subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True).stdout.strip() or ROOT / ".git").parent
PR_WORKFLOW = "FE8B3BCC-1973-4533-BB66-4D047A8E3C22"  # docs/xcode-cloud.md, "PR"

CUTOFF_HOUR = 5  # no card starts at or after this hour
STOP_HOUR = 7  # nothing new starts at all; a running builder writes its handoff
KILL_GRACE = timedelta(minutes=45)  # past STOP_HOUR, a card's claude is stopped
CAPPED_CARDS = 3
USAGE_STOP = 0.9
# On the uncapped night, a five-hour window still open in the morning keeps this much free.
MORNING_RESERVE = 0.5
HOURS_LIMIT = 70  # this month's Xcode Cloud PR hours, of the plan's 100
PUSH_LIMIT = 4  # pushes a night that start an Xcode Cloud run

# A PR touching one of these is never merged at night (fnmatch, where * also matches /). The
# runner's own files are here too, so no night can loosen its gates.
PROTECTED = [
    ".github/workflows/*", "scripts/pr-check.sh", ".github/no-code-paths",
    ".claude/settings*.json", "Config/*.xcconfig", "*project.pbxproj",
    "Packages/Package.swift", "*.xctestplan", "*.entitlements", "ci_scripts/*",
    ".swiftlint.yml", "*/.swiftlint.yml", ".swiftformat", "*/.swiftformat",
    "scripts/nightly-tooling.py", "scripts/nightly-tooling-test.py", "scripts/nightly-retro.sh",
    ".claude/skills/nightly-card/*",
]
DAY_ONLY = (".claude/", "docs/")  # a PR entirely under these waits for the day
TEST_DIRS = ("Packages/Tests", "PlusPlusUITests")
TEST_PATTERN = r"@Test([^A-Za-z]|$)|func test[A-Z_]"
FEWER_TESTS = "Fewer tests:"  # the PR body's line that explains a drop


def die(message):
    sys.exit(message)


def log(message):
    print(f"{datetime.now().strftime('%H:%M')} {message}", flush=True)
    return message


def local(stamp):
    """A unix time as a local datetime."""
    return datetime.fromtimestamp(stamp).astimezone()


def when(stamp):
    """An ISO timestamp with any number of fraction digits (see scripts/ci-times.py)."""
    stamp = re.sub(r"\.(\d+)", lambda m: "." + m[1][:6].ljust(6, "0"), stamp)
    return datetime.fromisoformat(stamp.replace("Z", "+00:00"))


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
    windows = (info or {}).get("unifiedWindows") or {}
    weekly = {name: w for name, w in windows.items() if name != "five_hour"}
    return bool(weekly) and all(w["resetsAt"] <= stop.timestamp() for w in weekly.values())


def usage_gate(info, now, cutoff, stop, uncapped):
    """("go", None), ("wait", until), or ("stop", why), from a rate_limit_event's rate_limit_info.

    Every window counts, whatever its name; one whose reset has passed counts as fresh. A full
    five-hour window waits for its reset only when that lands before the cutoff.
    """
    windows = (info or {}).get("unifiedWindows") or {}
    if not windows:
        return "stop", "no rate_limit_event in tonight's logs, so usage is unknown"
    wait = None
    for name, w in sorted(windows.items()):
        resets = local(w["resetsAt"])
        if resets <= now:
            continue
        used = w.get("utilization") or 0
        state = f"{name} at {used:.2f} ({w.get('status')}), resets {resets:%a %H:%M}"
        if w.get("status") != "allowed" or used >= USAGE_STOP:
            if name == "five_hour" and resets < cutoff:
                wait = max(wait or resets, resets)
                continue
            return "stop", state
        if uncapped and name == "five_hour" and resets > stop and used >= 1 - MORNING_RESERVE:
            return "stop", f"{state}; keeping {MORNING_RESERVE:.0%} of it for the morning"
    return ("wait", wait) if wait else ("go", None)


def cards_left(count, uncapped):
    return True if uncapped else count < CAPPED_CARDS


def last_rate_limit(paths):
    """The rate_limit_info of the last rate_limit_event in these stream-json logs, oldest first."""
    found = None
    for path in paths:
        for line in Path(path).read_text(errors="replace").splitlines():
            if '"rate_limit_event"' not in line:
                continue
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if event.get("type") == "rate_limit_event":
                found = event.get("rate_limit_info")
    return found


def limit_hit(lines):
    """Whether a claude run's stream-json lines end in a usage limit."""
    for line in lines:
        if "usage_limit_reached" in line:
            return True
        try:
            event = json.loads(line)
        except ValueError:
            continue
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


def xcode_cloud_gate(month_hours, pushes, app_card):
    """None, or why a card that would start an Xcode Cloud run can't start tonight."""
    if not app_card:
        return None
    if month_hours > HOURS_LIMIT:
        return f"{month_hours:.1f} Xcode Cloud hours this month, above {HOURS_LIMIT}"
    if pushes >= PUSH_LIMIT:
        return f"{pushes} pushes tonight started Xcode Cloud runs, the night's limit"
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


def verifier_record(comments):
    """(hash, failures) of the newest "Verifier record" comment, or None when there is none."""
    records = [c for c in comments if c.startswith("Verifier record")]
    if not records:
        return None
    lines = records[-1].splitlines()
    match = re.match(r"Verifier record, (\w+)", lines[0])
    failures = [line for line in lines[1:] if re.match(r"- (criterion|crash),", line)]
    return (match[1] if match else None), failures


def only_tests(files):
    """Whether these files are all tests, which a verifier adds after its build."""
    return all(re.search(r"test", f, re.I) for f in files)


def test_drops(before, after):
    return [(t, before[t], after.get(t, 0)) for t in sorted(before) if after.get(t, 0) < before[t]]


SAFE_LATE = re.compile(r"^(cd|ls|cat|head|tail|grep|git( -C \S+)? (add|commit|status|diff|log|show|rev-parse))\b")


def hook_decision(tool, command, now, stop, app_push, pushes, hours, handoff):
    """None to allow a card's tool call, else the reason it's denied."""
    late = now >= stop
    late_reason = (f"It is past {STOP_HOUR} am, so the night starts nothing new. Commit what builds, "
                   f"write the handoff note to {handoff}, and end your turn.")
    if tool in ("Agent", "Task"):
        return late_reason if late else None
    if tool != "Bash":
        return None
    if re.search(r"\bgh\s+pr\s+merge\b", command):
        return "The nightly runner arms auto-merge itself, once the verifier has passed. Never merge."
    pushing = re.search(r"\bgit\b[^;&|\n]*\bpush\b", command)
    if late:
        segments = [s.strip() for s in re.split(r"&&|\|\||;|\n", command) if s.strip()]
        if pushing or not all(SAFE_LATE.match(s) for s in segments):
            return late_reason
    if pushing and app_push:
        why = xcode_cloud_gate(hours, pushes, True)
        if why:
            return (f"This push would start an Xcode Cloud run, and {why}. Don't push: park the "
                    "card, saying so in your last line.")
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
    bodies = dict(re.findall(r"^==> (\S+) <==\n(.*?)(?=^==> |\Z)", shown, re.M | re.S))
    return [(*r, bodies.get(r[0], "")) for r in todo]


def board(*args, stdin=None):
    sh(str(ROOT / "scripts/board.sh"), *args, stdin=stdin)


def classify(files):
    return sh(str(ROOT / "scripts/pr-check.sh"), "classify", stdin="\n".join(files) + "\n").strip()


def xcode_cloud_runs():
    out = sh("asc", "xcode-cloud", "build-runs", "--workflow-id", PR_WORKFLOW, "--sort", "-number",
             "--limit", "200")
    return json.loads(out)["data"]


def test_counts(rev):
    out = sh("git", "grep", "-c", "-E", TEST_PATTERN, rev, "--", *TEST_DIRS, check=False)
    counts = {}
    for line in out.splitlines():
        path, n = line.split(":", 1)[1].rsplit(":", 1)
        parts = path.split("/")
        target = parts[2] if parts[0] == "Packages" else parts[0]
        counts[target] = counts.get(target, 0) + int(n)
    return counts


def slug(title):
    words = re.findall(r"[a-z0-9]+", title.lower())
    return "night-" + "-".join(words[:6])


class Night:
    def __init__(self, folder, now, dry_run):
        self.dir = Path(folder).resolve()
        self.now = now
        self.dry_run = dry_run
        self.window = night_window(now)
        self.digest = []
        self.parked = []
        self.waiting = []
        self.usage = []
        self.tried = set()
        self.cards = 0
        self.ended = "no card was eligible"

    def logs(self):
        return sorted(self.dir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime)

    def state(self, **values):
        path = self.dir / "state.json"
        current = json.loads(path.read_text()) if path.exists() else {}
        current.update(values)
        path.write_text(json.dumps(current))

    def run(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        self.start = datetime.now().astimezone()
        sh("git", "fetch", "--quiet", "origin", "main")
        self.tests_before = test_counts("origin/main")
        if not self.window:
            self.ended = log(f"No tooling cards: they start only from midnight to {CUTOFF_HOUR} am.")
            return self.finish()
        cutoff, stop = self.window
        while True:
            info = last_rate_limit(self.logs())
            uncapped = is_uncapped(info, stop)
            now = self.clock()
            if now >= cutoff:
                self.ended = log(f"No more cards: it is past {CUTOFF_HOUR} am.")
                break
            if not cards_left(self.cards, uncapped):
                self.ended = log(f"No more cards: {self.cards} tonight, the limit on a night the weekly "
                                 "limit doesn't reset.")
                break
            decision, detail = usage_gate(info, now, cutoff, stop, uncapped)
            if decision == "stop":
                self.ended = log(f"No more cards: {detail}.")
                break
            if decision == "wait":
                log(f"Waiting for the five-hour window to reset at {detail:%H:%M}.")
                if self.dry_run:
                    break
                time.sleep(max(0, (detail - datetime.now().astimezone()).total_seconds()) + 60)
                continue
            card = self.next_card()
            if not card:
                break
            if self.dry_run:
                self.show_plan(card, info, uncapped)
                break
            self.cards += 1
            try:
                if self.take(card, info) == "limit":
                    self.ended = "A usage limit stopped a card's run."
                    break
            except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
                # Nothing after a failure is trusted: end the night, with the digest saying why.
                self.ended = log(f"No more cards: the runner failed on \"{card[1]}\": {error}")
                self.parked.append(f"{card[1]}: the runner failed ({error}); check its card, worktree, and PR")
                break
        return self.finish()

    def clock(self):
        return self.now if self.dry_run else datetime.now().astimezone()

    def next_card(self):
        """The first eligible card that won't collide with an open PR or the Xcode Cloud budget."""
        runs = xcode_cloud_runs()
        self.hours = month_hours(runs, self.clock())
        self.pushes = self.push_count()
        open_prs = gh_json("pr", "list", "--state", "open", "--json", "number,files")
        open_files = {pr["number"]: [f["path"] for f in pr["files"]] for pr in open_prs}
        repo_files = set(sh("git", "ls-tree", "-r", "--name-only", "origin/main").split())
        for item, status, feature, title, body in board_cards():
            if item in self.tried:
                continue
            why = eligibility(status, feature, body)
            likely = likely_files(body, repo_files)
            if not why:
                clashes = {n: overlap(likely, files) for n, files in open_files.items()}
                clashes = {n: f for n, f in clashes.items() if f}
                if clashes:
                    why = "it may touch what " + ", ".join(f"#{n} ({', '.join(f)})" for n, f in clashes.items()) + " changes"
            if not why and likely:
                why = xcode_cloud_gate(self.hours, self.pushes, classify(sorted(likely)) != "docs")
            if why:
                if re.search(r"^Nightly:", body, re.M):
                    log(f"Skipped \"{title}\": {why}.")
                    self.tried.add(item)
                continue
            return item, title, body
        self.ended = log("No eligible tooling card left in Todo.")
        return None

    def push_count(self):
        path = self.dir / "pushes"
        return len(path.read_text().splitlines()) if path.exists() else 0

    def command(self, item, worktree, branch, settings):
        return ["claude", "--name", "Nightly card", "-p", "--permission-mode", "auto",
                "--output-format", "stream-json", "--verbose", "--settings", str(settings),
                f"/nightly-card {item} {worktree} {branch}"]

    def paths(self, title):
        name = slug(title)
        worktree = MAIN / ".claude/worktrees" / name
        n = 2
        while worktree.exists():
            worktree = MAIN / ".claude/worktrees" / f"{name}-{n}"
            n += 1
        return worktree, worktree.name

    def settings(self, worktree, handoff, path):
        hook = f"/usr/bin/env python3 {ROOT / 'scripts/nightly-tooling.py'} hook {self.dir} {worktree}"
        path.write_text(json.dumps({
            "permissions": {"deny": ["Bash(gh pr merge:*)"]},
            "hooks": {"PreToolUse": [{"matcher": "Bash|Agent|Task",
                                      "hooks": [{"type": "command", "command": hook, "timeout": 60}]}]},
        }, indent=2))

    def show_plan(self, card, info, uncapped):
        item, title, _ = card
        worktree, branch = self.paths(title)
        log(f"Dry run: would take \"{title}\" ({item}).")
        log(f"  usage: {usage_line(info)}; {'uncapped' if uncapped else f'capped at {CAPPED_CARDS}'}")
        log(f"  Xcode Cloud: {self.hours:.1f} h this month, {self.pushes} pushes tonight")
        log(f"  worktree {worktree} on branch {branch}, from origin/main")
        log("  " + " ".join(self.command(item, worktree, branch, self.dir / "card-1-settings.json")))
        log("Stopped before changing anything.")

    def take(self, card, info):
        item, title, body = card
        self.tried.add(item)
        n = self.cards
        worktree, branch = self.paths(title)
        handoff = f".slices/{branch}-handoff.md"
        sh("git", "fetch", "--quiet", "origin", "main")
        sh("git", "worktree", "add", "--no-track", str(worktree), "-b", branch, "origin/main")
        stop = self.window[1]
        self.state(stop=stop.isoformat(), hours=self.hours, handoff=handoff)
        settings = self.dir / f"card-{n}-settings.json"
        self.settings(worktree, handoff, settings)
        board("status", item, "In Progress")
        board("state", item, stdin=f"- Nightly run of {self.start:%Y-%m-%d}, card {n}: led by "
              f"scripts/nightly-tooling.py, not a session.\n- Worktree: `.claude/worktrees/{branch}`, "
              f"branch `{branch}`; handoff `{handoff}`.\n")
        log(f"Card {n}: \"{title}\" in {worktree}; usage before: {usage_line(info)}.")
        stream = self.dir / f"card-{n}.jsonl"
        deadline = stop + KILL_GRACE
        with stream.open("w") as out:
            process = subprocess.Popen(self.command(item, worktree, branch, settings), cwd=worktree,
                                       stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT,
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
                      "--json", "number,title,state,headRefOid,body")
        pr = prs[0] if prs else None
        if limit_hit(lines):
            self.park(item, title, pr, "the usage limit stopped its run")
            return "limit"
        if not pr:
            return self.park(item, title, None, f"no PR; its lead ended with: {reply or 'nothing'}")
        return self.decide(item, title, pr)

    def decide(self, item, title, pr):
        n, sha = pr["number"], pr["headRefOid"]
        sh("git", "fetch", "--quiet", "origin", f"pull/{n}/head", check=False)
        comments = json.loads(sh("gh", "pr", "view", str(n), "--json", "comments",
                                 "--jq", "[.comments[].body]"))
        record = verifier_record(comments)
        if not record:
            return self.park(item, title, pr, "no verifier record on the PR")
        built, failures = record
        if failures:
            return self.park(item, title, pr, "the verifier found " + "; ".join(f[2:] for f in failures))
        if not built:
            return self.park(item, title, pr, "its verifier record names no commit")
        later = sh("git", "diff", "--name-only", f"{built}..{sha}", check=False).split()
        if not only_tests(later):
            return self.park(item, title, pr, "changes after the verifier's build that it never saw")
        base = sh("git", "merge-base", "origin/main", sha).strip()
        drops = test_drops(test_counts(base), test_counts(sha))
        if drops and FEWER_TESTS not in pr["body"]:
            return self.park(item, title, pr, "fewer tests (" + ", ".join(f"{t} {b} → {a}" for t, b, a in drops)
                             + f") and no \"{FEWER_TESTS}\" line in its body")
        files = sh(str(ROOT / "scripts/pr-check.sh"), "files", str(n)).split()
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
        self.digest.append(digest_block(pr, merged, files, self.proof(n, sha, built, files)))
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

    def proof(self, n, sha, built, files):
        route = classify(files)
        check = "PR check passed, lint only"
        if route != "docs":
            run = next((r for r in xcode_cloud_runs()
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
        runs = xcode_cloud_runs()
        now = datetime.now().astimezone()
        sh("git", "fetch", "--quiet", "origin", "main")
        after = test_counts("origin/main")
        behind = [pr for pr in gh_json("pr", "list", "--state", "open",
                                       "--json", "number,title,mergeStateStatus")
                  if pr["mergeStateStatus"] == "BEHIND"]
        lines = [f"Nightly tooling {self.start:%Y-%m-%d}: {len(self.digest)} merged, "
                 f"{len(self.parked)} parked, {len(self.waiting)} waiting for the maintainer"]
        lines += self.digest
        lines.append(f"Xcode Cloud: {len(runs_since(runs, self.start))} runs tonight, "
                     f"{month_hours(runs, now):.1f} h this month")
        lines.append("Tests: " + ", ".join(f"{t} {self.tests_before.get(t, 0)} → {after.get(t, 0)}"
                                           for t in sorted(set(self.tests_before) | set(after))))
        lines += [f"Parked: {p}" for p in self.parked]
        lines += [f"Waiting: {w}" for w in self.waiting]
        lines += [f"Behind main: #{pr['number']} {pr['title']}" for pr in behind]
        lines += [f"Usage: {u}" for u in self.usage]
        lines.append(f"Ended: {self.ended}")
        text = "\n".join(lines)
        (self.dir / "digest.md").write_text(text + "\n")
        print(text)
        subprocess.run([str(ROOT / "scripts/tidy.sh")], cwd=ROOT, check=False)


def usage_line(info):
    windows = (info or {}).get("unifiedWindows") or {}
    return ", ".join(f"{n} {w.get('utilization', 0):.2f}" for n, w in sorted(windows.items())) or "unknown"


def last_reply(lines):
    for line in reversed(lines):
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get("type") == "result":
            reply = str(event.get("result") or "").strip().splitlines()
            return reply[-1] if reply else ""
    return ""


def hook(folder, worktree):
    """The PreToolUse hook: exit 2 with the reason on stderr denies the call."""
    call = json.load(sys.stdin)
    folder = Path(folder)
    state = json.loads((folder / "state.json").read_text())
    command = (call.get("tool_input") or {}).get("command", "")
    pushes_file = folder / "pushes"
    pushes = len(pushes_file.read_text().splitlines()) if pushes_file.exists() else 0
    app_push = False
    if call.get("tool_name") == "Bash" and re.search(r"\bgit\b[^;&|\n]*\bpush\b", command):
        files = sh("git", "diff", "--name-only", "origin/main...HEAD", cwd=worktree, check=False).split()
        app_push = bool(files) and classify(files) != "docs"
    why = hook_decision(call.get("tool_name"), command, datetime.now().astimezone(),
                        datetime.fromisoformat(state["stop"]), app_push, pushes, state["hours"],
                        state["handoff"])
    if why:
        print(why, file=sys.stderr)
        sys.exit(2)
    if app_push:
        with pushes_file.open("a") as out:
            out.write(f"{datetime.now().astimezone().isoformat()} {worktree}\n")


def main(args):
    if args[:1] == ["run"] and len(args) >= 2:
        now = datetime.now().astimezone()
        if "--now" in args:
            now = datetime.fromisoformat(args[args.index("--now") + 1]).astimezone()
        Night(args[1], now, "--dry-run" in args).run()
    elif args[:1] == ["hook"] and len(args) == 3:
        hook(args[1], args[2])
    elif args[:1] == ["digest"]:
        folders = [Path(args[1])] if len(args) > 1 else sorted((ROOT / ".build/retro").glob("20*"))
        digests = [f / "digest.md" for f in folders if (f / "digest.md").exists()]
        print(digests[-1].read_text().rstrip() if digests else "No nightly tooling digest yet.")
    else:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        sys.exit(64)


if __name__ == "__main__":
    main(sys.argv[1:])
