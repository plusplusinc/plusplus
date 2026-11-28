#!/usr/bin/env python3
"""`scripts/device.sh`'s arguments, and its turn to a link when no iPhone is in reach, with
`xcrun` and `xcodebuild` replaced by stand-ins that record each call: no build, no phone, no
network.

    python3 scripts/device-test.py
"""
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

DEVICE = Path(__file__).resolve().with_name("device.sh")
STAND_IN = """#!/bin/bash
echo "$(basename "$0") $*" >> "$CALLS"
case "$(basename "$0") $*" in
    "xcrun devicectl list devices"*) echo "${DEVICES:-$NO_DEVICES}" ;;
    *) exit 1 ;;
esac
"""


class Arguments(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.calls = Path(self.dir.name) / "calls"
        self.calls.touch()
        tools = Path(self.dir.name) / "bin"
        tools.mkdir()
        for name in ("xcrun", "xcodebuild"):
            (tools / name).write_text(STAND_IN)
            (tools / name).chmod(0o755)
        # No wrangler on this PATH, so a run that reaches the link stops before it archives.
        self.env = {"PATH": f"{tools}:/usr/bin:/bin", "HOME": os.environ["HOME"],
                    "CALLS": str(self.calls), "PLUSPLUS_OLDER_SCHEMA": "1",
                    "NO_DEVICES": '{"result": {"devices": []}}',
                    "PLUSPLUS_BUILDS_WORKER": "builds", "PLUSPLUS_BUILDS_HOST": "builds.example"}

    def tearDown(self):
        self.dir.cleanup()

    def run_device(self, *args):
        return subprocess.run([str(DEVICE), *args], env=self.env, capture_output=True, text=True,
                              timeout=60)

    def test_an_unknown_argument_prints_usage_and_builds_nothing(self):
        for argument in ("--link", "--bogus"):
            result = self.run_device(argument)
            self.assertEqual(result.returncode, 64, argument)
            self.assertEqual(result.stdout, "", argument)
            self.assertIn("usage: scripts/device.sh [--list]", result.stderr, argument)
            # What to do next: run it bare, since the link needs no flag.
            self.assertIn("makes an install link itself when no iPhone is in reach", result.stderr,
                          argument)
            self.assertEqual(self.calls.read_text(), "", argument)

    def test_the_list_holds_the_phone_in_reach_and_never_its_watch(self):
        def device(kind, udid, name, transport, state):
            return {"properties": {
                "hardware": {"deviceType": kind, "udid": udid, "reality": "physical"},
                "connection": {"pairingState": "paired", "transportType": transport,
                               "state": state},
                "state": {"name": name},
            }}
        self.env["DEVICES"] = json.dumps({"result": {"devices": [
            device("iPhone", "PHONE-1", "Test iPhone", "wired", "connected"),
            device("appleWatch", "WATCH-1", "Test Watch", None, "connected"),
        ]}})
        result = self.run_device("--list")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "PHONE-1\tTest iPhone\n")

    def test_with_no_iphone_in_reach_it_turns_to_a_link_unasked(self):
        result = self.run_device()
        self.assertIn("no iPhone available, so making an install link", result.stdout)
        self.assertEqual(result.returncode, 69, result.stderr)
        self.assertIn("wrangler is not installed", result.stderr)
        self.assertNotIn("xcodebuild", self.calls.read_text())


if __name__ == "__main__":
    unittest.main()
