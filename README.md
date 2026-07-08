# ++ (PlusPlus)

An iOS fitness tracker where **your training data is a git repo you own**.
The `++` mark is the increment operator — squint and it's a dumbbell.

## What it does

- **Build routines** from a built-in exercise catalog or your own custom
  exercises (muscle group, equipment, form notes, reference video) — your
  personal library grows by choice, not by default
- **Supersets** as a first-class structure — groups rotate strictly
  (A1 B1 A2 B2 …) during execution
- **Keyboard-free logging**: steppers + wheel pickers for weight, reps,
  rep ranges ("15–20"), and durations; sensible defaults from empty
- **Run routines** with prefilled set logging, a date-based rest countdown
  (survives backgrounding, notifies when rest ends), "last time" context
  from history, and routine-level notes at session start
- **History** that snapshots everything at run time — editing or deleting
  a template never rewrites what you actually did
- **Export/import** the whole library through a documented, deterministic
  JSON format

Built for a real acceptance case: a physical-therapy prescription with
band work, rep ranges, form cues, and a reference video — entered exactly
as prescribed.

## The platform: repo-as-backend

There is no PlusPlus server. Training data serializes to versioned JSON
(sorted keys, ISO-8601 dates — clean diffs) in a layout shared by the
app, the CLI, and agents:

```
program/exercises/   one exercise per file
program/routines/    one routine per file
history/YYYY/        finished sessions — append-only
```

- **`plusplus` CLI** (Linux + macOS): `init`, `lint`, `stats`, `import`,
  `export`, and `mcp` — an MCP server exposing the repo to agents,
  including a fenced `propose_program_change` that writes branches, never
  pushes
- **App ↔ GitHub sync** (in progress, #23): device-flow auth, per-file
  three-way merge for templates, append-only pushes for sessions
- **Agents**: see [`docs/AGENTS.md`](docs/AGENTS.md);
  [`docs/recipes/`](docs/recipes/) has copy-paste Actions (schema lint on
  PRs, weekly stats report)
- **Claude**: `plusplus init` scaffolds training repos with a CLAUDE.md +
  skills (weekly-review / tweak-program / deload-check), and this repo is
  a Claude Code plugin marketplace — `/plugin marketplace add
  plusplusinc/plusplus`, then `/plugin install plusplus@plusplus`

Architecture and format contract: [`docs/PLATFORM.md`](docs/PLATFORM.md).

## Repo tour

| Directory | What it is |
|---|---|
| `PlusPlus/` | iOS app (SwiftUI + SwiftData, iOS 26) |
| `PlusPlusWatch/` | watchOS companion: wrist execution over WatchConnectivity, HealthKit workout sessions, append-only sync-back |
| `PlusPlusWidgets/` · `PlusPlusShared/` | Widget extension (rest Live Activity, Today/Streak widgets, App Intents) + the sources it shares with the app |
| `PlusPlusKit/` | Platform-pure SwiftPM package: taxonomy, metrics, interchange codec/validator, sync engine. No SwiftUI/SwiftData — tested on Linux in CI to keep it that way |
| `PlusPlusCLI/` | The `plusplus` CLI + MCP server (SwiftPM executable, Linux-native) |
| `PlusPlusTests/` · `PlusPlusKit/Tests/` · `PlusPlusCLI/Tests/` | Unit suites for all three layers — every push runs them in CI |
| `PlusPlusUITests/` | Smoke flows that run on the CI simulator and upload screenshots |

## Development

Requirements: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The `.xcodeproj` is generated, not checked in:

```sh
xcodegen generate
open PlusPlus.xcodeproj
```

The Kit and CLI build anywhere Swift 6 does:

```sh
swift test --package-path PlusPlusKit
swift test --package-path PlusPlusCLI
swift build -c release --package-path PlusPlusCLI   # → .build/release/plusplus
```

CI (`.github/workflows/ci.yml`) runs the app suite on a macOS runner and
the Kit/CLI suites on Linux; UI smoke tests run on pushes to main and by
manual dispatch, uploading a `ui-screenshots` artifact. Tagging `v*` cuts
a CLI release with Linux/macOS binaries.

Work is tracked in GitHub issues; changes land via PRs. `CLAUDE.md` holds
architecture principles, the decisions log, and session discipline — this
project is developed largely through Claude Code sessions, including
fully remote ones (the Linux-testable core exists partly so remote
sessions can verify their own work).

## License

PlusPlus is open source with a deliberate split:

- **The app** (`PlusPlus/`, `PlusPlusWatch/`, `PlusPlusWidgets/`, and this repo as a whole) is licensed under **[AGPL-3.0](LICENSE)** — read it, fork it, contribute to it; shipping a rebranded clone obligates you to publish your changes under the same terms.
- **The contract** — [`PlusPlusKit/`](PlusPlusKit/LICENSE) (the interchange format, codec, validator, diff/schedule engines) and [`PlusPlusCLI/`](PlusPlusCLI/LICENSE) — is **MIT**. The format is meant to be adopted: build importers, exporters, tools, and agents on it without copyleft obligations.

The interchange format's conformance fixtures (`PlusPlusKit/Tests/PlusPlusKitTests/Fixtures/`) are the language-neutral spec; MIT applies to those too.
