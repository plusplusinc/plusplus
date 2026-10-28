#!/usr/bin/env python3
"""The nightly runner's gates against fixtures: no network, no board, no claude.

    python3 scripts/nightly-tooling-test.py
"""
import contextlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

spec = importlib.util.spec_from_file_location("nightly", Path(__file__).with_name("nightly-tooling.py"))
nightly = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nightly)

NIGHT = datetime(2026, 10, 28, 1, 30).astimezone()  # a Wednesday, 1:30 am local
CUTOFF, STOP = nightly.night_window(NIGHT)


def at(hours):
    """A unix time this many hours after 1:30 am."""
    return (NIGHT + timedelta(hours=hours)).timestamp()


def info(five=0.1, week=0.1, five_resets=3, week_resets=100, five_status="allowed", **more):
    windows = {"five_hour": {"utilization": five, "resetsAt": at(five_resets), "status": five_status},
               "seven_day": {"utilization": week, "resetsAt": at(week_resets), "status": "allowed"}}
    windows.update(more)
    return {"status": "allowed", "rateLimitType": "five_hour", "unifiedWindows": windows}


class TimeOfNight(unittest.TestCase):
    def test_cards_start_from_midnight_to_five(self):
        self.assertEqual(CUTOFF.hour, 5)
        self.assertEqual(STOP.hour, 7)
        self.assertEqual(CUTOFF.date(), NIGHT.date())
        self.assertIsNotNone(nightly.night_window(NIGHT.replace(hour=0, minute=0)))
        self.assertIsNotNone(nightly.night_window(NIGHT.replace(hour=4, minute=59)))

    def test_no_cards_from_five_to_midnight(self):
        for hour in (5, 7, 12, 23):
            self.assertIsNone(nightly.night_window(NIGHT.replace(hour=hour)), hour)


class Usage(unittest.TestCase):
    def gate(self, event, uncapped=False):
        return nightly.usage_gate(event, NIGHT, CUTOFF, STOP, uncapped)

    def test_low_usage_goes(self):
        self.assertEqual(self.gate(info()), ("go", None))

    def test_no_event_stops(self):
        self.assertEqual(self.gate(None)[0], "stop")
        self.assertEqual(self.gate({"status": "allowed"})[0], "stop")

    def test_a_window_at_ninety_percent_stops(self):
        self.assertEqual(self.gate(info(week=0.9))[0], "stop")
        self.assertEqual(self.gate(info(week=0.89)), ("go", None))

    def test_any_window_counts_whatever_its_name(self):
        extra = {"seven_day_opus": {"utilization": 0.95, "resetsAt": at(50), "status": "allowed"}}
        decision, why = self.gate(info(**extra))
        self.assertEqual(decision, "stop")
        self.assertIn("seven_day_opus", why)

    def test_a_window_not_allowed_stops(self):
        rejected = {"seven_day": {"utilization": 0.5, "resetsAt": at(100), "status": "rejected"}}
        self.assertEqual(self.gate(info(**rejected))[0], "stop")

    def test_a_full_five_hour_window_waits_when_it_resets_before_five(self):
        self.assertEqual(self.gate(info(five=0.95, five_resets=2)), ("wait", nightly.local(at(2))))

    def test_a_full_five_hour_window_stops_when_it_resets_after_five(self):
        self.assertEqual(self.gate(info(five=0.95, five_resets=4))[0], "stop")

    def test_a_window_whose_reset_passed_counts_as_fresh(self):
        self.assertEqual(self.gate(info(five=0.95, five_resets=-0.5)), ("go", None))

    def test_the_uncapped_night_keeps_a_morning_reserve(self):
        # Five-hour window resetting at 8:30 am, after the 7 am stop, at 0.6 used.
        self.assertEqual(self.gate(info(five=0.6, five_resets=7), uncapped=True)[0], "stop")
        self.assertEqual(self.gate(info(five=0.6, five_resets=7), uncapped=False), ("go", None))
        self.assertEqual(self.gate(info(five=0.4, five_resets=7), uncapped=True), ("go", None))

    def test_uncapped_only_when_every_weekly_window_resets_by_seven(self):
        resets_at_seven = (STOP - NIGHT).total_seconds() / 3600
        self.assertTrue(nightly.is_uncapped(info(week_resets=resets_at_seven), STOP))
        self.assertFalse(nightly.is_uncapped(info(week_resets=resets_at_seven + 0.1), STOP))
        other = {"seven_day_opus": {"utilization": 0, "resetsAt": at(50), "status": "allowed"}}
        self.assertFalse(nightly.is_uncapped(info(week_resets=1, **other), STOP))
        self.assertFalse(nightly.is_uncapped(None, STOP))

    def test_reads_the_last_event_in_the_night_logs(self):
        with tempfile.TemporaryDirectory() as folder:
            first, second = Path(folder, "retro.jsonl"), Path(folder, "card-1.jsonl")
            first.write_text(json.dumps({"type": "rate_limit_event", "rate_limit_info": info(five=0.1)}) + "\n")
            second.write_text("not json\n" + json.dumps({"type": "rate_limit_event", "rate_limit_info": info(five=0.4)})
                              + "\n" + json.dumps({"type": "result", "is_error": False}) + "\n")
            found = nightly.last_rate_limit([first, second])
            self.assertEqual(found["unifiedWindows"]["five_hour"]["utilization"], 0.4)
            self.assertIsNone(nightly.last_rate_limit([]))

    def test_a_limit_error_is_a_limit_hit(self):
        ok = [json.dumps({"type": "result", "is_error": False, "result": "PR #12"})]
        self.assertFalse(nightly.limit_hit(ok))
        self.assertTrue(nightly.limit_hit([json.dumps({"type": "result", "is_error": True, "api_error_status": 429})]))
        self.assertTrue(nightly.limit_hit([json.dumps({"type": "result", "is_error": True,
                                                       "result": "You've hit your session limit · resets 11:20am"})]))
        self.assertTrue(nightly.limit_hit([json.dumps({"type": "rate_limit_event",
                                                       "rate_limit_info": {"status": "rejected"}})]))
        self.assertTrue(nightly.limit_hit(['{"apiError": "usage_limit_reached"}']))
        # A tool's output that mentions the limit, as reading this runner's own code would.
        tool_output = {"type": "user", "message": {"content": [{"type": "tool_result", "content": "usage_limit_reached"}]}}
        self.assertFalse(nightly.limit_hit([json.dumps(tool_output)]))
        self.assertFalse(nightly.limit_hit([json.dumps({"type": "result", "is_error": True, "api_error_status": 500})]))


