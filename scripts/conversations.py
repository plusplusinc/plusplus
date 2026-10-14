#!/usr/bin/env python3
"""The conversation in this repo's Claude Code sessions since a given time, for the retro.

    scripts/conversations.py <since> [file]
    scripts/conversations.py --retro-reply

<since> is a local date (2026-10-13, meaning midnight), a local time (2026-10-13T21:30), or a
time with an offset (2026-10-13T04:00:00Z). Prints, per session and oldest first, what the
maintainer typed and the text the assistant showed, with local times. Dropped: tool calls and
their results, thinking, system reminders, skill bodies, command output, task notifications,
and messages from other sessions. A slash command shows as "/name args", and AskUserQuestion
as its questions with their option labels, then the answers and any notes. Subagents show only
as one line each: how many of their tool calls failed. Each session's heading names its
transcript, for reading around a specific moment. The nightly retro's own session (named
"Nightly retro", see the retro skill) is skipped, so a run never reads the last run's digest.

Reads the transcripts Claude Code keeps under ~/.claude/projects/: the folder for the main
checkout and one per worktree under .claude/worktrees/, whichever checkout this runs from.
Files not modified since <since> are not opened. With a file, writes the conversation there
(making its folder) and prints only the first line: how many sessions, or "No sessions since".

With --retro-reply, prints instead the last reply of the newest "Nightly retro" session in the
main checkout: all the text it showed since the last message it received (a prompt or a
subagent's hand-back), API errors included, after a line with its local time. That is a
night's report, for scripts/nightly-retro.sh show.
"""
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

RETRO_SESSION_TITLE = "Nightly retro"
# Typed into no prompt, though they arrive without an origin: older sessions' agent-team
# messages, and the notice after the app quits mid-turn.
NOT_TYPED_PREFIXES = ("Another Claude session sent a message", "The app was quit while")
OUTPUT_TAGS = re.compile(r"^<(local-command-stdout|local-command-stderr|bash-stdout|bash-stderr)>")
TIMESTAMP = re.compile(r'"timestamp":"([^"]+)"')
REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.DOTALL)


def usage():
    print(__doc__.strip(), file=sys.stderr)
    print("\n  scripts/conversations.py 2026-10-13    # since local midnight", file=sys.stderr)
    sys.exit(2)


def parse_since(text):
    """The time, in UTC."""
    try:
        moment = datetime.fromisoformat(text.strip().replace("Z", "+00:00"))
    except ValueError:
        print(f"Not a date or time: {text!r}. Use 2026-10-13 or 2026-10-13T21:30.", file=sys.stderr)
        sys.exit(2)
    if moment.tzinfo is None:
        moment = moment.astimezone()
    return moment.astimezone(timezone.utc)


class Since:
    """The start time in the forms the filters compare: transcript timestamps are UTC strings
    ending in 'Z', which sort as times; file modification times are epoch seconds."""

    def __init__(self, moment):
        self.moment = moment
        self.stamp = moment.strftime("%Y-%m-%dT%H:%M:%S.000Z")
        self.epoch = moment.timestamp()


