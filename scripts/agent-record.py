#!/usr/bin/env python3
"""Each PR's record of its agents, and the tally of those records across merged PRs.

    scripts/agent-record.py line <role> '<usage line>' [--model M] [--round N] [--after TOKENS] [--note TEXT]
    scripts/agent-record.py post <pr> '<line>'...
    scripts/agent-record.py tally <since YYYY-MM-DD>

`line` prints one record line for one agent run, from the usage line of its task notification
(`<usage><subagent_tokens>…</subagent_tokens><tool_uses>…</tool_uses><duration_ms>…</duration_ms></usage>`;
the whole notification works too): `- <role>, <model>, round <n>: <tokens> tokens, <tool uses>
tool uses, <minutes> min[; <note>]`. The role is a row of docs/agent-tooling.md's "Models by task",
whose model the line takes; --model names another, the one the run was on, and is required for a
role with no row (a plain general-purpose agent: the default it fell to). Round 1 is the
build, and each fix round after a verifier is the next. A resumed agent's tokens count its earlier
runs too: --after takes that earlier total, and the line keeps only this run's. It reads no network.

`post` checks each line's shape and adds them to the PR as one comment headed `Agent record`, as
the verifier's record is a comment headed `Verifier record`: a comment can be added after the
merge, and the squash commit stays as it was. One `gh pr comment` call.

`tally` reads every PR merged to main since the date, with its comments and its commits' check
states, in one GraphQL request per 100 PRs (about 2 of the 5,000 points an hour each; the run
prints what it cost), and counts only comments by the repo's owner, members, or collaborators.
Per role and model it prints runs, tokens and minutes per PR, and, for the builder, fix rounds
and failed pushes (a commit whose checks failed) per PR, and for the verifier, the findings it
caught that the builder missed (its record's `new` lines) per PR. A PR with no agent record is
counted as missing, never as zeros. It needs `gh`.

Tests: python3 scripts/agent-record-test.py, with a stand-in `gh`, which scripts/test.sh runs.
"""
import argparse
import importlib.util
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEADER = "Agent record"
VERIFIER = "Verifier record"
TRUSTED = {"OWNER", "MEMBER", "COLLABORATOR"}
FAILED = {"FAILURE", "ERROR"}
LINE = re.compile(r"^- (?P<role>[\w -]+?), (?P<model>[\w.\[\]-]+), round (?P<round>\d+): (?P<tokens>\d+) tokens, "
                  r"(?P<tools>\d+) tool uses, (?P<minutes>\d+(\.\d)?) min(; (?P<note>.+))?$")
FINDING = re.compile(r"^- \w+, (new|known):")
QUERY = """query($q: String!, $after: String) {
  search(type: ISSUE, first: 100, query: $q, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes { ... on PullRequest { number
      comments(first: 100) { nodes { body authorAssociation } }
      commits(first: 100) { nodes { commit { statusCheckRollup { state } } } } } } }
  rateLimit { cost remaining } }"""


