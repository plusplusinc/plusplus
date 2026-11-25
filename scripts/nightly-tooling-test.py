#!/usr/bin/env python3
"""The night's steps and gates against fixtures: no network, no board, no claude.

    python3 scripts/nightly-tooling-test.py
"""
import contextlib
import importlib.util
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent

spec = importlib.util.spec_from_file_location("nightly", Path(__file__).with_name("nightly-tooling.py"))
nightly = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nightly)

NIGHT = datetime(2026, 10, 28, 1, 30).astimezone()  # a Wednesday, 1:30 am local
CUTOFF, STOP = nightly.night_window(NIGHT)
SESSION = "night-session-id"
TO_SEVEN = (STOP - NIGHT).total_seconds() / 3600  # hours from 1:30 am to the 7 am stop


def stub(test, **stubs):
    """Replaces the script's functions for this test only."""
    saved = {name: getattr(nightly, name) for name in stubs}
    test.addCleanup(lambda: [setattr(nightly, n, f) for n, f in saved.items()])
    for name, value in stubs.items():
        setattr(nightly, name, value)


def write_usage(folder, *windows, age=timedelta(minutes=1)):
    """usage.json as the app's usage tool writes it: (label, percent used, hours after 1:30 am to
    its reset) each, written `age` before 1:30 am."""
    resets = [(NIGHT + timedelta(hours=h)).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.066Z")
              for _, _, h in windows]
    (Path(folder) / "usage.json").write_text(json.dumps({"plan": {"windows": [
        {"label": label, "percentUsed": used, "resetsAt": reset} for (label, used, _), reset in zip(windows, resets)]}}))
    stamp = (NIGHT - age).timestamp()
    os.utime(Path(folder) / "usage.json", (stamp, stamp))


def night_folder(test, seen=True):
    """A night `begin` started at 1:30 am in <root>/main/.build/retro/2026-10-28, where the guard has
    seen the session's own calls and usage is low and fresh."""
    root = Path(os.path.realpath(tempfile.mkdtemp()))
    test.addCleanup(shutil.rmtree, root, True)
    night = nightly.Night(root / "main/.build/retro/2026-10-28")
    night.write("state.json", {"start": NIGHT.isoformat(), "phase": None})
    (night.dir / "session").write_text(SESSION + "\n")
    if seen:
        (night.dir / "guard-seen").write_text("none\tlead\n")
    write_usage(night.dir, ("Weekly · all models", 40, 100))
    return night


def open_card(night, item="PVTI_1", branch="night-card", worktree="/w", stop=STOP):
    """A card as `next` leaves it: its entry, and its phase open."""
    night.write("cards.json", night.cards() + [{"item": item, "title": "Card", "branch": branch, "worktree": str(worktree),
                                                "usage": "Usage: Weekly 40%", "decision": "open"}])
    night.set_state(hours=1.0, phase={"kind": "card", "item": item, "title": "Card", "worktree": str(worktree),
                                      "branch": branch, "handoff": str(night.dir / "h.md"), "stop": stop.isoformat()})


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


class UsageGate(unittest.TestCase):
    """The usage `next` reads from the night's usage.json, as the app's usage tool lists it."""

    def gate(self, *windows, taken=0, age=timedelta(minutes=1)):
        folder = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, folder, True)
        write_usage(folder, *windows)
        return nightly.usage_gate(nightly.plan_windows(folder), age, NIGHT, STOP, taken)

    def test_low_usage_goes(self):
        self.assertIsNone(self.gate(("Weekly · all models", 40, 100), ("Weekly · Fable", 30, 100)))

    def test_usage_older_than_fifteen_minutes_or_unreadable_starts_no_card(self):
        self.assertIn("over 15 minutes old", self.gate(("Weekly", 10, 100), age=timedelta(minutes=16)))
        self.assertIn("over 15 minutes old", self.gate(("Weekly", 10, 100), age=None))
        self.assertIsNone(self.gate(("Weekly", 10, 100), age=timedelta(minutes=14)))
        for rows in ("usage.json is missing", "usage.json lists no windows"):
            self.assertEqual(nightly.usage_gate(rows, timedelta(0), NIGHT, STOP, 0), f"usage is unknown: {rows}")
        unreadable = [("Weekly", 10.0, None), ("Weekly", 10.0, "soon")]
        for row in unreadable:
            self.assertIn("has no reset time", nightly.usage_gate([row], timedelta(0), NIGHT, STOP, 0), row)

    def test_any_window_at_ninety_percent_starts_no_card(self):
        self.assertIn("Weekly · Fable at 90%", self.gate(("Weekly · all models", 40, 100), ("Weekly · Fable", 90, 100)))
        self.assertIn("Current session at 95%", self.gate(("Current session", 95, 2), ("Weekly", 10, 100)))
        self.assertIsNone(self.gate(("Weekly · Fable", 89, 100)))

    def test_a_window_whose_reset_passed_counts_as_fresh(self):
        self.assertIsNone(self.gate(("Current session", 99, -0.5), ("Weekly", 10, 100)))

    def test_three_cards_on_a_capped_night_and_a_fourth_only_when_every_weekly_window_resets_by_seven(self):
        capped = [("Weekly · all models", 40, 100), ("Weekly · Fable", 40, TO_SEVEN)]
        self.assertEqual([self.gate(*capped, taken=n) is None for n in range(5)], [True, True, True, False, False])
        uncapped = [("Weekly · all models", 40, TO_SEVEN), ("Weekly · Fable", 40, 1)]
        self.assertIsNone(self.gate(*uncapped, taken=10))
        self.assertIsNotNone(self.gate(("Weekly", 40, TO_SEVEN + 0.1), taken=3))
        # A weekly reset already past is a new week, not an uncapped night.
        self.assertIsNotNone(self.gate(("Weekly", 40, -0.5), taken=3))
        # No weekly window at all is no uncapped night either.
        self.assertIsNotNone(self.gate(("Current session", 10, 2), taken=3))

    def test_the_uncapped_night_keeps_a_morning_reserve(self):
        # A session window resetting at 8:30 am, after the 7 am stop, at 60% used.
        weekly = ("Weekly", 40, TO_SEVEN)
        self.assertIn("keeping 50% of it for the morning", self.gate(weekly, ("Current session", 60, 7)))
        self.assertIsNone(self.gate(("Weekly", 40, 100), ("Current session", 60, 7)))
        self.assertIsNone(self.gate(weekly, ("Current session", 40, 7)))
        self.assertIsNone(self.gate(weekly, ("Current session", 60, 3)))


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

    def test_a_push_that_starts_a_run_waits_past_seventy_hours_or_four_runs(self):
        self.assertIsNone(nightly.xcode_cloud_gate(69.9, 3))
        self.assertIn("70", nightly.xcode_cloud_gate(70.1, 0))
        self.assertIn("4 Xcode Cloud runs", nightly.xcode_cloud_gate(10, 4))

    def test_an_app_card_needs_room_for_two_runs(self):
        gate = lambda hours, runs: nightly.xcode_cloud_gate(hours, runs, nightly.EXPECTED_RUNS)  # noqa: E731
        self.assertIsNone(gate(69.9, 2))
        self.assertEqual(gate(10, 3), "3 Xcode Cloud runs tonight, and a card that may change "
                                      "the app needs room for 2 of the night's 4")
        self.assertIn("70", gate(70.1, 0))


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
                "PlusPlus.xcodeproj/xcshareddata/xcschemes/PlusPlus.xcscheme", "scripts/lint.sh", "scripts/lint-tools.sh",
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


class OpenPRs(unittest.TestCase):
    """A card waits for an open PR changing a file it names, unless that is a retro PR's Markdown."""

    REPO = "CLAUDE.md\n.claude/rules/testing.md\nscripts/nightly-tooling.py\nPackages/Sources/App/Row.swift\ndocs/pr-check.md\n"
    BODY = "## Problem\nx\n\nNightly: faster CI; its time\n\n## Success\nRun it.\n\n## Plan\n- Edit `{}`.\n"

    def choose(self, prs, names):
        cards = [(f"PVTI_{i}", "Definitely", "-", f"card {i}", self.BODY.format(name)) for i, name in enumerate(names)]
        stub(self, board_rows=lambda: [], board_cards=lambda rows: cards, xcode_cloud_runs=lambda: [],
             gh_json=lambda *a: prs if a[-1] == "number,files,title" else self.fail(a), classify=lambda files: "docs",
             sh=lambda *a, **k: self.REPO)
        card, _, held = nightly.choose(night_folder(self), NIGHT, set())
        return card, held

    @staticmethod
    def pr(n, title, *files):
        return {"number": n, "title": title, "files": [{"path": f} for f in files]}

    def test_a_retro_prs_markdown_holds_no_card_back(self):
        retro = self.pr(161, "Retro of #150: x", ".claude/rules/testing.md", "docs/pr-check.md")
        card, held = self.choose([retro], [".claude/rules/testing.md"])
        self.assertEqual(card[1], "card 0")
        self.assertEqual(held, [])

    def test_a_script_or_swift_file_still_holds_a_card_back(self):
        retro = self.pr(161, "Retro of #150: x", ".claude/rules/testing.md", "scripts/nightly-tooling.py")
        slice_ = self.pr(164, "Keep the +1 out", "Packages/Sources/App/Row.swift")
        card, held = self.choose([retro, slice_], ["scripts/nightly-tooling.py", "Packages/Sources/App/Row.swift"])
        self.assertIsNone(card)
        self.assertEqual(held[0], '"card 0" may touch what #161 (scripts/nightly-tooling.py) changes; '
                                  "merge or close #161 so a night can take it")
        self.assertIn("#164 (Packages/Sources/App/Row.swift)", held[1])

    def test_markdown_outside_the_rules_or_in_another_pr_still_holds_a_card_back(self):
        card, held = self.choose([self.pr(161, "Retro of #150: x", "CLAUDE.md"),
                                  self.pr(158, "Prune the agent docs", ".claude/rules/testing.md")],
                                 ["CLAUDE.md", ".claude/rules/testing.md"])
        self.assertIsNone(card)
        self.assertIn("#161 (CLAUDE.md)", held[0])
        self.assertIn("#158", held[1])


