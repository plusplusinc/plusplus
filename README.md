# PlusPlus

A workout tracker for incrementing yourself. Native iOS and watchOS. Swift 6, SwiftUI,
SwiftData + CloudKit, iOS 27 and up.

## Getting started

```sh
brew bundle              # formatting, lint, readable build output
open PlusPlus.xcodeproj
```

No generation step. The project is committed, `App/` is a buildable folder, and the code lives
in one local Swift package, so a file on disk is in the build.

The project signs with the PlusPlus team. To run on a device with your own team, override it
in `Config/Local.xcconfig` (gitignored):

```
DEVELOPMENT_TEAM = XXXXXXXXXX
```

### Hot reload

With [InjectionNext](https://github.com/johnno1962/InjectionNext) 2.0.1 or later in
`/Applications`, these two lines in `Config/Local.xcconfig` make saved edits appear in the
running simulator app in about a second, keeping its state. Simulator Debug builds only;
device, Release, and CI builds never see them.

```
OTHER_LDFLAGS[config=Debug][sdk=iphonesimulator*] = $(inherited) -Xlinker -interposable /Applications/InjectionNext.app/Contents/Resources/lib$(PLATFORM_NAME)Injection.dylib
EMIT_FRONTEND_COMMAND_LINES[config=Debug][sdk=iphonesimulator*] = YES
```

Launch with `scripts/run.sh`, which tells the app where the sources are. The first save or two
after a launch only loads the build logs. A view redraws on reload when it declares
`@ObserveHotReload private var hotReload` and ends its body with `.hotReloadable()`. Changes to
stored properties or to which files exist need a relaunch, which `scripts/run.sh` does.

## Everyday commands

```sh
scripts/test.sh          # package tests on macOS, no simulator, seconds
scripts/build.sh         # app for the simulator, compact diagnostics
scripts/test.sh sim      # everything on the simulator, including snapshots
scripts/run.sh           # build, install, launch, screenshot
scripts/device.sh        # the same on the iPhone, else an install link
scripts/sim.sh shots     # light, dark, and XXXL screenshots of the running app
scripts/lint.sh --fix    # SwiftFormat, SwiftLint, US English
```

## Layout

| Path | What lives there |
| --- | --- |
| `App/` | Entry point and screens. |
| `Packages/Sources/WorkoutStore` | Exercises and other domain types; the SwiftData container and storage modes. |
| `Packages/Sources/DesignSystem` | Design tokens and shared components. SwiftUI only, no domain knowledge. |
| `Config/` | Every build setting, as xcconfig. Nothing lives in the pbxproj. |
| `scripts/` | Build, test, lint, and run, shared by humans, agents, and CI. |
| `ci_scripts/` | Xcode Cloud hooks. |
| `.claude/` | Agent rules, skills, and hooks. See `docs/agent-tooling.md`. |

The dependency rules between the packages are the architecture; they are spelled out in
[CLAUDE.md](CLAUDE.md), which is also what agents read first.

## Status and contributing

Early: the app launches into the routine you last edited, or an empty one, which you can name
and add built-in exercises to, each with its own sets, reps or time, and weight, set in a sheet.
Every change saves on the phone, an unnamed routine is named for its exercises, and nothing
syncs yet. Status, architecture, and the branching rules are in
[CLAUDE.md](CLAUDE.md); Xcode Cloud, PR checks, and TestFlight builds in
[docs/xcode-cloud.md](docs/xcode-cloud.md).
