#!/usr/bin/env python3
"""An Xcode Cloud PR run's times against the budgets in scripts/xcresult.py.

    scripts/ci-times.py <branch>        the newest run of the branch's commits
    scripts/ci-times.py --run <number>  that run

Prints the run's number and commit, its time from start to finish against its budget and the
4-minute aim, and, once it has finished, each test target's time and each UI test's, as
scripts/test.sh sim prints them locally. Reported, never failed: it exits 0 whatever the
times, 1 only when it can't find the run. It reads App Store Connect through `asc`, with three
or four calls: the workflow's last 50 runs, the run's actions, and its test results. On Xcode
Cloud a parameterized test reports one time, so a serial target's time can read low by its
extra cases.
"""
import json
import pathlib
import re
import subprocess
import sys
from datetime import datetime

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from xcresult import BUDGETS, ROOT, RUN_AIM, budget_lines, over, serial_targets  # noqa: E402

PR_WORKFLOW = "FE8B3BCC-1973-4533-BB66-4D047A8E3C22"  # docs/xcode-cloud.md, "PR"


def asc(*args):
    result = subprocess.run(["asc", "xcode-cloud", *args], capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"asc xcode-cloud {' '.join(args)} failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)


def when(stamp):
    return datetime.fromisoformat(stamp.replace("Z", "+00:00"))


def find_run(runs, branch=None, number=None):
    if number is not None:
        return next((r for r in runs if r["attributes"]["number"] == number), None)
    # The branch's recent commits, newest first; the newest run of the newest one that ran.
    ref = f"origin/{branch}" if git("rev-parse", "--verify", f"origin/{branch}").returncode == 0 else branch
    log = git("rev-list", "--max-count=50", ref)
    if log.returncode != 0:
        sys.exit(f"no branch {branch!r} here; fetch it, or pass --run <number>")
    for sha in log.stdout.split():
        matches = [r for r in runs if r["attributes"]["sourceCommit"]["commitSha"] == sha]
        if matches:
            return max(matches, key=lambda r: r["attributes"]["number"])
    return None


def target_of(class_name, design_system_types):
    if class_name.endswith("UITests"):
        return "PlusPlusUITests"
    return "DesignSystemTests" if class_name in design_system_types else "WorkoutStoreTests"


def design_system_types(sha):
    # The suites DesignSystemTests declares at the run's commit, so no list here goes stale.
    files = git("ls-tree", "-r", "--name-only", sha, "Packages/Tests/DesignSystemTests").stdout
    types = set()
    for path in files.split():
        if path.endswith(".swift"):
            text = git("show", f"{sha}:{path}").stdout
            types.update(re.findall(r"\b(?:struct|class|enum|extension)\s+(\w+)", text))
    return types


def main(argv):
    if len(argv) == 2 and not argv[1].startswith("-"):
        branch, number = argv[1], None
    elif len(argv) == 3 and argv[1] == "--run" and argv[2].isdigit():
        branch, number = None, int(argv[2])
    else:
        print(__doc__, file=sys.stderr)
        return 64
    runs = asc("build-runs", "--workflow-id", PR_WORKFLOW, "--sort", "-number", "--limit", "50")["data"]
    run = find_run(runs, branch, number)
    if not run:
        what = f"run {number}" if number is not None else f"a run of {branch}'s last 50 commits"
        print(f"no Xcode Cloud PR run found for {what} among the last 50; it may not have started yet")
        return 1
    a = run["attributes"]
    sha = a["sourceCommit"]["commitSha"]
    if git("cat-file", "-e", f"{sha}^{{commit}}").returncode != 0:
        git("fetch", "--quiet", "origin", sha)  # the run's test plan and suites are read from it
    print(f"Xcode Cloud run {a['number']} on {sha[:7]}: {a.get('completionStatus') or a['executionProgress']}")
    budget = BUDGETS["run"][1]
    if not a.get("finishedDate"):
        if a.get("startedDate"):
            elapsed = (datetime.now(when(a["startedDate"]).tzinfo) - when(a["startedDate"])).total_seconds()
            print(f"  running for {elapsed:.0f} s so far (budget {budget} s, aim {RUN_AIM} s)")
        return 0
    total = (when(a["finishedDate"]) - when(a["startedDate"])).total_seconds()
    print(f"  start to finish {over(total, budget)}, aim {RUN_AIM} s")
    actions = asc("actions", "--run-id", run["id"])["data"]
    test = next((x for x in actions if x["attributes"]["actionType"] == "TEST"), None)
    if not test:
        print("  no test action in this run")
        return 0
    results = asc("test-results", "list", "--action-id", test["id"], "--limit", "200", "--paginate")["data"]
    types = design_system_types(sha)
    rows = []
    for r in results:
        attrs = r["attributes"]
        seconds = max((d.get("duration") or 0 for d in attrs.get("destinationTestResults") or []), default=0)
        rows.append((target_of(attrs["className"], types), f"{attrs['className']}/{attrs['name']}", seconds))
    plan = git("show", f"{sha}:PlusPlus.xctestplan")
    if plan.returncode != 0:
        sys.exit(f"can't read {sha[:7]}'s test plan: {plan.stderr.strip()}")
    serial = serial_targets(plan.stdout)
    for line in budget_lines(rows, serial, 1):
        print(f"  {line}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