class Count(unittest.TestCase):
    def test_three_cards_on_a_capped_night(self):
        self.assertEqual([nightly.cards_left(n, False) for n in range(5)], [True, True, True, False, False])

    def test_no_count_on_the_uncapped_night(self):
        self.assertTrue(nightly.cards_left(10, True))


class XcodeCloud(unittest.TestCase):
    def run_(self, started, minutes, finished=True):
        start = datetime.fromisoformat(started + "+00:00")
        attributes = {"createdDate": started + "Z", "startedDate": started + ".5Z"}
        if finished:
            attributes["finishedDate"] = (start + timedelta(minutes=minutes)).isoformat()
        return {"attributes": attributes}

    def test_month_hours_sum_this_months_runs(self):
        now = datetime.fromisoformat("2026-10-28T06:00:00+00:00")
        runs = [self.run_("2026-10-27T10:00:00", 30), self.run_("2026-10-01T00:10:00", 90),
                self.run_("2026-09-30T23:00:00", 600), self.run_("2026-10-28T05:30:00", 0, finished=False)]
        self.assertAlmostEqual(nightly.month_hours(runs, now), 0.5 + 1.5 + 0.5, places=3)

    def test_runs_since_the_night_started(self):
        since = datetime.fromisoformat("2026-10-28T04:00:00+00:00")
        runs = [self.run_("2026-10-28T03:59:00", 10), self.run_("2026-10-28T04:10:00", 10)]
        self.assertEqual(len(nightly.runs_since(runs, since)), 1)

    def test_a_card_that_starts_a_run_waits_past_seventy_hours_or_four_runs(self):
        self.assertIsNone(nightly.xcode_cloud_gate(69.9, 3))
        self.assertIn("70", nightly.xcode_cloud_gate(70.1, 0))
        self.assertIn("4 Xcode Cloud runs", nightly.xcode_cloud_gate(10, 4))


class Paths(unittest.TestCase):
    def test_protected_paths(self):
        hits = ["scripts/pr-check.sh", ".github/workflows/pr-check.yml", ".github/no-code-paths",
                ".claude/settings.json", ".claude/settings.local.json", "Config/Base.xcconfig",
                "PlusPlus.xcodeproj/project.pbxproj", "Packages/Package.swift", "PlusPlus.xctestplan",
                "App/PlusPlus.entitlements", "ci_scripts/ci_post_clone.sh", ".swiftlint.yml",
                "Packages/Tests/.swiftlint.yml", ".swiftformat", "scripts/nightly-tooling.py",
                "scripts/nightly-retro.sh", ".claude/skills/nightly-card/SKILL.md", "scripts/xcresult.py",
                "scripts/tidy.sh", ".claude/hooks/on-edit.sh",
                # What CI runs or installs, and what steers the night's agents.
                "PlusPlus.xcodeproj/xcshareddata/xcschemes/PlusPlus.xcscheme", "scripts/lint.sh",
                "scripts/check-us-english.sh", "Brewfile", "Packages/Package.resolved",
                ".github/pull_request_template.md", ".claude/agents/verifier.md", ".claude/skills/pr/SKILL.md",
                ".claude/rules/testing.md", "CLAUDE.md", "AGENTS.md", ".mcp.json"]
        hits += [".claude/skills/run/SKILL.md", ".claude/skills/brief/SKILL.md"]
        safe = ["scripts/ci-times.py", "docs/pr-check.md", "PlusPlusUITests/Waits.swift", "scripts/test.sh",
                "Packages/Sources/WorkoutStore/Namer.swift", "Config/README.md"]
        self.assertEqual(nightly.protected(hits + safe), hits)

    def test_only_claude_and_docs_wait_for_the_day(self):
        self.assertTrue(nightly.day_only([".claude/skills/pr/SKILL.md", "docs/pr-check.md"]))
        self.assertFalse(nightly.day_only([".claude/skills/pr/SKILL.md", "scripts/tidy.sh"]))
        self.assertFalse(nightly.day_only([]))

    def test_likely_files_and_overlap(self):
        repo = {"PlusPlusUITests/Waits.swift", "PlusPlusUITests/SettlingTests.swift", "scripts/tidy.sh", ".swiftformat"}
        body = ("Today `reading(_:until:)` in `PlusPlusUITests/Waits.swift`, and `scripts/tidy.sh --dry-run`, "
                "the `.swiftformat` header, all of `PlusPlusUITests/`.")
        likely = nightly.likely_files(body, repo)
        self.assertEqual(likely, {"PlusPlusUITests/Waits.swift", "scripts/tidy.sh", ".swiftformat", "PlusPlusUITests/"})
        self.assertEqual(nightly.overlap(likely, ["PlusPlusUITests/SettlingTests.swift", "docs/x.md"]),
                         ["PlusPlusUITests/SettlingTests.swift"])
        self.assertEqual(nightly.overlap({"scripts/tidy.sh"}, ["scripts/tidy.sh.bak", "docs/x.md"]), [])


