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

# Seconds, as (local, Xcode Cloud). Local is CI divided by 1.25, the ratio measured in 2026-10.
BUDGETS = {
    "package": (10, None),  # scripts/test.sh, both swift test runs
    "WorkoutStoreTests": (8, 10),
    "DesignSystemTests": (24, 30),
    "DesignSystemTests, a test": (1.6, 2),
    "PlusPlusUITests": (290, 360),
    "PlusPlusUITests, a test": (72, 90),
    "run": (None, 660),  # an Xcode Cloud PR run, start to finish
}
RUN_AIM = 240  # the run's aim, printed beside its budget


def over(seconds, budget):
    return f"{seconds:.1f} s (budget {budget:g} s){' OVER BUDGET' if seconds > budget else ''}"


def serial_targets(plan_text):
    """The test plan's targets whose tests run one at a time, so their times add up: a UI target
    unless parallelizable, and a Swift Testing target only when parallelizable is false, since
    Swift Testing runs a target's tests in parallel when the plan doesn't say."""
    serial = set()
    for t in json.loads(plan_text)["testTargets"]:
        name, flag = t["target"]["name"], t.get("parallelizable")
        if flag is False or (flag is None and name.endswith("UITests")):
            serial.add(name)
    return serial


def bundle_times(tests, serial):
    """Each target's time from (target, test, seconds) rows. A serial target's tests add up. A
    parallel target's tests start together and Swift Testing times each from that start, so
    its time is its longest test's."""
    times = {}
    for target, _, seconds in tests:
        if target in serial:
            times[target] = times.get(target, 0) + seconds
        else:
            times[target] = max(times.get(target, 0), seconds)
    return times


def budget_lines(tests, serial, column):
    """Lines for each target, each UI test, and each DesignSystem test over its own budget.
    column is 0 for local budgets, 1 for Xcode Cloud's."""
    lines = []
    order = list(BUDGETS)
    by_target = bundle_times(tests, serial)
    for target in sorted(by_target, key=lambda t: order.index(t) if t in order else len(order)):
        seconds = by_target[target]
        budget = BUDGETS.get(target, (None, None))[column]
        lines.append(f"{target} {over(seconds, budget) if budget else f'{seconds:.1f} s'}")
        per_test = BUDGETS.get(f"{target}, a test", (None, None))[column]
        # Only a serial target's tests are timed on their own.
        if not per_test or target not in serial:
            continue
        for t, name, s in sorted(tests, key=lambda row: -row[2]):
            # Every UI test is listed; another target's test only when it alone is over.
            if t == target and (target == "PlusPlusUITests" or s > per_test):
                lines.append(f"  {name} {over(s, per_test)}")
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


def case_seconds(node):
    # A parameterized test's own duration is the mean of its cases; its cost is their sum.
    cases = [c for c in node.get("children") or [] if c.get("nodeType") == "Arguments"]
    if cases:
        return sum(c.get("durationInSeconds") or 0 for c in cases)
    return node.get("durationInSeconds") or 0


def package(log):
    # Each swift test run ends "Test run with N tests in M suites passed after X seconds."
    text = pathlib.Path(log).read_text(errors="replace")
    runs = re.findall(r"Test run with \d+ tests? .*? after ([\d.]+) seconds", text)
    if runs:
        print(f"package tests {over(sum(map(float, runs)), BUDGETS['package'][0])}")
    return 0


def times(bundle):
    data = load("test-results", "tests", bundle=bundle)
    if not data:
        print(f"no test results in {bundle}")
        return 0
    rows = []

    def walk(node, target=None):
        if node.get("nodeType") in ("Unit test bundle", "UI test bundle"):
            target = node.get("name")
        if node.get("nodeType") == "Test Case":
            rows.append((target, node.get("nodeIdentifier"), case_seconds(node)))
            return
        for child in node.get("children") or []:
            walk(child, target)

    for node in data.get("testNodes") or []:
        walk(node)
    serial = serial_targets((ROOT / "PlusPlus.xctestplan").read_text())
    print("times against local budgets (reported, never failed):")
    for line in budget_lines(rows, serial, 0):
        print(f"  {line}")
    return 0


if __name__ == "__main__":
    commands = {"build": build, "tests": tests, "times": times, "package": package}
    if len(sys.argv) != 3 or sys.argv[1] not in commands:
        print(__doc__, file=sys.stderr)
        sys.exit(64)
    sys.exit(commands[sys.argv[1]](sys.argv[2]))
