#!/usr/bin/env python3
"""scripts/stale-simulators.py's choice of which worktree simulators scripts/tidy.sh deletes,
against a scratch records folder, a fake device list, and fake running commands; and what
scripts/tidy.sh then does with that choice, run in a scratch clone against a fake xcrun and gh,
so no real simulator is read or deleted and nothing reaches the network.

    python3 scripts/stale-simulators-test.py    # scripts/test.sh runs it
"""
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("stale", ROOT / "scripts" / "stale-simulators.py")
stale_simulators = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stale_simulators)

NOW = 1_800_000_000
HOUR = 3600
DAY = 24 * HOUR
MAIN = "/clone/plusplus"
WORKTREE = "/clone/plusplus/.claude/worktrees/topic"


class Stale(unittest.TestCase):
    def setUp(self):
        self.records = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.records)
        self.devices = []
        self.worktrees = [MAIN, WORKTREE]
        self.commands = ["/bin/zsh", "claude"]

    def record(self, name, age, state="Shutdown"):
        path = os.path.join(self.records, name)
        Path(path).touch()
        os.utime(path, (NOW - age, NOW - age))
        if state:
            self.devices.append({"name": f"PlusPlus {name}", "state": state})

    def stale(self, limit=DAY):
        old = stale_simulators.old_records(self.records, self.worktrees, limit, NOW)
        return list(stale_simulators.stale(old, self.devices, self.commands))

    def test_a_record_unused_two_days_is_stale_with_its_idle_time(self):
        self.record("topic", 2 * DAY)
        self.assertEqual(self.stale(), [("topic", 2 * DAY)])

    def test_a_record_used_within_the_day_is_not(self):
        self.record("topic", DAY - HOUR)
        self.assertEqual(self.stale(), [])

    def test_a_booted_simulator_is_not_deleted(self):
        self.record("topic", 2 * DAY, state="Booted")
        self.assertEqual(self.stale(), [])

    def test_a_worktree_running_xcodebuild_keeps_its_simulator(self):
        self.record("topic", 2 * DAY)
        self.commands.append(f"xcodebuild test -project {WORKTREE}/PlusPlus.xcodeproj")
        self.assertEqual(self.stale(), [])

    def test_xcodebuild_in_another_worktree_does_not_count(self):
        self.record("topic", 2 * DAY)
        self.commands.append(f"xcodebuild test -project {WORKTREE}-two/PlusPlus.xcodeproj")
        self.assertEqual(self.stale(), [("topic", 2 * DAY)])

    def test_the_main_checkout_is_never_stale(self):
        self.record("plusplus", 30 * DAY)
        self.assertEqual(self.stale(), [])

    def test_a_worktree_named_like_the_main_checkout_does_not_claim_its_simulator(self):
        self.worktrees.append("/clone/plusplus/.claude/worktrees/plusplus")
        self.record("plusplus", 30 * DAY)
        self.assertEqual(self.stale(), [])

    def test_the_boot_lock_is_not_a_record(self):
        self.record(".boot.lock", 30 * DAY, state=None)
        self.assertEqual(stale_simulators.old_records(self.records, self.worktrees, DAY, NOW), [])

    def test_a_shorter_limit_makes_a_two_hour_old_record_stale(self):
        self.record("topic", 2 * HOUR)
        self.assertEqual(self.stale(limit=HOUR), [("topic", 2 * HOUR)])

    def test_a_record_whose_worktree_is_gone_is_left_to_tidy_s_other_loop(self):
        self.record("gone", 2 * DAY)
        self.assertEqual(self.stale(), [])

    def test_a_record_without_a_simulator_is_skipped(self):
        self.record("topic", 2 * DAY, state=None)
        self.assertEqual(self.stale(), [])

    def test_a_name_matching_two_simulators_is_skipped(self):
        self.record("topic", 2 * DAY)
        self.devices.append({"name": "PlusPlus topic", "state": "Shutdown"})
        self.assertEqual(self.stale(), [])


