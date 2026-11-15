#!/usr/bin/env python3
"""Prints "<worktree>\t<idle seconds>" for each worktree simulator scripts/tidy.sh deletes because
no script has used it for longer than the limit, though its worktree is still there.

    python3 scripts/stale-simulators.py <records folder> <checkout> <limit seconds>

scripts/common.sh's stale_worktree_simulators runs it; scripts/stale-simulators-test.py tests
stale(), which makes the choice from what main() reads.
"""
import json
import os
import re
import subprocess
import sys
import time


def stale(records, devices, worktrees, limit, now, commands):
    """Yields (worktree, idle seconds) for each record older than limit whose worktree is still
    listed and is not the main checkout (the first one git lists), whose one simulator is shut
    down, and in whose worktree no xcodebuild runs. A record whose worktree is gone is tidy's
    other loop's; a name matching more than one simulator is skipped, as scripts/common.sh
    refuses to pick between them."""
    paths = {os.path.basename(path): path for path in worktrees[1:]}
    for name in sorted(os.listdir(records)):
        if name not in paths:
            continue
        idle = int(now - os.path.getmtime(os.path.join(records, name)))
        if idle <= limit:
            continue
        matches = [d for d in devices if d["name"] == f"PlusPlus {name}"]
        if len(matches) != 1 or matches[0]["state"] != "Shutdown":
            continue
        # The match scripts/common.sh's idle_worktree_simulators uses: a long test run touches
        # the record only as it starts.
        running = re.compile(f"xcodebuild.*{re.escape(paths[name])}/")
        if any(running.search(command) for command in commands):
            continue
        yield name, idle


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: python3 scripts/stale-simulators.py <records folder> <checkout> <limit seconds>")
    records, checkout, limit = sys.argv[1], sys.argv[2], int(sys.argv[3])
    now = time.time()
    # tidy runs this at every session start, and most days no record is old enough: skip the reads.
    # The folder also holds scripts/common.sh's .boot.lock, which is no record.
    if not os.path.isdir(records) or all(now - os.path.getmtime(os.path.join(records, name)) <= limit
                                         for name in os.listdir(records) if not name.startswith(".")):
        return
    devices = [d for ds in json.loads(run("xcrun", "simctl", "list", "devices", "--json"))["devices"].values()
               for d in ds]
    worktrees = [line[len("worktree "):] for line in run("git", "-C", checkout, "worktree", "list", "--porcelain")
                 .splitlines() if line.startswith("worktree ")]
    commands = run("ps", "-axww", "-o", "command=").splitlines()
    for name, idle in stale(records, devices, worktrees, limit, now, commands):
        print(name, idle, sep="\t")


if __name__ == "__main__":
    main()
