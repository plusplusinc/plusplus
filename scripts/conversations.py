#!/usr/bin/env python3
"""The conversation in this repo's Claude Code sessions since a given time, for the retro.

    scripts/conversations.py <since>

<since> is a local date (2026-10-13, meaning midnight), a local time (2026-10-13T21:30), or a
time with an offset (2026-10-13T04:00:00Z). Prints, per session and oldest first, what the
maintainer typed and the text the assistant showed, with local times. Dropped: tool calls and
their results, thinking, system reminders, skill bodies, command output, task notifications,
and messages from other sessions. A slash command shows as "/name args". Subagents show only
as one line each: how many of their tool calls failed. The nightly retro's own session (named
"Nightly retro", see the retro skill) is skipped, so a run never reads the last run's digest.

Reads the transcripts Claude Code keeps under ~/.claude/projects/: the folder for the main
checkout and one per worktree under .claude/worktrees/, whichever checkout this runs from.
Files not modified since <since> are not opened.
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
REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.DOTALL)


def usage():
    print(__doc__.strip(), file=sys.stderr)
    print("\n  scripts/conversations.py 2026-10-13    # since local midnight", file=sys.stderr)
    sys.exit(2)


def parse_since(text):
    """The time as a UTC string comparable with transcript timestamps, which are all UTC 'Z'."""
    try:
        moment = datetime.fromisoformat(text.strip().replace("Z", "+00:00"))
    except ValueError:
        print(f"Not a date or time: {text!r}. Use 2026-10-13 or 2026-10-13T21:30.", file=sys.stderr)
        sys.exit(2)
    if moment.tzinfo is None:
        moment = moment.astimezone()
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


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
    worktrees = sorted(projects.glob(name + "--claude-worktrees-*"))
    return [(projects / name, "main checkout")] + [
        (folder, "worktree " + folder.name[len(name) + len("--claude-worktrees-"):]) for folder in worktrees
    ]


def entries(path):
    with open(path, encoding="utf-8", errors="replace") as lines:
        for line in lines:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if isinstance(entry, dict):
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


def shown(entry):
    """The text the assistant showed, without thinking or tool calls."""
    message = entry.get("message", {})
    if entry.get("isSidechain") or message.get("model") == "<synthetic>":
        return None
    content = message.get("content")
    if not isinstance(content, list):
        return None
    text = "\n".join(part.get("text", "") for part in content if part.get("type") == "text").strip()
    return text or None


def tool_results(entry):
    """(results, failures) among the tool results an entry carries."""
    content = entry.get("message", {}).get("content")
    if entry.get("type") != "user" or not isinstance(content, list):
        return 0, 0
    results = [part for part in content if isinstance(part, dict) and part.get("type") == "tool_result"]
    return len(results), sum(1 for part in results if part.get("is_error"))


def subagent_counts(session_dir, since, since_epoch):
    """(label, failed, total) for each subagent of a session that made tool calls since then."""
    counts = []
    for path in sorted((session_dir / "subagents").glob("agent-*.jsonl")):
        if path.stat().st_mtime < since_epoch:
            continue
        total = failed = 0
        for entry in entries(path):
            if entry.get("timestamp", "") >= since:
                results, failures = tool_results(entry)
                total += results
                failed += failures
        if not total:
            continue
        stem = path.name[: -len(".jsonl")]
        label = stem
        meta = session_dir / "subagents" / (stem + ".meta.json")
        skill = session_dir / "subagents" / (stem + ".forked-skill.json")
        if meta.exists():
            info = json.loads(meta.read_text())
            label = " ".join(filter(None, [info.get("agentType"), info.get("description") and f"({info['description']})"]))
        elif skill.exists():
            label = "/" + json.loads(skill.read_text()).get("skillName", stem)
        counts.append((label, failed, total))
    return counts


def session(path, where, since, since_epoch):
    custom_title = ai_title = None
    messages = []
    total = failed = 0
    for entry in entries(path):
        kind = entry.get("type")
        if kind == "custom-title":
            if entry.get("customTitle") == RETRO_SESSION_TITLE:
                return None
            custom_title = entry.get("customTitle")
        elif kind == "ai-title":
            ai_title = entry.get("aiTitle")
        timestamp = entry.get("timestamp", "")
        if timestamp < since:
            continue
        results, failures = tool_results(entry)
        total += results
        failed += failures
        text = typed(entry) if kind == "user" else shown(entry) if kind == "assistant" else None
        if text:
            messages.append((timestamp, "Dave" if kind == "user" else "Claude", text))
    subagents = subagent_counts(path.with_suffix(""), since, since_epoch)
    if not messages and not subagents:
        return None
    first = messages[0][0] if messages else None
    title = custom_title or ai_title
    header = f"## Session {path.stem}, {where}"
    if title:
        header += f": {title}"
    if first:
        header += f" ({local(first, '%a %d %b %H:%M')} to {local(messages[-1][0])})"
    failures = f"Failed tool calls: {failed} of {total}"
    if subagents:
        failing = [f"{label} {f} of {t}" for label, f, t in subagents if f]
        clean = len(subagents) - len(failing)
        rest = [f"{clean} {'more ' if failing else ''}with none"] if clean else []
        failures += "; subagents: " + ", ".join(failing + rest)
    lines = [header, failures]
    lines += [f"\n[{local(timestamp)}] {who}: {text}" for timestamp, who, text in messages]
    return first or "", "\n".join(lines)


def main():
    if len(sys.argv) != 2 or sys.argv[1].startswith("-"):
        usage()
    since = parse_since(sys.argv[1])
    since_epoch = datetime.strptime(since[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc).timestamp()
    found = []
    for folder, where in project_folders():
        for path in folder.glob("*.jsonl"):
            if path.stat().st_mtime >= since_epoch:
                result = session(path, where, since, since_epoch)
                if result:
                    found.append(result)
    if not found:
        print(f"No sessions since {local(since, '%a %d %b %H:%M')}.")
        return
    print(f"# {len(found)} sessions since {local(since, '%a %d %b %H:%M')}\n")
    print("\n\n".join(text for _, text in sorted(found)))


if __name__ == "__main__":
    main()
