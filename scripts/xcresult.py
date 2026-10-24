#!/usr/bin/env python3
"""Compact summaries of an .xcresult bundle for humans and agents.

    scripts/xcresult.py build <bundle>   one line per error and warning, 1-based line numbers
    scripts/xcresult.py tests <bundle>   one-line totals plus each failure's message; exits 1
                                         when no tests ran or there is no summary
    scripts/xcresult.py times <bundle>   each test bundle's time against its local budget (wall
                                         time; a parallel UI target's also its tests' sum as
                                         cost), each UI test's, and any DesignSystem test over
                                         its own; reports only, and always exits 0
    scripts/xcresult.py package <log>    the package tests' time on macOS, from swift test's
                                         output, against its budget; always exits 0

The budgets are defined here once; scripts/test.sh and scripts/ci-times.py print against them,
and .claude/rules/testing.md's table repeats them. A run over budget is reported, never failed.

xcresulttool reports 0-based line numbers in its JSON; compilers and editors are 1-based, so
this adds one. Everything else is passed through as-is.
"""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Budgets in seconds on Xcode Cloud. A local run's are these divided by LOCAL_RATIO, the ratio
# of CI to local times measured in 2026-10 with one test at a time on both.
LOCAL_RATIO = 1.25
# A UI test's local budget when its target runs in parallel. Five clones of the simulator share
# the Mac, so each test's own time grows: run 296's serial CI times over two local parallel runs
# measured 1.04 to 1.09. The lowest keeps a test under budget on CI under it locally too.
LOCAL_RATIO_PARALLEL_UI = 1.04
# Per test target: (all its tests, any one of them or None, whether every test is listed).
TARGETS = {
    "WorkoutStoreTests": (10, None, False),
    "DesignSystemTests": (30, 2, False),
    "PlusPlusUITests": (360, 90, True),
}
PACKAGE = 10  # scripts/test.sh on macOS, both swift test runs' test time, locally
RUN = 660  # an Xcode Cloud PR run, start to finish
RUN_AIM = 240  # the run's aim, printed beside its budget


def over(seconds, budget):
    return f"{seconds:.1f} s (budget {budget:.3g} s){' OVER BUDGET' if seconds > budget else ''}"


def parallel_targets(plan_text):
    """The test plan's targets whose tests run at the same time. A UI target only when the plan
    says parallelizable, which hands its classes to clones of the simulator; a Swift Testing
    target unless the plan says parallelizable is false, since Swift Testing runs its tests in
    parallel when the plan doesn't say."""
    parallel = set()
    for t in json.loads(plan_text)["testTargets"]:
        name, flag = t["target"]["name"], t.get("parallelizable")
        if flag is True or (flag is None and not is_ui(name)):
            parallel.add(name)
    return parallel


def is_ui(target):
    return target.endswith("UITests")


def bundle_times(tests, parallel):
    """Each target's time from (target, test, seconds) rows. A serial target's tests add up. A
    parallel Swift Testing target's tests start together and each is timed from that start, so
    its time is its longest test's. A parallel UI target's tests are each timed on their own,
    so their sum is their cost, not the wall time."""
    times = {}
    for target, _, seconds in tests:
        if target in parallel and not is_ui(target):
            times[target] = max(times.get(target, 0), seconds)
        else:
            times[target] = times.get(target, 0) + seconds
    return times


def budget_lines(tests, parallel, on_ci, walls=None):
    """Lines for each target, and for each of its tests that is listed or over its own budget.
    A target's budget holds its wall time; for a parallel UI target that comes from walls, and
    without it the line gives the sum as cost and no verdict. Only a UI target's tests, or a
    serial target's, are timed on their own."""
    walls = walls or {}
    lines = []
    by_target = bundle_times(tests, parallel)
    order = list(TARGETS)
    for target in sorted(by_target, key=lambda t: order.index(t) if t in order else len(order)):
        total, per_test, lists_all = TARGETS.get(target, (None, None, False))
        scale = 1 if on_ci else 1 / LOCAL_RATIO
        seconds = by_target[target]
        if target in parallel and is_ui(target):
            summed = f"its tests {seconds:.1f} s summed, in parallel"
            if target in walls:
                lines.append(f"{target} wall time {over(walls[target], total * scale)}; {summed}")
            else:
                lines.append(f"{target} {summed}; no wall time here, so no verdict")
            if not on_ci:
                scale = 1 / LOCAL_RATIO_PARALLEL_UI
        else:
            lines.append(f"{target} {over(seconds, total * scale) if total else f'{seconds:.1f} s'}")
        if not per_test or (target in parallel and not is_ui(target)):
            continue
        for t, name, s in sorted(tests, key=lambda row: -row[2]):
            if t == target and (lists_all or s > per_test * scale):
                lines.append(f"  {name} {over(s, per_test * scale)}")
    return lines


