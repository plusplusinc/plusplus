#!/usr/bin/env python3
"""scripts/models.py's check and hook, against a copy of this repo's table, definitions, and
nightly scripts, and a stand-in home folder.

    python3 scripts/models-test.py    # scripts/test.sh runs it
"""
import contextlib
import importlib.util
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("models", ROOT / "scripts" / "models.py")
models = importlib.util.module_from_spec(spec)
spec.loader.exec_module(models)

COPIED = ["docs/agent-tooling.md", ".claude/agents", "scripts/nightly-retro.sh", "scripts/nightly-tooling.py"]


class Fixture(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        for path in COPIED:
            source, target = ROOT / path, self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            (shutil.copytree if source.is_dir() else shutil.copy)(source, target)
        self.home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.home)
        (self.home / ".claude/agents").mkdir(parents=True)
        (self.home / ".claude/agents/shot-doctor.md").write_text("---\nname: shot-doctor\nmodel: fable\n---\n")

    def edit(self, path, old, new):
        file = self.root / path
        text = file.read_text()
        self.assertIn(old, text)
        file.write_text(text.replace(old, new, 1))


class Check(Fixture):
    def test_this_repo_agrees_with_its_table(self):
        self.assertEqual(models.problems(ROOT), [])

    def test_a_definition_on_another_model_fails(self):
        self.edit(".claude/agents/planner.md", "model: claude-fable-5-2", "model: claude-opus-5-5")
        self.assertEqual(models.problems(self.root),
                         ['.claude/agents/planner.md: model: is "claude-opus-5-5", the table says "claude-fable-5-2"'])

    def test_a_definition_with_no_model_fails(self):
        self.edit(".claude/agents/builder.md", "model: claude-opus-5-5\n", "")
        self.assertEqual(len(models.problems(self.root)), 1)

    def test_a_definition_or_script_on_another_effort_fails(self):
        self.edit(".claude/agents/planner.md", "effort: high", "effort: low")
        self.edit("scripts/nightly-retro.sh", "RETRO_EFFORT=high", "RETRO_EFFORT=medium")
        self.assertEqual(models.problems(self.root),
                         ['.claude/agents/planner.md: effort: is "low", the table says "high"',
                          'scripts/nightly-retro.sh: RETRO_EFFORT is "medium", the table says "high"'])

    def test_a_malformed_table_fails_the_check(self):
        self.edit("docs/agent-tooling.md", "| Role | Set in | Model |", "| Role | Where | Model |")
        self.assertEqual(models.check(self.root), 1)
        self.edit("docs/agent-tooling.md", "## Models by task", "## Models")
        self.assertEqual(models.check(self.root), 1)

    def test_a_script_on_another_model_fails(self):
        self.edit("scripts/nightly-tooling.py", 'CARD_MODEL = "claude-fable-5-2"', 'CARD_MODEL = "claude-opus-5-5"')
        self.assertEqual(models.problems(self.root),
                         ['scripts/nightly-tooling.py: CARD_MODEL is "claude-opus-5-5", the table says "claude-fable-5-2"'])

    def test_a_model_set_but_never_passed_fails(self):
        self.edit("scripts/nightly-retro.sh", '--model \\"$RETRO_MODEL\\"', "")
        self.assertEqual(models.problems(self.root), ["scripts/nightly-retro.sh: RETRO_MODEL is set but never passed"])

    def test_a_definition_with_no_row_fails(self):
        (self.root / ".claude/agents/scout.md").write_text("---\nname: scout\nmodel: haiku\n---\n")
        self.assertEqual(models.problems(self.root),
                         ['.claude/agents/scout.md has no row in docs/agent-tooling.md\'s "Models by task" table'])

    def test_a_one_off_row_takes_only_an_alias_and_no_effort(self):
        self.edit("docs/agent-tooling.md", "| lookup | Agent tool | `haiku` | — |", "| lookup | Agent tool | `claude-haiku-5-5` | low |")
        self.assertEqual(len(models.problems(self.root)), 2)

    def test_a_verifier_on_the_builders_model_fails(self):
        self.edit("docs/agent-tooling.md", "| verifier | `.claude/agents/verifier.md` | `claude-fable-5-2`",
                  "| verifier | `.claude/agents/verifier.md` | `claude-opus-5-5`")
        self.edit(".claude/agents/verifier.md", "model: claude-fable-5-2", "model: claude-opus-5-5")
        self.assertEqual(models.problems(self.root),
                         ["verifier: runs on the builder's model, claude-opus-5-5; the table needs them to differ"])

    def test_a_missing_hook_entry_only_warns(self):
        self.assertFalse(models.hook_wired(self.root))
        (self.root / ".claude/settings.json").write_text(json.dumps({"hooks": {"PreToolUse": [
            {"matcher": "Agent", "hooks": [{"type": "command", "command": models.HOOK_COMMAND}]}]}}))
        self.assertTrue(models.hook_wired(self.root))
        self.assertEqual(models.problems(self.root), [])


class Hook(Fixture):
    def run_hook(self, **tool_input):
        self.stderr = io.StringIO()
        with contextlib.redirect_stderr(self.stderr):
            return models.hook(io.StringIO(json.dumps({"tool_name": "Agent", "tool_input": tool_input})),
                               self.root, self.home)

    def test_a_one_off_with_no_model_is_refused_naming_the_table(self):
        for kind in ("general-purpose", "Explore", "Plan", "claude-code-guide", "claude", None):
            with self.subTest(kind=kind):
                self.assertEqual(self.run_hook(subagent_type=kind, prompt="Find X"), 2)
                self.assertIn('docs/agent-tooling.md\'s "Models by task"', self.stderr.getvalue())

    def test_a_one_off_with_a_model_runs(self):
        self.assertEqual(self.run_hook(subagent_type="Explore", model="haiku", prompt="Find X"), 0)

    def test_a_fork_a_plugin_agent_and_a_users_agent_run(self):
        for kind in ("fork", "design:critic", "shot-doctor"):
            with self.subTest(kind=kind):
                self.assertEqual(self.run_hook(subagent_type=kind, prompt="Go"), 0)

    def test_a_repo_agent_runs_on_its_definitions_family(self):
        self.assertEqual(self.run_hook(subagent_type="builder", prompt="Build"), 0)
        self.assertEqual(self.run_hook(subagent_type="builder", model="opus", prompt="Build"), 0)

    def test_a_repo_agent_given_another_family_is_refused(self):
        self.assertEqual(self.run_hook(subagent_type="verifier", model="opus", prompt="Verify"), 2)

    def test_a_users_agent_of_a_repo_agents_name_is_no_way_round(self):
        (self.home / ".claude/agents/verifier.md").write_text("---\nname: verifier\nmodel: opus\n---\n")
        self.assertEqual(self.run_hook(subagent_type="verifier", model="opus", prompt="Verify"), 2)

    def test_its_own_error_allows_the_call(self):
        (self.root / "docs/agent-tooling.md").unlink()
        self.assertEqual(self.run_hook(subagent_type="general-purpose", prompt="Go"), 1)
        self.assertIn("allowing the call", (self.root / ".build/agent-hook.log").read_text())

    def test_unreadable_input_allows_the_call(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(models.hook(io.StringIO("not json"), self.root, self.home), 1)


if __name__ == "__main__":
    unittest.main()