class Eligibility(unittest.TestCase):
    BODY = "## Problem\nx\n\nNightly: faster CI; the PR check's time\n\n## Success\nRun it: it passes.\n\n## Plan\n- y\n"

    def test_an_eligible_card(self):
        self.assertIsNone(nightly.eligibility("Todo", "-", self.BODY))

    def test_product_and_unmarked_cards_wait_for_the_day(self):
        self.assertIn("feature", nightly.eligibility("Todo", "Routine screen", self.BODY))
        self.assertIn("Nightly", nightly.eligibility("Todo", "-", self.BODY.replace("Nightly:", "Later:")))
        self.assertIn("Backlog", nightly.eligibility("Backlog", "-", self.BODY))
        self.assertIn("check", nightly.eligibility("Todo", "-", self.BODY.replace("## Success\nRun it: it passes.\n", "")))


class Verifier(unittest.TestCase):
    def test_the_newest_record_decides(self):
        comments = ["Verifier record, abc1234\n- criterion, new: it failed",
                    "a reply", "Verifier record, def5678\n- test, new: x, unit, 0.1 s\n- design, known: y"]
        self.assertEqual(nightly.verifier_record(comments), ("def5678", [], []))

    def test_a_failed_criterion_or_a_crash_fails(self):
        _, failures, unread = nightly.verifier_record(["Verifier record, abc1234\n- criterion, new: a\n- crash, new: b\n- No findings"])
        self.assertEqual((len(failures), unread), (2, []))

    def test_a_line_off_the_format_is_unread_never_a_pass(self):
        for line in ["- Criterion, new: it failed", "  - criterion, new: it failed", "- criterion new: it failed",
                     "* criterion, new: it failed", "- criterion, New: it failed", "it failed"]:
            self.assertEqual(nightly.verifier_record([f"Verifier record, abc1234\n{line}"])[2], [line], line)
        self.assertEqual(nightly.verifier_record(["Verifier record, abc1234\n\n"])[2], ["(no lines)"])

    def test_the_header_names_a_commit_or_nothing(self):
        self.assertIsNone(nightly.verifier_record(["Verifier record, the latest\n- No findings"])[0])
        self.assertEqual(nightly.verifier_record(["Verifier record, abc1234 \n- No findings"])[0], "abc1234")

    def test_no_record(self):
        self.assertIsNone(nightly.verifier_record(["LGTM"]))

    def test_after_the_verifier_only_tests_may_change(self):
        self.assertTrue(nightly.only_tests(["PlusPlusUITests/WaitsTests.swift", "Packages/Tests/X/YTests.swift"]))
        self.assertTrue(nightly.only_tests([]))
        self.assertFalse(nightly.only_tests(["PlusPlusUITests/WaitsTests.swift", "App/Root.swift"]))
        for not_a_test in ["Packages/Sources/WorkoutStore/Latest.swift", "scripts/test.sh", "scripts/nightly-tooling-test.py"]:
            self.assertFalse(nightly.only_tests([not_a_test]), not_a_test)

    def test_fewer_tests(self):
        before = {"WorkoutStoreTests": 161, "DesignSystemTests": 118}
        self.assertEqual(nightly.test_drops(before, {"WorkoutStoreTests": 162, "DesignSystemTests": 117}),
                         [("DesignSystemTests", 118, 117)])
        self.assertEqual(nightly.test_drops(before, before), [])

    def test_only_a_fewer_tests_line_naming_the_target_explains_a_drop(self):
        drops = [("DesignSystemTests", 118, 117)]
        self.assertEqual(nightly.unexplained_drops(drops, "Fewer tests: DesignSystemTests drops a duplicate."), [])
        for body in ["x", "Says no `Fewer tests:` line is needed.", "Fewer tests: WorkoutStoreTests, a duplicate.",
                     "  Fewer tests: DesignSystemTests"]:
            self.assertEqual(nightly.unexplained_drops(drops, body), drops, body)

    def test_a_test_in_a_comment_or_a_string_does_not_count(self):
        source = """@Test func a() {}
@MainActor @Test("named") func b() {}
// @Test func c() {}
/* @Test func d() {}
   @Test func e() {} */
let text = "@Test func f() // not a comment"
func testG() {}
    // func testH() {}
"""
        self.assertEqual(nightly.count_tests(source), 3)


