#!/usr/bin/env python3
"""scripts/board.sh against a stand-in `gh` that answers from a fixture: no network, no board.

    python3 scripts/board-test.py    # scripts/test.sh runs it
"""
import json
import os
import shutil
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

## Feature:  Drawer\r
The drawer.\r

## Voice
Plain words.
"""


class Readme(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.folder)
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

    def test_a_section_saved_with_crlf_and_a_double_space_still_matches(self):
        run = self.board("Drawer")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout, "## Feature:  Drawer\nThe drawer.\n")

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


CARD = "## Problem\nToday nothing.\n\n## State\nLed by session session_0A1b, since 2026-11-20.\nWorktree w.\n"


class Card(unittest.TestCase):
    """`state` and `body` against one draft card, which a write must not take from its session
    or strip to its State."""

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.folder)
        gh = self.folder / "gh"
        gh.write_text('#!/bin/bash\necho "$*" >> "$(dirname "$0")/calls.log"\n'
                      'printf \'HTTP/2.0 200 OK\\r\\n\\r\\n\'\ncat "$(dirname "$0")/response.json"\n')
        gh.chmod(0o755)
        self.card(status="In Progress")

    def card(self, status, body=CARD):
        item = {"id": "PVTI_1", "fullDatabaseId": 1, "status": {"name": status}, "feature": None,
                "project": {"number": 2, "owner": {"login": "plusplusinc"}},
                "content": {"id": "DI_1", "title": "A card", "body": body}}
        (self.folder / "response.json").write_text(json.dumps({"data": {"nodes": [item]}}))

    def board(self, *args, stdin):
        env = dict(os.environ, PATH=f"{self.folder}:{os.environ['PATH']}")
        return subprocess.run([str(BOARD), *args], input=stdin, capture_output=True, text=True, env=env)

    def wrote(self):
        log = self.folder / "calls.log"
        return log.exists() and "updateProjectV2DraftIssue" in log.read_text()

    def test_another_session_cannot_replace_the_state_of_a_card_in_progress(self):
        run = self.board("state", "PVTI_1", stdin="Led by session session_9Zz8, since 2026-11-21.\n")
        self.assertEqual(run.returncode, 1)
        self.assertIn("names session_0A1b as leading it", run.stderr)
        self.assertIn("--take", run.stderr)
        self.assertFalse(self.wrote())

    def test_with_take_it_can(self):
        run = self.board("state", "PVTI_1", "--take", stdin="Led by session session_9Zz8.\n")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertTrue(self.wrote())

    def test_the_leading_session_rewrites_its_own_state(self):
        run = self.board("state", "PVTI_1", stdin="Phase: built. Led by session session_0A1b.\n")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertTrue(self.wrote())

    def test_a_state_that_names_no_session_is_written(self):
        run = self.board("state", "PVTI_1", stdin="Seen again on run 12.\n")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertTrue(self.wrote())

    def test_a_card_not_in_progress_is_free_to_take(self):
        for status in ("Definitely", "Done"):
            self.card(status=status)
            run = self.board("state", "PVTI_1", stdin="Led by session session_9Zz8.\n")
            self.assertEqual(run.returncode, 0, run.stderr)
        self.assertTrue(self.wrote())

    def test_a_card_in_progress_with_no_state_is_free_to_take(self):
        self.card(status="In Progress", body="## Problem\nToday nothing.\n")
        run = self.board("state", "PVTI_1", stdin="Led by session session_9Zz8.\n")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertTrue(self.wrote())

    def test_a_body_that_is_only_a_state_section_is_refused(self):
        run = self.board("body", "PVTI_1", stdin="\n## State\nLed by session session_0A1b.\n")
        self.assertEqual(run.returncode, 1)
        self.assertIn("only a State section", run.stderr)
        self.assertFalse((self.folder / "calls.log").exists())

    def test_a_whole_body_is_written(self):
        run = self.board("body", "PVTI_1", stdin=CARD)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertTrue(self.wrote())


class Status(unittest.TestCase):
    """`status` points a session that takes a card at /onward, and says nothing otherwise."""

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.folder)
        options = [{"id": "O_1", "name": "In Progress"}, {"id": "O_2", "name": "Done"}]
        project = {"id": "PVT_1", "field": {"id": "F_1", "options": options}}
        response = {"data": {"organization": {"projectV2": project}}}
        (self.folder / "response.json").write_text(json.dumps(response))
        gh = self.folder / "gh"
        gh.write_text('#!/bin/bash\necho "$*" >> "$(dirname "$0")/calls.log"\n'
                      'printf \'HTTP/2.0 200 OK\\r\\n\\r\\n\'\ncat "$(dirname "$0")/response.json"\n')
        gh.chmod(0o755)

    def board(self, *args):
        env = dict(os.environ, PATH=f"{self.folder}:{os.environ['PATH']}")
        return subprocess.run([str(BOARD), "status", "PVTI_1", *args], capture_output=True, text=True, env=env)

    def test_in_progress_points_at_onward(self):
        run = self.board("In Progress")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("/onward", run.stdout)
        self.assertIn("agent-record.py", run.stdout)
        self.assertIn("updateProjectV2ItemFieldValue", (self.folder / "calls.log").read_text())

    def test_any_other_status_prints_nothing(self):
        run = self.board("Done")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout, "")


if __name__ == "__main__":
    unittest.main()
