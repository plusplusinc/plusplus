#!/usr/bin/env python3
"""scripts/agent-record.py against a stand-in `gh` that answers from a fixture: no network.

The fixture's #171 and #159 carry those PRs' real agent runs (2026-11-11).

    python3 scripts/agent-record-test.py    # scripts/test.sh runs it
"""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "agent-record.py"


def usage(tokens, tools, ms):
    return (f"<usage><subagent_tokens>{tokens}</subagent_tokens><tool_uses>{tools}</tool_uses>"
            f"<duration_ms>{ms}</duration_ms></usage>")


RECORD_171 = """Agent record
- builder, claude-opus-5-5, round 1: 117245 tokens, 23 tool uses, 3.1 min; stopped by a write guard, no change made
- builder, claude-opus-5-5, round 1: 205129 tokens, 126 tool uses, 20.7 min
- verifier, claude-fable-5-2, round 1: 132709 tokens, 42 tool uses, 5.2 min"""
FIX_171 = "Agent record\r\n- builder, claude-opus-5-5, round 2: 30471 tokens, 33 tool uses, 3.9 min"
VERIFIER_171 = "Verifier record, abc1234\n" + "\n".join(f"- criterion, new: finding {i}" for i in range(5)) + \
    "\n- design, known: named in the body"
RECORD_159 = "Agent record\n- lookup, sonnet, round 1: 83926 tokens, 7 tool uses, 0.6 min"


def pr(number, comments=(), states=("SUCCESS",)):
    return {"number": number,
            "comments": {"nodes": [{"body": body, "authorAssociation": who} for body, who in comments]},
            "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": s} if s else None}} for s in states]}}


PRS = [
    pr(171, [(RECORD_171, "OWNER"), (VERIFIER_171, "OWNER"), (FIX_171, "MEMBER")], ("FAILURE", "SUCCESS", None)),
    pr(159, [(RECORD_159, "OWNER")]),
    pr(160, [("Verifier record, def5678\n- test, new: a gap, fast, 2 s", "OWNER")]),
    pr(161, [("Agent record\n- builder, claude-haiku-5-5, round 9: 1 tokens, 1 tool uses, 0.1 min", "NONE")]),
]