def decide(command="", tool="Bash", now=NIGHT, app=True, runs=0, hours=10):
    """The hook's decision, with a run_gate built from what the branch changes and the night's runs."""
    gate = lambda starts: app and nightly.xcode_cloud_gate(hours, runs)  # noqa: E731
    return nightly.hook_decision(tool, command, now, STOP, ".slices/h.md", gate) or None


class Hook(unittest.TestCase):
    def decide(self, tool, command="", now=NIGHT, app=False, runs=0, hours=10):
        return decide(command, tool, now, app, runs, hours)

    def test_ordinary_work_is_allowed(self):
        self.assertIsNone(self.decide("Bash", "scripts/build.sh"))
        self.assertIsNone(self.decide("Agent"))
        self.assertIsNone(self.decide("Bash", "git push -u origin night-x", app=True, runs=3))
        self.assertIsNone(self.decide("Bash", "git push -u origin night-x", app=False, runs=9, hours=99))

    def test_only_a_git_push_or_a_new_pr_may_start_a_run(self):
        for command in ["git push", "git -C /w push -u origin x", "cd /w && git push", "make; git push origin x",
                        "gh pr create --title t --body-file -", "gh pr ready 7"]:
            self.assertTrue(nightly.call_risks(command)[1], command)
        for command in ['git commit -m "Retry the push on 429"', "git stash push", "gh pr view 7", "gh pr checks 7"]:
            self.assertEqual(nightly.call_risks(command), (None, None), command)
        late = STOP + timedelta(minutes=1)
        self.assertIsNone(self.decide("Bash", 'git commit -m "push later"', now=late))

    def test_never_merge(self):
        self.assertIn("Never merge", self.decide("Bash", "gh pr merge 12 --squash"))
        self.assertIn("Never merge", self.decide("Bash", "cd x && gh  pr merge --auto"))

    def test_the_fifth_run_or_past_seventy_hours_is_denied(self):
        self.assertIn("Xcode Cloud", self.decide("Bash", "git -C /w push", app=True, runs=4))
        self.assertIn("Xcode Cloud", self.decide("Bash", "git push", app=True, hours=70.5))

    def test_from_seven_only_the_handoff(self):
        late = STOP + timedelta(minutes=1)
        self.assertIn(".slices/h.md", self.decide("Agent", now=late))
        self.assertIn("past 7", self.decide("Bash", "scripts/build.sh", now=late))
        self.assertIn("past 7", self.decide("Bash", "git push", now=late))
        self.assertIsNone(self.decide("Bash", "cd /w && git add -A && git commit -m handoff", now=late))
        self.assertIsNone(self.decide("Write", now=late))

    def test_from_seven_a_pipe_or_substitution_is_no_way_out(self):
        late = STOP + timedelta(minutes=1)
        for command in ["cat x | sh", "grep -l a f | xargs rm -rf", 'git commit -m "$(scripts/build.sh)"',
                        "cat x\nscripts/build.sh", "git -C /w push"]:
            self.assertIn("past 7", self.decide("Bash", command, now=late), command)
        self.assertIsNone(self.decide("Bash", "git -C /w status && git --no-pager diff | head", now=late))


class Digest(unittest.TestCase):
    def test_a_merged_pr_has_its_undo_line(self):
        line = nightly.digest_block({"number": 120, "title": "Lint the UI tests"}, "0123456789abcdef",
                                    [".swiftlint.yml", "PlusPlusUITests/A.swift", "Packages/Tests/B/C.swift"],
                                    "verifier record at abc1234, PR check passed on Xcode Cloud run 330")
        self.assertEqual(line, "#120 Lint the UI tests — 0123456 — .swiftlint.yml, Packages/Tests, PlusPlusUITests — "
                               "verifier record at abc1234, PR check passed on Xcode Cloud run 330 — undo: git revert 0123456")


