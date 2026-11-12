#!/usr/bin/env python3
"""scripts/board.sh against a stand-in `gh` that answers from a fixture: no network, no board.

    python3 scripts/board-test.py    # scripts/test.sh runs it
"""
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

BOARD = Path(__file__).resolve().parent / "board.sh"
README = """# Board

Intro.

## Feature: Routine screen
Design: a link.

### Decided
- One.

## Feature: Drawer\r
The drawer.\r

## Voice
Plain words.
"""


class Readme(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp())
        response = {"data": {"organization": {"projectV2": {"id": "PVT_1", "readme": README}}}}
        (self.folder / "response.json").write_text(json.dumps(response))
        # gh api graphql --include: headers, a blank line, then the body. Each call's arguments
        # go to calls.log, so a test can see whether anything wrote.
        gh = self.folder / "gh"
        gh.write_text('#!/bin/bash\necho "$*" >> "$(dirname "$0")/calls.log"\n'
                      'printf \'HTTP/2.0 200 OK\\r\\n\\r\\n\'\ncat "$(dirname "$0")/response.json"\n')
        gh.chmod(0o755)

    def board(self, *args, stdin=""):
        env = dict(os.environ, PATH=f"{self.folder}:{os.environ['PATH']}")
        return subprocess.run([str(BOARD), "readme", *args], input=stdin, capture_output=True, text=True, env=env)

    def calls(self):
        log = self.folder / "calls.log"
        return log.read_text() if log.exists() else ""

    def test_a_feature_prints_its_section_to_the_next_heading(self):
        run = self.board("Routine screen")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout, "## Feature: Routine screen\nDesign: a link.\n\n### Decided\n- One.\n")

    def test_a_section_saved_with_crlf_reads_without_it(self):
        run = self.board("Drawer")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout, "## Feature: Drawer\nThe drawer.\n")

    def test_an_unknown_feature_fails_naming_the_features(self):
        run = self.board("Routines")
        self.assertEqual(run.returncode, 1)
        self.assertEqual(run.stdout, "")
        self.assertIn("its features: Routine screen, Drawer", run.stderr)

    def test_a_heading_that_is_no_feature_is_not_one(self):
        self.assertEqual(self.board("Voice").returncode, 1)

    def test_with_a_feature_stdin_never_writes(self):
        run = self.board("Drawer", stdin="# A whole new README\n")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertNotIn("mutation", self.calls())

    def test_with_no_feature_it_still_writes_stdin(self):
        run = self.board(stdin="# A whole new README\n")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("updateProjectV2", self.calls())

    def test_with_no_feature_and_no_stdin_it_prints_the_whole_readme(self):
        run = self.board()
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("## Voice\nPlain words.", run.stdout)
        self.assertIn("## Feature: Routine screen", run.stdout)

    def test_two_features_print_usage(self):
        self.assertEqual(self.board("Drawer", "Voice").returncode, 64)


if __name__ == "__main__":
    unittest.main()