class NightDigest(unittest.TestCase):
    """The night skill's usage gate, its outcome, and the digest whose first line says which."""

    def setUp(self):
        self.night = Path(tempfile.mkdtemp()) / "2026-11-26"
        self.night.mkdir()
        self.addCleanup(shutil.rmtree, self.night.parent, True)

    def usage(self, *windows):
        (self.night / "usage.json").write_text(json.dumps({"plan": {"windows": [
            {"label": label, "percentUsed": used, "resetsAt": "2026-11-28T09:00:00Z"} for label, used in windows]}}))

    def main(self, *args):
        """main's output and exit status."""
        status = []

        def call():
            try:
                nightly.main([args[0], str(self.night), *args[1:]])
            except SystemExit as exit_:
                status.append(exit_.code)
        return io_of(call), (status or [0])[0]

    def digest(self):
        return io_of(lambda: nightly.main(["digest", str(self.night)])).splitlines()

    def test_a_night_that_ran_says_so_first(self):
        self.usage(("Current session", 12), ("Weekly", 40))
        self.assertEqual(self.main("outcome", "ran")[0], "Night 2026-11-26: ran\n")
        self.assertEqual(self.digest(), ["Night 2026-11-26: ran", "Usage: Current session 12%, Weekly 40%"])
        self.assertEqual((self.night / "digest.md").read_text().splitlines(), self.digest())

    def test_a_night_whose_retro_failed_says_why_first(self):
        self.usage(("Weekly", 40))
        (self.night / "main-checkout.txt").write_text("Main checkout not brought up to date: x\n")
        self.main("outcome", "failed", "retro", "the retro skill isn't there")
        self.assertEqual(self.digest(), ["Night 2026-11-26: failed: retro, the retro skill isn't there",
                                         "Not checked: Main checkout not brought up to date: x", "Usage: Weekly 40%"])

    def test_a_night_with_no_outcome_says_it_is_running_or_stopped_early(self):
        self.assertEqual(self.digest(), ["Night 2026-11-26: no outcome recorded: still running, or it stopped early",
                                         "Not checked: usage, usage.json is missing"])

    def test_an_outcome_needs_ran_or_a_step_and_why(self):
        for args in (["failed", "retro"], ["fine"], ["ran", "x"]):
            with self.subTest(args=args), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(self.main("outcome", *args)[1], 64)
        self.assertFalse((self.night / "outcome.txt").exists())

    def test_usage_saved_in_the_sessions_own_folder_is_copied_into_the_nights(self):
        self.usage(("Weekly", 40))
        saved = self.night.parent / "saved-usage.json"
        (self.night / "usage.json").rename(saved)
        self.assertEqual(self.main("usage", str(saved)), ("Usage: Weekly 40%\n", 0))
        self.assertEqual((self.night / "usage.json").read_bytes(), saved.read_bytes())

    def test_a_weekly_window_at_97_percent_stops_the_night(self):
        self.usage(("Current session", 99), ("Weekly (all models)", 96.5))
        self.assertEqual(self.main("usage"), ("Usage: Current session 99%, Weekly (all models) 96.5%\n", 0))
        self.usage(("Current session", 10), ("Weekly (all models)", 97))
        self.assertEqual(self.main("usage")[1], 1)
        go_on, line = nightly.usage_check(self.night)
        self.assertFalse(go_on)
        self.assertEqual(line, "Weekly (all models) at 97%, resetting 2026-11-28T09:00:00Z")

    def test_the_usage_tools_own_output_reads(self):
        # mcp__ccd_session_mgmt__get_usage's reply on 2026-11-25, its context part left out.
        (self.night / "usage.json").write_text(json.dumps({"plan": {"status": "ok", "plan": "Ultra", "windows": [
            {"label": "Weekly · all models", "percentUsed": 97, "resetsAt": "2026-11-25T11:00:00.066Z", "resetsIn": "5h 36m"},
            {"label": "Weekly · Fable", "percentUsed": 92, "resetsAt": "2026-11-25T11:00:00.066Z", "resetsIn": "5h 36m"}],
            "extraUsage": {"enabled": False, "currency": "USD"}}}))
        self.assertEqual(nightly.usage_check(self.night),
                         (False, "Weekly · all models at 97%, resetting 2026-11-25T11:00:00.066Z"))
        self.assertEqual(self.digest()[-1], "Usage: Weekly · all models 97%, Weekly · Fable 92%")

    def test_unreadable_usage_goes_on_and_the_digest_says_so(self):
        for text in ("not json", '{"plan": {}}', '{"plan": {"windows": [{"label": "Weekly"}]}}'):
            with self.subTest(text=text):
                (self.night / "usage.json").write_text(text)
                go_on, line = nightly.usage_check(self.night)
                self.assertTrue(go_on)
                self.assertTrue(line.startswith("Usage unreadable: usage.json isn't the usage tool's plan.windows"), line)
                self.assertTrue(self.digest()[-1].startswith("Not checked: usage, "))

    def begin(self, session):
        return nightly.begin(nightly.Night(self.night), NIGHT, session)

    def test_begin_records_the_session_and_keeps_an_earlier_start(self):
        self.usage(("Weekly", 40))
        (self.night / "outcome.txt").write_text("failed: retro, x\n")
        self.assertEqual(self.begin("first"), ["Night 2026-11-26: begun"])
        start = nightly.Night(self.night).state()["start"]
        self.assertFalse((self.night / "outcome.txt").exists())
        self.assertFalse((self.night / "usage.json").exists())
        self.begin("second")
        self.assertEqual((self.night / "session").read_text(), "second\n")
        self.assertEqual(nightly.Night(self.night).state(), {"start": start, "phase": None})

    def test_begin_without_a_session_id_records_none_and_says_no_card_will_start(self):
        self.begin("earlier")
        self.assertEqual(self.begin(None), ["Night 2026-11-26: begun", "No session id: no card will start tonight."])
        self.assertFalse((self.night / "session").exists())
        night = nightly.Night(self.night)
        (night.dir / "guard-seen").write_text("none\tlead\n")
        self.assertIn("no session id was recorded", nightly.refusal(night, NIGHT, None))

    def test_begin_parks_a_card_a_dead_session_left_open(self):
        calls = []
        stub(self, disarm=lambda night: calls.append("disarm"), board=lambda *a, stdin=None: calls.append((a, stdin)))
        night = nightly.Night(self.night)
        night.write("state.json", {"start": NIGHT.isoformat()})
        open_card(night)
        self.assertIn('Parked "Card" of 2026-11-26: the night\'s session ended before deciding on it.',
                      self.begin("next"))
        self.assertIsNone(night.state()["phase"])
        self.assertEqual(night.entry("PVTI_1")["decision"], "parked")
        self.assertEqual(calls[0], "disarm")
        self.assertEqual(calls[1][0], ("state", "PVTI_1"))
        self.assertIn("still In Progress", calls[1][1])
        self.assertIn("Parked: Card: the night's session ended before deciding on it", "\n".join(self.digest()))

    def test_begin_parks_a_card_the_night_before_left_open(self):
        calls = []
        stub(self, disarm=lambda night: calls.append(night.dir.name), board=lambda *a, stdin=None: calls.append(a))
        before = nightly.Night(self.night.parent / "2026-11-25")
        before.write("state.json", {"start": NIGHT.isoformat()})
        open_card(before)
        line = 'Parked "Card" of 2026-11-25: the night\'s session ended before deciding on it.'
        self.assertIn(line, self.begin("tonight"))
        self.assertEqual((before.entry("PVTI_1")["decision"], before.state()["phase"]), ("parked", None))
        self.assertEqual(calls, ["2026-11-25", ("state", "PVTI_1")])
        self.assertIn(line, self.digest())
        self.assertNotIn(line, self.begin("again"))

    def night_of_three(self):
        """A night whose first card merged, second parked, and third waits for the maintainer."""
        night = nightly.Night(self.night)
        night.write("state.json", {"start": NIGHT.isoformat(), "night_read": True, "tests_before": {"T": 3},
                                   "phase": None})
        night.write("cards.json", [
            {"item": "PVTI_1", "title": "Lint the UI tests", "branch": "night-a", "decision": "merged", "pr": 120,
             "pr_title": "Lint the UI tests", "merge": "0123456789abcdef", "files": [".swiftlint.yml", "PlusPlusUITests/A.swift"],
             "proof": "verifier record at abc1234, PR check passed", "usage": "Usage: Weekly 40%", "armed_at": NIGHT.isoformat()},
            {"item": "PVTI_2", "title": "Speed up CI", "branch": "night-b", "decision": "parked", "pr": 121,
             "why": "no verifier record on the PR", "where": "PR #121 is a draft with auto-merge off", "usage": "Usage: Weekly 45%"},
            {"item": "PVTI_3", "title": "Tidy the docs", "branch": "night-c", "decision": "waiting", "pr": 122,
             "pr_title": "Tidy the docs", "why": "it changes only .claude/ and docs/, which waits for the day",
             "usage": "Usage: Weekly 50%"}])
        night.write("notes.json", {"closing": {"runs": 2, "hours": 12.5, "tests": {"T": 4}, "behind": []},
                                   "ended": "3 cards tonight, the limit on a night the weekly limit doesn't reset"})
        return night

    def test_a_merged_a_parked_and_a_waiting_card_each_get_their_line(self):
        self.usage(("Weekly", 40))
        self.night_of_three()
        # The closing reads: two runs tonight, 12.5 hours this month, main's tests, no PR behind.
        stub(self, xcode_cloud_runs=lambda *a, **k: [], runs_tonight=lambda *a: 2, month_hours=lambda *a: 12.5,
             sh=lambda *a, **k: "", test_counts=lambda rev: {"T": 4}, gh_json=lambda *a: [])
        self.assertEqual(self.digest()[1:], [
            "Usage: Weekly 40%",
            "Nightly tooling 2026-11-26: 1 merged, 1 parked, 1 waiting for the maintainer",
            "#120 Lint the UI tests — 0123456 — .swiftlint.yml, PlusPlusUITests — verifier record at abc1234, "
            "PR check passed — undo: git revert 0123456",
            "Xcode Cloud: 2 runs tonight, 12.5 h this month", "Tests: T 3 → 4",
            "Parked: Speed up CI: no verifier record on the PR (PR #121 is a draft with auto-merge off)",
            "Waiting: #122 Tidy the docs: it changes only .claude/ and docs/, which waits for the day",
            "Usage: Lint the UI tests: at its start, Weekly 40%", "Usage: Speed up CI: at its start, Weekly 45%",
            "Usage: Tidy the docs: at its start, Weekly 50%",
            "Ended: 3 cards tonight, the limit on a night the weekly limit doesn't reset"])

    def test_a_night_with_no_card_says_why(self):
        self.usage(("Weekly", 40))
        night = nightly.Night(self.night)
        night.write("state.json", {"start": NIGHT.isoformat(), "phase": None})
        night.note("ended", "cards start only from midnight to 5 am.")
        self.assertEqual(self.digest(), ["Night 2026-11-26: no outcome recorded: still running, or it stopped early",
                                         "Usage: Weekly 40%", "No card started: cards start only from midnight to 5 am."])

    def test_the_bare_digest_reads_files_only_and_writes_none(self):
        self.usage(("Weekly", 40))
        self.night_of_three()
        (self.night / "digest.md").write_text("the night's own\n")
        main = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, main, True)
        stub(self, main_checkout=lambda: main, sh=lambda *a, **k: self.fail(a),
             gh_json=lambda *a: self.fail(a), xcode_cloud_runs=lambda *a: self.fail(a))
        (main / ".build/retro").mkdir(parents=True)
        (main / ".build/retro/2026-11-26").symlink_to(self.night)
        out = io_of(lambda: nightly.main(["digest"]))
        self.assertIn("Nightly tooling 2026-11-26: 1 merged", out)
        self.assertEqual((self.night / "digest.md").read_text(), "the night's own\n")

    def test_a_failed_closing_read_is_a_not_checked_line_and_the_digest_is_still_written(self):
        self.usage(("Weekly", 40))
        self.night_of_three()

        def fails(*args, **kwargs):
            raise RuntimeError("gh: HTTP 502")
        stub(self, xcode_cloud_runs=fails, sh=fails, gh_json=fails)
        digest = self.digest()
        self.assertEqual(digest[1:5], ["Not checked: Xcode Cloud's runs (gh: HTTP 502)",
                                       "Not checked: main's test counts (gh: HTTP 502)",
                                       "Not checked: the open PRs behind main (gh: HTTP 502)",
                                       "Not checked: tonight's merges (gh: HTTP 502)"])
        self.assertIn("Nightly tooling 2026-11-26: 1 merged, 1 parked, 1 waiting for the maintainer", digest)
        self.assertEqual((self.night / "digest.md").read_text().splitlines(), digest)


class Uninstall(unittest.TestCase):
    """scripts/nightly-retro.sh uninstall against a fake launchctl and a scratch plist."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, True)
        (self.root / "bin").mkdir()
        fake = self.root / "bin/launchctl"
        fake.write_text('#!/bin/bash\necho "$*" >> "$FAKE_LOG"\n'
                        'case "$1" in print) [ -e "$FAKE_LOADED" ] ;; bootout) rm -f "$FAKE_LOADED" ;; esac\n')
        fake.chmod(0o755)
        self.plist = self.root / "test.nightly.plist"
        self.env = {**os.environ, "PATH": f"{self.root / 'bin'}:{os.environ['PATH']}", "FAKE_LOG": str(self.root / "log"),
                    "FAKE_LOADED": str(self.root / "loaded"), "NIGHTLY_RETRO_LABEL": "test.nightly",
                    "NIGHTLY_RETRO_PLIST": str(self.plist)}

    def uninstall(self):
        out = subprocess.run(["bash", str(SCRIPTS / "nightly-retro.sh"), "uninstall"], env=self.env,
                             capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)
        return out.stdout

    def test_an_installed_agent_is_booted_out_and_its_plist_deleted(self):
        (self.root / "loaded").touch()
        self.plist.write_text("<plist/>\n")
        out = self.uninstall()
        self.assertFalse(self.plist.exists())
        self.assertIn(f"bootout gui/{os.getuid()}/test.nightly", (self.root / "log").read_text())
        self.assertIn("Stopped the launchd agent test.nightly.", out)

    def test_an_agent_already_gone_succeeds(self):
        out = self.uninstall()
        self.assertNotIn("bootout", (self.root / "log").read_text())
        self.assertEqual(out, "The launchd agent test.nightly is gone; the scheduled task in the Claude app runs the night.\n")

    def test_its_usage_names_uninstall_catch_up_and_show_only(self):
        out = subprocess.run(["bash", str(SCRIPTS / "nightly-retro.sh")], capture_output=True, text=True)
        self.assertEqual(out.returncode, 64)
        commands = re.findall(r"nightly-retro\.sh (\S+)", out.stderr)
        self.assertEqual(commands, ["catch-up", "show", "uninstall"])


class CatchUp(unittest.TestCase):
    """scripts/nightly-retro.sh catch-up in a scratch main checkout, one commit behind its origin."""

    def setUp(self):
        self.root = Path(os.path.realpath(tempfile.mkdtemp()))
        self.addCleanup(shutil.rmtree, self.root, True)
        self.night = self.root / "night"
        self.night.mkdir()
        self.git("init", "-q", "-b", "main", cwd=self.root / "origin")
        (self.root / "origin/scripts").mkdir()
        shutil.copy(SCRIPTS / "nightly-retro.sh", self.root / "origin/scripts/nightly-retro.sh")
        (self.root / "origin/README").write_text("base\n")
        self.git("add", "-A", cwd=self.root / "origin")
        self.git("commit", "-q", "-m", "base", cwd=self.root / "origin")
        self.git("clone", "-q", str(self.root / "origin"), str(self.root / "main"), cwd=self.root)
        self.git("commit", "-q", "--allow-empty", "-m", "merged since", cwd=self.root / "origin")

    def git(self, *args, cwd):
        cwd.mkdir(parents=True, exist_ok=True)
        return subprocess.run(["git", "-c", "user.email=t@example.com", "-c", "user.name=t", *args], cwd=cwd,
                              check=True, capture_output=True, text=True).stdout.strip()

    def catch_up(self):
        out = subprocess.run(["bash", str(self.root / "main/scripts/nightly-retro.sh"), "catch-up", str(self.night)],
                             capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)
        return self.git("log", "-1", "--format=%s", cwd=self.root / "main")

    def test_a_clean_main_fast_forwards(self):
        self.assertEqual(self.catch_up(), "merged since")
        self.assertFalse((self.night / "main-checkout.txt").exists())

    def test_a_change_origin_left_alone_stays_through_the_fast_forward(self):
        (self.root / "main/README").write_text("edited\n")
        self.assertEqual(self.catch_up(), "merged since")
        self.assertEqual((self.root / "main/README").read_text(), "edited\n")
        self.assertFalse((self.night / "main-checkout.txt").exists())

    def test_a_change_to_a_file_origin_changed_stays_and_says_why(self):
        (self.root / "origin/README").write_text("theirs\n")
        self.git("commit", "-q", "-am", "changes the README", cwd=self.root / "origin")
        (self.root / "main/README").write_text("edited\n")
        self.assertEqual(self.catch_up(), "base")
        self.assertEqual((self.root / "main/README").read_text(), "edited\n")
        why = "it has uncommitted changes to files origin/main changed"
        self.assertIn(why, (self.night / "main-checkout.txt").read_text())
        self.assertTrue(nightly.checkout_note(self.night)[0].startswith(
            f"Not checked: Main checkout not brought up to date: {why}; the night runs "))

    def test_a_main_with_its_own_commit_stays_and_says_why(self):
        self.git("commit", "-q", "--allow-empty", "-m", "local", cwd=self.root / "main")
        self.assertEqual(self.catch_up(), "local")
        self.assertIn("its main has commits origin/main doesn't", (self.night / "main-checkout.txt").read_text())

    def test_another_branch_stays_and_says_why(self):
        self.git("checkout", "-q", "-b", "side", cwd=self.root / "main")
        self.assertEqual(self.catch_up(), "base")
        self.assertIn("it is on side, not main", (self.night / "main-checkout.txt").read_text())

    def test_no_file_says_nothing(self):
        self.assertEqual(nightly.checkout_note(self.night), [])


class Eligibility(unittest.TestCase):
    BODY = "## Problem\nx\n\nNightly: faster CI; the PR check's time\n\n## Success\nRun it: it passes.\n\n## Plan\n- y\n"

    def test_an_eligible_card(self):
        self.assertIsNone(nightly.eligibility("Definitely", "-", self.BODY))

    def test_product_and_unmarked_cards_wait_for_the_day(self):
        self.assertIn("feature", nightly.eligibility("Definitely", "Routine screen", self.BODY))
        self.assertIn("Nightly", nightly.eligibility("Definitely", "-", self.BODY.replace("Nightly:", "Later:")))
        self.assertIn("Maybe", nightly.eligibility("Maybe", "-", self.BODY))
        self.assertIn("check", nightly.eligibility("Definitely", "-", self.BODY.replace("## Success\nRun it: it passes.\n", "")))


class CloseMerged(unittest.TestCase):
    """An In Progress card a night parked, or left waiting, goes to Done once its PR merges."""

    PARKED = ("## Problem\nx\n\n## State\n- Parked by the nightly run: why. PR #150 is a draft with "
              "auto-merge off.\n- Next: a daytime /onward reads the PR and the handoff in `.slices/`.\n")
    WAITING = "## Problem\nx\n\n## State\n- PR #156 waits for the maintainer, unmerged: why.\n"

    def test_the_state_names_the_pr(self):
        self.assertEqual(nightly.left_pr(self.PARKED), 150)
        self.assertEqual(nightly.left_pr(self.WAITING), 156)
        self.assertIsNone(nightly.left_pr("## Problem\nPR #150 is a draft with auto-merge off.\n"))
        self.assertIsNone(nightly.left_pr("## State\n- Next: plan it.\n"))

    def close(self, states, dry_run=False):
        cards = [("PVTI_1", "In Progress", "-", "parked", self.PARKED),
                 ("PVTI_2", "In Progress", "-", "waiting", self.WAITING),
                 ("PVTI_3", "Definitely", "-", "queued", self.PARKED)]
        calls = []
        stub(self, board_bodies=lambda rows: [c for c in cards if c[:4] in rows],
             gh_json=lambda *a: {"state": states[a[2]]}, board=lambda *a, stdin=None: calls.append(a))
        closed, unchecked = nightly.close_merged([c[:4] for c in cards], dry_run)
        self.assertEqual(unchecked, [])
        return closed, calls

    def test_only_a_merged_prs_card_moves(self):
        closed, calls = self.close({"150": "MERGED", "156": "OPEN"})
        self.assertEqual(calls, [("status", "PVTI_1", "Done")])
        self.assertEqual(closed, ["parked, since #150 merged"])

    def test_a_dry_run_moves_nothing(self):
        self.assertEqual(self.close({"150": "MERGED", "156": "MERGED"}, dry_run=True)[1], [])


class UpdateCards(unittest.TestCase):
    """The card the night adds for a lint tool `scripts/lint-tools.sh outdated` names."""

    OUTDATED = "swiftformat 0.64.4 0.64.5\nswiftlint 0.65.0 0.65.1\n"

    def titles(self, rows):
        return [title for title, _ in nightly.update_cards(self.OUTDATED, rows)]

    def test_each_outdated_tool_gets_an_eligible_card(self):
        cards = nightly.update_cards(self.OUTDATED, [("PVTI_1", "Definitely", "-", "Speed up CI")])
        self.assertEqual([t for t, _ in cards], ["Update swiftformat to 0.64.5", "Update swiftlint to 0.65.1"])
        for _, body in cards:
            self.assertIsNone(nightly.eligibility("Definitely", "-", body))

    def test_a_card_by_its_title_in_any_status_is_never_duplicated(self):
        self.assertEqual(self.titles([("PVTI_1", "Done", "-", "Update swiftformat to 0.64.5"),
                                      ("PVTI_2", "Maybe", "-", "Update swiftlint to 0.65.1")]), [])

    def test_an_open_card_for_an_older_release_holds_its_tool_back(self):
        self.assertEqual(self.titles([("PVTI_1", "In Progress", "-", "Update swiftformat to 0.64.3"),
                                      ("PVTI_2", "Done", "-", "Update swiftlint to 0.64.0")]),
                         ["Update swiftlint to 0.65.1"])


class LintToolsOutdated(unittest.TestCase):
    """`scripts/lint-tools.sh outdated` against its real pins, with a stand-in for gh."""

    PINS = dict(re.findall(r'"(swiftformat|swiftlint) (\S+) ', (SCRIPTS / "lint-tools.sh").read_text()))

    def outdated(self, swiftformat, swiftlint):
        bin_dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, bin_dir, True)
        gh = bin_dir / "gh"
        gh.write_text(f"""#!/bin/sh
