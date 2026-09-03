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
        return
    print(
        f"tests: {s.get('result')} total={s.get('totalTestCount')} "
        f"passed={s.get('passedTests')} failed={s.get('failedTests')} skipped={s.get('skippedTests')}"
    )
    for failure in s.get("testFailures") or []:
        print(f"  FAIL {failure.get('testName')}: {(failure.get('failureText') or '').strip()}")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("build", "tests"):
        print(__doc__, file=sys.stderr)
        sys.exit(64)
    {"build": build, "tests": tests}[sys.argv[1]](sys.argv[2])
