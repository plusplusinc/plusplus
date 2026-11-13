#!/usr/bin/env python3
"""Each PR's record of its agents, and the tally of those records across merged PRs.

    scripts/agent-record.py line <role> '<usage line>' [--model M] [--round N] [--after TOKENS] [--note TEXT]
    scripts/agent-record.py post <pr> '<line>'...
    scripts/agent-record.py tally <since YYYY-MM-DD>

`line` prints one record line for one agent run, from the usage line of its task notification
(`<usage><subagent_tokens>…</subagent_tokens><tool_uses>…</tool_uses><duration_ms>…</duration_ms></usage>`;
the whole notification works too): `- <role>, <model>, round <n>: <tokens> tokens, <tool uses>
tool uses, <minutes> min[; <note>]`. The role is a row of docs/agent-tooling.md's "Models by task"
(a one-off by its agent's name: lookup, repro, edit, reviewer), and the model is that row's: a
--model that differs is refused. Only a row with no single model (the lead) and a plain
`general-purpose` agent, which has no row, take --model, the model the run was on (for
general-purpose, the default it fell to). A model is stored as its full id, an alias turned into the
id the table pins for its family, so the tally groups the two together. Round 1 is the build, and
each fix round after a verifier is the next. A resumed agent's notification counts its earlier runs'
tokens but only this run's tool uses and time (measured 2026-11-11: a builder reported 205129
tokens, 126 tool uses, 1244020 ms, then, resumed, 235600 tokens, 33 tool uses, 236542 ms), so
--after takes the earlier token total and subtracts it from the tokens alone. It reads no network.

`post` checks each line's shape and adds them to the PR as one comment headed `Agent record`, as
the verifier's record is a comment headed `Verifier record`: a comment can be added after the
merge, and the squash commit stays as it was. One `gh pr comment` call.

`tally` reads every PR merged to main since the date, with its comments and its commits' check
states, in one GraphQL request per 100 PRs (about 2 of the 5,000 points an hour each), and then,
for the commits of recorded PRs whose checks read failed, their checks, in one more request per
100 commits (about 1 point): a check cancelled by the next push is no failure. The run prints what
it cost. It counts only comments by the repo's owner, members, or collaborators. Per role and model
it prints runs, tokens and minutes per PR, and, for the builder, fix rounds and failed pushes per
PR, and for the verifier, per PR, the problems it caught that the builder missed (its record's
`new` lines but `test`) and the tests it added (`test, new`). A PR with no agent record is named
as having none, never counted as zeros. It needs `gh`. At night, `scripts/nightly-tooling.py tally`
calls the same fetch and tally and writes them to the night's folder for the retro and the setup
review.

Tests: python3 scripts/agent-record-test.py, with a stand-in `gh`, which scripts/test.sh runs.
"""
import argparse
import importlib.util
import json
import re
import subprocess
import sys
import time
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEADER = "Agent record"
VERIFIER = "Verifier record"
GENERAL = "general-purpose"  # no row: the model it fell to is passed
TRUSTED = {"OWNER", "MEMBER", "COLLABORATOR"}
ROLLUP_FAILED = {"FAILURE", "ERROR"}
RUN_FAILED = {"FAILURE", "TIMED_OUT", "STARTUP_FAILURE"}  # a check run's conclusion; CANCELLED is none
GH_LIMIT = 120  # seconds one GraphQL request may take, so a hung gh never holds the night's tally
LINE = re.compile(r"^- (?P<role>[\w -]+?), (?P<model>[\w.\[\]-]+), round (?P<round>\d+): (?P<tokens>\d+) tokens, "
                  r"(?P<tools>\d+) tool uses, (?P<minutes>\d+(\.\d)?) min(; (?P<note>.+))?$")
FINDING = re.compile(r"^- (?P<kind>\w+), new:")
QUERY = """query($q: String!, $after: String) {
  search(type: ISSUE, first: 100, query: $q, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes { ... on PullRequest { number mergedAt
      comments(first: 100) { nodes { body authorAssociation } }
      commits(first: 100) { nodes { commit { id statusCheckRollup { state } } } } } } }
  rateLimit { cost remaining } }"""
