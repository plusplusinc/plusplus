#!/usr/bin/env python3
"""Compact summaries of an .xcresult bundle for humans and agents.

    scripts/xcresult.py build <bundle>   one line per error and warning, 1-based line numbers
    scripts/xcresult.py tests <bundle>   one-line totals plus each failure's message

xcresulttool reports 0-based line numbers in its JSON; compilers and editors are 1-based, so
this adds one. Everything else is passed through as-is.
"""
import json
import subprocess
import sys


def load(kind, bundle):
    args = ["xcrun", "xcresulttool", "get", kind, "--path", bundle, "--compact"]
    try:
        out = subprocess.run(args, capture_output=True, text=True, check=True).stdout
        return json.loads(out)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return None


def location(issue):
    url = issue.get("sourceURL") or ""
    if not url:
        return ""
    path = url.split("file://")[-1].split("#")[0]
    line = ""
    if "StartingLineNumber=" in url:
        raw = url.split("StartingLineNumber=")[1].split("&")[0]
        line = ":" + str(int(raw) + 1)
    return path + line


def build(bundle):
    data = load("build-results", bundle)
    if not data:
        return
    for kind in ("errors", "warnings"):
        for issue in data.get(kind) or []:
            print(f"{kind[:-1]}: {location(issue)}: {issue.get('message', '')}")


def tests(bundle):
    args = ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", bundle, "--compact"]
    try:
        summary = json.loads(subprocess.run(args, capture_output=True, text=True, check=True).stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return
    print(
        "tests: {result} total={totalTestCount} passed={passedTests} "
        "failed={failedTests} skipped={skippedTests}".format(**{
            k: summary.get(k) for k in
            ("result", "totalTestCount", "passedTests", "failedTests", "skippedTests")
        })
    )
    for failure in summary.get("testFailures") or []:
        text = (failure.get("failureText") or "").strip()
        print(f"  FAIL {failure.get('testName')}: {text}")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("build", "tests"):
        print(__doc__, file=sys.stderr)
        sys.exit(64)
    {"build": build, "tests": tests}[sys.argv[1]](sys.argv[2])
