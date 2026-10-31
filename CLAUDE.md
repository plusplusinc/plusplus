# PlusPlus

A native iOS and watchOS workout tracker. Swift 6, SwiftUI, SwiftData + CloudKit. iOS 27 is the
minimum and new platform APIs are adopted freely. It gets used mid-set, one-handed. What the
product believes, and what the work aims for (the right product, built right, mostly
autonomous), are in `docs/principles.md`.

This file is the constitution: loaded every session, kept short. Detail lives in
`.claude/rules/*.md`, which load when you touch matching files, and in `docs/`. If this file and a
rules file disagree, this file wins.

**Status: routines, saved, a drawer between them, and a workout logged set by set on one.** The app launches into the routine last
opened or edited, or a new, empty one, which you can name and add built-in exercises to. ++, or
a swipe in from the left edge, slides the screen aside, darkened, onto a drawer: Routines, the
three routines last opened or edited, the last edited first, and New, an action, never marked;
an untouched new routine showing takes the first of the three rows, in gray. The place showing
sits on a fill, and nothing in the drawer changes while it shows. A haptic plays as it starts to
open and as it starts to shut. Routines opens the Routines screen, every saved routine by name
in the drawer's font, latest first, with no lines between rows; a row or its + pushes the routine, which a back chevron or the edge swipe pops. Every change saves on the phone
on its own: an untouched new routine is never saved, and one cleared to nothing is deleted. An
unnamed routine with exercises gets a name, written in code from its exercises' tags, which it
keeps across launches and which opens as text to edit. Each exercise in a routine carries its
own sets, reps or time, and weight, starting at the exercise's defaults and saved with the
routine; its row reads them, saying when a number is per side, and the routine's equipment
shows under its title. Tapping a row opens its values in a sheet, a row per value with a − / +
stepper, and Delete in its menu. Holding a row lifts it, and dragging moves it to a new place,
scrolling the list near its edges; VoiceOver moves it with Move up and Move down. Holding a
row's dot and dragging over other rows joins them into a superset, which a loop beside the rail
marks and whose rows share one round count; a held row resting half a second over a plain
neighbor pairs with it, at the larger set count; an end's dot moves that end, a body drag
carries a row in or out, and VoiceOver joins and leaves with actions. While a row or dot is
held, the superset the drag affects sits in a sunken area. Start, once the routine has an
exercise, runs a workout on the same screen: the first exercise grows into the current one, its
set, equipment, and numbers large, with no swipe. The key at the bottom, where Start was, a
capsule that stays put, logs the set at the numbers shown with a tap, saved at once, with a
haptic and a +1: "Log set", "Log left" then "Log right" where the exercise is per side, "Log
last set". Half a second later the next set rolls in, and after an exercise's last set a green
blob pulls out of the node, runs the rail, and plops into the next exercise's, which then grows
as the last shrinks, a superset going round its members by round. Scrolled away, the key shows
an arrow and the exercise's name and goes back to it; while a finger is on the list the key
keeps its role, and across roles one key drops out of the bottom edge as the next rises.
Started rows show a bar per set, purple once done, and a finished row's node turns purple;
after the last set, the key reads Finish workout and finishes it. End takes ++'s place
and asks "End this workout?": Finish workout, offered once a set is logged, keeps it, and
launch then opens a new routine; Discard workout keeps nothing. The time, at top right, pauses
and resumes. A workout survives a relaunch, keeps the screen on, and locks the drawer, and
every edit stays on. The app shows only in dark
appearance (`Config/Base.xcconfig`); the light palette is seen only in snapshots.
`WorkoutStore` holds the domain types, the stored models behind `RoutineStore` in a versioned
schema, workouts with their time and logged sets, the namer, the order sets go in and the next one, and the routines' recency. Nothing syncs yet.

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
  for cards, the board README, plans, State sections, and docs. Writing about a change that
  hasn't landed (a PR body, a commit, a handoff, a report, a message) is read before it
  exists, so keep today and the change apart: "Today the verifier reports only to the lead";
  "With this change, it also comments on the PR"; never the result in the plain present. Once
  it has landed, say where ("On `main` since #70"). A prompt asking for such writing asks for
  the same.

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
Anything the maintainer throws out, or the lead finds along the way, becomes a card through
`/brief`, which looks for one already there and places it in that queue; a small tooling or
process change the lead recommends in answer to their question is made then, in its own PR,
not offered as a card. Working files go in `.slices/`.
The maintainer's time is for the product. Tooling, CI, tests, and process (a standalone card
that changes nothing they see in the app, and the nightly retro's PR) are the lead's to find,
card, align, build, verify, and merge on its own once CI is green, alongside a product slice
where it can, telling them in a line what landed (Dave, 2026-10-28). It checks first that the
change is worth its cost and safe to undo. What reaches outside the repo or can't be undone
still waits for their word: spending money, or Xcode Cloud hours beyond the plan, a `v*` tag,
an account's settings, deleting what isn't the lead's.

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
scripts/test.sh              # package and script tests on macOS, no simulator, seconds
scripts/build.sh             # app for the simulator, compact diagnostics
scripts/test.sh sim          # everything on the simulator, including snapshots
scripts/run.sh [name]        # build, install, launch, screenshot to .build/screenshots/
scripts/device.sh [--link]   # build, install, launch on the iPhone, else an install link
scripts/sim.sh <command>     # drive the simulator: shots, appearance, reset, erase, log, motion
scripts/lint.sh [--fix]      # SwiftFormat, SwiftLint, US English, as CI runs them
scripts/board.sh <command>   # the private project board; run bare to list its commands
scripts/pr-check.sh <command> # the PR check's logic, run against a PR or commit
```

Reach an external service through its own CLI (`gh`, `asc`). A wrapper script or MCP server
has to earn its place; `docs/agent-tooling.md` says when, and how to build a script agents call.

Apple documentation: the `sosumi` MCP server works with Xcode closed. The `xcode` MCP server
gives live diagnostics and preview rendering, and on Xcode 27 runs headless with Xcode closed.
See `docs/agent-tooling.md`.

## Branching

**`main` only moves through pull requests. Never commit to it directly**, not even a one-line
fix. Branch protection enforces this server-side. Work in a worktree; the main checkout stays on
`main`, driving the maintainer's simulator and the nightly retro.

```sh
git fetch origin main
git worktree add --no-track .claude/worktrees/<topic> -b <topic> origin/main
git push -u origin <topic>
gh pr create --title "<title>" --body-file -   # body on stdin; --fill skips the PR template
```

CI must be green before a PR merges. **Merges are squashed**: the PR title and body become the
one commit on `main`, so write the body as a commit message that is also true before the
merge ("Tense tells the truth"). Notes about review order or "as
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
