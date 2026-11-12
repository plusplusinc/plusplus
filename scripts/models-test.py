#!/usr/bin/env python3
"""scripts/models.py's check, against a copy of this repo's table, definitions, and nightly
scripts.

    python3 scripts/models-test.py    # scripts/test.sh runs it
"""
import importlib.util
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("models", ROOT / "scripts" / "models.py")
models = importlib.util.module_from_spec(spec)
spec.loader.exec_module(models)

COPIED = ["docs/agent-tooling.md", ".claude/agents", ".claude/skills", "scripts/nightly-retro.sh",
          "scripts/nightly-tooling.py"]


class Fixture(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        for path in COPIED:
            source, target = ROOT / path, self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            (shutil.copytree if source.is_dir() else shutil.copy)(source, target)

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
        found = models.problems(self.root)
        self.assertEqual(found[0], "scripts/nightly-retro.sh: RETRO_MODEL is set but never passed")
        self.assertTrue(found[1].startswith("scripts/nightly-retro.sh: a claude start passes no model the table sets"))

    def test_a_scripts_model_with_no_row_fails(self):
        self.edit("docs/agent-tooling.md", "| retro | `scripts/nightly-retro.sh RETRO`", "| retro | user settings")
        self.assertIn('scripts/nightly-retro.sh: RETRO_MODEL has no row "scripts/nightly-retro.sh RETRO" in '
                      'docs/agent-tooling.md\'s "Models by task" table', models.problems(self.root))

    def test_every_start_of_claude_is_found(self):
        self.assertEqual(len(models.starts((ROOT / "scripts/nightly-tooling.py").read_text(), shell=False)), 2)
        self.assertEqual(len(models.starts((ROOT / "scripts/nightly-retro.sh").read_text(), shell=True)), 1)

    def test_a_start_with_no_table_model_fails(self):
        for script, line in (("scripts/nightly-tooling.py", '\nsubprocess.run(["claude", "-p", "/retro"])\n'),
                             ("scripts/nightly-tooling.py", '\nsubprocess.run(["claude", "-p", "--model", "opus"])\n'),
                             ("scripts/nightly-retro.sh", '\n    claude -p "/retro" >> out\n'),
                             ("scripts/nightly-retro.sh", '\n  x && claude --name y \\\n    --print "/z"\n')):
            with self.subTest(line=line):
                file = self.root / script
                before = file.read_text()
                file.write_text(before + line)
                self.assertEqual(len(models.problems(self.root)), 1)
                self.assertIn("a claude start passes no model the table sets", models.problems(self.root)[0])
                file.write_text(before)

    def test_a_definition_with_no_row_fails(self):
        (self.root / ".claude/agents/scout.md").write_text("---\nname: scout\nmodel: haiku\n---\n")
        self.assertEqual(models.problems(self.root),
                         ['.claude/agents/scout.md has no row in docs/agent-tooling.md\'s "Models by task" table'])

    def test_a_row_with_no_definition_fails(self):
        (self.root / ".claude/agents/reviewer.md").unlink()
        self.assertEqual(models.problems(self.root), ["reviewer: .claude/agents/reviewer.md doesn't exist"])

    def test_an_alias_fails_where_a_row_pins_a_model(self):
        self.edit("docs/agent-tooling.md", "| `claude-haiku-5-5` |", "| `haiku` |")
        self.edit(".claude/agents/lookup.md", "model: claude-haiku-5-5", "model: haiku")
        self.edit("scripts/nightly-retro.sh", "RETRO_MODEL=claude-fable-5-2", "RETRO_MODEL=fable")
        self.edit("docs/agent-tooling.md", "| `scripts/nightly-retro.sh RETRO` | `claude-fable-5-2` |",
                  "| `scripts/nightly-retro.sh RETRO` | `fable` |")
        found = models.problems(self.root)
        self.assertEqual(len(found), 2, found)
        self.assertTrue(found[0].startswith('scripts/nightly-retro.sh RETRO: "fable" is an alias'))
        self.assertTrue(found[1].startswith('.claude/agents/lookup.md: "haiku" is an alias'))

    def test_two_definitions_of_one_name_fail(self):
        (self.root / ".claude/agents/finder.md").write_text(
            (self.root / ".claude/agents/lookup.md").read_text())
        found = models.problems(self.root)
        self.assertIn('.claude/agents/finder.md and .claude/agents/lookup.md share the name "lookup", '
                      "so Claude Code runs only one of them", found)
        self.assertNotIn("lookup: .claude/agents/lookup.md doesn't exist", found)

    def test_the_table_sets_the_seven_definitions(self):
        rows = models.table((ROOT / models.TABLE).read_text())
        self.assertEqual({row["Set in"] for row in rows if row["Set in"].startswith(".claude/agents/")},
                         {f".claude/agents/{name}.md" for name in
                          ("planner", "builder", "verifier", "lookup", "repro", "edit", "reviewer")})

    def test_a_skill_passing_a_model_to_a_repo_agent_fails(self):
        self.edit(".claude/skills/nightly-card/SKILL.md", "Start a `verifier`, again with no model,",
                  'Start a `verifier` (`model: "opus"`),')
        found = models.problems(self.root)
        self.assertEqual(len(found), 1, found)
        self.assertRegex(found[0], r"^\.claude/skills/nightly-card/SKILL\.md:\d+: passes a model to `verifier`")

    def test_a_model_passed_to_a_built_in_agent_passes(self):
        self.edit(".claude/skills/nightly-card/SKILL.md", "Start a `verifier`, again with no model,",
                  "Start a `general-purpose` agent (`model: fable`), then a `verifier`, again with no model,")
        self.assertEqual(models.problems(self.root), [])

    def test_a_verifier_on_the_builders_model_fails(self):
        self.edit("docs/agent-tooling.md", "| verifier | `.claude/agents/verifier.md` | `claude-fable-5-2`",
                  "| verifier | `.claude/agents/verifier.md` | `claude-opus-5-5`")
        self.edit(".claude/agents/verifier.md", "model: claude-fable-5-2", "model: claude-opus-5-5")
        self.assertEqual(models.problems(self.root),
                         ["verifier: runs on the builder's model, claude-opus-5-5; the table needs them to differ"])


if __name__ == "__main__":
    unittest.main()
