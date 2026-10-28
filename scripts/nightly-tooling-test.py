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
                "scripts/nightly-retro.sh", ".claude/skills/nightly-card/SKILL.md"]
        safe = ["scripts/tidy.sh", "docs/pr-check.md", "PlusPlusUITests/Waits.swift",
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


if __name__ == "__main__":
    unittest.main()