class Decide(unittest.TestCase):
    """Night.decide against a real git repo, with gh and the board recorded instead of called."""

    def setUp(self):
        self.repo = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.repo, True)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "night@example.com")
        self.git("config", "user.name", "night")
        for name in (".swiftlint.yml", "scripts/a.py"):
            self.write(name, "x\n")
        self.write("Packages/Tests/WorkoutStoreTests/T.swift", "@Test func a() {}\n@Test func b() {}\n")
        self.git("add", "-A")
        self.git("commit", "-qm", "base")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.calls = []
        real = nightly.sh

        def sh(*args, cwd=None, stdin=None, check=True):
            if args[0] == "git":
                return "" if args[1] == "fetch" else real(*args, cwd=self.repo, stdin=stdin, check=check)
            self.calls.append(" ".join(str(a) for a in args))
            return "me\n" if args[:3] == ("gh", "api", "user") else ""

        self.saved = nightly.sh, nightly.ROOT
        nightly.sh, nightly.ROOT = sh, self.repo
        self.night = nightly.Night(self.repo / "night", NIGHT, False)
        self.night.wait_merge = lambda n: "f" * 40

    def tearDown(self):
        nightly.sh, nightly.ROOT = self.saved

    def git(self, *args):
        return nightly.subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True,
                                      text=True).stdout.strip()

    def write(self, name, text):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def pr(self, change, record="- No findings", body="x"):
        self.git("checkout", "-q", "-b", "card", "origin/main")
        change()
        self.git("add", "-A")
        self.git("commit", "-qm", "card")
        sha = self.git("rev-parse", "HEAD")
        comments = [{"body": f"Verifier record, {sha[:7]}\n{record}", "author": {"login": "me"}}] if record else []
        return {"number": 7, "title": "Card", "headRefOid": sha, "body": body, "comments": comments}

    def test_a_passing_card_arms_auto_merge_at_its_head(self):
        pr = self.pr(lambda: self.write("scripts/a.py", "y\n"))
        self.assertEqual(self.night.decide("PVTI_1", "Card", pr), "merged")
        self.assertIn(f"gh pr merge 7 --auto --squash --match-head-commit {pr['headRefOid']}", self.calls)

    def test_a_renamed_protected_file_waits_unmerged_and_the_digest_says_so(self):
        pr = self.pr(lambda: (self.repo / ".swiftlint.yml").rename(self.repo / "lint.yml"))
        self.assertEqual(self.night.decide("PVTI_1", "Card", pr), "waiting")
        self.assertFalse([c for c in self.calls if c.startswith("gh pr merge")])
        self.assertIn(".swiftlint.yml", self.night.waiting[0])

    def test_a_failed_card_goes_to_draft_with_auto_merge_off_and_its_state_says_why(self):
        pr = self.pr(lambda: self.write("scripts/a.py", "y\n"), record="- criterion, new: it broke")
        self.assertEqual(self.night.decide("PVTI_1", "Card", pr), "parked")
        self.assertIn("gh pr merge 7 --disable-auto", self.calls)
        self.assertIn("gh pr ready 7 --undo", self.calls)
        self.assertTrue(any(c.endswith("board.sh state PVTI_1") for c in self.calls))
        self.assertIn("it broke", self.night.parked[0])

    def test_no_merge_without_a_verifier_record(self):
        pr = self.pr(lambda: self.write("scripts/a.py", "y\n"), record=None)
        self.assertEqual(self.night.decide("PVTI_1", "Card", pr), "parked")
        self.assertFalse([c for c in self.calls if "--auto" in c])

    def test_a_test_count_drop_without_its_line_parks(self):
        pr = self.pr(lambda: self.write("Packages/Tests/WorkoutStoreTests/T.swift", "@Test func a() {}\n"))
        self.assertEqual(self.night.decide("PVTI_1", "Card", pr), "parked")

    def test_a_test_commented_out_is_a_drop(self):
        pr = self.pr(lambda: self.write("Packages/Tests/WorkoutStoreTests/T.swift",
                                        "@Test func a() {}\n// @Test func b() {}\n"))
        self.assertEqual(self.night.decide("PVTI_1", "Card", pr), "parked")
        self.assertIn("WorkoutStoreTests 2 → 1", self.night.parked[0])

    def test_a_drop_its_body_explains_merges(self):
        pr = self.pr(lambda: self.write("Packages/Tests/WorkoutStoreTests/T.swift", "@Test func a() {}\n"),
                     body="Fewer tests: WorkoutStoreTests loses b, which a covers.")
        self.assertEqual(self.night.decide("PVTI_1", "Card", pr), "merged")

    def test_a_record_off_the_format_parks(self):
        pr = self.pr(lambda: self.write("scripts/a.py", "y\n"), record="- Criterion, new: it broke")
        self.assertEqual(self.night.decide("PVTI_1", "Card", pr), "parked")
        self.assertFalse([c for c in self.calls if "--auto" in c])
        self.assertIn("can't read", self.night.parked[0])

    def test_a_scheme_or_lint_script_change_waits(self):
        for name in ("PlusPlus.xcodeproj/xcshareddata/xcschemes/PlusPlus.xcscheme", "scripts/lint.sh"):
            self.git("checkout", "-q", "main")
            self.git("branch", "-qD", "card") if self.git("branch", "--list", "card") else None
            pr = self.pr(lambda: self.write(name, "exit 0\n"))
            self.assertEqual(self.night.decide("PVTI_1", "Card", pr), "waiting", name)
        self.assertFalse([c for c in self.calls if c.startswith("gh pr merge")])


