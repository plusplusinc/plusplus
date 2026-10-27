#!/usr/bin/env python3
"""Compact summaries of an .xcresult bundle for humans and agents.

    scripts/xcresult.py build <bundle>   one line per error and warning, 1-based line numbers
    scripts/xcresult.py tests <bundle>   one-line totals plus each failure's message; exits 1
                                         when no tests ran or there is no summary
    scripts/xcresult.py times <bundle>   each test bundle's time against its local budget, each
                                         UI test's, and any DesignSystem test over its own;
                                         reports only, and always exits 0
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
# Per test target: (all its tests, any one of them or None, whether every test is listed).
TARGETS = {
    "WorkoutStoreTests": (10, None, False),
    "DesignSystemTests": (30, 2, False),
    "PlusPlusUITests": (360, 90, True),
}
PACKAGE = 10  # scripts/test.sh on macOS, both swift test runs' test time, locally
# A run's start-to-finish time has no budget: in runs 317 and 318 about 250 s of it was Xcode
# Cloud's own steps (machine start, clone, the hand-off to the simulator, collecting results),
# and the last of those varied by 34 s between the two with nothing changed. The tests are
# what this repo controls, so their budgets above are the check.


def over(seconds, budget):
    return f"{seconds:.1f} s (budget {budget:.3g} s){' OVER BUDGET' if seconds > budget else ''}"


def parallel_targets(plan_text):
    """The test plan's Swift Testing targets whose tests run at the same time: those the plan
    doesn't mark parallelizable false, since Swift Testing runs its tests in parallel when the
    plan doesn't say. The UI target runs one test at a time (.claude/rules/testing.md)."""
    parallel = set()
    for t in json.loads(plan_text)["testTargets"]:
        name = t["target"]["name"]
        if t.get("parallelizable") is not False and not is_ui(name):
            parallel.add(name)
    return parallel


def is_ui(target):
    return target.endswith("UITests")


def bundle_times(tests, parallel):
    """Each target's time from (target, test, seconds) rows. A serial target's tests add up. A
    parallel target's tests start together and each is timed from that start, so its time is
    its longest test's."""
    times = {}
    for target, _, seconds in tests:
        if target in parallel:
            times[target] = max(times.get(target, 0), seconds)
        else:
            times[target] = times.get(target, 0) + seconds
    return times


def budget_lines(tests, parallel, on_ci):
    """Lines for each target, and for each of its tests that is listed or over its own budget.
    Only a serial target's tests are timed on their own."""
    lines = []
    by_target = bundle_times(tests, parallel)
    order = list(TARGETS)
    for target in sorted(by_target, key=lambda t: order.index(t) if t in order else len(order)):
        total, per_test, lists_all = TARGETS.get(target, (None, None, False))
        scale = 1 if on_ci else 1 / LOCAL_RATIO
        seconds = by_target[target]
        lines.append(f"{target} {over(seconds, total * scale) if total else f'{seconds:.1f} s'}")
        if not per_test or target in parallel:
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
    print("times against local budgets (reported, never failed):")
    for line in budget_lines(rows, parallel, on_ci=False):
        print(f"  {line}")
    return 0


if __name__ == "__main__":
    commands = {"build": build, "tests": tests, "times": times, "package": package}
    if len(sys.argv) != 3 or sys.argv[1] not in commands:
        print(__doc__, file=sys.stderr)
        sys.exit(64)
    sys.exit(commands[sys.argv[1]](sys.argv[2]))