# Stands in for xcrun: answers tidy's reads from devices.json beside it, and writes every call to
# xcrun.log in place of acting, so a test reads there which simulators tidy deleted or shut down.
FAKE_XCRUN = """#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
here, args = os.path.dirname(os.path.abspath(__file__)), sys.argv[1:]
with open(os.path.join(here, "xcrun.log"), "a") as log:
    print(*args, file=log)
iphone = {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17"}
runtimes = [{"platform": "iOS", "isAvailable": True, "version": "27.2", "supportedDeviceTypes": [iphone]}]
if args == ["--sdk", "iphonesimulator", "--show-sdk-version"]:
    print("27.2")
elif args[:2] == ["simctl", "list"]:
    if args[2] == "devices" and os.path.exists(os.path.join(here, "fail-list")):
        sys.exit("fake xcrun: the device list fails")
    devices = json.load(open(os.path.join(here, "devices.json")))
    # "<n> <udid> <record>": just before the nth device list, a script touches that record and
    # boots that simulator.
    boot, count = os.path.join(here, "boot-on-list"), os.path.join(here, "device-lists")
    if args[2] == "devices" and os.path.exists(boot):
        n, udid, record = Path(boot).read_text().split(maxsplit=2)
        lists = int(Path(count).read_text()) + 1 if os.path.exists(count) else 1
        Path(count).write_text(str(lists))
        if lists == int(n):
            Path(record).touch()
            for device in devices:
                if device["udid"] == udid:
                    device["state"] = "Booted"
            Path(here, "devices.json").write_text(json.dumps(devices))
    print(json.dumps({"devices": {"iOS-27-2": devices}, "runtimes": runtimes}))
elif args[:3] == ["simctl", "runtime", "list"]:
    print("{}")
"""
READS = ("simctl list", "simctl runtime list", "--sdk")
SWEEP = "simctl delete unavailable"  # tidy's last step, for simulators left without a runtime


