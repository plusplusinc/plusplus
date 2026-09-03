# PlusPlus

A workout tracker for incrementing yourself. Native iOS and watchOS. Swift 6, SwiftUI,
SwiftData + CloudKit, iOS 26 and up.

## Getting started

```sh
brew install swiftformat swiftlint xcbeautify   # formatting, lint, readable build output
open PlusPlus.xcodeproj
```

No generation step, no bootstrap script. The project is committed, `App/` is a buildable folder,
and the code lives in local Swift packages, so a file on disk is in the build.

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
| `App/` | Entry point and entitlements. Deliberately thin. |
| `Packages/WorkoutCore` | Domain types and pure logic. Foundation only. Currently empty. |
| `Packages/WorkoutStore` | Storage wiring: App Group container, CloudKit, storage modes. |
| `Packages/DesignSystem` | Design tokens, and soon components. SwiftUI only. |
| `Packages/Features` | Screens. Currently empty. |
| `Config/` | Every build setting, as xcconfig. Nothing lives in the pbxproj. |
| `scripts/` | Build, test, lint, and run, shared by humans, agents, and CI. |
| `ci_scripts/` | Xcode Cloud hooks. |
| `.claude/` | Agent rules, skills, hooks, and subagents. See `docs/agent-tooling.md`. |

The dependency rules between the packages are the architecture; they are spelled out in
[CLAUDE.md](CLAUDE.md), which is also what agents read first.

## Status

Foundation only. The app builds, runs, and renders a placeholder. There are no features and no
data model yet, by design. What exists is the scaffolding: project and build configuration,
module layering, design tokens, storage wiring, test harness, tooling, and CI.

Not built yet: Watch app, Live Activity, HealthKit, widgets. The App Group and CloudKit
container are configured already because they determine where the database lives, which is
expensive to change once real data exists.

## Contributing

`main` only moves through pull requests, squash-merged, with Xcode Cloud green. See
[docs/ci.md](docs/ci.md).
