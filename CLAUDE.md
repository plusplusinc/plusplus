# PlusPlus

A native iOS and watchOS workout tracker. Swift 6, SwiftUI, SwiftData + CloudKit. iOS 26 is the
minimum and new platform APIs are adopted freely. It gets used mid-set, one-handed.

This file is the constitution: loaded every session, kept short. Detail lives in
`.claude/rules/*.md`, which load when you touch matching files, and in `docs/`. If this file and a
rules file disagree, this file wins.

**Status: foundation only.** The app builds, runs, and renders a placeholder. There are no
features and no data model; the model follows the first feature.

## Architecture

The Xcode project is a thin shell. Code lives in one local Swift package, `Packages/`, whose
targets are the layers. A target cannot import what it does not list, so the compiler enforces
the arrows; SwiftLint custom rules catch the imports and idioms it cannot.

```
App ──> DesignSystem   (SwiftUI only, no domain code)
 └────> WorkoutStore   (SwiftData, no UI)
```

**These arrows are the rule, not a description.** New code goes in the lowest layer that can
hold it, and a new layer gets a target when it has code. Nothing imports `App`.

Plain SwiftUI, no view-model layer: views hold presentation logic, `@Observable` stores hold
state, stateless services hold side effects, free functions hold the math. The app and
`DesignSystem` are main-actor by default; `WorkoutStore` is nonisolated.

## How we work

- **Lean.** Nothing is added because it might be needed: no targets, entitlements, config,
  tokens, rules, abstractions, or docs for features that do not exist yet. Something gets added
  when the code being written needs it, and the PR says which present need it serves. A rule in
  this file or in `.claude/rules/` describes what the code does today, not a plan. When in doubt,
  leave it out; adding later is cheap, and removing later is not.
- **Small steps, paired.** Plan briefly, change one thing, verify it, show it. Explain a
  platform-specific choice in a sentence or two when it first appears; no tutorials in docs.
- **Root causes, right altitude.** When something fails, diagnose before patching. No inline
  lint disables, `@unchecked Sendable`, sleeps, or retries to make a symptom go away. If a
  workaround is genuinely right, say so and why.
- **Done means verified.** A change is done when the build ran, the relevant tests ran, and for
  UI a screenshot was looked at. Say exactly what was run.
- **The repo may become public.** No secrets, personal data, or scratch notes in tracked
  files. The team ID is not a secret and lives in `Config/Base.xcconfig`; `Config/Local.xcconfig`
  is the gitignored place for per-developer overrides. Temporary files go in `.build/` or
  outside the repo.
- **US English** in code, comments, docs, and commits. A hook checks every edit.

## Working in the project

- **Never hand-edit `project.pbxproj`.** It is under fifty lines and `scripts/lint.sh` fails if
  it grows. Build settings live in `Config/*.xcconfig`; dependencies in `Packages/Package.swift`.
- `App/` is a buildable folder: a file on disk is in the target. Anything in it ships inside the
  app bundle, so never leave notes or scratch files there.
- The package appears in the project both as a package reference and as a folder reference. The
  folder reference is what lets the app scheme run the package's test targets; remove it and
  `xcodebuild test` finds no test bundles.

## Commands

The scripts are the single source of truth; the `/build`, `/test`, `/lint`, `/run`, and `/pr`
skills wrap them, and Xcode Cloud runs the same lint script.

```sh
scripts/test.sh              # package tests on macOS, no simulator, seconds
scripts/build.sh             # app for the simulator, compact diagnostics
scripts/test.sh sim          # everything on the simulator, including snapshots
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

## Rules files

Loaded automatically when you touch matching files; read them before working in that area.

- `.claude/rules/swift.md`: concurrency defaults, `@Observable`, no force unwraps.
- `.claude/rules/swiftui.md`: plain SwiftUI, tokens, Dynamic Type, accessibility.
- `.claude/rules/swiftdata.md`: `StorageMode` and the CloudKit schema constraints.
- `.claude/rules/testing.md`: tiers, the snapshot helper, naming.

## Gotchas

- `-only-testing` with a misspelled identifier runs zero tests and exits 0. Check the total.
- `plutil -extract` rewrites the file in place. Use `plutil -p` to inspect, or pass `-o -`.