def load(*subcommand, bundle):
    args = ["xcrun", "xcresulttool", "get", *subcommand, "--path", bundle, "--compact"]
    try:
        return json.loads(subprocess.run(args, capture_output=True, text=True, check=True).stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return None


def location(issue):
    url = issue.get("sourceURL") or ""
    if not url:
        return ""
    path = url.split("file://")[-1].split("#")[0]
    if "StartingLineNumber=" not in url:
        return path
    line = int(url.split("StartingLineNumber=")[1].split("&")[0]) + 1
    return f"{path}:{line}"


def build(bundle):
    data = load("build-results", bundle=bundle) or {}
    for kind in ("errors", "warnings"):
        for issue in data.get(kind) or []:
            print(f"{kind[:-1]}: {location(issue)}: {issue.get('message', '')}")


def tests(bundle):
    s = load("test-results", "summary", bundle=bundle)
    if not s:
        print(f"no test summary in {bundle}")
        return 1
    print(
        f"tests: {s.get('result')} total={s.get('totalTestCount')} "
        f"passed={s.get('passedTests')} failed={s.get('failedTests')} skipped={s.get('skippedTests')}"
    )
    for failure in s.get("testFailures") or []:
        print(f"  FAIL {failure.get('testName')}: {(failure.get('failureText') or '').strip()}")
    # xcodebuild reports success for an -only-testing identifier that matches nothing.
    if not s.get("totalTestCount"):
        print("no tests ran; an -only-testing identifier that matches nothing does this")
        return 1
    return 0


def case_seconds(node, parallel):
    # A parameterized test's own duration is the mean of its cases. Run one at a time, its cost
    # is their sum; in parallel, its longest case's.
    cases = [c.get("durationInSeconds") or 0 for c in node.get("children") or []
             if c.get("nodeType") == "Arguments"]
    if cases:
        return max(cases) if parallel else sum(cases)
    return node.get("durationInSeconds") or 0


def ui_wall_time(bundle, rows):
    """A parallel UI target's wall time, from its first test's start to its last one's end. The
    test tree has no start times; each test's activities do, one xcresulttool call a test."""
    spans = []
    for _, test_id, seconds in rows:
        data = load("test-results", "activities", "--test-id", test_id, bundle=bundle) or {}
        runs = data.get("testRuns") or [{}]
        start = next((a.get("startTime") for a in runs[0].get("activities") or []), None)
        if start is None:
            return None
        spans.append((start, start + seconds))
    return max(end for _, end in spans) - min(start for start, _ in spans) if spans else None


def package(log):
    # Each swift test run ends "Test run with N tests in M suites passed after X seconds."
    text = pathlib.Path(log).read_text(errors="replace")
    runs = re.findall(r"Test run with \d+ tests? .*? after ([\d.]+) seconds", text)
    if not runs:
        print("package tests: no test run's time in swift test's output")
    else:
        print(f"package tests {over(sum(map(float, runs)), PACKAGE)}")
    return 0


def times(bundle):
    data = load("test-results", "tests", bundle=bundle)
    if not data:
        print(f"no test results in {bundle}")
        return 0
    parallel = parallel_targets((ROOT / "PlusPlus.xctestplan").read_text())
    rows = []

    def walk(node, target=None):
        if node.get("nodeType") in ("Unit test bundle", "UI test bundle"):
            target = node.get("name")
        if node.get("nodeType") == "Test Case":
            rows.append((target, node.get("nodeIdentifier"), case_seconds(node, target in parallel)))
            return
        for child in node.get("children") or []:
            walk(child, target)

    for node in data.get("testNodes") or []:
        walk(node)
    walls = {t: ui_wall_time(bundle, [r for r in rows if r[0] == t])
             for t in parallel if is_ui(t) and any(r[0] == t for r in rows)}
    print("times against local budgets (reported, never failed):")
    for line in budget_lines(rows, parallel, on_ci=False, walls={t: w for t, w in walls.items() if w}):
        print(f"  {line}")
    return 0


if __name__ == "__main__":
    commands = {"build": build, "tests": tests, "times": times, "package": package}
    if len(sys.argv) != 3 or sys.argv[1] not in commands:
        print(__doc__, file=sys.stderr)
        sys.exit(64)
    sys.exit(commands[sys.argv[1]](sys.argv[2]))
