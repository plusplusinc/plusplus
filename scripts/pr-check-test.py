#!/usr/bin/env python3
"""`scripts/pr-check.sh reverts` against branches built in a temporary repository: no network.

    python3 scripts/pr-check-test.py

The replay is #136's case: a branch cut from main, main gaining a commit meanwhile (#134, a line
of Swift and a snapshot), and the branch squashed with `git reset --soft` onto the newer main, so
its stale copies undo that commit.
"""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

CHECK = Path(__file__).resolve().with_name("pr-check.sh")
ROW = "struct RailRow {\n    let dot = Dot()\n    var body: some View { dot }\n}\n"
LANDED = "struct RailRow {\n    let dot = Dot()\n    var body: some View { dot.fixed() }\n}\n"


class Reverts(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.repo = Path(self.dir.name)
        self.git("init", "-q", "-b", "main")
        self.write("RailRow.swift", ROW)
        self.write("row.png", b"\x89PNG old")
        self.write("common.sh", "boot() {\n    simctl boot\n}\n")
        self.commit("Start")
        # The branch's session starts here, as #136's did from #133.
        self.git("switch", "-q", "-c", "tooling")
        self.write("common.sh", "boot() {\n    cap_boots\n    simctl boot\n}\n")
        self.commit("Cap how many boot at once")
        # Meanwhile main gains #134.
        self.git("switch", "-q", "main")
        self.write("RailRow.swift", LANDED)
        self.write("row.png", b"\x89PNG new")
        self.commit("Keep the dot in place (#134)")
        self.landed = self.git("rev-parse", "HEAD")
        self.git("switch", "-q", "tooling")

    def tearDown(self):
        self.dir.cleanup()

    def git(self, *args):
        env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
               "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com"}
        return subprocess.run(["git", *args], cwd=self.repo, env=env, capture_output=True, text=True,
                              check=True).stdout.strip()

    def write(self, name, content):
        path = self.repo / name
        path.write_bytes(content if isinstance(content, bytes) else content.encode())

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def check(self):
        return subprocess.run(["bash", str(CHECK), "reverts", "main", "HEAD"], cwd=self.repo,
                              capture_output=True, text=True)

    def test_a_squash_onto_the_newer_main_fails_naming_what_it_undoes(self):
        self.git("reset", "--soft", "main")
        self.commit("Cap how many boot at once")
        result = self.check()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("Keep the dot in place (#134): undone in RailRow.swift, row.png", result.stderr)
        self.assertIn("merge origin/main", result.stderr)

    def test_a_branch_brought_up_to_date_by_a_merge_passes(self):
        self.git("merge", "-q", "--no-edit", "main")
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("reverts nothing", result.stdout)

    def test_a_merged_branch_squashed_onto_its_merge_base_passes(self):
        self.git("merge", "-q", "--no-edit", "main")
        self.git("reset", "--soft", self.git("merge-base", "HEAD", "main"))
        self.commit("Cap how many boot at once")
        self.assertEqual(self.check().returncode, 0)

    def test_a_branch_behind_main_passes(self):
        # Its diff, from the merge base, leaves #134's lines alone; the ruleset makes it merge
        # main before it lands.
        self.assertEqual(self.check().returncode, 0)

    def test_a_follow_up_that_changes_some_of_the_commits_lines_passes(self):
        self.git("merge", "-q", "--no-edit", "main")
        self.write("RailRow.swift", LANDED.replace("let dot = Dot()", "let dot = Dot(size: 8)"))
        self.commit("Size the dot")
        self.assertEqual(self.check().returncode, 0)

    def test_a_revert_made_with_git_revert_passes(self):
        self.git("merge", "-q", "--no-edit", "main")
        self.git("revert", "--no-edit", self.landed)
        self.assertEqual(self.check().returncode, 0, self.check().stderr)

    def test_a_revert_by_hand_fails(self):
        self.git("merge", "-q", "--no-edit", "main")
        self.write("RailRow.swift", ROW)
        self.commit("Put the old row back")
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("undone in RailRow.swift", result.stderr)


if __name__ == "__main__":
    unittest.main()
