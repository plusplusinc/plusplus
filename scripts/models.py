#!/usr/bin/env python3
"""Each agent's model, from the table in docs/agent-tooling.md ("Models by task").

    scripts/models.py check    # the definitions and nightly scripts agree with the table

`check` reads the table and compares it with what sets each model: an agent definition's `model:`
and `effort:` in .claude/agents/, and a nightly script's <NAME>_MODEL and <NAME>_EFFORT for a row
set in "scripts/<file> <NAME>". It fails naming each disagreement, a definition with no row, a row
whose definition or script doesn't exist, two definitions of one name, a model that isn't a full
ID, and a verifier on the builder's model. In each script in
scripts/ but the tests, it also fails on a <NAME>_MODEL with no row, and on a start of claude
passing no --model the table covers: in shell, a non-comment line (backslash continuations joined)
with the word `claude` followed by `-p` or `--print`; in Python, a list starting with the string
"claude" that holds "-p" or "--print". In each skill and agent definition, it fails on a line that
names one of this repo's agents in backticks and passes it a `model:`, which would override the
definition's. scripts/lint.sh runs it.

Tests: python3 scripts/models-test.py, which scripts/test.sh runs.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLE = "docs/agent-tooling.md"
HEADING = "## Models by task"
SECTION = HEADING[3:]
COLUMNS = ["Role", "Set in", "Model", "Effort", "Why", "Set", "Evidence"]
ALIASES = {"fable", "opus", "sonnet", "haiku"}  # Claude Code's model aliases, each its family's newest
MODEL_ID = re.compile(r"claude-([a-z]+)-\d+(-\d+)*$")
EFFORTS = {"low", "medium", "high", "xhigh", "max"}
SET = re.compile(r"\d{4}-\d{2}-\d{2}(, trial for \d+ PRs)?")  # a row on trial says for how many PRs
USER_SETTINGS = "user settings"  # the lead's row: the maintainer's choice, not the repo's


def cells(line):
    return [c.strip().strip("`").strip() for c in line.strip().strip("|").split("|")]


def table(text):
    """The rows of the first table under HEADING, as dicts keyed by COLUMNS."""
    section = re.search(rf"^{re.escape(HEADING)}\s*$(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not section:
        raise ValueError(f"{TABLE} has no \"{SECTION}\" section")
    lines = [line for line in section[1].splitlines() if line.lstrip().startswith("|")]
    if len(lines) < 3 or cells(lines[0]) != COLUMNS:
        raise ValueError(f"{TABLE}'s \"{SECTION}\" table needs the columns {' | '.join(COLUMNS)}")
    rows = []
    for line in lines[2:]:
        row = cells(line)
        if len(row) != len(COLUMNS):
            raise ValueError(f"{TABLE}: a row has {len(row)} cells, not {len(COLUMNS)}: {line.strip()}")
        rows.append(dict(zip(COLUMNS, row)))
    return rows


def frontmatter(text):
    """The `key: value` lines between a definition's opening --- lines."""
    match = re.match(r"---\n(.*?)\n---\n", text, re.S)
    return dict(re.findall(r"^(\w+):\s*(.*?)\s*$", match[1], re.M)) if match else {}


def definitions(root):
    """{path: frontmatter} for each definition in root's .claude/agents/, the path relative to root."""
    return {str(path.relative_to(root)): frontmatter(path.read_text())
            for path in sorted(Path(root, ".claude/agents").glob("*.md"))}


def family(model):
    """`opus` for both `opus` and `claude-opus-5-5`; None for `inherit` or anything else."""
    if model in ALIASES:
        return model
    match = MODEL_ID.match(model or "")
    return match[1] if match else None


def assigned(text, name):
    """The value a script gives NAME: `NAME=value` in shell, `NAME = "value"` in Python."""
    match = re.search(rf"^\s*{name}\s*=\s*[\"']?([\w.\[\]-]+)", text, re.M)
    return match[1] if match else None


def starts(text, shell):
    """Each start of a `claude` session in a script's text, as the text of the command.

    Shell: a line, not a comment, joined with any lines its trailing backslashes continue, where
    the word `claude` is followed later by `-p` or `--print`. Python: a list whose first element
    is the string "claude" and which holds "-p" or "--print"."""
    if shell:
        lines = re.sub(r"\\\n", " ", text).splitlines()
        return [line for line in lines if not line.lstrip().startswith("#")
                and re.search(r"(^|[\s;&|(\"'])claude(\s.*)?\s(-p|--print)\b", line)]
    return [m[0] for m in re.finditer(r"\[\s*\"claude\"[^\]]*\]", text) if re.search(r"\"(-p|--print)\"", m[0])]