class Loop(unittest.TestCase):
    """Night.run's card count, with the board, the PRs, and each card's run stubbed."""

    BODY = "## Problem\nx\n\nNightly: faster CI; its time\n\n## Success\nRun it.\n"

    def night(self, results, weekly_resets, take=None, event=None, finish=False):
        cards = [(f"PVTI_{i}", "Todo", "-", f"card {i}", self.BODY) for i in range(4)]
        stubs = {"board_cards": lambda: cards, "xcode_cloud_runs": lambda: [], "gh_json": lambda *a: [],
                 "classify": lambda files: "app: x", "sh": lambda *a, **k: "", "test_counts": lambda rev: {}}
        saved = {name: getattr(nightly, name) for name in stubs}
        self.addCleanup(lambda: [setattr(nightly, n, f) for n, f in saved.items()])
        for name, stub in stubs.items():
            setattr(nightly, name, stub)
        folder = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, folder, True)
        event = event or info(week_resets=weekly_resets)
        (folder / "retro.jsonl").write_text(json.dumps({"type": "rate_limit_event", "rate_limit_info": event}) + "\n")
        night = nightly.Night(folder, NIGHT, False)
        night.clock = lambda: NIGHT
        if not finish:
            night.finish = lambda: None
        taken = []

        def taking(card, _):
            taken.append(card[1])
            night.tried.add(card[0])
            return results[len(taken) - 1]

        night.take = take or taking
        night.taken = taken
        night.run()
        return night

    def test_four_eligible_cards_on_a_capped_night_three_run(self):
        self.assertEqual(self.night(["merged"] * 4, weekly_resets=100).taken, ["card 0", "card 1", "card 2"])

    def test_after_a_failed_card_the_next_runs(self):
        self.assertEqual(self.night(["parked", "merged", "merged", "merged"], weekly_resets=100).taken,
                         ["card 0", "card 1", "card 2"])

    def test_a_crash_mid_card_leaves_a_state_and_a_digest(self):
        board_calls = []
        saved = nightly.board, nightly.tidy
        self.addCleanup(lambda: (setattr(nightly, "board", saved[0]), setattr(nightly, "tidy", saved[1])))
        nightly.board = lambda *a, stdin=None: board_calls.append((a, stdin))
        nightly.tidy = lambda: None

        def crash(card, _):
            raise AttributeError("'list' object has no attribute 'get'")

        night = self.night([], weekly_resets=100, take=crash, finish=True)
        digest = (night.dir / "digest.md").read_text()
        self.assertIn("Ended: No more cards: the runner failed: AttributeError", digest)
        self.assertIn("Parked: card 0: the runner failed", digest)
        self.assertEqual(board_calls[0][0], ("state", "PVTI_0"))
        self.assertIn("still In Progress", board_calls[0][1])

    def test_an_unreadable_usage_event_ends_the_night_with_a_digest(self):
        saved = nightly.tidy
        self.addCleanup(setattr, nightly, "tidy", saved)
        nightly.tidy = lambda: None
        event = info()
        del event["unifiedWindows"]["seven_day"]["resetsAt"]
        night = self.night(["merged"], weekly_resets=100, event=event, finish=True)
        self.assertEqual(night.taken, [])
        self.assertIn("Ended: No more cards: the usage window seven_day can't be read",
                      (night.dir / "digest.md").read_text())

    def test_the_uncapped_night_takes_the_fourth(self):
        resets_at_seven = (STOP - NIGHT).total_seconds() / 3600
        self.assertEqual(len(self.night(["merged"] * 4, weekly_resets=resets_at_seven).taken), 4)


class Bypass(unittest.TestCase):
    """Spellings of a merge or an Xcode Cloud run that the hook has to stop."""

    def decide(self, command, app=True, runs=9):
        return decide(command, app=app, runs=runs)

    def test_a_merge_with_the_repo_flag_is_denied(self):
        for command in ["gh pr -R plusplusinc/plusplus merge 7 --squash", "gh -R plusplusinc/plusplus pr merge 7",
                        "gh api repos/plusplusinc/plusplus/pulls/7/merge -X PUT"]:
            self.assertIsNotNone(self.decide(command, app=False), command)

    def test_a_push_past_the_limit_is_denied_however_it_is_spelled(self):
        for command in ["git -c push.default=current push", "FOO=1 git push", "bash -c 'git push'",
                        "asc xcode-cloud run --workflow-id x"]:
            self.assertIsNotNone(self.decide(command), command)

    def test_every_merge_spelling_is_denied_whatever_the_budget(self):
        for command in ["gh api -X PUT repos/o/r/pulls/7/merge", "gh api --method PUT /repos/o/r/pulls/7/merge",
                        "gh api repos/o/r/merges -f base=main -f head=x",
                        "gh api graphql -f query='mutation { mergePullRequest(input: {}) { clientMutationId } }'",
                        "gh api graphql -F query=@merge.graphql", "gh api graphql --input q.json",
                        "/opt/homebrew/bin/gh pr merge 7", "echo 7 | xargs gh pr merge", "eval gh pr merge 7",
                        'sh -c "gh pr merge 7 --auto"', 'git commit -m "$(gh pr merge 7)"', "cd x && `gh pr merge 7`",
                        "gh alias set m 'pr merge'", "git push --no-verify", "git -c core.hooksPath=/dev/null push",
                        "env -u GIT_CONFIG_COUNT git push", "GIT_CONFIG_COUNT=0 git push"]:
            self.assertIsNotNone(self.decide(command, app=False, runs=0), command)

    def test_every_push_spelling_past_the_limit_is_denied(self):
        for command in ["env git push", "env FOO=1 git push", "/usr/bin/git push", "command git push", "time git push",
                        "git --no-pager push", "git --git-dir .git push", "bash -lc 'cd /w && git push'",
                        "nohup git push 2>&1 | tail -1", "git push 'unbalanced", "gh -R o/r pr create --title t",
                        "gh api repos/o/r/pulls -f head=x -f base=main", "gh api -X PATCH repos/o/r/git/refs/heads/x"]:
            self.assertIn("Xcode Cloud run", self.decide(command) or "", command)
            self.assertIsNone(self.decide(command, runs=3), command)

    def test_an_xcode_cloud_change_is_denied_and_a_read_allowed(self):
        for command in ["asc --profile p xcode-cloud run --workflow-id x", "asc xcode-cloud workflows update --id x",
                        "asc xcode-cloud workflows delete --id x", "asc xcode-cloud products delete --id x"]:
            self.assertIsNotNone(self.decide(command, app=False), command)
        for command in ["asc xcode-cloud build-runs list --workflow-id x", "asc xcode-cloud status --run-id 1 --wait",
                        "asc xcode-cloud doctor --run-id 1", "asc xcode-cloud artifacts download --id 1"]:
            self.assertIsNone(self.decide(command, app=False), command)

    def test_text_about_a_merge_is_no_merge(self):
        body = "gh pr create --title 'Close the merge gate' --body-file - <<'BODY'\nIt denies gh pr merge 7.\nBODY"
        for command in [body, 'git commit -m "Deny gh pr merge"', "gh pr view 7 --json mergeStateStatus",
                        "grep -n 'gh pr merge' scripts/x.py", "git merge origin/main",
                        "gh api graphql -f query='{ viewer { login } }'", "gh api repos/o/r/pulls/7"]:
            self.assertIsNone(self.decide(command, app=False), command)

    def test_the_budget_is_read_only_for_a_call_that_may_start_a_run(self):
        calls = []
        nightly.hook_decision("Bash", "scripts/build.sh && git commit -m push && gh api repos/o/r/pulls",
                              NIGHT, STOP, "h", calls.append)
        self.assertEqual(calls, [])