case "$2" in
    *SwiftFormat*) tag={swiftformat} ;;
    *SwiftLint*) tag={swiftlint} ;;
esac
[ "$tag" = fail ] && {{ echo "HTTP 503" >&2; exit 1; }}
echo "$tag"
""")
        gh.chmod(0o755)
        return subprocess.run(["bash", str(SCRIPTS / "lint-tools.sh"), "outdated"], capture_output=True,
                              text=True, env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"})

    def test_a_newer_release_is_named_and_the_same_or_older_is_not(self):
        result = self.outdated("v9.99.10", "0.0.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, f"swiftformat {self.PINS['swiftformat']} 9.99.10\n")

    def test_tools_at_their_pin_print_nothing(self):
        result = self.outdated(self.PINS["swiftformat"], self.PINS["swiftlint"])
        self.assertEqual((result.returncode, result.stdout), (0, ""))
        self.assertIn("every pinned tool is at its latest release", result.stderr)

    def test_an_unreadable_release_fails_naming_the_tool_after_checking_the_rest(self):
        result = self.outdated("fail", "9.99.0")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, f"swiftlint {self.PINS['swiftlint']} 9.99.0\n")
        self.assertIn("could not read swiftformat's latest release", result.stderr)


class Verifier(unittest.TestCase):
    def test_the_newest_record_decides(self):
        comments = ["Verifier record, abc1234\n- criterion, new: it failed",
                    "a reply", "Verifier record, def5678\n- test, new: x, unit, 0.1 s\n- design, known: y"]
        self.assertEqual(nightly.verifier_record(comments), ("def5678", [], []))

    def test_a_failed_criterion_or_a_crash_fails(self):
        _, failures, unread = nightly.verifier_record(["Verifier record, abc1234\n- criterion, new: a\n- crash, new: b\n- No findings"])
        self.assertEqual((len(failures), unread), (2, []))

    def test_an_other_line_is_read_and_not_a_failure(self):
        _, failures, unread = nightly.verifier_record(["Verifier record, abc1234\n- other, known: a tier over budget on main"])
        self.assertEqual((failures, unread), ([], []))

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


WORKTREE = nightly.ROOT / ".claude/worktrees/night-card"
NIGHT_DIR = nightly.ROOT / ".build/retro/2026-10-28"


def fence(cwd=None):
    """The fence of a card in WORKTREE, as the runner lays it out."""
    return nightly.Fence(WORKTREE, nightly.ROOT, NIGHT_DIR, cwd)


def decide(command="", tool="Bash", now=NIGHT, app=True, runs=0, hours=10, path="", inputs=(), cwd=None):
    """The hook's decision, with a run_gate built from what the branch changes and the night's runs."""
    gate = lambda starts: app and nightly.xcode_cloud_gate(hours, runs)  # noqa: E731
    return nightly.hook_decision(tool, command, now, STOP, ".slices/h.md", gate, fence(cwd), path, inputs) or None


class Hook(unittest.TestCase):
    def decide(self, tool, command="", now=NIGHT, app=False, runs=0, hours=10, path=""):
        return decide(command, tool, now, app, runs, hours, path)

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
        self.assertIsNone(self.decide("Write", now=late, path=".slices/h.md"))
        for tool in ("Write", "Edit", "NotebookEdit"):
            self.assertIn("past 7", self.decide(tool, now=late, path="App/Root.swift"), tool)
            self.assertIsNone(self.decide(tool, path="App/Root.swift"), tool)
        self.assertIn("past 7", self.decide("mcp__xcode__BuildProject", now=late))
        self.assertIsNone(self.decide("mcp__xcode__BuildProject"))
        self.assertIsNone(self.decide("Read", now=STOP - timedelta(minutes=1)))

    def test_the_hook_sees_edits_and_mcp_calls_and_outlasts_its_reads(self):
        settings = json.loads((SCRIPTS.parent / ".claude/settings.json").read_text())
        hooks = [h for h in settings.get("hooks", {}).get("PreToolUse", [])
                 if any("night-guard.sh" in c.get("command", "") for c in h["hooks"])]
        if not hooks:
            self.skipTest("the night's guard isn't in .claude/settings.json yet")
        hook = hooks[0]
        for tool in ("Bash", "Agent", "Edit", "Write", "NotebookEdit", "mcp__xcode__RunAllTests"):
            self.assertRegex(tool, f"^({hook['matcher']})$")
        # Two reads (classify, then Xcode Cloud) give up before Claude Code would time the hook out.
        self.assertGreater(hook["hooks"][0]["timeout"], 2 * nightly.READ_TIMEOUT + 30)

    def test_from_seven_a_pipe_or_substitution_is_no_way_out(self):
        late = STOP + timedelta(minutes=1)
        for command in ["cat x | tee y", "cat x > y", "grep -l a f | xargs rm -rf", 'git commit -m "$(scripts/build.sh)"',
                        "cat x\nscripts/build.sh", "git -C /w push"]:
            self.assertIn("past 7", self.decide("Bash", command, now=late), command)
        self.assertIsNone(self.decide("Bash", "git -C /w status && git --no-pager diff | head", now=late))


class SetupReview(unittest.TestCase):
    FIRST = datetime(2026, 12, 1, 0, 20).astimezone()  # the first night of December

    def reports(self, *names, first="# Setup review, Xcode 27.1"):
        folder = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, folder)
        for name in names:
            (folder / name).write_text(f"{first}\n\nKept: everything.\n")
        return folder

    def test_the_newest_report_says_when_and_on_which_xcode(self):
        folder = self.reports("report-2026-10-30.md", "report-2026-11-11.md", "notes.md")
        self.assertEqual(nightly.last_review(folder), ("2026-11", "27"))
        self.assertIsNone(nightly.last_review(self.reports()))
        self.assertEqual(nightly.last_review(self.reports("report-2026-11-11.md", first="# Setup review")),
                         ("2026-11", None))

    def test_xcodes_major_version(self):
        self.assertEqual(nightly.xcode_major("Xcode 27.1\nBuild version 27A123\n"), "27")
        self.assertEqual(nightly.xcode_major("Xcode 28"), "28")
        self.assertIsNone(nightly.xcode_major("xcode-select: error: no developer tools"))
        self.assertIsNone(nightly.xcode_major(None))

    def test_due_once_a_month_at_the_first_night_with_none(self):
        self.assertIn("December 2026", nightly.review_due(("2026-11", "27"), self.FIRST, "27"))
        # A first night missed while the Mac was off is caught up the next night.
        self.assertIsNotNone(nightly.review_due(("2026-11", "27"), self.FIRST.replace(day=3), "27"))
        self.assertIsNone(nightly.review_due(("2026-12", "27"), self.FIRST.replace(day=2), "27"))
        self.assertIsNotNone(nightly.review_due(None, self.FIRST, "27"))

    def test_due_again_on_a_newer_major_xcode(self):
        self.assertIn("Xcode 28", nightly.review_due(("2026-12", "27"), self.FIRST.replace(day=9), "28"))
        # Back from a beta is no new Xcode.
        self.assertIsNone(nightly.review_due(("2026-12", "28"), self.FIRST.replace(day=9), "27"))
        self.assertIsNone(nightly.review_due(("2026-12", "27"), self.FIRST.replace(day=9), None))
        self.assertIsNone(nightly.review_due(("2026-12", None), self.FIRST.replace(day=9), "28"))

    def test_a_review_that_wrote_no_report_is_tried_once_more(self):
        retro = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, retro)
        for night in ("2026-11-01", "2026-12-01", "2026-12-02", "2026-12-03"):
            (retro / night).mkdir()
        (retro / "2026-12-03/notes.json").write_text('{"ended": "x"}')  # a night with no review
        (retro / "2026-11-01/notes.json").write_text('{"review": "Setup review 2026-11-01: 2 cards"}')
        (retro / "2026-12-01/notes.json").write_text('{"review": null}')
        (retro / "2026-12-02/notes.json").write_text("not json")
        self.assertEqual(nightly.review_tries(retro, self.FIRST), 1)
        self.assertIsNotNone(nightly.review_due(("2026-11", "27"), self.FIRST.replace(day=2), "27", tries=1))
        (retro / "2026-12-02/notes.json").write_text('{"review": null}')
        self.assertEqual(nightly.review_tries(retro, self.FIRST), 2)
        self.assertIsNone(nightly.review_due(("2026-11", "27"), self.FIRST.replace(day=3), "27", tries=2))

    def review(self, now, due="none has run in December 2026 yet"):
        night = night_folder(self)
        reports = night.dir.parents[2] / ".slices/review-setup"
        (night.dir / nightly.REVIEW_TALLY).write_text("tally\n")
        stub(self, review_reason=lambda now: (due, night.dir.parents[2]), tallies=lambda *a, **k: self.fail(a))
        return night, nightly.open_review(night, now, SESSION), reports

    def test_a_due_review_opens_its_phase_with_ninety_minutes_or_five_am_whichever_is_first(self):
        for now, deadline in ((self.FIRST, self.FIRST + timedelta(minutes=90)),
                              (self.FIRST.replace(hour=4), self.FIRST.replace(hour=5, minute=0))):
            with self.subTest(now=now):
                night, why, reports = self.review(now)
                self.assertEqual(why, "none has run in December 2026 yet")
                self.assertEqual(night.state()["phase"], {"kind": "review", "deadline": deadline.isoformat(),
                                                          "reports": str(reports)})
                self.assertIn("review", night.notes())
                self.assertIn("Setup review: no reply", nightly.night_digest(night.dir))

    def test_no_review_due_opens_nothing_and_exits_one(self):
        night, why, _ = self.review(self.FIRST, due=None)
        self.assertIsNone(why)
        self.assertIsNone(night.state()["phase"])
        self.assertNotIn("review", night.notes())
        status = []
        with contextlib.redirect_stdout(io.StringIO()) as out:
            try:
                nightly.main(["review", str(night.dir)])
            except SystemExit as exit_:
                status.append(exit_.code)
        self.assertEqual((status, out.getvalue()), ([1], "No setup review tonight.\n"))

    def test_a_due_review_the_guard_cant_hold_opens_nothing_and_the_digest_says_why(self):
        night = night_folder(self, seen=False)
        stub(self, review_reason=lambda now: ("none has run in December 2026 yet", night.dir.parents[2]))
        status, text = nightly.run_review(night, self.FIRST, SESSION)
        self.assertEqual(status, 1)
        self.assertIn("the guard never judged this session's calls", text)
        self.assertIsNone(night.state()["phase"])
        self.assertTrue(nightly.night_digest(night.dir)[-1].startswith(
            "Setup review: due (none has run in December 2026 yet), not run: the guard never judged"))

    def test_a_review_that_fails_to_open_exits_two(self):
        night = night_folder(self)
        night.set_state(phase={"kind": "review", "deadline": "x", "reports": "x"})
        stub(self, review_reason=lambda now: ("due", night.dir.parents[2]))
        self.assertEqual(nightly.run_review(night, self.FIRST, SESSION),
                         (2, "review failed: ValueError: the review is still open"))

    def test_review_end_closes_the_phase_and_the_digest_shows_its_line(self):
        night, _, _ = self.review(self.FIRST)
        line = "Setup review 2026-12-01: 3 cards, 1 question; report in .slices/review-setup/"
        io_of(lambda: nightly.main(["review-end", str(night.dir), line]))
        self.assertIsNone(night.state()["phase"])
        self.assertIn(f"Setup review: {line}", nightly.night_digest(night.dir))

    def test_only_at_night(self):
        for hour in (5, 12, 23):
            self.assertIsNone(nightly.review_due(None, self.FIRST.replace(hour=hour), "27"), hour)


class AgentTally(unittest.TestCase):
    """The agents' tallies the night writes for the retro and the setup review."""

    def setUp(self):
        self.night = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.night)
        self.fetched = []

    def fetch(self, since):
        self.fetched.append(since)
        return [{"number": 1, "mergedAt": "2026-10-20T10:00:00Z"}, {"number": 2, "mergedAt": "2026-11-05T10:00:00Z"},
                {"number": 3, "mergedAt": "2026-11-11T23:00:00Z"}], 2, 4998

    @staticmethod
    def tally(prs, since):
        return f"since {since}: " + " ".join(f"#{pr['number']}" for pr in prs)

    def test_one_fetch_writes_each_file_from_its_own_date(self):
        nightly.write_tallies(self.night, {
            nightly.TALLY: [("", "2026-10-13")],
            nightly.REVIEW_TALLY: [("Since the last setup review, 2026-11-01:", "2026-11-01"),
                                   ("Trial: builder on claude-sonnet-5-5, 2026-11-10, trial for 5 PRs; since its start:",
                                    "2026-11-10")]}, self.fetch, self.tally)
        self.assertEqual(self.fetched, ["2026-10-13"])
        retro = (self.night / nightly.TALLY).read_text()
        self.assertTrue(retro.startswith("since 2026-10-13: #1 #2 #3\n"), retro)
        self.assertIn("cost 2 GraphQL points; 4998 left", retro)
        review = (self.night / nightly.REVIEW_TALLY).read_text()
        self.assertIn("Since the last setup review, 2026-11-01:\nsince 2026-11-01: #2 #3", review)
        self.assertIn("since its start:\nsince 2026-11-10: #3", review)

    def test_a_failed_fetch_writes_why_in_each_file_and_goes_on(self):
        def fails(since):
            raise subprocess.CalledProcessError(1, ["gh", "api", "graphql", "-f", "query=…"],
                                                stderr="error\ngh: not signed in\n")
        nightly.write_tallies(self.night, {nightly.TALLY: [("", "2026-10-13")],
                                           nightly.REVIEW_TALLY: [("x", "2026-11-01")]}, fails, self.tally)
        for name in (nightly.TALLY, nightly.REVIEW_TALLY):
            self.assertEqual((self.night / name).read_text(),
                             "No tally tonight: gh api graphql failed: gh: not signed in\n")

    def test_a_hung_fetch_says_how_long_not_the_query(self):
        def hangs(since):
            raise subprocess.TimeoutExpired(["gh", "api", "graphql", "-f", "query=" + "x" * 500], 120)
        nightly.write_tallies(self.night, {nightly.TALLY: [("", "2026-10-13")]}, hangs, self.tally)
        self.assertEqual((self.night / nightly.TALLY).read_text(), "No tally tonight: GitHub's answers took over 120 s\n")

    def stand_in_gh(self, script):
        """A gh on the PATH, running script, for this test only."""
        folder = self.night / "bin"
        folder.mkdir(exist_ok=True)
        (folder / "gh").write_text(f"#!/bin/sh\n{script}\n")
        (folder / "gh").chmod(0o755)
        path = os.environ["PATH"]
        os.environ["PATH"] = f"{folder}:{path}"
        self.addCleanup(os.environ.__setitem__, "PATH", path)

    def test_one_hung_request_is_cut_off_at_its_limit(self):
        self.stand_in_gh("sleep 30")
        record = nightly.agent_record()
        record.GH_LIMIT = 0.5
        start = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired) as caught:
            record.fetch("2026-10-13")
        self.assertLess(time.monotonic() - start, 5)
        self.assertEqual(caught.exception.timeout, 0.5)

    def test_a_fetch_that_pages_is_cut_off_at_the_whole_limit(self):
        # Each page answers in a fifth of a second, far inside its own limit, and twenty pages take
        # four seconds: only the bound on them all ends the fetch before its last page.
        def page(more):
            return json.dumps({"data": {"search": {"pageInfo": {"hasNextPage": more, "endCursor": "x"}, "nodes": []},
                                        "rateLimit": {"cost": 1, "remaining": 4999}}})
        count = self.night / "pages"
        self.stand_in_gh(f"sleep 0.2\necho . >> '{count}'\n"
                         f"if [ $(wc -l < '{count}') -lt 20 ]; then echo '{page(True)}'; else echo '{page(False)}'; fi")
        record = nightly.agent_record()
        start = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired) as caught:
            record.fetch("2026-10-13", limit=1)
        self.assertLess(time.monotonic() - start, 3)
        self.assertEqual(caught.exception.timeout, 1)
        count.unlink()
        nightly.write_tallies(self.night, {nightly.TALLY: [("", "2026-10-13")]},
                              lambda since: record.fetch(since, limit=1), self.tally)
        self.assertEqual((self.night / nightly.TALLY).read_text(), "No tally tonight: GitHub's answers took over 1 s\n")

    def test_the_review_starts_at_its_last_report_and_each_trial(self):
        now = datetime(2026, 12, 1, 0, 20).astimezone()
        self.assertEqual(nightly.review_parts("2026-11-11", now, [("builder", "claude-sonnet-5-5",
                                                                   "2026-11-20, trial for 5 PRs")]),
                         [("Since the last setup review, 2026-11-11:", "2026-11-11"),
                          ("Trial: builder on claude-sonnet-5-5, 2026-11-20, trial for 5 PRs; since its start:",
                           "2026-11-20")])
        self.assertEqual(nightly.review_parts(None, now, []),
                         [("No setup review's report yet, so over the last 30 days:", "2026-11-01")])
        self.assertEqual(nightly.review_parts(None, now, "ValueError: no table")[1],
                         ("Trials not read: ValueError: no table", None))

    def test_the_last_reports_whole_date(self):
        for name in ("report-2026-10-30.md", "report-2026-11-11.md", "notes.md"):
            (self.night / name).write_text("# Setup review\n")
        self.assertEqual(nightly.last_review_date(self.night), "2026-11-11")
        (self.night / "report-2026-10-30.md").unlink()
        (self.night / "report-2026-11-11.md").unlink()
        self.assertIsNone(nightly.last_review_date(self.night))

    def test_the_command_with_gh_refusing_writes_why_and_exits_cleanly(self):
        bin_dir = self.night / "bin"
        bin_dir.mkdir()
        (bin_dir / "gh").write_text("#!/bin/sh\necho 'gh: not signed in' >&2\nexit 1\n")
        (bin_dir / "gh").chmod(0o755)
        night = self.night / "2026-11-12"
        out = subprocess.run([sys.executable, str(SCRIPTS / "nightly-tooling.py"), "tally", str(night)],
                             capture_output=True, text=True, env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"})
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual((night / nightly.TALLY).read_text(),
                         "No tally tonight: gh api graphql failed: gh: not signed in\n")

    def test_the_command_counts_the_prs_github_says_merged(self):
        # Like GitHub, the stand-in answers only the fields the query asks for, so the night's
        # tally counts these PRs only when scripts/agent-record.py's query asks when each merged.
        bin_dir = self.night / "bin"
        bin_dir.mkdir()
        merged = f"{datetime.now().astimezone() - timedelta(days=2):%Y-%m-%dT%H:%M:%SZ}"
        (bin_dir / "gh").write_text(f"""#!/usr/bin/env python3
import json, sys
query = " ".join(sys.argv)
fields = {{"mergedAt": {merged!r}}} if "mergedAt" in query else {{}}
nodes = [dict(number=n, comments=dict(nodes=[]), commits=dict(nodes=[]), **fields) for n in (41, 42)]
print(json.dumps({{"data": {{"search": {{"pageInfo": {{"hasNextPage": False, "endCursor": None}}, "nodes": nodes}},
                             "rateLimit": {{"cost": 1, "remaining": 4999}}}}}}))
""")
        (bin_dir / "gh").chmod(0o755)
        night = self.night / "night"
        out = subprocess.run([sys.executable, str(SCRIPTS / "nightly-tooling.py"), "tally", str(night)],
                             capture_output=True, text=True, timeout=60,
                             env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"})
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn(": 2 merged,", (night / nightly.TALLY).read_text())


class Digest(unittest.TestCase):
    def test_a_merged_pr_has_its_undo_line(self):
        line = nightly.digest_block({"number": 120, "title": "Lint the UI tests"}, "0123456789abcdef",
                                    [".swiftlint.yml", "PlusPlusUITests/A.swift", "Packages/Tests/B/C.swift"],
                                    "verifier record at abc1234, PR check passed on Xcode Cloud run 330")
        self.assertEqual(line, "#120 Lint the UI tests — 0123456 — .swiftlint.yml, Packages/Tests, PlusPlusUITests — "
                               "verifier record at abc1234, PR check passed on Xcode Cloud run 330 — undo: git revert 0123456")


class Decide(unittest.TestCase):
    """`decide`'s gates against a real git repo, with gh and the board recorded instead of called,
    on a card the guard saw a builder work on."""

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

        def sh(*args, cwd=None, stdin=None, check=True, timeout=None):
            if args[0] == "git":
                return "" if args[1] == "fetch" else real(*args, cwd=self.repo, stdin=stdin, check=check)
            self.calls.append(" ".join(str(a) for a in args))
            return "me\n" if args[:3] == ("gh", "api", "user") else ""

        self.saved = nightly.sh, nightly.ROOT
        nightly.sh, nightly.ROOT = sh, self.repo
        self.addCleanup(lambda: (setattr(nightly, "sh", self.saved[0]), setattr(nightly, "ROOT", self.saved[1])))
        self.night = night_folder(self)
        open_card(self.night)
        (self.night.dir / "guard-seen").write_text("none\tlead\ncard PVTI_1\tlead\ncard PVTI_1\tbuilder\n")
        stub(self, wait_merge=lambda night, entry: ("merged", "merged"), classify=lambda files: "app: x",
             xcode_cloud_runs=lambda *a, **k: [])

    def settle(self, pr):
        return nightly.settle(self.night, self.night.entry("PVTI_1"), pr, NIGHT)[0]

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

    def why(self):
        return self.night.entry("PVTI_1")["why"]

    def test_a_passing_card_arms_auto_merge_at_its_head(self):
        pr = self.pr(lambda: self.write("scripts/a.py", "y\n"))
        self.assertEqual(self.settle(pr), "merged")
        self.assertIn(f"gh pr merge 7 --auto --squash --match-head-commit {pr['headRefOid']}", self.calls)
        entry = self.night.entry("PVTI_1")
        self.assertEqual((entry["decision"], entry["pr"], entry["head"]), ("armed", 7, pr["headRefOid"]))

    def test_a_card_whose_subagents_the_guard_never_saw_is_parked_unarmed(self):
        (self.night.dir / "guard-seen").write_text("none\tlead\ncard PVTI_1\tlead\ncard PVTI_2\tbuilder\n")
        pr = self.pr(lambda: self.write("scripts/a.py", "y\n"))
        self.assertEqual(self.settle(pr), "parked")
        self.assertFalse([c for c in self.calls if "--auto " in c])
        self.assertIn("gh pr merge 7 --disable-auto", self.calls)
        self.assertEqual(self.why(), "the guard never judged a subagent's call for this card, so it ran unguarded")

    def test_a_renamed_protected_file_waits_unmerged_and_the_digest_says_so(self):
        pr = self.pr(lambda: (self.repo / ".swiftlint.yml").rename(self.repo / "lint.yml"))
        self.assertEqual(self.settle(pr), "waiting")
        self.assertFalse([c for c in self.calls if "--auto " in c])
        self.assertIn(".swiftlint.yml", self.why())
        self.assertIn("Waiting: #7 Card: it touches .swiftlint.yml", "\n".join(nightly.night_digest(self.night.dir)))

    def test_a_failed_card_goes_to_draft_with_auto_merge_off_and_its_state_says_why(self):
        pr = self.pr(lambda: self.write("scripts/a.py", "y\n"), record="- criterion, new: it broke")
        self.assertEqual(self.settle(pr), "parked")
        self.assertIn("gh pr merge 7 --disable-auto", self.calls)
        self.assertIn("gh pr ready 7 --undo", self.calls)
        self.assertTrue(any(c.endswith("board.sh state PVTI_1") for c in self.calls))
        self.assertIn("it broke", self.why())

    def test_no_merge_without_a_verifier_record(self):
        pr = self.pr(lambda: self.write("scripts/a.py", "y\n"), record=None)
        self.assertEqual(self.settle(pr), "parked")
        self.assertFalse([c for c in self.calls if "--auto" in c])

    def test_a_test_count_drop_without_its_line_parks(self):
        pr = self.pr(lambda: self.write("Packages/Tests/WorkoutStoreTests/T.swift", "@Test func a() {}\n"))
        self.assertEqual(self.settle(pr), "parked")

    def test_a_test_commented_out_is_a_drop(self):
        pr = self.pr(lambda: self.write("Packages/Tests/WorkoutStoreTests/T.swift",
                                        "@Test func a() {}\n// @Test func b() {}\n"))
        self.assertEqual(self.settle(pr), "parked")
        self.assertIn("WorkoutStoreTests 2 → 1", self.why())

    def test_a_drop_its_body_explains_merges(self):
        pr = self.pr(lambda: self.write("Packages/Tests/WorkoutStoreTests/T.swift", "@Test func a() {}\n"),
                     body="Fewer tests: WorkoutStoreTests loses b, which a covers.")
        self.assertEqual(self.settle(pr), "merged")

    def test_a_record_off_the_format_parks(self):
        pr = self.pr(lambda: self.write("scripts/a.py", "y\n"), record="- Criterion, new: it broke")
        self.assertEqual(self.settle(pr), "parked")
        self.assertFalse([c for c in self.calls if "--auto" in c])
        self.assertIn("can't read", self.why())

    def test_a_branch_or_pr_name_already_used_is_never_reused(self):
        self.git("branch", "night-card")
        stub(self, gh_json=lambda *a: [{"headRefName": "night-card-2"}])
        worktree, branch = nightly.paths("Card")
        self.assertEqual((branch, worktree.name), ("night-card-3", "night-card-3"))

    def test_a_scheme_or_lint_script_change_waits(self):
        for name in ("PlusPlus.xcodeproj/xcshareddata/xcschemes/PlusPlus.xcscheme", "scripts/lint.sh"):
            self.git("checkout", "-q", "main")
            self.git("branch", "-qD", "card") if self.git("branch", "--list", "card") else None
            self.night.update("PVTI_1", decision="open")
            pr = self.pr(lambda: self.write(name, "exit 0\n"))
            self.assertEqual(self.settle(pr), "waiting", name)
        self.assertFalse([c for c in self.calls if "--auto " in c])


class Armed(unittest.TestCase):
    """`decide` on an armed PR: it waits inside the call, then asks to be run again, never arming twice."""

    def setUp(self):
        self.night = night_folder(self)
        open_card(self.night)
        self.calls, self.views = [], []
        stub(self, sh=lambda *a, **k: self.calls.append(" ".join(map(str, a))) or "",
             board=lambda *a, stdin=None: self.calls.append(" ".join(("board.sh",) + a)),
             gh_json=self.gh, MERGE_POLL=timedelta(0), classify=lambda files: "docs")
        stub_sleep = nightly.time.sleep
        self.addCleanup(setattr, nightly.time, "sleep", stub_sleep)
        nightly.time.sleep = lambda s: None
        self.night.update("PVTI_1", decision="armed", pr=7, pr_title="Card", head="a" * 40, built="abc1234",
                          files=["scripts/a.py"], armed_at=datetime.now().astimezone().isoformat())

    def gh(self, *args):
        if args[:2] == ("pr", "view"):
            return self.views.pop(0) if len(self.views) > 1 else self.views[0]
        return []

    def decide(self):
        return nightly.run_decide(self.night, "PVTI_1", "PR #7", NIGHT)

    def test_an_armed_pr_not_yet_merged_asks_to_be_run_again(self):
        self.views = [{"state": "OPEN", "statusCheckRollup": []}]
        self.assertEqual(self.decide(), (3, "armed: run decide again"))
        self.assertEqual(self.night.entry("PVTI_1")["decision"], "armed")
        self.assertEqual(self.night.state()["phase"]["item"], "PVTI_1")

    def test_a_second_call_on_an_armed_pr_does_not_arm_again_and_a_merge_closes_it(self):
        self.views = [{"state": "OPEN", "statusCheckRollup": [{"name": "Route", "conclusion": "FAILURE"}]}]
        self.assertEqual(self.decide()[0], 3)
        self.views = [{"state": "MERGED", "mergeCommit": {"oid": "f" * 40}, "statusCheckRollup": []}]
        self.assertEqual(self.decide(), (0, f"#7 merged as {'f' * 7}."))
        self.assertFalse([c for c in self.calls if "--auto " in c])
        self.assertIn("board.sh status PVTI_1 Done", self.calls)
        entry = self.night.entry("PVTI_1")
        self.assertEqual((entry["decision"], entry["proof"]), ("merged", "verifier record at abc1234, PR check passed, lint only"))
        self.assertIsNone(self.night.state()["phase"])

    def test_an_armed_pr_whose_check_fails_or_an_hour_passes_is_parked(self):
        self.views = [{"state": "OPEN", "statusCheckRollup": [{"name": "PR check", "conclusion": "FAILURE"}]}]
        self.assertEqual(self.decide()[0], 0)
        self.assertEqual(self.night.entry("PVTI_1")["decision"], "parked")
        self.assertIn("gh pr merge 7 --disable-auto", self.calls)
        open_card(self.night, item="PVTI_2")
        self.night.update("PVTI_2", decision="armed", pr=8, pr_title="Card", armed_at=(
            datetime.now().astimezone() - timedelta(minutes=61)).isoformat())
        self.views = [{"state": "OPEN", "statusCheckRollup": []}]
        self.assertEqual(nightly.run_decide(self.night, "PVTI_2", "", NIGHT)[0], 0)
        self.assertIn("didn't finish within the hour", self.night.entry("PVTI_2")["why"])

    def test_every_outcome_closes_the_phase(self):
        outcomes = {"merged": [{"state": "MERGED", "mergeCommit": {"oid": "f" * 40}, "statusCheckRollup": []}],
                    "parked": [{"state": "OPEN", "statusCheckRollup": [{"name": "PR check", "conclusion": "FAILURE"}]}]}
        for decision, views in outcomes.items():
            with self.subTest(decision=decision):
                self.night.set_state(phase={"kind": "card", "item": "PVTI_1"})
                self.night.update("PVTI_1", decision="armed")
                self.views = views
                self.decide()
                self.assertEqual(self.night.entry("PVTI_1")["decision"], decision)
                self.assertIsNone(self.night.state()["phase"])
        # And a failure: the card is parked, its phase closed, and the night's PRs disarmed.
        self.night.set_state(phase={"kind": "card", "item": "PVTI_1"})
        self.night.update("PVTI_1", decision="armed", armed_at="not a time")
        self.views = [{"state": "OPEN", "statusCheckRollup": []}]
        status, why = self.decide()
        self.assertEqual(status, 2)
        self.assertTrue(why.startswith("deciding failed: ValueError"), why)
        self.assertEqual(self.night.entry("PVTI_1")["decision"], "parked")
        self.assertIsNone(self.night.state()["phase"])


class Next(unittest.TestCase):
    """`next` over a night's folder, with the board, the PRs, Xcode Cloud, and git stubbed."""

    BODY = "## Problem\nx\n\nNightly: faster CI; its time\n\n## Success\nRun it.\n\n## Plan\n- Edit `scripts/a.py`.\n"

    def setUp(self):
        self.night = night_folder(self)
        self.root = self.night.dir.parents[2]
        self.calls, self.prs, self.hours = [], [], 1.0
        self.kind = "app: scripts/a.py"
        self.cards = [(f"PVTI_{i}", "Definitely", "-", f"card {i}", self.BODY) for i in range(5)]
        self.outdated = subprocess.CompletedProcess([], 0, "", "")
        stub(self, board_rows=lambda: [], board_cards=lambda rows: self.cards, xcode_cloud_runs=lambda *a: [],
             month_hours=lambda runs, now: self.hours, gh_json=self.gh, classify=lambda files: self.kind,
             sh=self.sh, test_counts=lambda rev: {"WorkoutStoreTests": 3}, outdated_tools=lambda: self.outdated,
             board=self.board, main_checkout=lambda: self.root, install_pre_push=lambda night, worktree: None)

    def sh(self, *args, **kwargs):
        self.calls.append(" ".join(map(str, args)))
        return "scripts/a.py\n" if args[:2] == ("git", "ls-tree") else ""

    def gh(self, *args):
        return self.prs if args[-1] == "number,files,title" else []

    def board(self, *args, stdin=None):
        self.calls.append(" ".join(("board.sh",) + args))
        return "PVTI_new\n" if args[0] == "add" else ""

    def next(self, now=NIGHT, dry_run=False, session=SESSION):
        return nightly.run_next(self.night, now, session, dry_run)

    def decided(self):
        """As `decide` leaves the card it was given: parked, its phase closed."""
        item = self.night.state()["phase"]["item"]
        self.night.update(item, decision="parked", why="x", where="no PR")
        self.night.set_state(phase=None)

    def runs_tonight(self, n):
        (self.night.dir / "starts").write_text("".join(f"{i}\n" for i in range(n)))

    def test_a_taken_card_opens_its_phase_goes_in_progress_and_prints_where(self):
        status, text = self.next()
        worktree = self.root / ".claude/worktrees/night-card-0"
        self.assertEqual((status, text.splitlines()), (0, [
            "card PVTI_0", "title card 0", f"worktree {worktree}", "branch night-card-0",
            f"handoff {self.root / '.slices/night-card-0-handoff.md'}"]))
        self.assertIn(f"git worktree add --no-track {worktree} -b night-card-0 origin/main", self.calls)
        self.assertIn("board.sh status PVTI_0 In Progress", self.calls)
        phase = self.night.state()["phase"]
        self.assertEqual((phase["kind"], phase["item"], phase["worktree"], phase["stop"]),
                         ("card", "PVTI_0", str(worktree), STOP.isoformat()))
        self.assertEqual(self.night.entry("PVTI_0")["usage"], "Usage: Weekly · all models 40%")

    def test_no_card_from_five_to_midnight(self):
        for hour in (5, 12, 23):
            self.assertEqual(self.next(NIGHT.replace(hour=hour)), (1, "No card: cards start only from midnight to 5 am."))
        self.assertEqual(self.calls, [])

    def test_no_card_while_a_card_or_the_review_is_open(self):
        self.assertEqual(self.next()[0], 0)
        self.assertEqual(self.next(), (1, "No card: the card PVTI_0 is still open, so run decide or review-end first."))
        self.night.set_state(phase={"kind": "review", "deadline": STOP.isoformat()})
        self.assertIn("the review is still open", self.next()[1])

    def test_no_card_when_the_guard_never_saw_this_session(self):
        (self.night.dir / "guard-seen").write_text("card PVTI_9\tbuilder\n")
        self.assertIn("the guard never judged this session's calls", self.next()[1])
        self.assertNotIn("git worktree add", " ".join(self.calls))

    def test_no_card_when_the_recorded_session_is_not_this_one(self):
        self.assertEqual(self.next(session="another"), (1, "No card: this session isn't the one the night's start recorded."))
        self.assertIn("this session isn't", self.next(session=None)[1])
        (self.night.dir / "session").unlink()
        self.assertIn("no session id was recorded", self.next()[1])

    def test_stale_or_full_usage_starts_no_card_and_the_digest_says_why(self):
        write_usage(self.night.dir, ("Weekly · all models", 40, 100), age=timedelta(minutes=20))
        self.assertEqual(self.next(), (1, "No card: usage is unknown: usage.json is over 15 minutes old"))
        write_usage(self.night.dir, ("Weekly · all models", 92, 100))
        self.assertEqual(self.next()[0], 1)
        self.assertIn("No card started: Weekly · all models at 92%", nightly.night_digest(self.night.dir)[-1])

    def test_three_cards_on_a_capped_night_and_a_fourth_on_the_uncapped_one(self):
        for _ in range(3):
            self.assertEqual(self.next()[0], 0)
            self.decided()
        self.assertIn("3 cards tonight", self.next()[1])
        write_usage(self.night.dir, ("Weekly · all models", 40, TO_SEVEN))
        self.assertEqual(self.next()[1].splitlines()[0], "card PVTI_3")

    def test_at_four_runs_no_app_card_starts_and_no_worktree_is_made(self):
        self.runs_tonight(4)
        status, text = self.next()
        self.assertEqual(status, 1)
        self.assertNotIn("git worktree add", " ".join(self.calls))
        self.assertNotIn("board.sh status", " ".join(self.calls))
        self.assertIsNone(self.night.state()["phase"])
        self.assertTrue(nightly.night_digest(self.night.dir)[-1].startswith(
            'No card started: no card in Definitely may start tonight: "card 0": 4 Xcode Cloud runs tonight, and a '
            "card that may change the app needs room for 2 of the night's 4"))

    def test_an_app_card_needs_room_for_two_runs(self):
        self.runs_tonight(3)
        self.assertIn('"card 0": 3 Xcode Cloud runs tonight', self.next()[1])
        self.runs_tonight(2)
        self.assertEqual(self.next()[0], 0)

    def test_a_docs_only_card_starts_whatever_the_runs(self):
        self.runs_tonight(4)
        self.kind = "docs"
        self.assertEqual(self.next()[0], 0)

    def test_past_seventy_hours_no_app_card_starts(self):
        self.hours = 70.5
        self.assertIn("70.5 Xcode Cloud hours this month, above 70", self.next()[1])

    def test_a_dry_run_changes_nothing(self):
        self.outdated = subprocess.CompletedProcess([], 0, "swiftlint 0.65.0 0.65.1\n", "")
        before = sorted((p.name, p.read_bytes()) for p in self.night.dir.iterdir())
        with contextlib.redirect_stderr(io.StringIO()) as err:
            status, text = self.next(dry_run=True)
        self.assertEqual((status, text.splitlines()[0]), (0, "card PVTI_0"))
        self.assertIn("Dry run: would add: Update swiftlint to 0.65.1", err.getvalue())
        self.assertEqual(sorted((p.name, p.read_bytes()) for p in self.night.dir.iterdir()), before)
        self.assertFalse([c for c in self.calls if c.startswith(("board.sh", "git worktree"))])
        self.runs_tonight(4)
        before = sorted((p.name, p.read_bytes()) for p in self.night.dir.iterdir())
        self.assertEqual(self.next(dry_run=True)[0], 1)
        self.assertEqual(sorted((p.name, p.read_bytes()) for p in self.night.dir.iterdir()), before)

    def test_the_first_next_adds_update_cards_and_closes_merged_ones_once(self):
        # swiftformat's release couldn't be read; swiftlint's line still makes its card.
        self.outdated = subprocess.CompletedProcess([], 1, "swiftlint 0.65.0 0.65.1\n",
                                                    "could not read swiftformat's latest release\n")
        self.assertEqual(self.next()[0], 0)
        self.assertEqual(self.calls.count("board.sh add Update swiftlint to 0.65.1"), 1)
        self.assertIn("board.sh move PVTI_new top", self.calls)
        self.decided()
        self.next()
        self.assertEqual(self.calls.count("board.sh add Update swiftlint to 0.65.1"), 1)
        self.assertEqual(self.night.state()["tests_before"], {"WorkoutStoreTests": 3})
        digest = "\n".join(nightly.night_digest(self.night.dir))
        self.assertIn("Added: Update swiftlint to 0.65.1, at the top of Definitely", digest)
        self.assertIn("Not checked: which lint tools have a newer release (could not read swiftformat's", digest)

    def test_the_held_cards_open_the_digest(self):
        self.prs = [{"number": 164, "title": "Keep the +1 out", "files": [{"path": "scripts/a.py"}]}]
        self.assertEqual(self.next()[0], 1)
        digest = nightly.night_digest(self.night.dir)
        self.assertEqual(digest[1], 'Waits on an open PR: "card 0" may touch what #164 (scripts/a.py) changes; '
                                    "merge or close #164 so a night can take it")
        self.assertEqual(len([line for line in digest if line.startswith("Waits on")]), 5)

    def test_a_merge_that_skipped_the_gates_ends_the_cards(self):
        self.night.set_state(stopped="merged to main tonight without the night's gates: #50.")
        self.assertEqual(self.next(), (1, "No card: merged to main tonight without the night's gates: #50."))


class WorktreeHook(unittest.TestCase):
    """The card's worktree `next` makes, in a real clone whose git takes per-worktree config, as
    the Claude app sets the main checkout's."""

    def setUp(self):
        self.root = Path(os.path.realpath(tempfile.mkdtemp()))
        self.addCleanup(shutil.rmtree, self.root, True)
        self.main = self.root / "main"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(self.root / "origin.git")], check=True)
        subprocess.run(["git", "clone", "-q", str(self.root / "origin.git"), str(self.main)], check=True, capture_output=True)
        self.git("-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "base")
        self.git("push", "-q", "origin", "main")
        self.git("config", "extensions.worktreeConfig", "true")
        real = nightly.sh
        night = nightly.Night(self.main / ".build/retro/2026-10-28")
        night.write("state.json", {"start": NIGHT.isoformat(), "phase": None, "night_read": True})
        (night.dir / "session").write_text(SESSION + "\n")
        (night.dir / "guard-seen").write_text("none\tlead\n")
        write_usage(night.dir, ("Weekly", 10, 100))
        self.night = night
        cards = [("PVTI_1", "Definitely", "-", "A card", Next.BODY)]
        stub(self, sh=lambda *a, cwd=None, **k: real(*a, cwd=self.main, **k), gh_json=lambda *a: [],
             board_rows=lambda: [], board_cards=lambda rows: cards, xcode_cloud_runs=lambda *a: [],
             classify=lambda files: "app: x", board=lambda *a, stdin=None: "")

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.main, check=True, capture_output=True, text=True).stdout.strip()

    def test_the_card_taken_gets_a_worktree_with_the_nights_pre_push_hook(self):
        status, text = nightly.run_next(self.night, NIGHT, SESSION, False)
        self.assertEqual(status, 0, text)
        worktree = self.main / ".claude/worktrees/night-a-card"
        self.assertIn(f"worktree {worktree}", text)
        self.assertEqual(self.git("config", "--worktree", "--get", "core.hooksPath", cwd=worktree),
                         str(self.night.dir / "git-hooks"))
        self.assertEqual(subprocess.run(["git", "config", "--get", "core.hooksPath"], cwd=self.main).returncode, 1)
        self.assertIn(f"pre-push {self.night.dir}", (self.night.dir / "git-hooks/pre-push").read_text())

    def test_a_worktree_that_cannot_take_the_hook_is_removed_and_no_card_starts(self):
        self.git("config", "--unset", "extensions.worktreeConfig")
        status, text = nightly.run_next(self.night, NIGHT, SESSION, False)
        self.assertEqual(status, 1)
        self.assertTrue(text.startswith("No card: the worktree for \"A card\" couldn't take the night's pre-push hook"), text)
        self.assertFalse((self.main / ".claude/worktrees/night-a-card").exists())
        self.assertEqual(self.git("branch", "--list", "night-a-card"), "")
        self.assertEqual(self.night.cards(), [])
        self.assertIsNone(self.night.state()["phase"])


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
                              NIGHT, STOP, "h", calls.append, fence())
        self.assertEqual(calls, [])


