#!/usr/bin/env python3
"""Each agent's model, from the table in docs/agent-tooling.md ("Models by task").

    scripts/models.py check    # the definitions and nightly scripts agree with the table
    scripts/models.py hook     # the PreToolUse hook on the Agent tool, its JSON on stdin

`check` reads the table and compares it with what sets each model: an agent definition's `model:`
and `effort:` in .claude/agents/, and a nightly script's <NAME>_MODEL and <NAME>_EFFORT for a row
set in "scripts/<file> <NAME>". It fails naming each disagreement, a definition with no row, a
model the Agent tool can't take on a one-off row, and a verifier on the builder's model. It warns,
without failing, while .claude/settings.json has no PreToolUse entry running `hook` on the Agent
tool, which only the maintainer adds (agents can't edit that file). scripts/lint.sh runs it.

`hook` refuses an Agent call that would run on a model the table didn't choose: a one-off subagent
type with no definition naming a model (general-purpose, Explore, Plan, claude-code-guide, ...)
called with no `model`, and one of this repo's agents called with a `model` of another family than
its definition's, since the call's `model` wins over the definition's
(code.claude.com/docs/en/sub-agents). It always allows a fork, a plugin's agent (a `:` in its
type), and an agent defined in ~/.claude/agents/, which are the maintainer's. It exits 2 with the
reason on stderr, which Claude Code hands the caller. It only narrows: any error of its own allows
the call, exiting 1 with a line on stderr and in .build/agent-hook.log, so a bug in it can't stop
every subagent.

Tests: python3 scripts/models-test.py, which scripts/test.sh runs.
"""
import json
import re
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLE = "docs/agent-tooling.md"
HEADING = "## Models by task"
SECTION = HEADING[3:]
COLUMNS = ["Role", "Set in", "Model", "Effort", "Why", "Set", "Evidence"]
ALIASES = {"fable", "opus", "sonnet", "haiku"}  # all the Agent tool's `model` takes
MODEL_ID = re.compile(r"claude-([a-z]+)-\d+(-\d+)*$")
EFFORTS = {"low", "medium", "high", "xhigh", "max"}
NONE = "—"  # an Effort the row can't set: the Agent tool here takes no effort
USER_SETTINGS = "user settings"  # the lead's row: the maintainer's choice, not the repo's
AGENT_TOOL = "Agent tool"  # a one-off subagent's row: the model the caller passes
FORK = "fork"  # inherits the caller's model
HOOK_COMMAND = 'python3 "$CLAUDE_PROJECT_DIR/scripts/models.py" hook'  # the settings entry's command


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


def definitions(folder):
    """{name: frontmatter} for each definition in an agents folder, keyed by its `name:`, which is
    what the Agent tool's subagent_type matches, or else its file name."""
    found = {}
    for path in sorted(Path(folder).glob("*.md")):
        try:
            front = frontmatter(path.read_text())
        except OSError:
            continue
        found[front.get("name") or path.stem] = dict(front, path=path)
    return found


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


