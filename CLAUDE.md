# PlusPlus

A native iOS and watchOS workout tracker. Swift 6, SwiftUI, SwiftData + CloudKit. iOS 27 is the
minimum and new platform APIs are adopted freely. It gets used mid-set, one-handed. What the
product believes, and what the work aims for (the right product, built right, mostly
autonomous), are in `docs/principles.md`.

This file is the constitution: loaded every session, kept short. Detail lives in
`.claude/rules/*.md`, which load when you touch matching files, and in `docs/`. If this file and a
rules file disagree, this file wins.

**Status: first screen, saved.** The app launches into the routine last edited, or a new,
empty one, which you can name and add built-in exercises to. Every change saves on the phone
on its own: an untouched new routine is never saved, and one cleared to nothing is deleted. An
unnamed routine with exercises gets a name, written in code from its exercises' tags, which it
keeps across launches and which opens as text to edit. Each exercise in a routine carries its
own sets, reps or time, and weight, starting at the exercise's defaults and saved with the
routine; its row reads them, saying when a number is per side, and the routine's equipment
shows under its title. Tapping a row opens its values in a sheet, a row per value with a − / +
stepper, and Delete in its menu. `WorkoutStore` holds the domain types, the first stored models
behind `RoutineStore`, and the namer. Nothing syncs yet.

## Architecture

The Xcode project is a thin shell. Code lives in one local Swift package, `Packages/`, whose
targets are the layers. A target cannot import what it does not list, so the compiler enforces
the arrows; SwiftLint custom rules catch the imports and idioms it cannot.

```
App ──> DesignSystem   (SwiftUI only, no domain code)
 └────> WorkoutStore   (domain types, SwiftData, and routine naming; no UI)
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
- **The repo is public.** Every push publishes. No secrets, personal data, or scratch notes in
  tracked files. The team ID is not a secret and lives in `Config/Base.xcconfig`;
  `Config/Local.xcconfig` is the gitignored place for per-developer overrides. Build output and
  other regenerable files go in `.build/`. Product spec, acceptance criteria, and decisions live
  on the board; the gitignored `.slices/`, in the main checkout, holds only agents' technical
  working files (plans, handoffs, evidence).
- **US English** in code, comments, docs, and commits. A hook checks every edit.
- **Tense tells the truth.** A present-tense statement says how things are on `main` today, so
  write one only when it is. Something planned is an instruction ("Save the routine once it
  changes") or says "will". A decision that isn't built yet says it was decided. This holds
  for cards, the board README, plans, State sections, and docs. A PR body describes `main`
  after the merge, because it becomes the commit.

## Building features

The main session leads a slice: it writes the spec and acceptance criteria, makes technical
calls, and hands each phase, in order, to a subagent defined in `.claude/agents/`: planner,
builder, verifier, then a builder again for anything the verifier found. It reads their
summaries and screenshots, not their work, and goes to the maintainer only to align on a card
before it starts, for a product call, or to put a build in their hands; the maintainer tries
every slice before it merges. A subagent follows its definition, answers only to the lead, never
merges, and when it runs long writes a handoff note so a fresh one can continue in the same
worktree.
A slice with something to see goes on the maintainer's phone as soon as their feedback would help,
then in rounds while they are engaged. A round is shown, not done: it skips the thorough checks,
which wait until they say it's right and then run once, as the phases above.
The maintainer clears the lead's context between slices; `/onward` starts or resumes the next
card from the project board, whose Todo column, in board order, is one queue of feature slices
and standalone tasks.
Anything the maintainer throws out becomes a card through `/brief`, which places it in that
queue. Working files go in `.slices/`.

## Working in the project

- **Never hand-edit `project.pbxproj`, and keep it free of build settings.** Settings live in
  `Config/*.xcconfig` and `scripts/lint.sh` fails if one lands in the project, which Xcode's
  wizards occasionally do. Dependencies go in `Packages/Package.swift`.
- `App/` is a buildable folder: a file on disk is in the target. Anything in it ships inside the
  app bundle, so never leave notes or scratch files there.
- The package appears in the project both as a package reference and as a folder reference. The
  folder reference is what lets the app scheme run the package's test targets; remove it and
  `xcodebuild test` finds no test bundles.

## Commands

The scripts are the single source of truth; the `/build`, `/test`, `/lint`, `/run`, `/brief`,
`/onward`, `/pr`, and `/retro` skills wrap them, and Xcode Cloud runs the same lint script.

```sh
scripts/test.sh              # package tests on macOS, no simulator, seconds
scripts/build.sh             # app for the simulator, compact diagnostics
scripts/test.sh sim          # everything on the simulator, including snapshots
scripts/run.sh [name]        # build, install, launch, screenshot to .build/screenshots/
scripts/device.sh [--link]   # build, install, launch on the iPhone, else an install link
scripts/sim.sh <command>     # drive the simulator: shots, appearance, reset, erase-team, log
scripts/lint.sh [--fix]      # SwiftFormat, SwiftLint, US English, as CI runs them
scripts/board.sh <command>   # the private project board; run bare to list its commands
```

Reach an external service through its own CLI (`gh`, `asc`). A wrapper script or MCP server
has to earn its place; `docs/agent-tooling.md` says when, and how to build a script agents call.

Apple documentation: the `sosumi` MCP server works with Xcode closed. The `xcode` MCP server
gives live diagnostics and preview rendering, and on Xcode 27 runs headless with Xcode closed.
See `docs/agent-tooling.md`.

## Branching

**`main` only moves through pull requests. Never commit to it directly**, not even a one-line
fix. Branch protection enforces this server-side.

```sh
git switch -c <topic>
git push -u origin <topic>
gh pr create --title "<title>" --body-file -   # body on stdin; --fill skips the PR template
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

- `-only-testing` with a misspelled identifier runs zero tests and exits 0 in raw `xcodebuild`
  and the xcode MCP's `RunSomeTests`. `scripts/test.sh` fails on it; run filtered tests
  through it.
- `plutil -extract` rewrites the file in place. Use `plutil -p` to inspect, or pass `-o -`.
