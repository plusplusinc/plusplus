#!/usr/bin/env python3
"""The nightly runner's gates against fixtures: no network, no board, no claude.

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
from datetime import datetime, timedelta
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent

# A card's claude runs with the night's pre-push hook in GIT_CONFIG_*, which refused this file's
# pushes to its scratch repos when a card ran the tests (#150). The tests' own git starts without
# it; a test of the hook adds it back through Night.git_env().
for name in [name for name in os.environ if name.startswith("GIT_CONFIG_")]:
    del os.environ[name]

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
        self.assertTrue(nightly.is_uncapped(info(week_resets=resets_at_seven), NIGHT, STOP))
        self.assertFalse(nightly.is_uncapped(info(week_resets=resets_at_seven + 0.1), NIGHT, STOP))
        other = {"seven_day_opus": {"utilization": 0, "resetsAt": at(50), "status": "allowed"}}
        self.assertFalse(nightly.is_uncapped(info(week_resets=1, **other), NIGHT, STOP))
        self.assertFalse(nightly.is_uncapped(None, NIGHT, STOP))

    def test_a_weekly_reset_already_past_is_a_new_week_not_an_uncapped_night(self):
        self.assertFalse(nightly.is_uncapped(info(week_resets=-0.5), NIGHT, STOP))

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

    def night(self, prs, names):
        cards = [(f"PVTI_{i}", "Todo", "-", f"card {i}", self.BODY.format(name)) for i, name in enumerate(names)]
        stubs = {"board_rows": lambda: [], "board_cards": lambda rows: cards, "xcode_cloud_runs": lambda: [],
                 "gh_json": lambda *a: prs if a[-1] == "number,files,title" else self.fail(a), "classify": lambda files: "docs",
                 "sh": lambda *a, **k: self.REPO}
        saved = {name: getattr(nightly, name) for name in stubs}
        self.addCleanup(lambda: [setattr(nightly, n, f) for n, f in saved.items()])
        for name, stub in stubs.items():
            setattr(nightly, name, stub)
        night = nightly.Night(tempfile.mkdtemp(), NIGHT, True)
        self.addCleanup(shutil.rmtree, night.dir, True)
        night.start = NIGHT
        with contextlib.redirect_stdout(io.StringIO()):
            card = night.next_card()
        return night, card

    @staticmethod
    def pr(n, title, *files):
        return {"number": n, "title": title, "files": [{"path": f} for f in files]}

    def test_a_retro_prs_markdown_holds_no_card_back(self):
        retro = self.pr(161, "Retro of #150: x", ".claude/rules/testing.md", "docs/pr-check.md")
        night, card = self.night([retro], [".claude/rules/testing.md"])
        self.assertEqual(card[1], "card 0")
        self.assertEqual(night.held, [])

    def test_a_script_or_swift_file_still_holds_a_card_back(self):
        retro = self.pr(161, "Retro of #150: x", ".claude/rules/testing.md", "scripts/nightly-tooling.py")
        slice_ = self.pr(164, "Keep the +1 out", "Packages/Sources/App/Row.swift")
        night, card = self.night([retro, slice_], ["scripts/nightly-tooling.py", "Packages/Sources/App/Row.swift"])
        self.assertIsNone(card)
        self.assertEqual(night.held[0], '"card 0" may touch what #161 (scripts/nightly-tooling.py) changes; '
                                        "merge or close #161 so a night can take it")
        self.assertIn("#164 (Packages/Sources/App/Row.swift)", night.held[1])

    def test_markdown_outside_the_rules_or_in_another_pr_still_holds_a_card_back(self):
        night, card = self.night([self.pr(161, "Retro of #150: x", "CLAUDE.md"),
                                  self.pr(158, "Prune the agent docs", ".claude/rules/testing.md")],
                                 ["CLAUDE.md", ".claude/rules/testing.md"])
        self.assertIsNone(card)
        self.assertIn("#161 (CLAUDE.md)", night.held[0])
        self.assertIn("#158", night.held[1])

    def test_the_held_cards_open_the_digest(self):
        night, _ = self.night([self.pr(164, "Keep the +1 out", "Packages/Sources/App/Row.swift")],
                              ["Packages/Sources/App/Row.swift"])
        night.unchecked.append("x")
        self.assertEqual(night.top_lines(), ["Not checked: x", "Waits on an open PR: " + night.held[0]])


class ClaudeUpdate(unittest.TestCase):
    def note(self, text):
        with tempfile.TemporaryDirectory() as folder:
            if text is not None:
                (Path(folder) / "claude-update.txt").write_text(text + "\n")
            return nightly.update_note(folder)

    def test_a_version_change_is_one_plain_line(self):
        self.assertEqual(self.note("Claude Code 2.1.316 → 2.1.322"), ["Claude Code 2.1.316 → 2.1.322"])

    def test_a_failed_update_is_not_checked(self):
        line = "Claude Code update failed: no network (exit 1); running 2.1.316"
        self.assertEqual(self.note(line), ["Not checked: " + line])

    def test_already_the_latest_or_no_file_says_nothing(self):
        self.assertEqual(self.note("Claude Code 2.1.322, already the latest"), [])
        self.assertEqual(self.note(None), [])

    def test_the_update_opens_the_digest(self):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / "claude-update.txt").write_text("Claude Code 2.1.316 → 2.1.322\n")
            night = nightly.Night(folder, NIGHT, False)
            night.unchecked.append("x")
            self.assertEqual(night.top_lines(), ["Claude Code 2.1.316 → 2.1.322", "Not checked: x"])


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

    def test_a_changed_checkout_stays_and_says_why(self):
        (self.root / "main/README").write_text("edited\n")
        self.assertEqual(self.catch_up(), "base")
        self.assertIn("it has uncommitted changes", (self.night / "main-checkout.txt").read_text())
        self.assertTrue(nightly.checkout_note(self.night)[0].startswith(
            "Not checked: Main checkout not brought up to date: it has uncommitted changes; the night runs "))

    def test_another_branch_stays_and_says_why(self):
        self.git("checkout", "-q", "-b", "side", cwd=self.root / "main")
        self.assertEqual(self.catch_up(), "base")
        self.assertIn("it is on side, not main", (self.night / "main-checkout.txt").read_text())

    def test_no_file_says_nothing(self):
        self.assertEqual(nightly.checkout_note(self.night), [])


class Eligibility(unittest.TestCase):
    BODY = "## Problem\nx\n\nNightly: faster CI; the PR check's time\n\n## Success\nRun it: it passes.\n\n## Plan\n- y\n"

    def test_an_eligible_card(self):
        self.assertIsNone(nightly.eligibility("Todo", "-", self.BODY))

    def test_product_and_unmarked_cards_wait_for_the_day(self):
        self.assertIn("feature", nightly.eligibility("Todo", "Routine screen", self.BODY))
        self.assertIn("Nightly", nightly.eligibility("Todo", "-", self.BODY.replace("Nightly:", "Later:")))
        self.assertIn("Backlog", nightly.eligibility("Backlog", "-", self.BODY))
        self.assertIn("check", nightly.eligibility("Todo", "-", self.BODY.replace("## Success\nRun it: it passes.\n", "")))


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
                 ("PVTI_3", "Todo", "-", "queued", self.PARKED)]
        calls = []
        stubs = {"board_rows": lambda: [c[:4] for c in cards],
                 "board_bodies": lambda rows: [c for c in cards if c[:4] in rows],
                 "gh_json": lambda *a: {"state": states[a[2]]},
                 "board": lambda *a, stdin=None: calls.append(a)}
        saved = {name: getattr(nightly, name) for name in stubs}
        self.addCleanup(lambda: [setattr(nightly, n, f) for n, f in saved.items()])
        for name, stub in stubs.items():
            setattr(nightly, name, stub)
        night = nightly.Night(tempfile.mkdtemp(), NIGHT, dry_run)
        self.addCleanup(shutil.rmtree, night.dir, True)
        with contextlib.redirect_stdout(io.StringIO()):
            night.close_merged()
        return night, calls

    def test_only_a_merged_prs_card_moves(self):
        night, calls = self.close({"150": "MERGED", "156": "OPEN"})
        self.assertEqual(calls, [("status", "PVTI_1", "Done")])
        self.assertEqual(night.closed, ["parked, since #150 merged"])

    def test_a_dry_run_moves_nothing(self):
        self.assertEqual(self.close({"150": "MERGED", "156": "MERGED"}, dry_run=True)[1], [])


class UpdateCards(unittest.TestCase):
    """The card the night adds for a lint tool `scripts/lint-tools.sh outdated` names."""

    OUTDATED = "swiftformat 0.64.4 0.64.5\nswiftlint 0.65.0 0.65.1\n"

    def titles(self, rows):
        return [title for title, _ in nightly.update_cards(self.OUTDATED, rows)]

    def test_each_outdated_tool_gets_an_eligible_card(self):
        cards = nightly.update_cards(self.OUTDATED, [("PVTI_1", "Todo", "-", "Speed up CI")])
        self.assertEqual([t for t, _ in cards], ["Update swiftformat to 0.64.5", "Update swiftlint to 0.65.1"])
        for _, body in cards:
            self.assertIsNone(nightly.eligibility("Todo", "-", body))

    def test_a_card_by_its_title_in_any_status_is_never_duplicated(self):
        self.assertEqual(self.titles([("PVTI_1", "Done", "-", "Update swiftformat to 0.64.5"),
                                      ("PVTI_2", "Backlog", "-", "Update swiftlint to 0.65.1")]), [])

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
        with tempfile.TemporaryDirectory() as folder:
            nightly.Night(folder, NIGHT, False).settings("/w", Path(folder, "s.json"))
            hook = json.loads(Path(folder, "s.json").read_text())["hooks"]["PreToolUse"][0]
        for tool in ("Bash", "Agent", "Edit", "Write", "mcp__xcode__RunAllTests"):
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
        for night in ("2026-11-01", "2026-12-01", "2026-12-02"):
            (retro / night).mkdir()
        (retro / "2026-12-03").mkdir()  # a night with no review
        (retro / "2026-11-01" / nightly.REVIEW_STREAM).touch()
        (retro / "2026-12-01" / nightly.REVIEW_STREAM).touch()
        self.assertEqual(nightly.review_tries(retro, self.FIRST), 1)
        self.assertIsNotNone(nightly.review_due(("2026-11", "27"), self.FIRST.replace(day=2), "27", tries=1))
        (retro / "2026-12-02" / nightly.REVIEW_STREAM).touch()
        self.assertEqual(nightly.review_tries(retro, self.FIRST), 2)
        self.assertIsNone(nightly.review_due(("2026-11", "27"), self.FIRST.replace(day=3), "27", tries=2))

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
        self.assertFalse([c for c in self.calls if "--auto " in c])
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

    def test_a_branch_or_pr_name_already_used_is_never_reused(self):
        self.git("branch", "night-card")
        saved = nightly.gh_json
        self.addCleanup(setattr, nightly, "gh_json", saved)
        nightly.gh_json = lambda *a: [{"headRefName": "night-card-2"}]
        worktree, branch = self.night.paths("Card")
        self.assertEqual((branch, worktree.name), ("night-card-3", "night-card-3"))

    def test_auto_merge_waits_for_the_pr_check_and_only_it(self):
        saved = nightly.gh_json, nightly.time.sleep
        self.addCleanup(lambda: (setattr(nightly, "gh_json", saved[0]), setattr(nightly.time, "sleep", saved[1])))
        nightly.time.sleep = lambda s: None
        views = [{"state": "OPEN", "statusCheckRollup": []},
                 {"state": "OPEN", "statusCheckRollup": [{"name": "Route", "conclusion": "FAILURE"}]},
                 {"state": "MERGED", "mergeCommit": {"oid": "abc"}, "statusCheckRollup": []}]
        nightly.gh_json = lambda *a: views.pop(0)
        self.assertEqual(nightly.Night.wait_merge(self.night, 7), "abc")
        nightly.gh_json = lambda *a: {"state": "OPEN", "statusCheckRollup": [{"name": "PR check", "conclusion": "FAILURE"}]}
        self.assertIsNone(nightly.Night.wait_merge(self.night, 7))

    def test_a_scheme_or_lint_script_change_waits(self):
        for name in ("PlusPlus.xcodeproj/xcshareddata/xcschemes/PlusPlus.xcscheme", "scripts/lint.sh"):
            self.git("checkout", "-q", "main")
            self.git("branch", "-qD", "card") if self.git("branch", "--list", "card") else None
            pr = self.pr(lambda: self.write(name, "exit 0\n"))
            self.assertEqual(self.night.decide("PVTI_1", "Card", pr), "waiting", name)
        self.assertFalse([c for c in self.calls if "--auto " in c])


class Loop(unittest.TestCase):
    """Night.run's card count, with the board, the PRs, and each card's run stubbed."""

    BODY = "## Problem\nx\n\nNightly: faster CI; its time\n\n## Success\nRun it.\n"

    def night(self, results, weekly_resets, take=None, event=None, finish=False, gh=lambda *a: []):
        cards = [(f"PVTI_{i}", "Todo", "-", f"card {i}", self.BODY) for i in range(4)]
        stubs = {"board_rows": lambda: [], "board_cards": lambda rows: cards, "xcode_cloud_runs": lambda: [],
                 "gh_json": gh, "classify": lambda files: "app: x", "sh": lambda *a, **k: "",
                 "test_counts": lambda rev: {}}
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

        night.take = (lambda card, info: take(night, card, info)) if take else taking
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

        def crash(night, card, _):
            night.current = card  # as take() does once the card is In Progress
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

    def test_an_outdated_tool_becomes_the_top_card_and_the_digest_says_so(self):
        calls = []
        saved = nightly.board, nightly.tidy
        self.addCleanup(lambda: (setattr(nightly, "board", saved[0]), setattr(nightly, "tidy", saved[1])))
        nightly.board = lambda *a, stdin=None: calls.append(a) or ("PVTI_new\n" if a[0] == "add" else "")
        nightly.tidy = lambda: None
        # swiftformat's release couldn't be read; swiftlint's line still makes its card.
        outdated = subprocess.CompletedProcess([], 1, "swiftlint 0.65.0 0.65.1\n",
                                               "could not read swiftformat's latest release\n")
        saved_run = nightly.subprocess.run
        self.addCleanup(setattr, nightly.subprocess, "run", saved_run)
        nightly.subprocess.run = lambda *a, **k: outdated
        night = self.night(["merged"] * 4, weekly_resets=100, finish=True)
        self.assertEqual(calls[:2], [("add", "Update swiftlint to 0.65.1"), ("move", "PVTI_new", "top")])
        digest = (night.dir / "digest.md").read_text()
        self.assertIn("Added: Update swiftlint to 0.65.1, at the top of Todo", digest)
        self.assertIn("Not checked: which lint tools have a newer release (could not read swiftformat's", digest)

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
                              NIGHT, STOP, "h", calls.append, fence())
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

    def test_the_pre_push_hook_budgets_what_is_pushed_not_head(self):
        # The app commit goes on its own branch; HEAD stays on a docs-only one.
        self.git("checkout", "-q", "-b", "app")
        Path(self.root / "w/App").mkdir()
        Path(self.root / "w/App/X.swift").write_text("x\n")
        self.git("add", "-A")
        self.git("-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-qm", "app")
        self.git("checkout", "-q", "card")
        (self.night.dir / "state.json").write_text(json.dumps({"start": NIGHT.isoformat()}))  # no hours: fails
        result = subprocess.run(["git", "push", "-q", "origin", "app"], cwd=self.root / "w", env=self.night.git_env(),
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pre-push hook failed", result.stderr)

    def test_a_push_to_pr_media_goes(self):
        # As scripts/pr-media.sh makes it: a commit with no history shared with main. Read
        # through the budget, it has no merge base and would be refused (PR #177's night).
        (self.night.dir / "state.json").write_text(json.dumps({"start": NIGHT.isoformat()}))  # no hours: fails
        blob = subprocess.run(["git", "hash-object", "-w", "--stdin"], cwd=self.root / "w", input="png\n",
                              capture_output=True, text=True, check=True).stdout.strip()
        env = {**os.environ, "GIT_INDEX_FILE": str(self.root / "media-index")}
        subprocess.run(["git", "update-index", "--add", "--cacheinfo", f"100644,{blob},177/x.png"],
                       cwd=self.root / "w", env=env, check=True)
        tree = subprocess.run(["git", "write-tree"], cwd=self.root / "w", env=env, capture_output=True, text=True,
                              check=True).stdout.strip()
        commit = subprocess.run(["git", "-c", "user.email=t@example.com", "-c", "user.name=t", "commit-tree", tree,
                                 "-m", "media"], cwd=self.root / "w", capture_output=True, text=True,
                                check=True).stdout.strip()
        result = subprocess.run(["git", "push", "-q", "origin", f"{commit}:refs/heads/pr-media"], cwd=self.root / "w",
                                env=self.night.git_env(), capture_output=True, text=True)
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
            self.assertFalse(nightly.is_uncapped(info(week_resets=1, seven_day=w), NIGHT, STOP), w)
            self.assertIn("seven_day unreadable", nightly.usage_line(info(seven_day=w)))

    def test_info_that_isnt_an_object_reads_as_no_event(self):
        for value in ["allowed", 3, [1], {"unifiedWindows": "x"}, {"unifiedWindows": [1]}]:
            self.assertEqual(nightly.usage_gate(value, NIGHT, CUTOFF, STOP, False)[0], "stop", value)
            self.assertFalse(nightly.is_uncapped(value, NIGHT, STOP))
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
            saved = nightly.main_checkout
            self.addCleanup(setattr, nightly, "main_checkout", saved)
            nightly.main_checkout = lambda: Path(root)
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


class TidySlices(unittest.TestCase):
    """scripts/tidy.sh's .slices/ cleanup, run whole in a scratch clone with gh and the board faked."""

    ROWS = "PVTI_done  Done\t-\tA\nPVTI_todo  In Progress\t-\tB\n"

    def tidy(self, slices, rows=ROWS, board_fails=False):
        root, run, tidy = scratch_clone(self)
        board = root / "main/scripts/board.sh"
        board.write_text("#!/bin/bash\n" + ("echo 'quota spent' >&2; exit 1\n" if board_fails
                                             else f"[ \"$1\" = list ] && printf '{rows}'\n"))
        board.chmod(0o755)
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

    def test_an_agents_cleanup_removes_its_worktree_and_tidy_deletes_its_simulator(self):
        # The builder's and verifier's cleanup: `git worktree remove` from a shell still inside the
        # worktree, then the main checkout's tidy. xcrun is a stand-in that lists one simulator, the
        # worktree's, and records each call.
        worktree, run, tidy = self.finished_worktree()
        root = worktree.parents[3]
        records = root / "main/.git/plusplus-simulators"
        records.mkdir()
        (records / "done-card").write_text("")
        devices = {"devices": {"iOS": [{"name": "PlusPlus done-card", "udid": "UDID-1", "state": "Shutdown"}]}}
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
            self.assertEqual(case.night.decide("PVTI_1", "Card", pr), "waiting")
            self.assertIn("gh pr merge 7 --disable-auto", case.calls)
        finally:
            case.tearDown()
            case.doCleanups()

    def test_a_budget_read_that_times_out_denies_the_push(self):
        # The hook's own reads give up before Claude Code's hook timeout, which would run the call.
        root = Path(os.path.realpath(tempfile.mkdtemp()))
        self.addCleanup(shutil.rmtree, root, True)
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
        (root / "state.json").write_text(json.dumps({"start": NIGHT.isoformat(), "hours": 1, "handoff": "h",
                                                     "stop": (datetime.now() + timedelta(hours=1)).astimezone().isoformat()}))
        saved = nightly.READ_TIMEOUT, os.environ["PATH"], sys.stdin
        self.addCleanup(lambda: (setattr(nightly, "READ_TIMEOUT", saved[0]), os.environ.__setitem__("PATH", saved[1]),
                                 setattr(sys, "stdin", saved[2])))
        nightly.READ_TIMEOUT, os.environ["PATH"] = 1, f"{root / 'bin'}:{saved[1]}"
        sys.stdin = io.StringIO(json.dumps({"tool_name": "Bash", "tool_input": {"command": "git push"}}))
        start = time.monotonic()
        with self.assertRaises(SystemExit) as exit_, contextlib.redirect_stderr(io.StringIO()) as err:
            nightly.hook(root, root / "w")
        self.assertEqual(exit_.exception.code, 2)
        self.assertIn("TimeoutExpired", err.getvalue())
        self.assertLess(time.monotonic() - start, 10)