CHECKS = """query { nodes(ids: [%s]) { ... on Commit { id statusCheckRollup { contexts(first: 50) { nodes {
  __typename ... on CheckRun { conclusion } ... on StatusContext { state description } } } } } }
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


def canonical(model, rows, tool):
    """A model's full id: an alias becomes the id the table pins for its family, if it pins one."""
    family = tool.family(model)
    if family is None:
        raise ValueError(f"\"{model}\" is not a Claude model: pass an id like claude-opus-5-5, or an alias "
                         f"({', '.join(sorted(tool.ALIASES))})")
    if model not in tool.ALIASES:
        return model
    pinned = sorted({row["Model"] for row in rows.values()
                     if row["Model"] not in tool.ALIASES and tool.family(row["Model"]) == family})
    return pinned[0] if len(pinned) == 1 else model


def line(role, text, model=None, round=1, after=0, note=None, root=ROOT):
    tool = models()
    rows = {row["Role"]: row for row in tool.table((Path(root) / tool.TABLE).read_text())}
    if role == GENERAL:
        if not model:
            raise ValueError(f"a {GENERAL} agent has no row: pass --model, the default it fell to")
        model = canonical(model, rows, tool)
    elif role not in rows:
        raise ValueError(f"no role \"{role}\" in {tool.TABLE}'s \"{tool.SECTION}\" table: pass one of "
                         f"{', '.join(rows)}, or {GENERAL} with --model")
    elif tool.family(rows[role]["Model"]) is None:
        if not model:
            raise ValueError(f"the table gives {role} no single model (\"{rows[role]['Model']}\"): pass --model, "
                             "the one it ran on")
        model = canonical(model, rows, tool)
    else:
        table = canonical(rows[role]["Model"], rows, tool)
        if model and canonical(model, rows, tool) != table:
            raise ValueError(f"{role} runs on {table}, which the table sets; a run on another model is "
                             f"not one this record can hold: change the table's row first")
        model = table
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


def graphql(*fields, timeout=GH_LIMIT):
    args = ["gh", "api", "graphql"] + [arg for field in fields for arg in ("-f", field)]
    return json.loads(subprocess.run(args, capture_output=True, text=True, check=True,
                                     timeout=timeout).stdout)["data"]


def bodies(pr):
    return [c["body"].replace("\r\n", "\n").strip() for c in pr["comments"]["nodes"]
            if c.get("authorAssociation") in TRUSTED]


def rollups(pr):
    return [rollup for c in pr["commits"]["nodes"] if (rollup := (c["commit"] or {}).get("statusCheckRollup"))]


def fetch(since, limit=None):
    """The merged PRs, with the checks of each recorded PR's commits that read failed, and the
    GraphQL points the requests cost and left. Each request may take GH_LIMIT seconds, or, given
    a limit, all of them together that many: past it, TimeoutExpired, its timeout the limit."""
    until = time.monotonic() + limit if limit else None

    def ask(*fields):
        left = GH_LIMIT if until is None else until - time.monotonic()
        try:
            if left <= 0:
                raise subprocess.TimeoutExpired(["gh", "api", "graphql"], 0)
            return graphql(*fields, timeout=left)
        except subprocess.TimeoutExpired as error:
            raise subprocess.TimeoutExpired(error.cmd, limit or GH_LIMIT) from None

    query = f"repo:{repo()} is:pr is:merged base:main merged:>={since}"
    prs, cost, after = [], 0, None
    while True:
        data = ask(f"query={QUERY}", f"q={query}", *([f"after={after}"] if after else []))
        prs += [node for node in data["search"]["nodes"] if node]
        cost += data["rateLimit"]["cost"]
        remaining = data["rateLimit"]["remaining"]
        if not data["search"]["pageInfo"]["hasNextPage"]:
            break
        after = data["search"]["pageInfo"]["endCursor"]
    # Only a recorded PR's numbers are shown, so only its failed-looking commits are read again.
    unread = {c["commit"]["id"]: rollup for pr in prs if any(b.startswith(HEADER) for b in bodies(pr))
              for c in pr["commits"]["nodes"] if (rollup := (c["commit"] or {}).get("statusCheckRollup"))
              and rollup.get("state") in ROLLUP_FAILED and "contexts" not in rollup}
    ids = sorted(unread)
    for start in range(0, len(ids), 100):
        data = ask("query=" + CHECKS % ", ".join(json.dumps(i) for i in ids[start:start + 100]))
        for node in data["nodes"]:
            if node and node.get("statusCheckRollup"):
                unread[node["id"]]["contexts"] = node["statusCheckRollup"]["contexts"]
        cost += data["rateLimit"]["cost"]
        remaining = data["rateLimit"]["remaining"]
    return prs, cost, remaining


