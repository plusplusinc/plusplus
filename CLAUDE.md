# PlusPlus

A native iOS and watchOS workout tracker. Swift 6, SwiftUI, SwiftData + CloudKit. iOS 26 is the
minimum and new platform APIs are adopted freely. It gets used mid-set, one-handed.

This file is the constitution: loaded every session, kept short. Detail lives in
`.claude/rules/*.md`, which load when you touch matching files, and in `docs/`. If this file and a
rules file disagree, this file wins.

**Status: foundation only.** The app builds, runs, and renders a placeholder. There are no
features and no data model; the model follows the first feature. Do not add features, screens,
or domain types without being asked.

## Architecture

The Xcode project is a thin shell. Code lives in local Swift packages under `Packages/`.

```
App ──> Features ──> DesignSystem
              └────> WorkoutStore ──> WorkoutCore

DesignSystem  ──> SwiftUI only
WorkoutCore   ──> Foundation only
```

**These arrows are the rule, not a description.**

- `WorkoutCore` imports nothing but Foundation. No SwiftData, no SwiftUI. That is what lets its
  tests run in milliseconds without a simulator.
- `DesignSystem` never imports domain code. Components take strings and numbers.
- Features never import each other. Shared things move one layer down.
- Nothing imports `App`.

Plain SwiftUI, no view-model layer: views hold presentation logic, `@Observable` stores hold
state, stateless services hold side effects, free functions hold the math. The app,
`DesignSystem`, and `Features` are main-actor by default; `WorkoutCore` and `WorkoutStore` are
nonisolated so they run anywhere, including the Watch.

## How we work

- **Small steps, paired.** Plan briefly, change one thing, verify it, show it. Explain a
  platform-specific choice in a sentence or two when it first appears; no tutorials in docs.
- **Root causes, right altitude.** When something fails, diagnose before patching. No inline
  lint disables, `@unchecked Sendable`, sleeps, or retries to make a symptom go away. If a
  workaround is genuinely right, say so and why.
- **Done means verified.** A change is done when the build ran, the relevant tests ran, and for
  UI a screenshot was looked at. Say exactly what was run.
- **The repo may become public.** No secrets, team IDs, personal data, or scratch notes in
  tracked files. `Config/Local.xcconfig` holds the team ID and is gitignored. Temporary files go
  in `.build/` or outside the repo.
- **US English** in code, comments, docs, and commits. A hook checks every edit.

## Working in the project

- **Never hand-edit `project.pbxproj`.** It is under fifty lines and should stay that way. Build
  settings live in `Config/*.xcconfig`. Dependencies go in the relevant `Package.swift`.
- `App/` is a buildable folder: a file on disk is in the target. Anything in it ships inside the
  app bundle, so never leave notes or scratch files there.
- Local packages appear in the project both as package references and as folder references.
  The folder references are what let the app scheme run the packages' test targets; remove them
  and `xcodebuild test` finds no test bundles.
- `Config/Info.plist` holds only keys with no `INFOPLIST_KEY_*` equivalent.

## Commands

The scripts are the single source of truth; the `/build`, `/test`, `/lint`, `/run`, and `/pr`
skills wrap them, and Xcode Cloud runs the same lint script.

```sh
scripts/test.sh              # package tests on macOS, no simulator, seconds
scripts/build.sh             # app for the simulator, compact diagnostics
scripts/test.sh sim          # app scheme on the simulator: package, snapshot, and UI tests
scripts/run.sh [name]        # build, install, launch, screenshot to .build/screenshots/
scripts/lint.sh [--fix]      # SwiftFormat, SwiftLint, US English, as CI runs them
```

Apple documentation: the `sosumi` MCP server works with Xcode closed. The `xcode` MCP server
gives live diagnostics and preview rendering but needs Xcode open with the project loaded. See
`docs/agent-tooling.md`.

## Branching

**`main` only moves through pull requests. Never commit to it directly**, not even a one-line
fix. Branch protection enforces this server-side.

```sh
git switch -c <topic>
git push -u origin <topic>
gh pr create --fill
```

CI must be green before a PR merges. **Merges are squashed**: the PR title and body become the
one commit on `main`, so write the body as a commit message. Notes about review order or "as
discussed" belong in a PR comment, not the body.

## Persistence

`WorkoutStoreContainer` owns where and how data is stored, not what. `StorageMode` is explicit
(`.shared`, `.local`, `.inMemory`) because the modes point at different database files. The
CloudKit schema rules, and the fact that aggregates are computed in Swift, are in
`.claude/rules/swiftdata.md`.

## Design system

No raw colors, spacing, font sizes, or corner radii at call sites; use the tokens in
`Packages/DesignSystem`. Numbers that change in place use monospaced digits. Primary actions are
60pt and pinned, not 44pt inside a scrolling row. Liquid Glass stays in the functional layer.
Details in `.claude/rules/swiftui.md`.

## Testing

Swift Testing, cheapest tier first: pure logic in `WorkoutCore`, storage against an in-memory
container, snapshots for components, XCUITest only for core flows. Tests that need UIKit are
wrapped in `#if canImport(UIKit)` so `swift test` on macOS stays fast. Details in
`.claude/rules/testing.md`.

## Gotchas

- **Deleting the app does not reset data.** The store lives in the App Group container, which
  survives uninstall. Erase the simulator, or delete the container under
  `~/Library/Developer/CoreSimulator/Devices/<udid>/data/Containers/Shared/AppGroup/`.
- `.shared` storage works on the simulator even without provisioning, because the simulator
  does not enforce App Group or iCloud entitlements. A working simulator is not evidence that
  entitlements are set up.
- `-only-testing` with a misspelled identifier runs zero tests and exits 0. Check the total.
- `plutil -extract` rewrites the file in place. Use `plutil -p` to inspect.

## Not yet built

Watch app, Live Activity, HealthKit read/write, widgets. The App Group and CloudKit container
are configured now because they decide where the database lives, which is expensive to change
once real data exists. Live Watch-to-phone session state will go over WatchConnectivity, with
CloudKit as the backstop for history; CloudKit alone is too slow off Wi-Fi, which is the normal
state of a phone in a gym.
