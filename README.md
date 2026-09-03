# PlusPlus

A workout tracker for incrementing yourself. Native iOS and watchOS. Swift 6, SwiftUI,
SwiftData + CloudKit, iOS 26 and up.

## Getting started

```sh
brew bundle              # formatting, lint, readable build output
open PlusPlus.xcodeproj
```

No generation step. The project is committed, `App/` is a buildable folder, and the code lives
in one local Swift package, so a file on disk is in the build.

To run on a device, put your team ID in `Config/Local.xcconfig` (gitignored):

```
DEVELOPMENT_TEAM = XXXXXXXXXX
```

## Everyday commands

```sh
scripts/test.sh          # package tests on macOS, no simulator, seconds
scripts/build.sh         # app for the simulator, compact diagnostics
scripts/test.sh sim      # everything on the simulator, including snapshots
scripts/run.sh           # build, install, launch, screenshot
scripts/lint.sh --fix    # SwiftFormat, SwiftLint, US English
```

## Layout

| Path | What lives there |
| --- | --- |
| `App/` | Entry point. Deliberately thin. |
| `Packages/Sources/WorkoutStore` | Storage wiring: SwiftData container and storage modes. |
| `Packages/Sources/DesignSystem` | Design tokens. SwiftUI only, no domain knowledge. |
| `Config/` | Every build setting, as xcconfig. Nothing lives in the pbxproj. |
| `scripts/` | Build, test, lint, and run, shared by humans, agents, and CI. |
| `ci_scripts/` | Xcode Cloud hooks. |
| `.claude/` | Agent rules, skills, and hooks. See `docs/agent-tooling.md`. |

The dependency rules between the packages are the architecture; they are spelled out in
[CLAUDE.md](CLAUDE.md), which is also what agents read first.

## Status and contributing

Foundation only: no features, no data model yet, by design. Status, architecture, and the
branching rules are in [CLAUDE.md](CLAUDE.md); CI and releases in [docs/ci.md](docs/ci.md).