class HookFailsClosed(unittest.TestCase):
    """The hook as Claude Code runs it: any error exits 2, which denies the call."""

    def hook(self, folder, stdin, worktree=None):
        script = Path(__file__).with_name("nightly-tooling.py")
        return subprocess.run([sys.executable, str(script), "hook", str(folder), str(worktree or folder)],
                              input=stdin, capture_output=True, text=True)

    def test_no_state_denies(self):
        with tempfile.TemporaryDirectory() as folder:
            result = self.hook(folder, json.dumps({"tool_name": "Bash", "tool_input": {"command": "git push"}}))
            self.assertEqual(result.returncode, 2)
            self.assertIn("hook failed", result.stderr)

    def test_unreadable_input_denies(self):
        with tempfile.TemporaryDirectory() as folder:
            Path(folder, "state.json").write_text(json.dumps({"start": NIGHT.isoformat(), "stop": STOP.isoformat(),
                                                              "hours": 1, "handoff": "h"}))
            for stdin in ["", "not json", "[]", json.dumps({"tool_input": {"command": "ls"}})]:
                self.assertEqual(self.hook(folder, stdin).returncode, 2, stdin)

    def test_a_failed_budget_read_denies_the_push(self):
        with tempfile.TemporaryDirectory() as folder:
            # No such worktree, so reading what the branch changes fails.
            Path(folder, "state.json").write_text(json.dumps({"start": NIGHT.isoformat(), "hours": 1, "handoff": "h",
                                                              "stop": (datetime.now() + timedelta(hours=1)).astimezone().isoformat()}))
            push = json.dumps({"tool_name": "Bash", "tool_input": {"command": "git push"}})
            self.assertEqual(self.hook(folder, push, worktree=Path(folder, "gone")).returncode, 2)
            ls = json.dumps({"tool_name": "Bash", "tool_input": {"command": "ls"}})
            self.assertEqual(self.hook(folder, ls).returncode, 0)