class Tidy(unittest.TestCase):
    """scripts/tidy.sh in a clone of its own: a main checkout, "clone", with a local origin, and
    a worktree per simulator() call."""

    def setUp(self):
        # git lists a worktree by its real path, and tidy compares that with its own.
        self.tmp = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.clone = os.path.join(self.tmp, "clone")
        self.fake = os.path.join(self.tmp, "fake")
        self.records = os.path.join(self.clone, ".git", "plusplus-simulators")
        self.devices = []
        os.makedirs(os.path.join(self.clone, "scripts"))
        os.makedirs(self.fake)
        for script in ("tidy.sh", "common.sh", "stale-simulators.py"):
            shutil.copy(ROOT / "scripts" / script, os.path.join(self.clone, "scripts"))
        for name, text in (("xcrun", FAKE_XCRUN), ("gh", "#!/bin/sh\n")):  # gh: no merged PRs
            path = os.path.join(self.fake, name)
            Path(path).write_text(text)
            os.chmod(path, 0o755)
        # A night card's git carries the night's pre-push hook in GIT_CONFIG_*, which refuses the
        # scratch repo's push, as it did nightly-tooling-test.py's (#150).
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith(("PLUSPLUS_", "GIT_CONFIG_"))}
        self.env.update(
            PATH=self.fake + os.pathsep + os.environ["PATH"],
            GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1",
            GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.com",
            GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.com")
        origin = os.path.join(self.tmp, "origin.git")
        self.git("init", "--quiet", "-b", "main")
        self.git("add", "scripts")
        self.git("commit", "--quiet", "-m", "scripts")
        self.git("init", "--quiet", "--bare", origin)
        self.git("remote", "add", "origin", origin)
        self.git("push", "--quiet", "origin", "main")
        os.makedirs(self.records)

    def git(self, *args):
        return subprocess.run(["git", "-C", self.clone, *args], env=self.env, check=True,
                              capture_output=True, text=True).stdout

    def simulator(self, name, age, state="Shutdown", worktree=True, record=True):
        """A simulator "PlusPlus <name>", by default with a worktree of that name, fresh so tidy
        keeps it, and a record last used `age` seconds ago. Returns its udid."""
        udid = f"UDID-{name.split()[0]}"
        if worktree:
            self.git("worktree", "add", "--quiet", "-b", f"branch-{len(self.devices)}",
                     os.path.join(self.clone, ".claude", "worktrees", name))
        if record:
            path = os.path.join(self.records, name)
            Path(path).touch()
            os.utime(path, (time.time() - age,) * 2)
        self.devices.append({"name": f"PlusPlus {name}", "udid": udid, "state": state})
        return udid

    def tidy(self, *args, **env):
        """Runs tidy; returns what it printed and the xcrun calls that were not reads."""
        Path(self.fake, "devices.json").write_text(json.dumps(self.devices))
        log = Path(self.fake, "xcrun.log")
        log.write_text("")
        result = subprocess.run([os.path.join(self.clone, "scripts", "tidy.sh"), *args],
                                env={**self.env, **env}, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout + result.stderr, [c for c in log.read_text().splitlines() if not c.startswith(READS)]

    def one_of_each(self):
        self.simulator("topic", 2 * DAY)
        self.simulator("odd name [x]*", 3 * DAY)
        self.simulator("booted", 2 * DAY, state="Booted")
        self.simulator("recent", 2 * HOUR)
        self.simulator("clone", 30 * DAY, worktree=False)  # the main checkout's own
        self.simulator("person", 30 * DAY, worktree=False, record=False)

    def test_a_dry_run_names_each_stale_simulator_and_its_idle_time_and_deletes_nothing(self):
        self.one_of_each()
        before = sorted(os.listdir(self.records))
        out, acts = self.tidy("--dry-run")
        self.assertEqual(sorted(line for line in out.splitlines() if "simulator" in line), [
            'tidy: delete simulator "PlusPlus odd name [x]*", unused for 72h',
            'tidy: delete simulator "PlusPlus topic", unused for 48h',
            'tidy: shut down simulator "PlusPlus booted", idle over 30m',
        ])
        self.assertNotIn("worktree remove", out)
        self.assertEqual(acts, [])
        self.assertEqual(sorted(os.listdir(self.records)), before)

    def test_a_run_deletes_the_stale_shut_down_worktree_simulators_and_their_records_alone(self):
        self.one_of_each()
        worktrees, branches = self.git("worktree", "list"), self.git("branch", "--list")
        out, acts = self.tidy()
        self.assertIn('tidy: delete simulator "PlusPlus topic", unused for 48h', out)
        # The booted one is only shut down, by the 30-minute rule.
        self.assertEqual(sorted(acts), sorted([
            "simctl delete UDID-topic", "simctl delete UDID-odd", "simctl shutdown UDID-booted", SWEEP]))
        self.assertEqual(sorted(os.listdir(self.records)), ["booted", "clone", "recent"])
        self.assertEqual(self.git("worktree", "list"), worktrees)
        self.assertEqual(self.git("branch", "--list"), branches)

    def test_delete_hours_in_the_environment_sets_the_limit(self):
        self.simulator("recent", 2 * HOUR)
        out, acts = self.tidy(PLUSPLUS_SIM_DELETE_HOURS="1")
        self.assertIn('tidy: delete simulator "PlusPlus recent", unused for 2h', out)
        self.assertEqual(acts, ["simctl delete UDID-recent", SWEEP])
        self.assertEqual(os.listdir(self.records), [])

    def test_a_stale_simulator_booted_by_the_time_it_would_be_deleted_is_kept_and_left_booted(self):
        udid = self.simulator("topic", 2 * DAY)
        # The first device list finds it stale; a script touches its record and boots it before
        # the second, the one that would delete it.
        Path(self.fake, "boot-on-list").write_text(f"2 {udid} {os.path.join(self.records, 'topic')}")
        out, acts = self.tidy()
        self.assertIn('tidy: kept simulator "PlusPlus topic": Booted, so a script is using it', out)
        self.assertNotIn('delete simulator "PlusPlus topic"', out)
        self.assertEqual(acts, [SWEEP])
        self.assertEqual(os.listdir(self.records), ["topic"])

    def test_a_device_list_that_fails_deletes_nothing_and_tidy_goes_on(self):
        self.simulator("topic", 2 * DAY)
        Path(self.fake, "fail-list").touch()
        out, acts = self.tidy()
        self.assertIn("tidy: could not list unused simulators; none deleted", out)
        self.assertEqual(acts, [SWEEP])
        self.assertEqual(os.listdir(self.records), ["topic"])


if __name__ == "__main__":
    unittest.main()