def models():
    spec = importlib.util.spec_from_file_location("models", ROOT / "scripts" / "models.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def usage(text):
    """(tokens, tool uses, ms) from a task notification's usage line."""
    found = [re.search(rf"<{tag}>\s*(\d+)\s*</{tag}>", text) for tag in ("subagent_tokens", "tool_uses", "duration_ms")]
    if not all(found):
        raise ValueError("no usage line: pass the notification's <usage>…</usage>, with subagent_tokens, "
                         "tool_uses, and duration_ms")
    return tuple(int(m[1]) for m in found)


def line(role, text, model=None, round=1, after=0, note=None, root=ROOT):
    tool = models()
    rows = {row["Role"]: row for row in tool.table((Path(root) / tool.TABLE).read_text())}
    if role not in rows and not model:
        raise ValueError(f"no role \"{role}\" in {tool.TABLE}'s \"{tool.SECTION}\" table ({', '.join(rows)}): "
                         "pass --model, the one it ran on")
    model = model or rows[role]["Model"]
    if tool.family(model) is None:
        raise ValueError(f"the table gives {role} no single model (\"{model}\"): pass --model")
    tokens, tools, ms = usage(text)
    if after > tokens:
        raise ValueError(f"--after {after} is more than the run's {tokens} tokens")
    if round < 1:
        raise ValueError("--round starts at 1, the build")
    note = f"; {' '.join(note.split())}" if note else ""
    return f"- {role}, {model}, round {round}: {tokens - after} tokens, {tools} tool uses, {ms / 60000:.1f} min{note}"


def post(pr, lines):
    bad = [text for text in lines if not LINE.match(text)]
    if bad:
        raise ValueError(f"not a record line, as `line` prints them: {bad[0]}")
    body = "\n".join([HEADER, *lines])
    subprocess.run(["gh", "pr", "comment", str(pr), "--body-file", "-"], input=body, text=True, check=True)


def repo():
    url = subprocess.run(["git", "-C", str(ROOT), "remote", "get-url", "origin"],
                         capture_output=True, text=True, check=True).stdout.strip()
    return re.search(r"github\.com[:/](.+?)(\.git)?$", url)[1]


def fetch(since):
    """The merged PRs, and the GraphQL points the requests cost."""
    query = f"repo:{repo()} is:pr is:merged base:main merged:>={since}"
    prs, cost, after = [], 0, None
    while True:
        args = ["gh", "api", "graphql", "-f", f"query={QUERY}", "-f", f"q={query}"]
        if after:
            args += ["-f", f"after={after}"]
        data = json.loads(subprocess.run(args, capture_output=True, text=True, check=True).stdout)["data"]
        prs += [node for node in data["search"]["nodes"] if node]
        cost += data["rateLimit"]["cost"]
        page = data["search"]["pageInfo"]
        if not page["hasNextPage"]:
            return prs, cost, data["rateLimit"]["remaining"]
        after = page["endCursor"]


def records(pr):
    """(agent runs, new findings or None when no verifier record, failed pushes) of one PR."""
    bodies = [c["body"].replace("\r\n", "\n").strip() for c in pr["comments"]["nodes"]
              if c.get("authorAssociation") in TRUSTED]
    runs = [m.groupdict() for body in bodies if body.startswith(HEADER)
            for m in map(LINE.match, body.splitlines()[1:]) if m]
    verified = [body for body in bodies if body.startswith(VERIFIER)]
    found = sum(1 for body in verified for text in body.splitlines()[1:]
                if FINDING.match(text) and ", new:" in text) if verified else None
    failed = sum(1 for c in pr["commits"]["nodes"]
                 if ((c["commit"] or {}).get("statusCheckRollup") or {}).get("state") in FAILED)
    return runs, found, failed


def numbers(found):
    return ", ".join(f"#{n}" for n in found)


def tally(prs, since):
    """The tally's text, from the PRs merged since the date."""
    recorded, missing, verified_only = [], [], []
    rows = defaultdict(lambda: {"runs": 0, "prs": [], "tokens": 0, "minutes": 0.0})
    for pr in sorted(prs, key=lambda p: p["number"]):
        runs, found, failed = records(pr)
        if not runs:
            missing.append(pr["number"])
            if found is not None:
                verified_only.append(f"#{pr['number']} ({found} new)")
            continue
        builds = [int(r["round"]) for r in runs if r["role"] == "builder"]
        rounds = max(builds) - 1 if builds else None
        recorded.append((pr["number"], runs, found, failed, rounds))
        for r in runs:
            row = rows[(r["role"], r["model"])]
            row["runs"] += 1
            row["tokens"] += int(r["tokens"])
            row["minutes"] += float(r["minutes"])
            if (pr["number"], rounds, failed, found) not in row["prs"]:
                row["prs"].append((pr["number"], rounds, failed, found))
    out = [f"Agent records, PRs merged since {since}: {len(prs)} merged, {len(recorded)} with an agent record"
           + (f" ({numbers(n for n, *_ in recorded)})" if recorded else "")
           + (f"; {len(missing)} with none ({numbers(missing)})" if missing else "") + "."]
    if verified_only:
        out.append(f"Verifier records on PRs with no agent record, so no model to credit: {', '.join(verified_only)}.")
    if not recorded:
        out.append("No PR has an agent record, so there is nothing to tally.")
        return "\n".join(out)
    if missing:
        out.append("The PRs with none are left out of every number below.")
    out += ["", "Per role and model, over the PRs with a record:",
            f"{'role':<16} {'model':<18} {'runs':>4} {'PRs':>3} {'tokens/PR':>10} {'min/PR':>7}  per PR"]
    for (role, model), row in sorted(rows.items()):
        n = len(row["prs"])
        quality = ""
        if role == "builder":
            rounds = [p[1] for p in row["prs"] if p[1] is not None]
            quality = f"fix rounds {sum(rounds) / len(rounds):.1f}, failed pushes {sum(p[2] for p in row['prs']) / n:.1f}"
        elif role == "verifier":
            found = [p[3] for p in row["prs"] if p[3] is not None]
            quality = f"new findings {sum(found) / len(found):.1f}" if found else "no verifier record to count"
        out.append(f"{role:<16} {model:<18} {row['runs']:>4} {n:>3} {row['tokens'] // n:>10} "
                   f"{row['minutes'] / n:>7.1f}  {quality}".rstrip())
    out += ["", "Per PR:"]
    for number, runs, found, failed, rounds in recorded:
        parts = [f"#{number}: {len(runs)} runs, {sum(int(r['tokens']) for r in runs)} tokens, "
                 f"{sum(float(r['minutes']) for r in runs):.1f} min"]
        if rounds is not None:
            parts.append(f"fix rounds {rounds}")
        parts.append("no verifier record" if found is None else f"new findings {found}")
        parts.append(f"failed pushes {failed}")
        out.append(", ".join(parts))
    return "\n".join(out)


def main(argv):
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("command", nargs="?")
    parser.add_argument("args", nargs="*")
    parser.add_argument("--model")
    parser.add_argument("--round", type=int, default=1)
    parser.add_argument("--after", type=int, default=0)
    parser.add_argument("--note")
    opts, extra = parser.parse_known_args(argv)
    try:
        if extra:
            raise ValueError(f"unknown option {extra[0]}")
        if opts.command == "line" and len(opts.args) == 2:
            print(line(*opts.args, model=opts.model, round=opts.round, after=opts.after, note=opts.note))
            return 0
        if opts.command == "post" and len(opts.args) >= 2 and opts.args[0].isdigit():
            post(opts.args[0], opts.args[1:])
            return 0
        if opts.command == "tally" and len(opts.args) == 1 and re.fullmatch(r"\d{4}-\d{2}-\d{2}", opts.args[0]):
            prs, cost, remaining = fetch(opts.args[0])
            print(tally(prs, opts.args[0]))
            print(f"\nThis run cost {cost} GraphQL points; {remaining} left this hour.")
            return 0
    except ValueError as error:
        print(f"agent-record: {error}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        print(f"agent-record: {' '.join(error.cmd[:3])} failed: {(error.stderr or '').strip()} "
              "(is gh signed in? `gh auth status`)", file=sys.stderr)
        return 1
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