def hook_input(command="ls", tool="Bash", session=SESSION, agent=None, cwd=None, **tool_input):
    """A PreToolUse hook's input as Claude Code writes it: agent names the subagent's type."""
    call = {"session_id": session, "tool_name": tool, "tool_input": {"command": command, **tool_input}}
    if agent:
        call.update(agent_id="a1", agent_type=agent)
    if cwd:
        call["cwd"] = str(cwd)
    return json.dumps(call)


class HookFailsClosed(unittest.TestCase):
    """The guard as Claude Code runs it: once a call is the night's, any error exits 2, which
    denies it."""

    def hook(self, folder, stdin):
        script = Path(__file__).with_name("nightly-tooling.py")
        return subprocess.run([sys.executable, str(script), "hook", str(folder)], input=stdin, capture_output=True,
                              text=True)

    def setUp(self):
        self.night = night_folder(self)

    def test_unreadable_state_denies(self):
        (self.night.dir / "state.json").write_text("not json")
        result = self.hook(self.night.dir, hook_input("git push"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("The night's guard failed", result.stderr)
        (self.night.dir / "state.json").unlink()
        self.assertEqual(self.hook(self.night.dir, hook_input("ls")).returncode, 2)

    def test_unreadable_input_denies(self):
        # The shell script hands on only an input holding the night's session id.
        for stdin in [f"not json {SESSION}", f'["{SESSION}"]', json.dumps({"session_id": SESSION})]:
            open_card(self.night)
            self.assertEqual(self.hook(self.night.dir, stdin).returncode, 2, stdin)

    def test_a_failed_budget_read_denies_the_push(self):
        # No such worktree, so reading what the branch changes fails.
        open_card(self.night, worktree=self.night.dir / "gone", stop=datetime.now().astimezone() + timedelta(hours=1))
        self.assertEqual(self.hook(self.night.dir, hook_input("git push")).returncode, 2)
        self.assertEqual(self.hook(self.night.dir, hook_input("ls")).returncode, 0)

    def test_no_phase_passes_every_call(self):
        for command in ["git push", "gh pr merge 7", "rm -rf /tmp/x"]:
            result = self.hook(self.night.dir, hook_input(command))
            self.assertEqual((result.returncode, result.stderr), (0, ""), command)
        self.assertEqual(self.night.seen(), [["none", "lead"]])


class PrePush(unittest.TestCase):
    """The pre-push hook a card's worktree runs, whatever started the push."""

    def setUp(self):
        self.root = Path(os.path.realpath(tempfile.mkdtemp()))
        self.addCleanup(shutil.rmtree, self.root, True)
        self.main, self.w = self.root / "main", self.root / "main/.claude/worktrees/night-card"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(self.root / "origin.git")], check=True)
        subprocess.run(["git", "clone", "-q", str(self.root / "origin.git"), str(self.main)], check=True,
                       capture_output=True)
        self.git("-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "base",
                 cwd=self.main)
        self.git("push", "-q", "origin", "main", cwd=self.main)
        self.git("config", "extensions.worktreeConfig", "true", cwd=self.main)
        self.git("worktree", "add", "-q", "--no-track", str(self.w), "-b", "card", "origin/main", cwd=self.main)
        self.night = nightly.Night(self.main / ".build/retro/2026-10-28")
        self.night.write("state.json", {"start": NIGHT.isoformat(), "hours": 1})
        nightly.install_pre_push(self.night, self.w)

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.w, check=True, capture_output=True)

    def commit(self, name):
        Path(self.w / name).parent.mkdir(parents=True, exist_ok=True)
        Path(self.w / name).write_text("x\n")
        self.git("add", "-A")
        self.git("-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-qm", name)

    def push_from_python(self, name, cwd=None):
        self.commit(name)
        # A push the guard can't see in the command line.
        return subprocess.run([sys.executable, "-c", "import subprocess, sys; sys.exit(subprocess.run("
                               "['git', 'push', '-q', 'origin', 'HEAD:refs/heads/card']).returncode)"],
                              cwd=cwd or self.w, capture_output=True, text=True)

    def test_a_docs_push_goes(self):
        result = self.push_from_python("docs/x.md")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_branch_pushed_from_the_cards_worktree_is_the_nights(self):
        self.assertEqual(self.night.branches(), set())
        self.git("checkout", "-q", "-b", "fix-thing")
        self.commit("docs/x.md")
        result = subprocess.run(["git", "push", "-q", "origin", "fix-thing"], cwd=self.w, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.night.branches(), {"fix-thing"})

    def test_a_push_from_another_worktree_never_meets_the_hook(self):
        (self.night.dir / "state.json").unlink()  # the hook would fail, and refuse
        self.git("checkout", "-q", "-b", "day", cwd=self.main)
        Path(self.main / "App").mkdir()
        Path(self.main / "App/X.swift").write_text("x\n")
        self.git("add", "-A", cwd=self.main)
        self.git("-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-qm", "day", cwd=self.main)
        result = subprocess.run(["git", "push", "-q", "origin", "day"], cwd=self.main, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.night.branches(), set())  # the maintainer's sessions push as the same account

    def test_the_pre_push_hook_budgets_what_is_pushed_not_head(self):
        # The app commit goes on its own branch; HEAD stays on a docs-only one.
        self.git("checkout", "-q", "-b", "app")
        self.commit("App/X.swift")
        self.git("checkout", "-q", "card")
        self.night.write("state.json", {"start": NIGHT.isoformat()})  # no hours: fails
        result = subprocess.run(["git", "push", "-q", "origin", "app"], cwd=self.w, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pre-push hook failed", result.stderr)

    def test_a_push_to_pr_media_goes(self):
        # As scripts/pr-media.sh makes it: a commit with no history shared with main. Read
        # through the budget, it has no merge base and would be refused (PR #177's night).
        self.night.write("state.json", {"start": NIGHT.isoformat()})  # no hours: fails
        blob = subprocess.run(["git", "hash-object", "-w", "--stdin"], cwd=self.w, input="png\n",
                              capture_output=True, text=True, check=True).stdout.strip()
        env = {**os.environ, "GIT_INDEX_FILE": str(self.root / "media-index")}
        subprocess.run(["git", "update-index", "--add", "--cacheinfo", f"100644,{blob},177/x.png"],
                       cwd=self.w, env=env, check=True)
        tree = subprocess.run(["git", "write-tree"], cwd=self.w, env=env, capture_output=True, text=True,
                              check=True).stdout.strip()
        commit = subprocess.run(["git", "-c", "user.email=t@example.com", "-c", "user.name=t", "commit-tree", tree,
                                 "-m", "media"], cwd=self.w, capture_output=True, text=True,
                                check=True).stdout.strip()
        result = subprocess.run(["git", "push", "-q", "origin", f"{commit}:refs/heads/pr-media"], cwd=self.w,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_failure_refuses_the_push(self):
        (self.night.dir / "state.json").unlink()
        result = self.push_from_python("App/X.swift")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pre-push hook failed", result.stderr)


class Malformed(unittest.TestCase):
    """Files the night reads but didn't write: none of them may crash it."""

    def test_usage_that_isnt_the_tools_reads_as_unknown(self):
        with tempfile.TemporaryDirectory() as folder:
            for text in ["not json", "[1]", '{"plan": 3}', '{"plan": {"windows": [{"label": "W"}]}}',
                         '{"plan": {"windows": [{"label": "W", "percentUsed": "x"}]}}', '{"plan": {"windows": []}}']:
                Path(folder, "usage.json").write_text(text)
                rows = nightly.plan_windows(folder)
                self.assertIsInstance(rows, str, text)
                self.assertTrue(nightly.usage_gate(rows, timedelta(0), NIGHT, STOP, 0).startswith("usage is unknown"))
                self.assertTrue(nightly.usage_check(folder)[0], text)

    def test_the_digest_of_a_night_without_one_never_shows_an_earlier_one(self):
        with tempfile.TemporaryDirectory() as root:
            saved = nightly.main_checkout
            self.addCleanup(setattr, nightly, "main_checkout", saved)
            nightly.main_checkout = lambda: Path(root)
            for night in ("2026-10-27", "2026-10-28"):
                Path(root, ".build/retro", night).mkdir(parents=True)
            Path(root, ".build/retro/2026-10-27/digest.md").write_text("old digest\n")
            out = io_of(lambda: nightly.main(["digest"]))
            self.assertEqual(out, "Night 2026-10-28: no outcome recorded: still running, or it stopped early\n"
                                  "Not checked: usage, usage.json is missing\n")
            self.assertNotIn("old digest", out)
            self.assertFalse(Path(root, ".build/retro/2026-10-28/digest.md").exists(), "a bare digest only reads")


def io_of(call):
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        call()
    return buffer.getvalue()


def scratch_clone(test):
    """A main checkout at <root>/main with tidy.sh and common.sh, its origin a local bare repo, and
    a stand-in gh whose `pr list` prints <root>/merged ("<branch> <head sha> <number>" lines, none
    until a test writes them). Returns the root, a command runner in the checkout, and a function
    that runs tidy whole there and returns what it printed."""
    root = Path(os.path.realpath(tempfile.mkdtemp()))
    test.addCleanup(shutil.rmtree, root, True)
    def run(*a, cwd=root / "main"):
        return subprocess.run(a, cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()
    run("git", "init", "-q", "--bare", "-b", "main", str(root / "origin.git"), cwd=root)
    run("git", "clone", "-q", str(root / "origin.git"), "main", cwd=root)
    run("git", "config", "user.email", "t@example.com")
    run("git", "config", "user.name", "t")
    (root / "main/scripts").mkdir()
    for name in ("tidy.sh", "common.sh"):
        shutil.copy(SCRIPTS / name, root / "main/scripts" / name)
    bin_dir = root / "bin"
    bin_dir.mkdir()
    (root / "merged").write_text("")
    (bin_dir / "gh").write_text(f"#!/bin/bash\n[ \"$1 $2\" = 'pr list' ] && cat '{root / 'merged'}'\nexit 0\n")
    (bin_dir / "gh").chmod(0o755)
    run("git", "commit", "-q", "--allow-empty", "-m", "base")
    run("git", "push", "-q", "origin", "main")
    env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"}
    def tidy(*args):
        out = subprocess.run([str(root / "main/scripts/tidy.sh"), *args], cwd=root / "main", env=env,
                             capture_output=True, text=True)
        test.assertEqual(out.returncode, 0, out.stderr)
        return out.stdout
    return root, run, tidy


def fake_board(main, rows="", fails=False):
    """A stand-in scripts/board.sh in the checkout at <main>: `list` prints the rows given
    ("<id>  <status>\\t<feature>\\t<title>" lines), or fails the way a spent quota does."""
    board = main / "scripts/board.sh"
    board.write_text("#!/bin/bash\n" + ("echo 'quota spent' >&2; exit 1\n" if fails
                                         else f"[ \"$1\" = list ] && printf '{rows}'\n"))
    board.chmod(0o755)


class TidySlices(unittest.TestCase):
    """scripts/tidy.sh's .slices/ cleanup, run whole in a scratch clone with gh and the board faked."""

    ROWS = "PVTI_done  Done\t-\tA\nPVTI_todo  In Progress\t-\tB\n"

    def tidy(self, slices, rows=ROWS, board_fails=False):
        root, run, tidy = scratch_clone(self)
        fake_board(root / "main", rows, fails=board_fails)
        run("git", "worktree", "add", "-q", "-b", "live-card", str(root / "main/.claude/worktrees/live-card"))
        old = time.time() - 2 * 86400
        for name, text in slices.items():
            path = root / "main/.slices" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        for path in (root / "main/.slices").rglob("*"):
            if not path.name.startswith("fresh"):
                os.utime(path, (old, old))
        out = tidy()
        left = sorted(str(p.relative_to(root / "main/.slices")) for p in (root / "main/.slices").rglob("*") if p.is_file())
        return left, out

    def test_only_entries_whose_cards_are_all_done_go(self):
        left, out = self.tidy({"done-plan.md": "Card PVTI_done.", "mixed.md": "PVTI_done, then PVTI_todo",
                               "live-card-plan.md": "Cites PVTI_done only.", "notes.md": "no card",
                               "old/run.json": "PVTI_done", "gone.md": "PVTI_gone", "fresh-plan.md": "PVTI_done"})
        self.assertEqual(left, ["fresh-plan.md", "gone.md", "live-card-plan.md", "mixed.md", "notes.md"])
        self.assertIn("kept", out)
        self.assertIn("PVTI_gone, which the board doesn't have", out)

    def test_a_folder_naming_one_card_goes(self):
        left, _ = self.tidy({"one/a.md": "PVTI_done", "one/b.md": "PVTI_done again"})
        self.assertEqual(left, [])

    def test_a_board_error_keeps_everything_and_says_so(self):
        left, out = self.tidy({"done-plan.md": "PVTI_done"}, board_fails=True)
        self.assertEqual(left, ["done-plan.md"])
        self.assertIn("reading the board failed: quota spent", out)


class TidyWorktrees(unittest.TestCase):
    """scripts/tidy.sh keeps a finished worktree that a running process works in (2026-11-11: a
    verifier's tidy removed the live lead's worktree), and removes it once none does."""

    def finished_worktree(self):
        root, run, tidy = scratch_clone(self)
        worktree = root / "main/.claude/worktrees/done-card"
        run("git", "worktree", "add", "-q", "-b", "done-card", str(worktree))
        run("git", "commit", "-q", "--allow-empty", "-m", "work", cwd=worktree)
        (worktree / "Sources").mkdir()
        (root / "merged").write_text(f"done-card {run('git', 'rev-parse', 'HEAD', cwd=worktree)} 1\n")
        return worktree, run, tidy

    def test_a_worktree_a_session_works_in_stays_and_tidy_says_so(self):
        worktree, run, tidy = self.finished_worktree()
        # A session working in a folder of the worktree, the way a Claude session's process does.
        session = subprocess.Popen(["sleep", "60"], cwd=worktree / "Sources")
        self.addCleanup(session.wait)
        self.addCleanup(session.kill)
        out = tidy()
        self.assertTrue(worktree.exists())
        self.assertIn(f"tidy: kept {worktree}: finished, but sleep (pid {session.pid}) works in it", out)
        self.assertIn("done-card", run("git", "branch", "--list", "done-card"))

    def test_a_finished_worktree_no_process_works_in_goes(self):
        worktree, run, tidy = self.finished_worktree()
        out = tidy()
        self.assertFalse(worktree.exists())
        self.assertIn(f"tidy: git worktree remove {worktree}", out)
        self.assertEqual(run("git", "branch", "--list", "done-card"), "")

    def finished_worktree_with_working_files(self):
        """A finished worktree whose .slices/, gitignored as in the repo, holds a lead's handoff for
        PVTI_open; the main checkout is returned too, for its stand-in board."""
        worktree, _, tidy = self.finished_worktree()
        main = worktree.parent.parent.parent
        (main / ".git/info").mkdir(exist_ok=True)
        (main / ".git/info/exclude").write_text(".slices/\n")
        (worktree / ".slices").mkdir()
        (worktree / ".slices/done-card-handoff.md").write_text("Card PVTI_open.")
        return worktree, main, tidy

    def test_a_finished_worktree_holding_an_open_cards_working_files_stays_until_it_is_done(self):
        # A day session's lead keeps the slice's plan and handoff in its own worktree's gitignored
        # .slices/, which `git worktree remove` would delete with it.
        worktree, main, tidy = self.finished_worktree_with_working_files()
        fake_board(main, "PVTI_open  In Progress\\t-\\tA\\n")
        kept = f"tidy: kept {worktree}: finished, but its .slices/ holds files for PVTI_open, not Done yet"
        self.assertIn(kept, tidy("--dry-run"))
        self.assertIn(kept, tidy())
        self.assertTrue((worktree / ".slices/done-card-handoff.md").exists())
        fake_board(main, "PVTI_open  Done\\t-\\tA\\n")
        self.assertIn(f"tidy: git worktree remove {worktree}", tidy())
        self.assertFalse(worktree.exists())

    def test_working_files_that_name_no_card_go_with_their_finished_worktree(self):
        worktree, main, tidy = self.finished_worktree_with_working_files()
        (worktree / ".slices/done-card-handoff.md").write_text("No card named here.")
        fake_board(main, fails=True)  # never read: nothing names a card
        self.assertIn(f"tidy: git worktree remove {worktree}", tidy())
        self.assertFalse(worktree.exists())

    def test_a_finished_worktree_whose_working_files_the_board_cannot_judge_stays(self):
        worktree, main, tidy = self.finished_worktree_with_working_files()
        for rows, fails, why in (("", True, "reading the board for its .slices/ failed: quota spent"),
                                 ("PVTI_other  Done\\t-\\tA\\n", False, "its .slices/ names PVTI_open, which the board doesn't have")):
            with self.subTest(why=why):
                fake_board(main, rows, fails=fails)
                self.assertIn(f"tidy: kept {worktree}: finished, but {why}", tidy())
                self.assertTrue(worktree.exists())

    def test_a_session_worktree_left_detached_keeps_the_branch_it_left(self):
        # A session's fresh branch starts at main, so its tip is in main. On 2026-11-13 an agent
        # checked a PR's commit out in its lead's worktree, detached, and another agent's tidy then
        # deleted the lead's branch, which no worktree had checked out any more.
        root, run, tidy = scratch_clone(self)
        worktree = root / "main/.claude/worktrees/lead-session"
        run("git", "worktree", "add", "-q", "-b", "lead-session", str(worktree))
        run("git", "checkout", "-q", "--detach", "HEAD", cwd=worktree)
        # A branch merely left behind, checked out nowhere and never left by a live worktree, goes.
        run("git", "branch", "old-done")
        out = tidy()
        self.assertTrue(worktree.exists())
        self.assertEqual(run("git", "branch", "--list", "lead-session"), "lead-session")
        self.assertNotIn("lead-session", out)
        self.assertIn("tidy: git branch -D old-done", out)

    def agent_worktree(self, root, run, agent):
        """An isolation worktree as Claude Code makes one: agent-<id>, on worktree-agent-<id> at main."""
        worktree = root / f"main/.claude/worktrees/agent-{agent}"
        run("git", "worktree", "add", "-q", "-b", f"worktree-agent-{agent}", str(worktree))
        return worktree

    def test_a_removed_detached_worktree_frees_the_branch_it_left_in_the_same_run(self):
        # A detached worktree at main, idle for over a day, goes; the branch it left, at main and now
        # checked out nowhere, goes in the same run, and a dry run lists both and removes neither.
        root, run, tidy = scratch_clone(self)
        worktree = self.agent_worktree(root, run, "a1")
        run("git", "checkout", "-q", "--detach", "HEAD", cwd=worktree)
        old = time.time() - 2 * 86400
        git_dir = Path(run("git", "rev-parse", "--absolute-git-dir", cwd=worktree))
        for name in ("HEAD", "index", "logs/HEAD"):
            os.utime(git_dir / name, (old, old))
        for args in (["--dry-run"], []):
            with self.subTest(args=args):
                out = tidy(*args)
                self.assertIn(f"tidy: git worktree remove {worktree}", out)
                self.assertIn("tidy: git branch -D worktree-agent-a1", out)
                self.assertEqual(worktree.exists(), bool(args))
        self.assertEqual(run("git", "branch", "--list", "worktree-agent-a1"), "")

    def test_a_verifiers_worktree_left_detached_at_a_merged_prs_commit_goes(self):
        # A verifier checks the PR's commit out detached in its own worktree and commits a test there;
        # the PR's head, merged under the card's branch, has a builder commit on top. A worktree
        # detached at a commit no merged PR has stays, as does the branch it left.
        root, run, tidy = scratch_clone(self)
        verifier = self.agent_worktree(root, run, "v1")
        run("git", "checkout", "-q", "--detach", "HEAD", cwd=verifier)
        run("git", "commit", "-q", "--allow-empty", "-m", "verifier test", cwd=verifier)
        tip = run("git", "rev-parse", "HEAD", cwd=verifier)
        head = run("git", "commit-tree", f"{tip}^{{tree}}", "-p", tip, "-m", "builder fix")
        unmerged = self.agent_worktree(root, run, "w2")
        run("git", "checkout", "-q", "--detach", "HEAD", cwd=unmerged)
        run("git", "commit", "-q", "--allow-empty", "-m", "unpushed", cwd=unmerged)
        (root / "merged").write_text(f"night-card {head} 7\n")
        out = tidy()
        self.assertFalse(verifier.exists())
        self.assertEqual(run("git", "branch", "--list", "worktree-agent-v1"), "")
        self.assertTrue(unmerged.exists())
        self.assertEqual(run("git", "branch", "--list", "worktree-agent-w2"), "worktree-agent-w2")
        self.assertNotIn("agent-w2", out)

    def test_a_fresh_worktree_detached_at_main_stays_though_a_merged_prs_head_contains_it(self):
        # A PR must be up to date with main to merge, so each merged PR's head contains the main it
        # was merged onto. A worktree of main added to compare with, detached at a main commit, is
        # therefore in a merged PR's head; it goes by the day rule, not as a merged PR's commit.
        root, run, tidy = scratch_clone(self)
        head = run("git", "commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "a merged PR's head on main")
        (root / "merged").write_text(f"other-card {head} 8\n")
        compare = root / "main/.claude/worktrees/agent-v2-main"
        run("git", "worktree", "add", "-q", "--detach", str(compare), "origin/main")
        for args in (["--dry-run"], []):
            with self.subTest(args=args):
                self.assertNotIn("agent-v2-main", tidy(*args))
        self.assertTrue(compare.exists())

    def test_a_detached_worktree_with_work_past_a_merged_prs_head_stays(self):
        # A merged PR's head containing a detached worktree's commit says the commit landed, not what
        # was made after it: a commit on top of the merged head, or a file not committed there, keeps
        # the worktree and the branch it left, in a dry run too.
        root, run, tidy = scratch_clone(self)
        head = run("git", "commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "merged head")
        (root / "merged").write_text(f"night-card {head} 7\n")
        ahead = self.agent_worktree(root, run, "c1")
        run("git", "checkout", "-q", "--detach", head, cwd=ahead)
        run("git", "commit", "-q", "--allow-empty", "-m", "a test made after the merge", cwd=ahead)
        dirty = self.agent_worktree(root, run, "d1")
        run("git", "checkout", "-q", "--detach", head, cwd=dirty)
        (dirty / "NewTests.swift").write_text("// not committed\n")
        for args in (["--dry-run"], []):
            with self.subTest(args=args):
                out = tidy(*args)
                self.assertNotIn("agent-c1", out)
                self.assertNotIn("agent-d1", out)
        self.assertTrue(ahead.exists())
        self.assertTrue((dirty / "NewTests.swift").exists())
        self.assertEqual(run("git", "branch", "--list", "worktree-agent-c1", "worktree-agent-d1"),
                         "worktree-agent-c1\n  worktree-agent-d1")

    def recorded_simulator(self, root, name):
        """A record of worktree <name>'s simulator, and a stand-in xcrun that lists that one simulator
        and records each call in <root>/xcrun-calls. Returns the records folder."""
        records = root / "main/.git/plusplus-simulators"
        records.mkdir()
        (records / name).write_text("")
        devices = {"devices": {"iOS": [{"name": f"PlusPlus {name}", "udid": "UDID-1", "state": "Shutdown"}]}}
        runtimes = {"runtimes": [{"platform": "iOS", "isAvailable": True, "version": "1.0", "supportedDeviceTypes": [
            {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17"}]}]}
        (root / "bin/xcrun").write_text(f"""#!/bin/bash
echo "$*" >> '{root / "xcrun-calls"}'
case "$*" in
    "--sdk iphonesimulator --show-sdk-version") echo 1.0 ;;
    "simctl list --json runtimes") echo '{json.dumps(runtimes)}' ;;
    "simctl runtime list -j") echo '{{}}' ;;
    "simctl list devices"*) echo '{json.dumps(devices)}' ;;
esac
""")
        (root / "bin/xcrun").chmod(0o755)
        return records

    def test_a_locked_worktree_stays_and_the_run_goes_on_to_the_simulators(self):
        # A live agent's isolation worktree is locked, and `git worktree remove` refuses it; on
        # 2026-11-13 that failure ended a night's tidy before it deleted a scratch simulator.
        worktree, run, tidy = self.finished_worktree()
        root = worktree.parents[3]
        run("git", "worktree", "lock", "--reason", "claude agent agent-x1", str(worktree))
        records = self.recorded_simulator(root, "gone-card")
        for args in (["--dry-run"], []):
            with self.subTest(args=args):
                out = tidy(*args)
                self.assertIn(f"tidy: kept {worktree}: finished, but locked, so an agent holds it", out)
                self.assertNotIn("git worktree remove", out)
                self.assertIn('tidy: delete simulator "PlusPlus gone-card"', out)
        self.assertTrue(worktree.exists())
        self.assertIn("done-card", run("git", "branch", "--list", "done-card"))
        self.assertIn("simctl delete UDID-1", (root / "xcrun-calls").read_text().splitlines())
        self.assertEqual(list(records.iterdir()), [])

    def test_an_agents_cleanup_removes_its_worktree_and_tidy_deletes_its_simulator(self):
        # The builder's and verifier's cleanup: `git worktree remove` from a shell still inside the
        # worktree, then the main checkout's tidy. xcrun is a stand-in that lists one simulator, the
        # worktree's, and records each call.
        worktree, run, tidy = self.finished_worktree()
        root = worktree.parents[3]
        records = self.recorded_simulator(root, "done-card")
        run("git", "worktree", "remove", str(worktree), cwd=worktree)
        self.assertFalse(worktree.exists())
        out = tidy()
        self.assertIn('tidy: delete simulator "PlusPlus done-card"', out)
        self.assertIn("simctl delete UDID-1", (root / "xcrun-calls").read_text().splitlines())
        self.assertEqual(list(records.iterdir()), [])
        self.assertEqual(run("git", "branch", "--list", "done-card"), "")


class TidyFetch(unittest.TestCase):
    """scripts/tidy.sh fetches from GitHub over HTTPS whatever the clone's remote, so a session with
    no SSH key can run it. Nothing leaves the machine: the clone's proxy is a closed local port, so
    the fetch fails there, naming the address it asked for, and ssh is a stand-in that records a call."""

    def test_an_ssh_remote_is_fetched_over_https_and_ssh_never_runs(self):
        for remote in ("git@github.com:scratch/repo.git", "ssh://git@github.com/scratch/repo.git"):
            with self.subTest(remote=remote):
                root, run, _ = scratch_clone(self)
                run("git", "remote", "set-url", "origin", remote)
                run("git", "config", "http.proxy", "http://127.0.0.1:1")
                ssh = root / "bin/ssh"
                ssh.write_text(f"#!/bin/bash\necho called >> '{root / 'ssh-calls'}'\nexit 255\n")
                ssh.chmod(0o755)
                env = {**os.environ, "PATH": f"{root / 'bin'}:{os.environ['PATH']}", "GIT_SSH_COMMAND": str(ssh)}
                out = subprocess.run([str(root / "main/scripts/tidy.sh"), "--dry-run"], cwd=root / "main",
                                     env=env, capture_output=True, text=True)
                self.assertFalse((root / "ssh-calls").exists(), out.stderr)
                self.assertIn("'https://github.com/scratch/repo.git/'", out.stderr)
                self.assertIn("127.0.0.1", out.stderr)


class Reverify(unittest.TestCase):
    """Ways around the gates the re-verify found (2026-10-28) that no test above covers."""

    def test_a_merge_run_through_another_program_is_denied(self):
        # Guardrail 3: only the runner arms auto-merge. Each of these runs `gh pr merge` from a line
        # the hook can read whole, without a script file it would have to open.
        for command in ["python3 -c \"import os; os.system('gh pr merge 7 --auto')\"",
                        "node -e \"require('child_process').execSync('gh pr merge 7')\"",
                        "perl -e 'system(\"gh pr merge 7\")'",
                        "echo 'gh pr merge 7' | sh", "sh <<< 'gh pr merge 7'", "cat <<EOF | bash\ngh pr merge 7\nEOF",
                        "m=merge; gh pr $m 7", "gh pr $'merge' 7", "gh pr $(echo merge) 7", "gh pr merg* 7"]:
            self.assertIsNotNone(decide(command, app=False), command)

    def test_an_xcode_cloud_run_through_the_raw_api_is_denied(self):
        # The card's Xcode Cloud guardrail: no agent starts a run but by a counted push.
        for command in ["asc api POST /v1/ciBuildRuns --confirm --body-file run.json",
                        "asc api PATCH /v1/ciWorkflows/x --confirm --body '{}'"]:
            self.assertIsNotNone(decide(command, app=False), command)
        self.assertIsNone(decide("asc api GET /v1/ciProducts", app=False))

    def test_the_nights_own_gates_cannot_be_edited(self):
        # The hook and pre-push hook run the main checkout's runner and read the night's folder;
        # a card that edits them turns its own gates off.
        night = nightly.ROOT / ".build/retro/2026-10-28"
        for path in [nightly.ROOT / "scripts/nightly-tooling.py", night / "state.json", night / "git-hooks/pre-push",
                     Path.home() / ".config/gh/config.yml"]:
            self.assertIsNotNone(decide(tool="Write", path=str(path)), path)
        self.assertIsNotNone(decide(f"sed -i '' s/exit/pass/ {nightly.ROOT}/scripts/nightly-tooling.py", app=False))

    def test_a_pr_left_for_the_maintainer_has_auto_merge_off(self):
        # A protected PR stays unmerged: if anything armed auto-merge during the card's run, the
        # runner turns it off, as it does for a parked one.
        case = Decide("run")
        case.setUp()
        try:
            pr = case.pr(lambda: case.write(".swiftlint.yml", "y\n"))
            self.assertEqual(case.settle(pr), "waiting")
            self.assertIn("gh pr merge 7 --disable-auto", case.calls)
        finally:
            case.doCleanups()

    def test_a_budget_read_that_times_out_denies_the_push(self):
        # The hook's own reads give up before Claude Code's hook timeout, which would run the call.
        night = night_folder(self)
        root = night.dir.parents[3]
        git = lambda *a: subprocess.run(["git", "-c", "user.email=t@example.com", "-c", "user.name=t", *a],  # noqa: E731
                                        cwd=root / "w", check=True, capture_output=True)
        (root / "w/App").mkdir(parents=True)
        git("init", "-q", "-b", "main")
        git("commit", "-q", "--allow-empty", "-m", "base")
        git("update-ref", "refs/remotes/origin/main", "HEAD")
        (root / "w/App/X.swift").write_text("x\n")
        git("add", "-A")
        git("commit", "-qm", "card")
        (root / "bin").mkdir()
        (root / "bin/asc").write_text("#!/bin/sh\nsleep 30\n")
        (root / "bin/asc").chmod(0o755)
        open_card(night, worktree=root / "w", stop=datetime.now().astimezone() + timedelta(hours=1))
        saved = nightly.READ_TIMEOUT, os.environ["PATH"], sys.stdin
        self.addCleanup(lambda: (setattr(nightly, "READ_TIMEOUT", saved[0]), os.environ.__setitem__("PATH", saved[1]),
                                 setattr(sys, "stdin", saved[2])))
        nightly.READ_TIMEOUT, os.environ["PATH"] = 1, f"{root / 'bin'}:{saved[1]}"
        sys.stdin = io.StringIO(hook_input("git push", cwd=root / "w"))
        start = time.monotonic()
        with self.assertRaises(SystemExit) as exit_, contextlib.redirect_stderr(io.StringIO()) as err:
            nightly.hook(night.dir)
        self.assertEqual(exit_.exception.code, 2)
        self.assertIn("TimeoutExpired", err.getvalue())
        self.assertLess(time.monotonic() - start, 10)


class AutoMergeOff(unittest.TestCase):
    """Only the night's own merge merges: every other PR from the night's branches ends with
    auto-merge off, and a merge the night didn't arm ends the cards at the top of the digest."""

    def setUp(self):
        self.night = night_folder(self)
        self.calls = []
        stub(self, sh=lambda *a, **k: self.calls.append(" ".join(map(str, a))) or "")

    def test_every_pr_from_the_nights_branches_ends_with_auto_merge_off(self):
        open_card(self.night, branch="night-card")
        open_card(self.night, item="PVTI_2", branch="night-other")
        # A day session's PR opened tonight, armed by its own session, keeps its auto-merge.
        stub(self, gh_json=lambda *a: [
            {"number": 7, "autoMergeRequest": {"mergeMethod": "SQUASH"}, "headRefName": "night-card"},
            {"number": 9, "autoMergeRequest": {"mergeMethod": "SQUASH"}, "headRefName": "night-other"},
            {"number": 203, "autoMergeRequest": {"mergeMethod": "SQUASH"}, "headRefName": "save-every-change"},
            {"number": 8, "autoMergeRequest": None, "headRefName": "night-card"},
            {"number": 10, "autoMergeRequest": {"mergeMethod": "SQUASH"}, "headRefName": "fix-thing"}])
        (self.night.dir / "pushed").write_text("fix-thing\n")  # as the card worktree's pre-push hook left it
        nightly.disarm(self.night)
        self.assertEqual([c for c in self.calls if "--disable-auto" in c],
                         ["gh pr merge 7 --disable-auto", "gh pr merge 9 --disable-auto", "gh pr merge 10 --disable-auto"])

    def test_no_branch_of_the_nights_reads_nothing(self):
        stub(self, gh_json=lambda *a: self.fail("read the PRs"))
        nightly.disarm(self.night)

    def test_auto_merge_that_stays_on_fails(self):
        stub(self, sh=lambda *a, **k: "true\n" if "view" in a else "")
        with self.assertRaisesRegex(RuntimeError, "still on for #7"):
            nightly.disable_auto(7)

    def test_a_merge_the_night_did_not_arm_ends_the_cards_at_the_top_of_the_digest(self):
        open_card(self.night, branch="night-card-0")
        self.night.set_state(phase=None)
        merged = [{"number": 50, "title": "Sneaky", "mergedBy": {"login": "me"}, "mergeCommit": {"oid": "b" * 40},
                   "headRefName": "night-card-0"}]
        stub(self, gh_json=lambda *a: merged)
        nightly.audit(self.night)
        self.assertIn("#50", self.night.state()["stopped"])
        self.assertEqual(nightly.refusal(self.night, NIGHT, SESSION), self.night.state()["stopped"])
        digest = nightly.night_digest(self.night.dir)
        self.assertTrue(digest[1].startswith("Merged without the night's gates: #50 Sneaky, by me"), digest[1])
        self.assertIn("git revert bbbbbbb", digest[1])

    def test_a_day_sessions_merge_tonight_is_one_plain_line_and_the_night_goes_on(self):
        # The maintainer's session opened and merged it during the night, as the same account; and
        # the night's own merge, which it armed, is no finding either.
        open_card(self.night, branch="night-card")
        self.night.update("PVTI_1", decision="merged", pr=7, pr_title="Card", armed_at=NIGHT.isoformat(),
                          merge="c" * 40, files=["scripts/a.py"], proof="verifier record at abc1234, PR check passed")
        stub(self, gh_json=lambda *a: [
            {"number": 7, "title": "Card", "headRefName": "night-card"},
            {"number": 203, "title": "Save every change", "mergedBy": {"login": "me"},
             "mergeCommit": {"oid": "b" * 40}, "headRefName": "save-every-change"}])
        nightly.audit(self.night)
        self.assertNotIn("stopped", self.night.state())
        digest = nightly.night_digest(self.night.dir)
        self.assertFalse([line for line in digest if line.startswith("Merged without")], digest)
        self.assertIn("Also merged tonight, not by a card: #203 Save every change", digest)

    def test_a_merge_search_does_not_list_yet_is_still_found(self):
        open_card(self.night)
        self.night.update("PVTI_1", decision="unarmed", pr=8, pr_title="Card")
        stub(self, gh_json=lambda *a: [])
        nightly.audit(self.night)
        self.assertIn("#8", self.night.state()["stopped"])
        self.assertTrue(nightly.night_digest(self.night.dir)[1].startswith("Merged without the night's gates: #8 Card"))


class WritesStayInTheWorktree(unittest.TestCase):
    """A card writes only in its worktree and .slices/, and names none of the night's own files."""

    def test_an_edit_outside_the_worktree_and_slices_is_denied(self):
        for path in ["/tmp/x", str(Path.home() / ".zshrc"), str(nightly.ROOT / "App/Root.swift"),
                     str(WORKTREE / ".claude/settings.json"), str(WORKTREE / "../other/x")]:
            self.assertIn("only in its worktree", decide(tool="Edit", path=path) or "", path)
        for path in [str(WORKTREE / "scripts/x.py"), "scripts/x.py", str(nightly.ROOT / ".slices/night-card-handoff.md"),
                     str(WORKTREE / ".claude/skills/x/SKILL.md")]:
            self.assertIsNone(decide(tool="Write", path=path), path)

    def test_a_command_naming_the_nights_files_is_denied(self):
        for command in ["cat >> ~/.config/gh/config.yml <<EOF\naliases: {}\nEOF", "echo x > $HOME/.gitconfig",
                        f"cp x {NIGHT_DIR}/state.json", "cd .. && rm -rf night-card", "cd ../../.. && git config x y",
                        f"bash -c 'echo x > {nightly.ROOT}/.git/config'", "ln -s ~/.claude/settings.json s",
                        f"git -C {nightly.ROOT} commit -am x", "tee ${HOME}/.asc/config.json"]:
            self.assertIn("night's own files", decide(command, app=False) or "", command)

    def test_ordinary_commands_are_allowed(self):
        for command in ["git push -u origin night-card", "scripts/test.sh 2>&1 | tail -5", "ls > /dev/null",
                        "/usr/bin/env python3 scripts/x.py", f"cat {nightly.ROOT}/.slices/night-card-plan.md",
                        "echo x > /tmp/y", "git diff origin/main...HEAD", "ls ~", 'git commit -m "Read ~/.config/gh"']:
            self.assertIsNone(decide(command, app=False), command)

    def test_relative_paths_resolve_from_the_calls_directory(self):
        self.assertIsNotNone(decide("echo x > scripts/nightly-tooling.py", app=False, cwd=nightly.ROOT))
        self.assertIsNone(decide("echo x > scripts/nightly-tooling.py", app=False, cwd=WORKTREE))

    def test_a_symlink_out_of_the_worktree_is_followed(self):
        with tempfile.TemporaryDirectory() as root:
            worktree = Path(root, "main/.claude/worktrees/w")
            worktree.mkdir(parents=True)
            Path(root, "main/scripts").mkdir()
            (worktree / "out").symlink_to(Path(root, "main/scripts"))
            self.assertFalse(nightly.Fence(worktree, Path(root, "main"), Path(root, "night")).may_write(worktree / "out/x"))

    def test_another_tools_paths_are_checked_too(self):
        self.assertIsNotNone(decide(tool="mcp__xcode__XcodeWrite", inputs=[str(nightly.ROOT / "App/A.swift"), "x"]))
        self.assertIsNone(decide(tool="mcp__xcode__XcodeWrite", inputs=[str(WORKTREE / "App/A.swift")]))

    def test_a_relative_path_after_cd_into_the_worktree_is_the_worktrees(self):
        # The lead's calls start in the main checkout, so its subagents work as `cd <worktree> && ...`.
        for command in [f"cd {WORKTREE} && echo x > scripts/x.py", f"cd {WORKTREE}; sed -i '' s/a/b/ scripts/x.py"]:
            self.assertIsNone(decide(command, app=False, cwd=nightly.ROOT), command)
        for command in ["echo x > scripts/x.py", f"cd {WORKTREE} && cd $DIR && echo x > scripts/x.py",
                        f"cd {WORKTREE} && cd - && echo x > scripts/x.py", f"cd {WORKTREE}/.. && echo x > s"]:
            self.assertIsNotNone(decide(command, app=False, cwd=nightly.ROOT), command)


class GuardPassesOtherSessions(unittest.TestCase):
    """.claude/hooks/night-guard.sh, which every session's calls pass through: only the night's
    session's reach the guard."""

    def setUp(self):
        self.root = Path(os.path.realpath(tempfile.mkdtemp()))
        self.addCleanup(shutil.rmtree, self.root, True)
        (self.root / "scripts").mkdir()
        # A guard that denies whatever it is handed, so a call that reaches it shows.
        (self.root / "scripts/nightly-tooling.py").write_text("import sys\nprint('reached', file=sys.stderr)\n"
                                                              "sys.exit(2)\n")
        subprocess.run(["git", "init", "-q", "-b", "main", str(self.root)], check=True)

    def guard(self, stdin, project=None):
        script = SCRIPTS.parent / ".claude/hooks/night-guard.sh"
        return subprocess.run([str(script)], input=stdin, capture_output=True, text=True,
                              env={**os.environ, "CLAUDE_PROJECT_DIR": str(project or self.root)})

    def test_a_session_in_a_worktree_of_its_own_meets_the_main_checkouts_night(self):
        git = ["git", "-C", str(self.root), "-c", "user.email=t@example.com", "-c", "user.name=t"]
        subprocess.run(git + ["add", "-A"], check=True)
        subprocess.run(git + ["commit", "-qm", "base"], check=True)
        worktree = self.root / ".claude/worktrees/session"
        subprocess.run(git + ["worktree", "add", "-q", str(worktree)], check=True)
        (worktree / "scripts/nightly-tooling.py").write_text("import sys\nprint(sys.argv[2], file=sys.stderr)\n"
                                                             "sys.exit(2)\n")
        self.night("2026-10-28")
        self.assertEqual(self.guard(hook_input(session="day-session"), worktree).returncode, 0)
        result = self.guard(hook_input(), worktree)
        self.assertEqual((result.returncode, result.stderr), (2, f"{self.root}/.build/retro/2026-10-28\n"))

    def test_outside_git_every_call_passes(self):
        shutil.rmtree(self.root / ".git")
        self.night("2026-10-28")
        self.assertEqual(self.guard(hook_input()).returncode, 0)

    def night(self, date, session=SESSION):
        folder = self.root / ".build/retro" / date
        folder.mkdir(parents=True)
        if session is not None:
            (folder / "session").write_text(session + "\n")

    def test_no_night_folder_passes(self):
        self.assertEqual(self.guard(hook_input()).returncode, 0)

    def test_another_sessions_call_passes_and_the_nights_reaches_the_guard(self):
        self.night("2026-10-28")
        self.assertEqual(self.guard(hook_input(session="day-session")).returncode, 0)
        result = self.guard(hook_input())
        self.assertEqual((result.returncode, result.stderr), (2, "reached\n"))

    def test_a_guard_that_fails_any_other_way_denies(self):
        self.night("2026-10-28")
        (self.root / "scripts/nightly-tooling.py").write_text("raise SystemExit(1)\n")
        self.assertEqual(self.guard(hook_input()).returncode, 2)

    def test_only_the_newest_nights_session_counts(self):
        self.night("2026-10-27", session="old-night")
        self.night("2026-10-28")
        self.assertEqual(self.guard(hook_input(session="old-night")).returncode, 0)
        self.assertEqual(self.guard(hook_input()).returncode, 2)

    def test_a_night_with_no_session_recorded_passes(self):
        self.night("2026-10-28", session=None)
        self.assertEqual(self.guard(hook_input()).returncode, 0)
        (self.root / ".build/retro/2026-10-28/session").write_text("")
        self.assertEqual(self.guard(hook_input()).returncode, 0)


class NightFromAWorktree(unittest.TestCase):
    """A session the app starts in a worktree of its own still finds the main checkout's night."""

    def test_night_prints_the_main_checkouts_folder_and_script(self):
        root = Path(os.path.realpath(tempfile.mkdtemp()))
        self.addCleanup(shutil.rmtree, root, True)
        (root / "scripts").mkdir()
        for name in ("nightly-tooling.py", "xcresult.py"):
            shutil.copy(SCRIPTS / name, root / "scripts" / name)
        git = ["git", "-C", str(root), "-c", "user.email=t@example.com", "-c", "user.name=t"]
        subprocess.run(["git", "init", "-q", "-b", "main", str(root)], check=True)
        subprocess.run(git + ["add", "-A"], check=True)
        subprocess.run(git + ["commit", "-qm", "base"], check=True)
        worktree = root / ".claude/worktrees/session"
        subprocess.run(git + ["worktree", "add", "-q", str(worktree)], check=True)
        result = subprocess.run([sys.executable, str(worktree / "scripts/nightly-tooling.py"), "night"], cwd=worktree,
                                capture_output=True, text=True)
        today = datetime.now().astimezone().strftime("%Y-%m-%d")
        self.assertEqual((result.returncode, result.stdout),
                         (0, f"{root}/.build/retro/{today}\n{root}/scripts/nightly-tooling.py\n"), result.stderr)


class GuardPhases(unittest.TestCase):
    """What the guard allows the night's session in each phase, through hook_check."""

    def setUp(self):
        self.night = night_folder(self)
        self.main = self.night.dir.parents[2]
        self.worktree = self.main / ".claude/worktrees/night-card"
        self.worktree.mkdir(parents=True)
        self.night_script = f"{self.main}/scripts/nightly-tooling.py"

    def check(self, command="ls", tool="Bash", agent=None, cwd=None, **tool_input):
        text = hook_input(command, tool, agent=agent, cwd=cwd or self.main, **tool_input)
        return nightly.hook_check(self.night.dir, text)

    def test_another_session_whose_input_names_the_id_passes_and_is_not_recorded(self):
        open_card(self.night, worktree=self.worktree)
        text = hook_input(f"gh pr merge 7 # {SESSION}", session="day-session")
        self.assertIsNone(nightly.hook_check(self.night.dir, text))
        self.assertEqual(self.night.seen(), [["none", "lead"]])

    def test_each_phase_and_caller_is_recorded_once(self):
        open_card(self.night, worktree=self.worktree, stop=datetime.now().astimezone() + timedelta(hours=1))
        for agent in (None, "builder", "builder", "verifier"):
            self.check(agent=agent)
        self.assertEqual(self.night.seen(), [["none", "lead"], ["card PVTI_1", "lead"], ["card PVTI_1", "builder"],
                                             ["card PVTI_1", "verifier"]])

    def test_a_card_phase_holds_the_cards_gates(self):
        open_card(self.night, worktree=self.worktree, stop=datetime.now().astimezone() + timedelta(hours=1))
        self.assertIn("Never merge", self.check("gh pr merge 7 --squash", agent="builder"))
        self.assertIsNotNone(self.check(tool="Edit", file_path=str(self.main / "App/Root.swift"), agent="builder"))
        self.assertIsNone(self.check(tool="Edit", file_path=str(self.worktree / "App/Root.swift"), agent="builder"))

    def test_the_leads_closing_commands_pass_at_any_hour_and_nothing_else_past_last_call(self):
        open_card(self.night, worktree=self.worktree, stop=datetime.now().astimezone() - timedelta(minutes=46))
        for command in [f"{self.night_script} decide {self.night.dir} PVTI_1 'PR #7'",
                        f"/usr/bin/env python3 {self.night_script} digest {self.night.dir}",
                        f"{self.night_script} outcome {self.night.dir} ran"]:
            self.assertIsNone(self.check(command), command)
        self.assertIn("only the night's own", self.check("ls"))
        self.assertIn("only the night's own", self.check(f"{self.night_script} decide x PVTI_1", agent="builder"))
        for command in [f"{self.night_script} decide x PVTI_1 && gh pr merge 7", f"{self.night_script} next x",
                        f"{self.worktree}/scripts/nightly-tooling.py decide x PVTI_1"]:
            self.assertIn("only the night's own", self.check(command), command)

    def test_the_review_writes_only_its_report(self):
        reports = self.main / ".slices/review-setup"
        deadline = datetime.now().astimezone() + timedelta(minutes=30)
        self.night.set_state(phase={"kind": "review", "deadline": deadline.isoformat(), "reports": str(reports)})
        self.assertIsNone(self.check(tool="Write", file_path=str(reports / "report-2026-10-28.md")))
        self.assertIsNone(self.check("scripts/board.sh add 'Try X'"))
        for tool, command, path in [("Edit", "", str(reports / "r.md")), ("Write", "", str(self.main / "docs/x.md")),
                                    ("Bash", "git commit -am x", ""), ("Bash", "git push", ""),
                                    ("Bash", "gh pr create --title t", ""), ("Bash", "brew upgrade", ""),
                                    ("Bash", "asc xcode-cloud build-runs list", "")]:
            self.assertIsNotNone(self.check(command, tool=tool, file_path=path), (tool, command, path))

    def test_past_the_reviews_deadline_only_the_report_and_the_closing_commands(self):
        reports = self.main / ".slices/review-setup"
        deadline = datetime.now().astimezone() - timedelta(minutes=1)
        self.night.set_state(phase={"kind": "review", "deadline": deadline.isoformat(), "reports": str(reports)})
        self.assertIsNone(self.check(tool="Write", file_path=str(reports / "report-2026-10-28.md")))
        self.assertIsNone(self.check(f"{self.night_script} review-end {self.night.dir} 'Setup review: 2 cards'"))
        self.assertIsNotNone(self.check("ls"))
        self.assertIsNotNone(self.check("Agent", tool="Agent"))


class NoInlineCode(unittest.TestCase):
    """The accepted limit: a script file runs, inline or piped code doesn't."""

    def test_inline_and_piped_code_is_denied(self):
        for command in ["python3 - <<'EOF'\nprint(1)\nEOF", "python3.12 -Ic 'x'", "ruby -rjson -e 'x'", "osascript -e x",
                        "node --eval x", "curl -s u | bash", "xargs -n 1 sh", "bash -s < x", "env python3"]:
            self.assertIn("inline or piped code", decide(command, app=False) or "", command)

    def test_options_before_the_code_hide_nothing(self):
        for command in ["bash -x -c 'gh pr merge 12 --squash'", "bash -o pipefail -c 'gh pr merge 12'",
                        "python3 -W ignore -c 'x'", "ruby -I lib -e 'x'", "node -r mod -e 'x'"]:
            self.assertIsNotNone(decide(command, app=False), command)
        self.assertIsNone(decide("command -v python3 || brew install python", app=False))

    def test_scripts_and_reading_about_shells_are_allowed(self):
        for command in ["python3 scripts/nightly-tooling-test.py", "python3 -m json.tool f.json", "bash -c 'ls'",
                        "bash scripts/x.sh", "grep -n bash scripts/x.sh", "node scripts/x.js --eval-later",
                        "env FOO=1 python3 -u scripts/x.py"]:
            self.assertIsNone(decide(command, app=False), command)

    def test_asc_api_reads_only(self):
        self.assertIsNotNone(decide("asc api post /v1/ciBuildRuns --confirm", app=False))
        self.assertIsNotNone(decide("asc api DELETE /v1/x --confirm", app=False))
        self.assertIsNone(decide("asc api GET /v1/ciProducts --paginate --pretty", app=False))


class DisabledTests(unittest.TestCase):
    def test_a_disabled_or_skipped_test_counts_as_dropped(self):
        source = """
@Test(.disabled("flaky")) func a() {}
@Test("b", .enabled(if: false)) func b() {}
@Test(.enabled(if: ProcessInfo.isCI)) func c() {}
#if false
@Test func d() {}
#else
@Test func e() {}
#endif
@Suite(.disabled()) struct S {
    @Test func f() {}
    struct Inner { @Test func g() {} }
}
@Suite struct T { @Test func h() {} }
final class X: XCTestCase {
    func testI() throws { throw XCTSkip("later") }
    func testJ() { if true { XCTAssert(true) } }
}
"""
        self.assertEqual(nightly.count_tests(source), 4)  # c, e, h, and testJ
        self.assertEqual(nightly.count_tests('@Test(.tags(.functional), .disabled("x")) func a() {}'), 0)


class Lesser(unittest.TestCase):
    def test_reading_about_git_hooks_is_allowed_and_turning_them_off_is_not(self):
        for command in ["grep -n hooksPath scripts/x.py", "env | grep GIT_CONFIG"]:
            self.assertIsNone(decide(command, app=False), command)
        for command in ["env -i git push", "unset GIT_CONFIG_COUNT", "git config alias.p 'push --no-verify'",
                        "git push --no-verif", "find . -maxdepth 0 -exec git push --no-verify ;", "export GIT_CONFIG_COUNT=0",
                        "git config core.hooksPath x"]:
            self.assertIn("git hooks stay on", decide(command, app=False) or "", command)

if __name__ == "__main__":
    unittest.main()
