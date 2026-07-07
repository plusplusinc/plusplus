# PlusPlus Developer Platform

> Status: phase 1 in progress. Tracking issues: #20 (format), #21 (core package),
> #22 (app export/import), #23 (GitHub sync), #24 (CLI), #25 (agents).
> Owner-action TODOs at the bottom.

## Vision

PlusPlus's first niche is developers. The pitch: **your training data is yours,
as files, in your own GitHub repo** — readable JSON with clean diffs, editable by
you, your scripts, or your agents. The iPhone app (and later the watch) is the
execution surface at the gym; the repo is the durable, scriptable system of record
for programs and history.

What this unlocks, concretely:

- Point an agent at your routine repo: "review my last month and PR an adjustment
  to my program." No PlusPlus-specific tooling required — agents already speak
  GitHub.
- GitHub Actions on your own training data: weekly progress-report issues, schema
  lint on program PRs, badges.
- Every finished routine is a commit. Diffs show progression; the contribution
  graph goes green on gym days.
- A CLI (`plusplus`) for stats, program editing, and linting — over a plain git
  clone.

## Principles

1. **No PlusPlus server.** GitHub provides auth, storage, versioning, webhooks,
   and access control. We build zero infrastructure until demand proves otherwise.
2. **The file format is the API contract.** Everything — app export, repo sync,
   CLI, MCP — speaks the same versioned JSON (schema below). Nothing built on it
   is throwaway if a hosted API ever appears.
3. **Local-first at the gym.** The app's SwiftData store is the live source of
   truth during a session. Sync is opportunistic; a concrete basement changes
   nothing.
4. **History is append-only.** Finished sessions flow app → repo, one file each,
   and never conflict. Templates (exercises, routines) sync bidirectionally,
   per-file, with a keep-mine/take-theirs prompt on the rare true conflict.
5. **Deterministic serialization.** Sorted keys, ISO-8601 dates, stable array
   ordering. Git diffs of these files must be readable, or the whole story falls
   apart.

## Architecture

```
┌────────────┐   contents/git-data API   ┌──────────────────┐   git clone   ┌─────────────┐
│ iPhone app │ ◄────────────────────────► │  you/routines    │ ◄───────────► │ plusplus CLI │
│ (SwiftData │      (GitHub App,          │  (private repo)  │               │  / agents /  │
│  is live   │       device flow)         │                  │ ◄──webhooks── │  Actions     │
│  truth)    │                            └──────────────────┘               └─────────────┘
└────────────┘
        └── shared code: PlusPlusKit (pure Swift package: enums, metric/rep logic,
            interchange DTOs + codec + validation) — used by app, CLI, MCP server
```

- The app never runs git; it uses GitHub's REST contents/git-data APIs, with the
  required-SHA parameter providing optimistic concurrency (stale writes fail
  loudly instead of clobbering).
- The CLI uses actual git on a clone. Same files, two transports.
- The sync layer sits behind a `RepoStore` protocol; GitHub is one implementation
  (a local-folder implementation falls out for free and serves tests and
  non-GitHub users).

## Repo layout (the user's routine repo)

```
program/
  exercises/
    band-pulses.json          # one file per custom exercise (slugged name)
  routines/
    shoulder-pt.json          # one file per routine template
history/
  2026/
    2026-07-05-shoulder-pt.json   # one file per finished session; append-only
README.md                     # (later) auto-generated summary
```

Built-in library exercises are not written to the repo; routine files may
reference them by name, and the app resolves them against its seed library.
An exercise file is written only for custom exercises (or built-ins the user
has effectively customized).

## Interchange schema v1

Envelope rule: every document carries `schemaVersion` (currently `1`). Readers
reject versions above what they understand. All dates are ISO-8601 UTC. JSON is
encoded with sorted keys and pretty-printing.

The app's single-file export (backup / manual transport) is a bundle:

```json
{
  "schemaVersion": 1,
  "exercises": [
    {
      "equipment": ["Resistance Band"],
      "exerciseType": "weightReps",
      "isBuiltIn": false,
      "muscleGroup": "shoulders",
      "name": "Band Pulses",
      "notes": "Elbows bent, shoulder flexed to 90°.",
      "videoURL": "https://youtu.be/ykZHbcGNfII"
    }
  ],
  "routines": [
    {
      "groups": [
        {
          "exercises": [
            { "exercise": "Y Raise", "reps": 10, "weight": 5 },
            { "exercise": "T Raise", "reps": 10, "weight": 5 }
          ],
          "sets": 3
        },
        {
          "exercises": [
            { "exercise": "Band Pulses", "reps": 15, "repsUpper": 20 }
          ],
          "sets": 3
        }
      ],
      "name": "Shoulder PT",
      "restSeconds": 60
    }
  ],
  "sessions": [
    {
      "endedAt": "2026-07-05T15:04:11Z",
      "restSeconds": 60,
      "sets": [
        {
          "actualReps": 10, "actualWeight": 5,
          "completedAt": "2026-07-05T14:33:20Z",
          "exerciseName": "Y Raise", "exerciseType": "weightReps",
          "groupIndex": 0, "order": 0, "setNumber": 1,
          "targetRepsLower": 10, "targetWeight": 5
        }
      ],
      "startedAt": "2026-07-05T14:31:00Z",
      "routineName": "Shoulder PT"
    }
  ]
}
```

