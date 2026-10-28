#!/usr/bin/env python3
"""The nightly runner's gates against fixtures: no network, no board, no claude.

    python3 scripts/nightly-tooling-test.py
"""
import importlib.util
import json
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

    def test_a_card_that_starts_a_run_waits_past_seventy_hours_or_four_pushes(self):
        self.assertIsNone(nightly.xcode_cloud_gate(69.9, 3, True))
        self.assertIn("70", nightly.xcode_cloud_gate(70.1, 0, True))
        self.assertIn("4 pushes", nightly.xcode_cloud_gate(10, 4, True))
        self.assertIsNone(nightly.xcode_cloud_gate(99, 9, False))


class Paths(unittest.TestCase):
    def test_protected_paths(self):
        hits = ["scripts/pr-check.sh", ".github/workflows/pr-check.yml", ".github/no-code-paths",
                ".claude/settings.json", ".claude/settings.local.json", "Config/Base.xcconfig",
                "PlusPlus.xcodeproj/project.pbxproj", "Packages/Package.swift", "PlusPlus.xctestplan",
                "App/PlusPlus.entitlements", "ci_scripts/ci_post_clone.sh", ".swiftlint.yml",
                "Packages/Tests/.swiftlint.yml", ".swiftformat", "scripts/nightly-tooling.py",
                "scripts/nightly-retro.sh", ".claude/skills/nightly-card/SKILL.md", "scripts/xcresult.py",
                "scripts/tidy.sh", ".claude/hooks/on-edit.sh"]
        safe = ["scripts/ci-times.py", "docs/pr-check.md", "PlusPlusUITests/Waits.swift",
                ".claude/skills/pr/SKILL.md", "Packages/Sources/WorkoutStore/Namer.swift", "Config/README.md"]
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
        self.assertEqual(nightly.verifier_record(comments), ("def5678", []))

    def test_a_failed_criterion_or_a_crash_fails(self):
        _, failures = nightly.verifier_record(["Verifier record, abc1234\n- criterion, new: a\n- crash, new: b\n- No findings"])
        self.assertEqual(len(failures), 2)

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


class Hook(unittest.TestCase):
    def decide(self, tool, command="", now=NIGHT, app_push=False, pushes=0, hours=10):
        return nightly.hook_decision(tool, command, now, STOP, app_push, pushes, hours, ".slices/h.md")

    def test_ordinary_work_is_allowed(self):
        self.assertIsNone(self.decide("Bash", "scripts/build.sh"))
        self.assertIsNone(self.decide("Agent"))
        self.assertIsNone(self.decide("Bash", "git push -u origin night-x", app_push=True, pushes=3))
        self.assertIsNone(self.decide("Bash", "git push -u origin night-x", app_push=False, pushes=9, hours=99))

    def test_only_a_git_push_command_counts_as_a_push(self):
        for command in ["git push", "git -C /w push -u origin x", "cd /w && git push", "make; git push origin x"]:
            self.assertIsNotNone(nightly.PUSH.search(command), command)
        for command in ['git commit -m "Retry the push on 429"', "git stash push", "echo git push"]:
            self.assertIsNone(nightly.PUSH.search(command), command)
        late = STOP + timedelta(minutes=1)
        self.assertIsNone(self.decide("Bash", 'git commit -m "push later"', now=late))

    def test_never_merge(self):
        self.assertIn("Never merge", self.decide("Bash", "gh pr merge 12 --squash"))
        self.assertIn("Never merge", self.decide("Bash", "cd x && gh  pr merge --auto"))

    def test_the_fifth_app_push_or_past_seventy_hours_is_denied(self):
        self.assertIn("Xcode Cloud", self.decide("Bash", "git -C /w push", app_push=True, pushes=4))
        self.assertIn("Xcode Cloud", self.decide("Bash", "git push", app_push=True, hours=70.5))

    def test_from_seven_only_the_handoff(self):
        late = STOP + timedelta(minutes=1)
        self.assertIn(".slices/h.md", self.decide("Agent", now=late))
        self.assertIn("past 7", self.decide("Bash", "scripts/build.sh", now=late))
        self.assertIn("past 7", self.decide("Bash", "git push", now=late))
        self.assertIsNone(self.decide("Bash", "cd /w && git add -A && git commit -m handoff", now=late))
        self.assertIsNone(self.decide("Write", now=late))


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


class Loop(unittest.TestCase):
    """Night.run's card count, with the board, the PRs, and each card's run stubbed."""

    BODY = "## Problem\nx\n\nNightly: faster CI; its time\n\n## Success\nRun it.\n"

    def night(self, results, weekly_resets):
        cards = [(f"PVTI_{i}", "Todo", "-", f"card {i}", self.BODY) for i in range(4)]
        stubs = {"board_cards": lambda: cards, "xcode_cloud_runs": lambda: [], "gh_json": lambda *a: [],
                 "classify": lambda files: "app: x", "sh": lambda *a, **k: "", "test_counts": lambda rev: {}}
        saved = {name: getattr(nightly, name) for name in stubs}
        self.addCleanup(lambda: [setattr(nightly, n, f) for n, f in saved.items()])
        for name, stub in stubs.items():
            setattr(nightly, name, stub)
        folder = Path(tempfile.mkdtemp())
        event = info(week_resets=weekly_resets)
        (folder / "retro.jsonl").write_text(json.dumps({"type": "rate_limit_event", "rate_limit_info": event}) + "\n")
        night = nightly.Night(folder, NIGHT, False)
        night.clock, night.finish = (lambda: NIGHT), (lambda: None)
        taken = []

        def take(card, _):
            taken.append(card[1])
            night.tried.add(card[0])
            return results[len(taken) - 1]

        night.take = take
        night.run()
        return taken

    def test_four_eligible_cards_on_a_capped_night_three_run(self):
        self.assertEqual(self.night(["merged"] * 4, weekly_resets=100), ["card 0", "card 1", "card 2"])

    def test_after_a_failed_card_the_next_runs(self):
        self.assertEqual(self.night(["parked", "merged", "merged", "merged"], weekly_resets=100),
                         ["card 0", "card 1", "card 2"])

    def test_the_uncapped_night_takes_the_fourth(self):
        resets_at_seven = (STOP - NIGHT).total_seconds() / 3600
        self.assertEqual(len(self.night(["merged"] * 4, weekly_resets=resets_at_seven)), 4)


class Bypass(unittest.TestCase):
    """Spellings of a merge or an Xcode Cloud run that the hook has to stop. These fail today."""

    def decide(self, command, app_push=True, pushes=9):
        return nightly.hook_decision("Bash", command, NIGHT, STOP, app_push, pushes, 10, ".slices/h.md")

    def test_a_merge_with_the_repo_flag_is_denied(self):
        for command in ["gh pr -R plusplusinc/plusplus merge 7 --squash", "gh -R plusplusinc/plusplus pr merge 7",
                        "gh api repos/plusplusinc/plusplus/pulls/7/merge -X PUT"]:
            self.assertIsNotNone(self.decide(command, app_push=False), command)

    def test_a_push_past_the_limit_is_denied_however_it_is_spelled(self):
        for command in ["git -c push.default=current push", "FOO=1 git push", "bash -c 'git push'",
                        "asc xcode-cloud run --workflow-id x"]:
            self.assertIsNotNone(self.decide(command), command)


if __name__ == "__main__":
    unittest.main()