def local(timestamp, fmt="%H:%M"):
    moment = datetime.strptime(timestamp[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
    return moment.astimezone().strftime(fmt)


def project_folders():
    """The main checkout's transcript folder and its worktrees'. Claude Code names a project's
    folder after its path, with every character that is not a letter or digit turned into '-'."""
    script_dir = Path(__file__).resolve().parent
    git_dir = subprocess.run(
        ["git", "-C", str(script_dir), "rev-parse", "--path-format=absolute", "--git-common-dir"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    main_checkout = str(Path(git_dir).parent)
    name = re.sub(r"[^A-Za-z0-9]", "-", main_checkout)
    projects = Path.home() / ".claude" / "projects"
    return [projects / name] + sorted(projects.glob(name + "--claude-worktrees-*"))


def entries(path, since):
    """The file's entries from since on, and those with no time, such as titles. A line whose
    every timestamp, nested ones included, is older is skipped before parsing: a long session's
    file is mostly old tool output."""
    with open(path, encoding="utf-8", errors="replace") as lines:
        for line in lines:
            stamps = TIMESTAMP.findall(line)
            if stamps and max(stamps) < since.stamp:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if isinstance(entry, dict) and entry.get("timestamp", since.stamp) >= since.stamp:
                yield entry


def text_parts(content):
    if isinstance(content, str):
        return content
    parts = []
    for part in content or []:
        if part.get("type") == "text":
            parts.append(part.get("text", ""))
        elif part.get("type") == "image":
            parts.append("[image]")
        elif part.get("type") == "tool_result":
            return None
    return "\n".join(parts)


def typed(entry):
    """What the maintainer typed, or None for anything the app or an agent put in the prompt."""
    if entry.get("isMeta") or entry.get("isSidechain") or entry.get("isCompactSummary"):
        return None
    origin = (entry.get("origin") or {}).get("kind")
    if origin not in (None, "human"):
        return None
    text = text_parts(entry.get("message", {}).get("content"))
    if text is None:
        return None
    text = REMINDER.sub("", text).strip()
    if not text or text.startswith("Base directory for this skill") or OUTPUT_TAGS.match(text):
        return None
    if origin is None and text.startswith(NOT_TYPED_PREFIXES):
        return None
    command = re.search(r"<command-name>(.*?)</command-name>", text)
    if command:
        args = re.search(r"<command-args>(.*?)</command-args>", text, re.DOTALL)
        return " ".join(filter(None, [command.group(1).strip(), args and args.group(1).strip()]))
    shell = re.match(r"<bash-input>(.*?)</bash-input>", text, re.DOTALL)
    if shell:
        return "! " + shell.group(1).strip()
    return text


def shown(entry, asked):
    """The text the assistant showed, and the questions it asked with AskUserQuestion, one line
    each with the option labels; the ids of those questions go into asked. No thinking, no
    other tool calls."""
    message = entry.get("message", {})
    if entry.get("isSidechain") or message.get("model") == "<synthetic>":
        return None
    content = message.get("content")
    if not isinstance(content, list):
        return None
    lines = []
    for part in content:
        if part.get("type") == "text":
            lines.append(part.get("text", "").strip())
        elif part.get("type") == "tool_use" and part.get("name") == "AskUserQuestion":
            asked.add(part.get("id"))
            for question in (part.get("input") or {}).get("questions", []):
                labels = " | ".join(option.get("label", "") for option in question.get("options", []))
                lines.append(f"Asks ({question.get('header', '')}): {question.get('question', '')} [{labels}]")
    return "\n".join(line for line in lines if line) or None


def answered(entry, asked):
    """The maintainer's answers to an AskUserQuestion, one line per question, or None."""
    content = entry.get("message", {}).get("content")
    if not isinstance(content, list):
        return None
    for part in content:
        if not isinstance(part, dict) or part.get("tool_use_id") not in asked:
            continue
        result = entry.get("toolUseResult")
        if isinstance(result, dict) and result.get("answers"):
            headers = {q.get("question"): q.get("header") for q in result.get("questions", [])}
            notes = result.get("annotations") or {}
            lines = []
            for question, answer in result["answers"].items():
                note = notes.get(question)
                note = note.get("notes") if isinstance(note, dict) else None
                lines.append(f"{headers.get(question) or question}: {answer}" + (f" (note: {note})" if note else ""))
            return "\n".join(lines)
        text = text_parts(part.get("content")) or ""
        said = text.split("the user said:", 1)[-1].strip()
        if said.startswith("The user wants to clarify"):
            return "(declined the questions, to clarify first)"
        return said.split("\n\n")[0] or None
    return None


def read_json(path):
    """A small side file's contents, or None when it is missing or half-written."""
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


class ToolCalls:
    """How many tool calls returned, and how many of them failed."""

    def __init__(self):
        self.total = self.failed = 0

    def count(self, entry):
        content = entry.get("message", {}).get("content")
        if entry.get("type") != "user" or not isinstance(content, list):
            return
        for part in content:
            if isinstance(part, dict) and part.get("type") == "tool_result":
                self.total += 1
                self.failed += bool(part.get("is_error"))


def subagent_counts(session_dir, since):
    """(label, failed, total) for each subagent of a session that made tool calls since then."""
    counts = []
    for path in sorted((session_dir / "subagents").glob("agent-*.jsonl")):
        if path.stat().st_mtime < since.epoch:
            continue
        calls = ToolCalls()
        for entry in entries(path, since):
            calls.count(entry)
        if not calls.total:
            continue
        stem = path.name[: -len(".jsonl")]
        label = stem
        meta = session_dir / "subagents" / (stem + ".meta.json")
        skill = session_dir / "subagents" / (stem + ".forked-skill.json")
        info = read_json(meta)
        if info:
            label = " ".join(filter(None, [info.get("agentType"), info.get("description") and f"({info['description']})"]))
        elif read_json(skill):
            label = "/" + read_json(skill).get("skillName", stem)
        counts.append((label, calls.failed, calls.total))
    return counts


def session(path, since):
    custom_title = ai_title = None
    messages = []
    calls = ToolCalls()
    asked = set()
    for entry in entries(path, since):
        kind = entry.get("type")
        if kind == "custom-title":
            if entry.get("customTitle") == RETRO_SESSION_TITLE:
                return None
            custom_title = entry.get("customTitle")
        elif kind == "ai-title":
            ai_title = entry.get("aiTitle")
        timestamp = entry.get("timestamp")
        if not timestamp:
            continue
        calls.count(entry)
        if kind == "user":
            who, text = "Maintainer", typed(entry) or answered(entry, asked)
        elif kind == "assistant":
            who, text = "Claude", shown(entry, asked)
        else:
            continue
        if text:
            messages.append((timestamp, who, text))
    subagents = subagent_counts(path.with_suffix(""), since)
    if not messages and not subagents:
        return None
    first = messages[0][0] if messages else ""
    title = custom_title or ai_title
    header = f"## ~/{path.relative_to(Path.home())}"
    if title:
        header += f": {title}"
    if first:
        last = messages[-1][0]
        same_day = local(first, "%F") == local(last, "%F")
        header += f" ({local(first, '%a %d %b %H:%M')} to {local(last, '%H:%M' if same_day else '%a %d %b %H:%M')})"
    failures = f"Failed tool calls: {calls.failed} of {calls.total}"
    if subagents:
        failing = [f"{label} {f} of {t}" for label, f, t in subagents if f]
        clean = len(subagents) - len(failing)
        rest = [f"{clean} {'more ' if failing else ''}with none"] if clean else []
        failures += "; subagents: " + ", ".join(failing + rest)
    lines = [header, failures]
    lines += [f"\n[{local(timestamp)}] {who}: {text}" for timestamp, who, text in messages]
    return first, "\n".join(lines)


def retro_session():
    """The newest "Nightly retro" transcript in the main checkout, or None. `claude --name`
    writes the title as a transcript's first line, so only first lines are read."""
    paths = sorted(project_folders()[0].glob("*.jsonl"), key=lambda path: path.stat().st_mtime, reverse=True)
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as lines:
            try:
                first = json.loads(lines.readline())
            except ValueError:
                continue
        if isinstance(first, dict) and first.get("type") == "custom-title" and first.get("customTitle") == RETRO_SESSION_TITLE:
            return path
    return None


def last_reply(path):
    """All the text the assistant showed since the last message it received (a prompt or a
    subagent's hand-back), or since the one before when it has shown nothing since, as (UTC
    timestamp of its last part, text), or None. Claude Code writes each part of a reply as its
    own entry, and its own notices, such as an API error, as synthetic ones, which count here."""
    turn, last = [], None
    for entry in entries(path, Since(datetime.fromtimestamp(0, timezone.utc))):
        message = entry.get("message", {})
        if entry.get("type") == "user" and text_parts(message.get("content")) is not None:
            turn = []  # a message it received, not a tool's result
        elif entry.get("type") == "assistant" and entry.get("timestamp") and not entry.get("isSidechain"):
            synthetic = message.get("model") == "<synthetic>"
            text = text_parts(message.get("content")) if synthetic else shown(entry, set())
            if text:
                turn.append(text.strip())
                last = (entry["timestamp"], turn)
    return last and (last[0], "\n\n".join(last[1]))


def print_retro_reply():
    path = retro_session()
    if path is None:
        print(f'No "{RETRO_SESSION_TITLE}" session in {project_folders()[0]}.', file=sys.stderr)
        sys.exit(1)
    reply = last_reply(path)
    if reply is None:
        print(f"No reply yet in ~/{path.relative_to(Path.home())}.")
        return
    timestamp, text = reply
    print(f"Last reply, {local(timestamp, '%a %d %b %H:%M')}:\n\n{text}")


def main():
    if sys.argv[1:] == ["--retro-reply"]:
        print_retro_reply()
        return
    if len(sys.argv) not in (2, 3) or sys.argv[1].startswith("-"):
        usage()
    since = Since(parse_since(sys.argv[1]))
    found = []
    for folder in project_folders():
        for path in folder.glob("*.jsonl"):
            if path.stat().st_mtime >= since.epoch:
                result = session(path, since)
                if result:
                    found.append(result)
    shown_since = since.moment.astimezone().strftime("%a %d %b %H:%M")
    summary = f"# {len(found)} sessions since {shown_since}" if found else f"No sessions since {shown_since}."
    text = "\n\n".join([summary] + [text for _, text in sorted(found)]) + "\n"
    if len(sys.argv) == 3:
        out = Path(sys.argv[2])
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8")
        print(summary)
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
