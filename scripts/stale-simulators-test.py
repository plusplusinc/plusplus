#!/usr/bin/env python3
"""scripts/stale-simulators.py's choice of which worktree simulators scripts/tidy.sh deletes,
against a scratch records folder, a fake device list, and fake running commands.

    python3 scripts/stale-simulators-test.py    # scripts/test.sh runs it
"""
import importlib.util
import os
import shutil
import tempfile
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


if __name__ == "__main__":
    unittest.main()