def uncovered(root, covered):
    """Where a script in scripts/ (its tests aside) sets or starts a model the table doesn't cover:
    a <NAME>_MODEL with no row "scripts/<file> <NAME>", and a start of claude passing no such
    <NAME>_MODEL to --model."""
    found = []
    for path in sorted(Path(root, "scripts").glob("*")):
        if path.suffix not in (".sh", ".py") or path.stem.endswith("-test"):
            continue
        where = f"scripts/{path.name}"
        text = path.read_text()
        names = {name for name in re.findall(r"^\s*([A-Z]+)_MODEL\s*=", text, re.M)}
        for name in sorted(names):
            if f"{where} {name}" not in covered:
                found.append(f"{where}: {name}_MODEL has no row \"{where} {name}\" in {TABLE}'s \"{SECTION}\" table")
        passed = r"--model\s+\\?\"?\$(\w+)_MODEL" if path.suffix == ".sh" else r"\"--model\",\s*(\w+)_MODEL\b"
        for command in starts(text, path.suffix == ".sh"):
            match = re.search(passed, command)
            if not match or f"{where} {match[1]}" not in covered:
                found.append(f"{where}: a claude start passes no model the table sets: {' '.join(command.split())[:100]}")
    return found


def passed(root, names):
    """Where a skill or an agent definition tells a caller to pass a model to one of this repo's
    agents: a line naming the agent in backticks with a `model:` after it. A call's model
    overrides the definition's, so the table would not hold for that call."""
    found = []
    agent = re.compile(rf"`({'|'.join(map(re.escape, sorted(names)))})`.*\bmodel:\s*\S")
    for path in sorted(Path(root, ".claude/skills").glob("*/SKILL.md")) + sorted(Path(root, ".claude/agents").glob("*.md")):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            match = agent.search(line)
            if match:
                found.append(f"{path.relative_to(root)}:{number}: passes a model to `{match[1]}`, whose "
                             "definition sets it; a call's model overrides the definition's, so pass none")
    return found


def problems(root):
    """What disagrees with the table, one line each; empty when everything agrees."""
    root = Path(root)
    rows = table((root / TABLE).read_text())
    found = []
    roles = {row["Role"]: row for row in rows}
    agents = definitions(root)
    names = {}
    for where, front in agents.items():
        names.setdefault(front.get("name") or Path(where).stem, []).append(where)
    for name, wheres in sorted(names.items()):
        if len(wheres) > 1:
            found.append(f"{' and '.join(wheres)} share the name \"{name}\", so Claude Code runs only one of them")
    scripts = {}
    for row in rows:
        role, where, model, effort = row["Role"], row["Set in"], row["Model"], row["Effort"]
        if where == USER_SETTINGS:
            continue
        if not SET.fullmatch(row["Set"]):
            found.append(f"{role}: Set is \"{row['Set']}\", not a date like 2026-11-11, or one on trial "
                         "like \"2026-11-11, trial for 5 PRs\"")
        if model in ALIASES:
            found.append(f"{where}: \"{model}\" is an alias, which follows its family's newest release; "
                         "a definition or a script pins a full model ID such as claude-opus-5-5")
        elif family(model) is None:
            found.append(f"{role}: \"{model}\" is not a model ID such as claude-opus-5-5")
        if effort not in EFFORTS:
            found.append(f"{role}: effort \"{effort}\" is not one of {', '.join(sorted(EFFORTS))}")
        if where.startswith(".claude/agents/"):
            definition = agents.get(where)
            if definition is None:
                found.append(f"{role}: {where} doesn't exist")
                continue
            for key, want in (("model", model), ("effort", effort)):
                if definition.get(key) != want:
                    found.append(f"{where}: {key}: is \"{definition.get(key, '')}\", the table says \"{want}\"")
            continue
        script, _, name = where.partition(" ")
        if not script.startswith("scripts/") or not name:
            found.append(f"{role}: Set in \"{where}\" is none of: {USER_SETTINGS}, "
                         ".claude/agents/<file>.md, scripts/<file> <NAME>")
            continue
        try:
            if script not in scripts:
                scripts[script] = (root / script).read_text()
            text = scripts[script]
        except OSError:
            found.append(f"{role}: {script} doesn't exist")
            continue
        for suffix, want in (("MODEL", model), ("EFFORT", effort)):
            var = f"{name}_{suffix}"
            have = assigned(text, var)
            if have != want:
                found.append(f"{script}: {var} is \"{have or 'unset'}\", the table says \"{want}\"")
            elif len(re.findall(rf"\b{var}\b", text)) < 2:
                found.append(f"{script}: {var} is set but never passed")
    for where in sorted(agents.keys() - {row["Set in"] for row in rows}):
        found.append(f"{where} has no row in {TABLE}'s \"{SECTION}\" table")
    found += uncovered(root, {row["Set in"] for row in rows})
    if names:
        found += passed(root, names)
    builder, verifier = roles.get("builder"), roles.get("verifier")
    if builder and verifier and family(builder["Model"]) == family(verifier["Model"]):
        found.append(f"verifier: runs on the builder's model, {builder['Model']}; the table needs them to differ")
    return found


def check(root=ROOT):
    try:
        found = problems(root)
    except (OSError, ValueError) as error:
        found = [str(error)]
    for line in found:
        print(f"models: {line}", file=sys.stderr)
    if found:
        print(f"models: {TABLE}'s \"{SECTION}\" is the source; change the table and what sets the "
              "model together", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["check"]:
        sys.exit(check())
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    sys.exit(64)