def problems(root):
    """What disagrees with the table, one line each; empty when everything agrees."""
    root = Path(root)
    rows = table((root / TABLE).read_text())
    found = []
    roles = {}
    agents = definitions(root / ".claude/agents")
    for row in rows:
        role, where, model, effort = row["Role"], row["Set in"], row["Model"], row["Effort"]
        roles[role] = row
        if where == USER_SETTINGS:
            continue
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", row["Set"]):
            found.append(f"{role}: Set is \"{row['Set']}\", not a date like 2026-11-11")
        if where == AGENT_TOOL:
            if model not in ALIASES:
                found.append(f"{role}: the Agent tool takes only an alias ({', '.join(sorted(ALIASES))}), not \"{model}\"")
            if effort != NONE:
                found.append(f"{role}: the Agent tool takes no effort, so Effort reads \"{NONE}\", not \"{effort}\"")
            continue
        if family(model) is None:
            found.append(f"{role}: \"{model}\" is neither an alias ({', '.join(sorted(ALIASES))}) nor a model id")
        if effort not in EFFORTS:
            found.append(f"{role}: effort \"{effort}\" is not one of {', '.join(sorted(EFFORTS))}")
        if where.startswith(".claude/agents/"):
            definition = next((d for d in agents.values() if d["path"] == root / where), None)
            if definition is None:
                found.append(f"{role}: {where} doesn't exist")
                continue
            for key, want in (("model", model), ("effort", effort)):
                if definition.get(key) != want:
                    found.append(f"{where}: {key}: is \"{definition.get(key, '')}\", the table says \"{want}\"")
            continue
        script, _, name = where.partition(" ")
        if not script.startswith("scripts/") or not name:
            found.append(f"{role}: Set in \"{where}\" is none of: {USER_SETTINGS}, {AGENT_TOOL}, "
                         ".claude/agents/<file>.md, scripts/<file> <NAME>")
            continue
        try:
            text = (root / script).read_text()
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
    for definition in agents.values():
        where = str(definition["path"].relative_to(root))
        if not any(r["Set in"] == where for r in rows):
            found.append(f"{where} has no row in {TABLE}'s \"{SECTION}\" table")
    builder, verifier = roles.get("builder"), roles.get("verifier")
    if builder and verifier and family(builder["Model"]) == family(verifier["Model"]):
        found.append(f"verifier: runs on the builder's model, {builder['Model']}; the table needs them to differ")
    return found


def hook_wired(root):
    """Whether .claude/settings.json runs `hook` before the Agent tool."""
    try:
        settings = json.loads((Path(root) / ".claude/settings.json").read_text())
    except (OSError, ValueError):
        return False
    return any(entry.get("matcher") == "Agent" and hook.get("command", "").strip() == HOOK_COMMAND
               for entry in settings.get("hooks", {}).get("PreToolUse", [])
               for hook in entry.get("hooks", []))


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
    if not hook_wired(root):
        print("models: warning: .claude/settings.json has no PreToolUse entry for the Agent tool running "
              f"{HOOK_COMMAND}, so nothing refuses a model-less subagent; the maintainer "
              f"adds it by hand ({TABLE}, \"{SECTION}\")", file=sys.stderr)
    return 1 if found else 0


def refusal(call, root, home):
    """Why the hook refuses an Agent call, or None to let it run."""
    tool = call.get("tool_input") or {}
    kind = tool.get("subagent_type") or "general-purpose"
    model = tool.get("model")
    if kind == FORK or ":" in kind or kind in definitions(Path(home) / ".claude/agents"):
        return None
    ours = definitions(Path(root) / ".claude/agents").get(kind)
    named = (ours or {}).get("model")
    if named:
        if model and family(named) and family(model) != family(named):
            return (f"{kind} runs on {named}, which {TABLE}'s \"{SECTION}\" sets in "
                    f".claude/agents/{ours['path'].name}; a `model` of {model} would override it. "
                    "Start it again without `model`.")
        return None
    if model:
        return None
    kinds = [f"{r['Role']} {r['Model']}" for r in table((Path(root) / TABLE).read_text()) if r["Set in"] == AGENT_TOOL]
    return (f"A {kind} subagent needs a `model`: pass the one {TABLE}'s \"{SECTION}\" gives its kind of "
            f"task ({', '.join(kinds)}), and start it again.")


def hook(stdin=sys.stdin, root=ROOT, home=None):
    try:
        why = refusal(json.load(stdin), root, Path.home() if home is None else home)
    except Exception as error:  # noqa: BLE001 - it fails open: a bug here must not stop every subagent
        line = f"{datetime.now():%Y-%m-%d %H:%M:%S} models.py hook failed, allowing the call: {type(error).__name__}: {error}"
        print(line, file=sys.stderr)
        try:
            (Path(root) / ".build").mkdir(exist_ok=True)
            with (Path(root) / ".build/agent-hook.log").open("a") as log:
                log.write(line + "\n")
        except OSError:
            pass
        return 1
    if why:
        print(why, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) == 2 else ""
    if command == "check":
        sys.exit(check())
    if command == "hook":
        sys.exit(hook())
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    sys.exit(64)
