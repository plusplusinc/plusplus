#!/usr/bin/env python3
"""`scripts/pr-check.sh reverts` against branches built in a temporary repository, its `body`
check, and the no-code list's coverage of scripts/: no network.

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


class Body(unittest.TestCase):
    """`scripts/pr-check.sh body`: the Card, Verified, and Friction lines the retro reads."""

    def check(self, text, author="mrdavidjcole"):
        return subprocess.run(["bash", str(CHECK), "body"], input=text, capture_output=True, text=True,
                              cwd=CHECK.parent, env={**os.environ, "PR_AUTHOR": author})

    def test_lines_and_headings_pass_crlf_included(self):
        for text in ("Summary.\n\nCard: none, asked in the session\n\nVerified: lint\n\nFriction: none\n",
                     "Summary.\r\n\r\nCard: [t](u)\r\n## Verified\r\n- lint\r\n## Friction\r\n- none\r\n",
                     "**Card:** x\n**Verified**: y\nVerified, the rest (abc): z\nFriction: none\n"):
            self.assertEqual(self.check(text).returncode, 0, text)

    def test_a_body_without_them_fails_naming_each(self):
        result = self.check("Today X. With this change, Y.\n\nChecked locally:\n- lint\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Card Verified Friction", result.stderr)

    def test_dependabots_own_body_passes_and_no_one_elses(self):
        dependabot = "Bumps the swift group with 1 update: swift-snapshot-testing.\n\nUpdates `x` from 1.19.4 to 1.19.5\n"
        self.assertEqual(self.check(dependabot, author="dependabot[bot]").returncode, 0)
        for author in ("dependabot", "renovate[bot]", ""):
            self.assertNotEqual(self.check(dependabot, author=author).returncode, 0, author)


class NoCodeList(unittest.TestCase):
    """Every script is on .github/no-code-paths or named in its "Not listed" lines, so a new one
    no build runs never starts an Xcode Cloud run by being forgotten (#137's pr-media.sh did)."""

    def test_every_script_is_listed_or_named_as_not(self):
        lines = (CHECK.parent.parent / ".github" / "no-code-paths").read_text().splitlines()
        entries = {line.strip() for line in lines if line.strip() and not line.startswith("#")}
        comments = " ".join(line for line in lines if line.startswith("#"))
        for script in sorted(CHECK.parent.iterdir()):
            listed = {"scripts/", "scripts/" + script.name, script.name} & entries
            named = "scripts/" + script.name in comments
            self.assertTrue(listed or named, f"scripts/{script.name} is neither on .github/no-code-paths "
                            "nor named there as not listed: list it if no build or test reads it")


if __name__ == "__main__":
    unittest.main()
