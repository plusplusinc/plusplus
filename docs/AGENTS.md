# Point your agent at your routine repo

Your training data is a git repo of documented, deterministic JSON
(schema: `docs/PLATFORM.md`). That means agents can already work with it
three ways, from zero setup to turnkey.

## 1. No tooling: it's just files

Any agent that can read a repo can coach from it today:

- `program/exercises/*.json` — one exercise per file (muscle group, type,
  equipment, notes, video link)
- `program/routines/*.json` — templates; a group with more than one
  exercise is a superset
- `history/YYYY/*.json` — finished sessions, append-only, targets and
  actuals per set

Deterministic serialization (sorted keys, ISO-8601 dates) keeps diffs
clean, so "what changed in my program last month" is `git log -p program/`.

## 2. The CLI: structured answers, safe writes

```sh
plusplus lint --json      # {valid, counts, issues[{path, message}]}
plusplus stats --json     # per-exercise aggregates
plusplus export           # whole repo as one bundle file
plusplus init new-repo    # scaffold a fresh routine repo
```

Agents should lint before committing program edits — the same validator
gates the app's importer, so a green lint means the app will take it.

## 3. The MCP server: turnkey

`plusplus mcp --repo <path>` serves the repo over MCP (stdio). Example
client config:

```json
{
  "mcpServers": {
    "routines": {
      "command": "plusplus",
      "args": ["mcp", "--repo", "/Users/you/routines"]
    }
  }
}
```

Tools:

| Tool | What it returns |
|---|---|
| `list_exercises` | Exercise DTOs, verbatim interchange JSON |
| `list_routines` | Routine templates with groups/supersets and targets |
| `get_history` | Sessions, newest first (`limit`, `routine` filters) |
| `stats` | Per-exercise aggregates (`exercise` filter) |
| `lint` | `{valid, counts, issues}` |
| `propose_program_change` | Writes program files to a **new git branch**, commits, returns the branch name |

`propose_program_change` is the only mutating tool and it's deliberately
constrained: `program/**.json` paths only (history is append-only and off
limits), the work tree must be clean, the result must lint or the branch
is rolled back, and **nothing is ever pushed** — the CLI never
authenticates to GitHub. Review the branch, push it, open the PR; your
repo's lint recipe (`docs/recipes/`) is the second gate.

## Automation recipes

`docs/recipes/` has copy-paste GitHub Actions for routine repos: schema
lint on every program PR, and a weekly stats report filed as an issue.