class AutoMergeOff(unittest.TestCase):
    """Only the runner's own merge merges: every other PR of the night ends with auto-merge off,
    and a merge the runner didn't arm ends the night at the top of the digest."""

    BODY = Loop.BODY

    def test_every_pr_the_card_opened_ends_with_auto_merge_off(self):
        calls, root = [], Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root, True)

        def gh_json(*args):
            if "--author" in args:  # the card's PRs, both armed during its run
                return [{"number": 7, "autoMergeRequest": {"mergeMethod": "SQUASH"}},
                        {"number": 9, "autoMergeRequest": {"mergeMethod": "SQUASH"}}]
            return [{"number": 7, "title": "Card", "state": "OPEN", "headRefOid": "a" * 40, "body": "",
                     "comments": []}]

        stubs = {"sh": lambda *a, **k: calls.append(" ".join(map(str, a))) or "", "gh_json": gh_json,
                 "board": lambda *a, stdin=None: None}
        saved = {name: getattr(nightly, name) for name in stubs}
        self.addCleanup(lambda: [setattr(nightly, n, f) for n, f in saved.items()])
        for name, stub in stubs.items():
            setattr(nightly, name, stub)
        night = nightly.Night(root / "night", NIGHT, False)
        night.dir.mkdir()
        night.start, night.cards, night.hours = NIGHT, 1, 1.0
        (root / "w").mkdir()
        night.paths = lambda title: (root / "w", "night-card")
        night.command = lambda *a: ["true"]
        self.assertEqual(night.take(("PVTI_1", "Card", ""), info()), "parked")  # no verifier record
        self.assertIn("gh pr merge 7 --disable-auto", calls)
        self.assertIn("gh pr merge 9 --disable-auto", calls)
        self.assertIn("#9", night.waiting[0])

    def test_auto_merge_that_stays_on_ends_the_night(self):
        saved = nightly.sh
        self.addCleanup(setattr, nightly, "sh", saved)
        nightly.sh = lambda *a, **k: "true\n" if "view" in a else ""
        with self.assertRaisesRegex(RuntimeError, "still on for #7"):
            nightly.disable_auto(7)

    def test_a_merge_the_runner_did_not_arm_ends_the_night_at_the_top_of_the_digest(self):
        saved = nightly.tidy
        self.addCleanup(setattr, nightly, "tidy", saved)
        nightly.tidy = lambda: None
        merged = [{"number": 50, "title": "Sneaky", "mergedBy": {"login": "me"}, "mergeCommit": {"oid": "b" * 40}}]
        night = Loop.night(self, ["waiting"] * 4, weekly_resets=100, finish=True,
                           gh=lambda *a: merged if "merged" in a else [])
        self.assertEqual(night.taken, ["card 0"])
        digest = (night.dir / "digest.md").read_text().splitlines()
        self.assertTrue(digest[0].startswith("Merged without the runner: #50 Sneaky, by me"), digest[0])
        self.assertIn("git revert bbbbbbb", digest[0])

    def test_the_runners_own_merge_and_a_day_sessions_are_no_finding(self):
        night = nightly.Night(tempfile.mkdtemp(), NIGHT, False)
        self.addCleanup(shutil.rmtree, night.dir, True)
        night.start, night.armed, night.armed_before = NIGHT, {7}, {3}
        saved = nightly.gh_json
        self.addCleanup(setattr, nightly, "gh_json", saved)
        nightly.gh_json = lambda *a: [{"number": 7, "title": "Card"}, {"number": 3, "title": "Day"}]
        self.assertFalse(night.audit())

    def test_a_merge_search_does_not_list_yet_is_still_found(self):
        night = nightly.Night(tempfile.mkdtemp(), NIGHT, False)
        self.addCleanup(shutil.rmtree, night.dir, True)
        night.start, night.merged_during = NIGHT, [{"number": 8, "title": "Card"}]
        saved = nightly.gh_json
        self.addCleanup(setattr, nightly, "gh_json", saved)
        nightly.gh_json = lambda *a: []
        self.assertTrue(night.audit())
        self.assertEqual(night.top_lines()[0][:32], "Merged without the runner: #8 Ca")


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

    def test_an_agents_own_isolation_worktree_is_writable_for_its_calls(self):
        # The Agent tool makes an isolation worktree in the main checkout's .claude/worktrees/, as
        # agent-<agent id>; a verifier works and commits in its own there. The hook's cwd is the
        # session's, the card's worktree, so the agent's relative paths resolve from its own.
        with tempfile.TemporaryDirectory() as root:
            main = Path(os.path.realpath(root), "main")
            worktrees = main / ".claude/worktrees"
            for name in ("night-card", "agent-a1", "agent-b2"):
                (worktrees / name).mkdir(parents=True)
                (worktrees / name / ".git").write_text(f"gitdir: {main}/.git/worktrees/{name}\n")
            (worktrees / "agent-c3/.git").mkdir(parents=True)  # not a linked worktree

            def fence(agent):
                return nightly.Fence(worktrees / "night-card", main, Path(root, "night"), worktrees / "night-card", agent)

            self.assertTrue(fence("a1").may_write(worktrees / "agent-a1/Packages/Tests/A.swift"))
            self.assertTrue(fence("a1").may_write("Packages/Tests/A.swift"))
            self.assertEqual(fence("a1").resolve("x"), worktrees / "agent-a1/x")
            self.assertFalse(fence("a1").guarded(str(worktrees / "agent-a1")))
            self.assertFalse(fence("a1").may_write(worktrees / "agent-a1/.claude/settings.local.json"))
            self.assertTrue(fence("a1").may_write(worktrees / "night-card/x"))
            # Another agent's worktree, the card's own calls, and ids that name no worktree of one.
            self.assertTrue(fence("a1").guarded(str(worktrees / "agent-b2/x")))
            self.assertFalse(fence(None).may_write(worktrees / "agent-a1/x"))
            self.assertFalse(fence("c3").may_write(worktrees / "agent-c3/x"))
            self.assertFalse(fence("../night-card/../agent-a1").may_write(worktrees / "agent-a1/x"))
            self.assertFalse(fence(7).may_write(worktrees / "agent-a1/x"))
            # A call that says it runs inside the agent's worktree keeps its own directory.
            inside = nightly.Fence(worktrees / "night-card", main, Path(root, "night"), worktrees / "agent-a1/Packages", "a1")
            self.assertEqual(inside.resolve("x"), worktrees / "agent-a1/Packages/x")

    def test_the_hook_reads_agent_id_and_either_cwd_from_its_input(self):
        # The hook's input names the agent (agent_id) whose call it is. Its cwd for an agent's calls
        # has been seen both as the session's, the card's worktree, and as the agent's own; either
        # way the agent's relative paths land in its own worktree, and without agent_id they don't.
        with tempfile.TemporaryDirectory() as root:
            main = Path(os.path.realpath(root), "main")
            worktrees = main / ".claude/worktrees"
            for name in ("night-card", "agent-a1"):
                (worktrees / name).mkdir(parents=True)
                (worktrees / name / ".git").write_text(f"gitdir: {main}/.git/worktrees/{name}\n")
            night = Path(root, "night")
            night.mkdir()
            stop = (datetime.now().astimezone() + timedelta(hours=1)).isoformat()
            (night / "state.json").write_text(json.dumps({"stop": stop, "handoff": ".slices/h.md"}))

            def check(path, cwd, agent=None):
                call = {"tool_name": "Write", "cwd": str(cwd), "tool_input": {"file_path": path, "content": "x"}}
                if agent:
                    call["agent_id"] = agent
                with contextlib.redirect_stdout(io.StringIO()):
                    sys.stdin = io.StringIO(json.dumps(call))
                    try:
                        return nightly.hook_check(night, str(worktrees / "night-card"))
                    finally:
                        sys.stdin = sys.__stdin__

            for cwd in (worktrees / "night-card", worktrees / "agent-a1"):
                with self.subTest(cwd=cwd.name):
                    self.assertIsNone(check("Packages/Tests/A.swift", cwd, "a1"))
                    self.assertIsNone(check(str(worktrees / "agent-a1/Packages/Tests/A.swift"), cwd, "a1"))
                    self.assertIsNotNone(check(str(worktrees / "agent-a1/Packages/Tests/A.swift"), cwd))
                    self.assertIsNotNone(check(str(worktrees / "agent-a1/x"), cwd, "b2"))
            # Tonight's case: the agent's own cwd and no agent_id fences its relative writes.
            self.assertIsNotNone(check("Packages/Tests/A.swift", worktrees / "agent-a1"))

    def test_another_tools_paths_are_checked_too(self):
        self.assertIsNotNone(decide(tool="mcp__xcode__XcodeWrite", inputs=[str(nightly.ROOT / "App/A.swift"), "x"]))
        self.assertIsNone(decide(tool="mcp__xcode__XcodeWrite", inputs=[str(WORKTREE / "App/A.swift")]))


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