def failed(rollup):
    """Whether a commit's checks failed: one ran and failed, never one cancelled by the next push."""
    if rollup.get("state") not in ROLLUP_FAILED:
        return False
    if "contexts" not in rollup:
        return True  # not read again: only an unrecorded PR's, whose numbers aren't shown
    return any(c.get("conclusion") in RUN_FAILED if c.get("__typename") == "CheckRun"
               else c.get("state") in ROLLUP_FAILED and "cancel" not in (c.get("description") or "").lower()
               for c in rollup["contexts"]["nodes"])


def records(pr):
    """(agent runs, (problems, tests) or None when no verifier record, failed pushes) of one PR."""
    texts = bodies(pr)
    runs = [m.groupdict() for body in texts if body.startswith(HEADER)
            for m in map(LINE.match, body.splitlines()[1:]) if m]
    kinds = [m["kind"] for body in texts if body.startswith(VERIFIER)
             for m in map(FINDING.match, body.splitlines()[1:]) if m]
    found = (sum(k != "test" for k in kinds), kinds.count("test")) \
        if any(body.startswith(VERIFIER) for body in texts) else None
    return runs, found, sum(failed(rollup) for rollup in rollups(pr))


def numbers(found):
    return ", ".join(f"#{n}" for n in found)


def tally(prs, since):
    """The tally's text, from the PRs merged since the date."""
    recorded, missing, verified_only = [], [], []
    rows = defaultdict(lambda: {"runs": 0, "prs": [], "tokens": 0, "minutes": 0.0})
    for pr in sorted(prs, key=lambda p: p["number"]):
        runs, found, fails = records(pr)
        if not runs:
            missing.append(pr["number"])
            if found is not None:
                verified_only.append(f"#{pr['number']} ({found[0]} problems, {found[1]} tests)")
            continue
        builds = [int(r["round"]) for r in runs if r["role"] == "builder"]
        rounds = max(builds) - 1 if builds else None
        recorded.append((pr["number"], runs, found, fails, rounds))
        for r in runs:
            row = rows[(r["role"], r["model"])]
            row["runs"] += 1
            row["tokens"] += int(r["tokens"])
            row["minutes"] += float(r["minutes"])
            if (pr["number"], rounds, fails, found) not in row["prs"]:
                row["prs"].append((pr["number"], rounds, fails, found))
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
            quality = (f"problems caught {sum(f[0] for f in found) / len(found):.1f}, "
                       f"tests added {sum(f[1] for f in found) / len(found):.1f}") if found else "no verifier record to count"
        out.append(f"{role:<16} {model:<18} {row['runs']:>4} {n:>3} {row['tokens'] // n:>10} "
                   f"{row['minutes'] / n:>7.1f}  {quality}".rstrip())
    out += ["", "Per PR:"]
    for number, runs, found, fails, rounds in recorded:
        parts = [f"#{number}: {len(runs)} runs, {sum(int(r['tokens']) for r in runs)} tokens, "
                 f"{sum(float(r['minutes']) for r in runs):.1f} min"]
        if rounds is not None:
            parts.append(f"fix rounds {rounds}")
        parts.append("no verifier record" if found is None else f"problems caught {found[0]}, tests added {found[1]}")
        parts.append(f"failed pushes {fails}")
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
    except subprocess.TimeoutExpired as error:
        print(f"agent-record: {' '.join(error.cmd[:3])} took over {GH_LIMIT} s", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        print(f"agent-record: {' '.join(error.cmd[:3])} failed: {(error.stderr or '').strip()} "
              "(is gh signed in? `gh auth status`)", file=sys.stderr)
        return 1
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