In the repo layout, the same DTOs are stored one entity per file, wrapped in a
document envelope: `{ "schemaVersion": 1, "exercise": { … } }` (likewise
`"routine"` / `"session"` — see `InterchangeDocuments.swift`). A group with >1 exercise is a superset —
same uniform model as the app.

Semantics worth writing down:

- **Exercise references are by name** (the app enforces unique names). Multi-word
  names slug to file names (`Band Pulses` → `band-pulses.json`).
- **Rep ranges**: `reps` is the target (or range lower bound); `repsUpper`, when
  present, must exceed `reps`. `"15–20"` ⇒ `reps: 15, repsUpper: 20`.
- **Sessions snapshot everything** (names, types, targets) exactly like the app's
  data model, so history files stand alone even if templates change.
- **Import policy** (app side): exercises upsert by case-insensitive name;
  routines replace-or-create by name; sessions append only — an incoming session
  with the same routine name and start time as an existing one is skipped.
- **Units** (decided 2026-07-06, issue #33): weight numbers are unit-agnostic;
  a bundle's optional `units` field (`"lb"` / `"kg"`) declares what they mean,
  and **absent always means pounds** — every pre-units file stays valid.
  Nothing ever converts values: switching the app's unit setting (or a bundle
  declaring `kg`) changes labels, stepping, and defaults only. The per-file
  repo layout carries no units marker yet (lb-implied) — add a repo-level meta
  file only when a real kg repo exists.
- **Renames** (decided 2026-07-06, issue #32): exercise identity IS the name.
  Renaming an exercise starts a fresh identity — history and "last time" stay
  with the old name, and sync sees a new file alongside the old one (which the
  deletion-deferred policy keeps). The app warns on rename; case-only changes
  don't count (same slug, same match). No stable IDs, no rename manifest, by
  choice: cheapest model, and it matches how lifters think ("front squat" and
  "squat" are different lifts, not one lift renamed). Revisit only if it chafes.

## Sync semantics (phase: #23)

| Data | Direction | Conflict handling |
|---|---|---|
| Sessions | app → repo, on finish (queued offline) | none possible (new file, append-only) |
| Routines / exercises | bidirectional, on app foreground + manual pull | per-file SHA compare; only both-sides-changed prompts keep-mine/take-theirs |

Commit messages are human-readable: `Log: Shoulder PT — 8 sets`,
`Edit: Push Day (from iPhone)`.

Auth is a **GitHub App with device flow** (fine-grained, installed on exactly the
one routine repo), token in the Keychain. Not classic OAuth `repo` scope.

## Phases

1. **Format + core package** (#20, #21) — DTOs, deterministic codec, validation,
   `PlusPlusKit` SwiftPM package shared by everything, Linux CI. *Remote-buildable.*
2. **App export/import** (#22) — mapping + Settings UI. The manual-transport
   version of everything above; also the backup story. *Remote-buildable except
   hands-on UI validation.*
3. **GitHub sync in the app** (#23) — device flow, `RepoStore`, repo bootstrap,
   sync engine. *Groundwork shipped remotely: `FileLayout` (paths + append-only
   session placement) and `SyncPlanner` (pure per-file three-way merge:
   writes/pulls/conflicts, deletions deferred) live in PlusPlusKit with tests.
   Remaining — device-flow auth, the GitHub `RepoStore`, and wiring — needs
   Mac + GitHub App registration.*
4. **CLI** (#24) — v0 shipped: `plusplus lint / stats / import / export` in
   `PlusPlusCLI/` (Swift + swift-argument-parser; decisions recorded on the
   issue: Swift over Go, no GitHub auth — git is transport and auth).
   Conformance fixtures live in `PlusPlusKit/Tests/.../Fixtures/`. Remaining:
   `program` editing subcommands, Homebrew tap.
5. **Agents** (#25) — MCP server + showcase Actions. *Remote-buildable.*

Sequencing note: all platform work stays behind v1 validation (#1) in priority —
the phone loop must be confirmed working in hand first.

## TODO (owner actions — things Claude can't do remotely)

- [ ] **#1 Mac validation session** — walk the checklist on issue #1 (now includes
      export/import UI once #22 lands).
- [ ] **Register the GitHub App** for #23 (Settings → Developer settings → GitHub
      Apps): device flow enabled, Contents read/write as the only repo permission,
      no webhooks needed initially. Put the app slug/client ID somewhere Claude
      can reach (issue comment on #23 is fine — client IDs aren't secrets; the
      device flow needs no client secret).
- [ ] **Decide the public repo template name** (e.g. `plusplus-routines-template`)
      when #23/#25 need it.
- [ ] **Create a Homebrew tap repo** (`mrdavidjcole/homebrew-plusplus`) when #24
      is ready to ship.
- [ ] **Watch app (#6)** — unchanged; plan lives on the issue.