class Script(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.folder)
        # Each call's arguments and stdin go to calls.log; graphql answers from pages.json, one
        # page per call, in order.
        gh = self.folder / "gh"
        gh.write_text("""#!/usr/bin/env python3
import json, sys
from pathlib import Path
here = Path(__file__).parent
args = sys.argv[1:]
stdin = sys.stdin.read() if "--body-file" in args else ""
with (here / "calls.log").open("a") as log:
    log.write(json.dumps({"args": args, "stdin": stdin}) + "\\n")
if args[:2] == ["api", "graphql"]:
    pages = json.loads((here / "pages.json").read_text())
    count = sum(1 for line in (here / "calls.log").read_text().splitlines() if '"graphql"' in line)
    print(json.dumps(pages[count - 1]))
""")
        gh.chmod(0o755)
        self.pages([PRS])

    def pages(self, pages):
        answers = []
        for i, nodes in enumerate(pages):
            last = i == len(pages) - 1
            answers.append({"data": {"search": {"pageInfo": {"hasNextPage": not last, "endCursor": None if last else f"c{i}"},
                                                "nodes": nodes},
                                     "rateLimit": {"cost": 2, "remaining": 4990}}})
        (self.folder / "pages.json").write_text(json.dumps(answers))

    def run_script(self, *args):
        env = dict(os.environ, PATH=f"{self.folder}:{os.environ['PATH']}")
        return subprocess.run([str(SCRIPT), *args], capture_output=True, text=True, env=env)

    def calls(self):
        log = self.folder / "calls.log"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def test_a_line_takes_the_tables_model_and_the_usage(self):
        run = self.run_script("line", "builder", usage(205129, 126, 1244020))
        self.assertEqual(run.stdout, "- builder, claude-opus-5-5, round 1: 205129 tokens, 126 tool uses, 20.7 min\n")

    def test_a_resumed_run_keeps_only_its_own_tokens(self):
        run = self.run_script("line", "builder", usage(235600, 33, 236542), "--round", "2", "--after", "205129")
        self.assertEqual(run.stdout, "- builder, claude-opus-5-5, round 2: 30471 tokens, 33 tool uses, 3.9 min\n")

    def test_a_model_and_a_note_can_be_given(self):
        run = self.run_script("line", "lookup", "done " + usage(83926, 7, 35799), "--model", "sonnet",
                              "--note", "found it")
        self.assertEqual(run.stdout, "- lookup, sonnet, round 1: 83926 tokens, 7 tool uses, 0.6 min; found it\n")

    def test_a_role_with_no_row_needs_the_model_it_ran_on(self):
        run = self.run_script("line", "general-purpose", usage(1, 1, 1))
        self.assertEqual(run.returncode, 1)
        self.assertIn("pass --model", run.stderr)
        run = self.run_script("line", "general-purpose", usage(1, 1, 60000), "--model", "claude-opus-5-5")
        self.assertEqual(run.stdout, "- general-purpose, claude-opus-5-5, round 1: 1 tokens, 1 tool uses, 1.0 min\n")

    def test_no_usage_line_fails_saying_what_to_pass(self):
        run = self.run_script("line", "builder", "it went fine")
        self.assertEqual(run.returncode, 1)
        self.assertIn("subagent_tokens", run.stderr)

    def test_bare_prints_usage(self):
        run = self.run_script()
        self.assertEqual(run.returncode, 64)
        self.assertIn("tally <since", run.stderr)

    def test_post_adds_one_comment_with_the_header(self):
        lines = [RECORD_159.splitlines()[1], FIX_171.splitlines()[1].strip()]
        run = self.run_script("post", "159", *lines)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(self.calls(), [{"args": ["pr", "comment", "159", "--body-file", "-"],
                                         "stdin": "Agent record\n" + "\n".join(lines)}])

    def test_post_refuses_a_hand_written_line(self):
        run = self.run_script("post", "159", "- builder on opus, about 20 minutes")
        self.assertEqual(run.returncode, 1)
        self.assertEqual(self.calls(), [])

    def test_the_tally_counts_per_role_and_model_and_names_the_prs_with_none(self):
        run = self.run_script("tally", "2026-11-01")
        self.assertEqual(run.returncode, 0, run.stderr)
        out = run.stdout
        self.assertIn("4 merged, 2 with an agent record (#159, #171); 2 with none (#160, #161).", out)
        self.assertIn("Verifier records on PRs with no agent record, so no model to credit: #160 (1 new).", out)
        self.assertIn("The PRs with none are left out of every number below.", out)
        rows = {line.split()[0] + " " + line.split()[1]: line for line in out.splitlines() if "  " in line}
        self.assertRegex(rows["builder claude-opus-5-5"], r"3\s+1\s+352845\s+27.7  fix rounds 1.0, failed pushes 1.0$")
        self.assertRegex(rows["verifier claude-fable-5-2"], r"1\s+1\s+132709\s+5.2  new findings 5.0$")
        self.assertRegex(rows["lookup sonnet"], r"1\s+1\s+83926\s+0.6$")
        self.assertIn("#171: 4 runs, 485554 tokens, 32.9 min, fix rounds 1, new findings 5, failed pushes 1", out)
        self.assertIn("#159: 1 runs, 83926 tokens, 0.6 min, no verifier record, failed pushes 0", out)
        self.assertNotIn("claude-haiku-5-5", out)  # a record by someone outside the repo
        self.assertIn("This run cost 2 GraphQL points; 4990 left this hour.", out)

    def test_the_tally_fetches_once_per_page_with_only_the_merged_prs(self):
        self.pages([PRS[:2], PRS[2:]])
        run = self.run_script("tally", "2026-11-01")
        self.assertEqual(run.returncode, 0, run.stderr)
        calls = self.calls()
        self.assertEqual(len(calls), 2)
        self.assertIn("q=repo:plusplusinc/plusplus is:pr is:merged base:main merged:>=2026-11-01", calls[0]["args"])
        self.assertIn("after=c0", calls[1]["args"])
        self.assertIn("4 merged", run.stdout)
        self.assertIn("This run cost 4 GraphQL points", run.stdout)

    def test_with_no_record_the_tally_says_so_and_shows_no_numbers(self):
        self.pages([[pr(1), pr(2)]])
        run = self.run_script("tally", "2026-11-01")
        self.assertEqual(run.stdout.splitlines()[:2],
                         ["Agent records, PRs merged since 2026-11-01: 2 merged, 0 with an agent record; 2 with none (#1, #2).",
                          "No PR has an agent record, so there is nothing to tally."])
        self.assertNotIn("tokens/PR", run.stdout)

    def test_a_run_cancelled_by_the_next_push_is_no_failed_push(self):
        # #171's merge commit, as GitHub returns it: its Xcode Cloud run was cancelled when the
        # next push started one, which the rollup reports as FAILURE, and nothing failed.
        cancelled = {"state": "FAILURE", "contexts": {"nodes": [
            {"__typename": "CheckRun", "name": "Route", "status": "COMPLETED", "conclusion": "SUCCESS"},
            {"__typename": "CheckRun", "name": "PR check", "status": "COMPLETED", "conclusion": "CANCELLED"},
            {"__typename": "StatusContext", "context": "PlusPlus Workout Tracker | PR", "state": "FAILURE",
             "description": "cancelled"},
            {"__typename": "CheckRun", "name": "PlusPlus Workout Tracker | PR | Test - iOS", "status": "COMPLETED",
             "conclusion": "CANCELLED"}]}}
        number = pr(171, [(RECORD_171, "OWNER")], ("SUCCESS",))
        number["commits"]["nodes"].insert(0, {"commit": {"statusCheckRollup": cancelled}})
        self.pages([[number]])
        run = self.run_script("tally", "2026-11-01")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("failed pushes 0", run.stdout)

    def test_a_bad_date_prints_usage(self):
        self.assertEqual(self.run_script("tally", "November").returncode, 64)


if __name__ == "__main__":
    unittest.main()