class PrePush(unittest.TestCase):
    """The pre-push hook a card's git runs, whatever started the push."""

    def setUp(self):
        self.root = Path(os.path.realpath(tempfile.mkdtemp()))
        self.addCleanup(shutil.rmtree, self.root, True)
        git = lambda *a: subprocess.run(["git", *a], cwd=self.root / "w", check=True, capture_output=True)  # noqa: E731
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(self.root / "origin.git")], check=True)
        subprocess.run(["git", "clone", "-q", str(self.root / "origin.git"), str(self.root / "w")], check=True,
                       capture_output=True)
        git("-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "base")
        git("push", "-q", "origin", "main")
        git("checkout", "-q", "-b", "card")
        self.git = git
        self.night = nightly.Night(self.root / "night", NIGHT, False)
        self.night.dir.mkdir()
        (self.night.dir / "state.json").write_text(json.dumps({"start": NIGHT.isoformat(), "hours": 1}))

    def push_from_python(self, name):
        Path(self.root / "w" / name).parent.mkdir(parents=True, exist_ok=True)
        Path(self.root / "w" / name).write_text("x\n")
        self.git("add", "-A")
        self.git("-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-qm", "card")
        # A push the PreToolUse hook can't see in the command line.
        return subprocess.run([sys.executable, "-c", "import subprocess, sys; sys.exit(subprocess.run("
                               "['git', 'push', '-q', 'origin', 'card']).returncode)"],
                              cwd=self.root / "w", env=self.night.git_env(), capture_output=True, text=True)

    def test_a_docs_push_goes(self):
        result = self.push_from_python("docs/x.md")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_failure_refuses_the_push(self):
        (self.night.dir / "state.json").unlink()
        result = self.push_from_python("App/X.swift")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pre-push hook failed", result.stderr)


class Malformed(unittest.TestCase):
    """Events and log lines the runner reads but didn't write: none of them may crash it."""

    def test_an_unreadable_window_stops_the_night(self):
        broken = [{"utilization": 0.1, "status": "allowed"}, {"utilization": "0.1", "resetsAt": at(9), "status": "allowed"},
                  {"utilization": 0.1, "resetsAt": None}, "full", None, {"utilization": True, "resetsAt": at(9)}]
        for w in broken:
            decision, why = nightly.usage_gate(info(seven_day=w), NIGHT, CUTOFF, STOP, False)
            self.assertEqual(decision, "stop", w)
            self.assertIn("seven_day", why)
            self.assertFalse(nightly.is_uncapped(info(week_resets=1, seven_day=w), STOP), w)
            self.assertIn("seven_day unreadable", nightly.usage_line(info(seven_day=w)))

    def test_info_that_isnt_an_object_reads_as_no_event(self):
        for value in ["allowed", 3, [1], {"unifiedWindows": "x"}, {"unifiedWindows": [1]}]:
            self.assertEqual(nightly.usage_gate(value, NIGHT, CUTOFF, STOP, False)[0], "stop", value)
            self.assertFalse(nightly.is_uncapped(value, STOP))
            self.assertEqual(nightly.usage_line(value), "unknown")

    def test_lines_that_are_json_but_not_events_are_skipped(self):
        lines = ["[1, 2]", '"stderr text"', "3", "null", json.dumps({"type": "result", "result": "PR #9"}), "not json"]
        self.assertFalse(nightly.limit_hit(lines))
        self.assertEqual(nightly.last_reply(lines), "PR #9")
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder, "x.jsonl")
            log.write_text('["rate_limit_event"]\n' + json.dumps({"type": "rate_limit_event", "rate_limit_info": "x"}))
            self.assertEqual(nightly.last_rate_limit([log]), "x")

    def test_the_digest_of_a_night_without_one_never_shows_an_earlier_one(self):
        with tempfile.TemporaryDirectory() as root:
            saved = nightly.ROOT
            self.addCleanup(setattr, nightly, "ROOT", saved)
            nightly.ROOT = Path(root)
            for night in ("2026-10-27", "2026-10-28"):
                Path(root, ".build/retro", night).mkdir(parents=True)
            Path(root, ".build/retro/2026-10-27/digest.md").write_text("old digest\n")
            out = io_of(lambda: nightly.main(["digest"]))
            self.assertIn("No tooling digest for 2026-10-28", out)
            self.assertNotIn("old digest", out)


def io_of(call):
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        call()
    return buffer.getvalue()


class TidySlices(unittest.TestCase):
    """scripts/tidy.sh's .slices/ cleanup, run whole in a scratch clone with gh and the board faked."""

    ROWS = "PVTI_done  Done\t-\tA\nPVTI_todo  In Progress\t-\tB\n"

    def tidy(self, slices, rows=ROWS, board_fails=False):
        root = Path(os.path.realpath(tempfile.mkdtemp()))
        self.addCleanup(shutil.rmtree, root, True)
        run = lambda *a, cwd=root / "main": subprocess.run(a, cwd=cwd, check=True, capture_output=True, text=True)
        run("git", "init", "-q", "--bare", "-b", "main", str(root / "origin.git"), cwd=root)
        run("git", "clone", "-q", str(root / "origin.git"), "main", cwd=root)
        (root / "main/scripts").mkdir()
        for name in ("tidy.sh", "common.sh"):
            shutil.copy(Path(__file__).with_name(name), root / "main/scripts" / name)
        board = root / "main/scripts/board.sh"
        board.write_text("#!/bin/bash\n" + ("echo 'quota spent' >&2; exit 1\n" if board_fails
                                             else f"[ \"$1\" = list ] && printf '{rows}'\n"))
        board.chmod(0o755)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        (bin_dir / "gh").write_text("#!/bin/bash\nexit 0\n")
        (bin_dir / "gh").chmod(0o755)
        run("git", "-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "base")
        run("git", "push", "-q", "origin", "main")
        run("git", "worktree", "add", "-q", "-b", "live-card", str(root / "main/.claude/worktrees/live-card"))
        for name, text in slices.items():
            path = root / "main/.slices" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"}
        out = subprocess.run([str(root / "main/scripts/tidy.sh")], cwd=root / "main", env=env,
                             capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)
        left = sorted(str(p.relative_to(root / "main/.slices")) for p in (root / "main/.slices").rglob("*") if p.is_file())
        return left, out.stdout

    def test_only_entries_whose_cards_are_all_done_go(self):
        left, out = self.tidy({"done-plan.md": "Card PVTI_done.", "mixed.md": "PVTI_done, then PVTI_todo",
                               "live-card-plan.md": "Cites PVTI_done only.", "notes.md": "no card",
                               "old/run.json": "PVTI_done", "gone.md": "PVTI_gone"})
        self.assertEqual(left, ["gone.md", "live-card-plan.md", "mixed.md", "notes.md"])
        self.assertIn("kept", out)
        self.assertIn("PVTI_gone, which the board doesn't have", out)

    def test_a_folder_naming_one_card_goes(self):
        left, _ = self.tidy({"one/a.md": "PVTI_done", "one/b.md": "PVTI_done again"})
        self.assertEqual(left, [])

    def test_a_board_error_keeps_everything_and_says_so(self):
        left, out = self.tidy({"done-plan.md": "PVTI_done"}, board_fails=True)
        self.assertEqual(left, ["done-plan.md"])
        self.assertIn("reading the board failed: quota spent", out)


if __name__ == "__main__":
    unittest.main()
