# PlusPlus

A native iOS and watchOS workout tracker. Swift 6, SwiftUI, SwiftData + CloudKit. iOS 27 is the
minimum and new platform APIs are adopted freely. It gets used mid-set, one-handed. What the
product believes, what the work aims for (the right product, built right, mostly autonomous),
and who owns what are in `docs/principles.md`: the maintainer owns the product and its
decisions, and the lead owns the codebase, whose worth is how quickly and safely it turns
product intent into excellent behavior.

This file is the constitution: loaded every session, kept short. Detail lives in
`.claude/rules/*.md`, which load when you touch matching files (read the one for an area before
planning work in it), and in `docs/`. If this file and a rules file disagree, this file wins.

**Status.** The app is one screen and its drawer: a workout built from built-in and created exercises, each
with its sets, reps or time, weight, and rest, some joined into supersets, saved on the phone as
it is edited, and logged set by set on that same screen; a Workouts screen listing and
filtering the saved ones; and Log, the finished ones. Settings, from the drawer, picks Light,
Dark, or the phone's, and Void makes dark true black. Nothing syncs yet, and there is no
watch app yet.

This file does not say how a feature looks or behaves. That is in the doc comments of the types
that draw it, which `.claude/rules/swiftui.md` maps, and, as designed, in the board README
(`scripts/board.sh readme <feature>`). A slice changes the paragraph above only when it makes
one of its sentences false.

## Architecture

The Xcode project is a thin shell. Code lives in one local Swift package, `Packages/`, whose
targets are the layers. A target cannot import what it does not list, so the compiler enforces
the arrows; SwiftLint custom rules catch the imports and idioms it cannot.

```
App ──> DesignSystem   (SwiftUI only, no domain code)
 ├────> Session ──> WorkoutStore   (the open workout and its logged sets, observable; no UI)
 └────> WorkoutStore   (domain types, SwiftData, and workout naming; no UI)
```

`Session` ships inside the `WorkoutStore` product, so the app links it with no project change.

**These arrows are the rule, not a description.** New code goes in the lowest layer that can
hold it, and a new layer gets a target when it has code. Nothing imports `App`.

Plain SwiftUI, no view-model layer: views hold presentation logic, `@Observable` stores hold
state, stateless services hold side effects, free functions hold the math. The app,
`DesignSystem`, and `Session` are main-actor by default; `WorkoutStore` is nonisolated.

## How we work

- **Lean.** Nothing is added because it might be needed: no targets, entitlements, config,
  tokens, rules, abstractions, or docs for features that do not exist yet. Something gets added
  when the code being written needs it, and the PR says which present need it serves. A rule in
  this file or in `.claude/rules/` describes what the code does today, not a plan. When in doubt,
  leave it out; adding later is cheap, and removing later is not. The agent docs have a word
  budget that `scripts/lint.sh` enforces: to add a line, cut one, and lower the budget when a
  cut leaves room.
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
  on the board; the gitignored `.slices/` in the leading session's own worktree holds only
  agents' technical working files (plans, handoffs, evidence), which the card's State names by
  absolute path; the rules ledger, night handoffs, and setup reviews end in the main checkout's.
- **US English** in code, comments, docs, and commits. A hook checks every edit.
- **Tense tells the truth.** A present-tense statement says how things are on `main` today, so
  write one only when it is. Something planned is an instruction ("Save the workout once it
  changes") or says "will". A decision that isn't built yet says it was decided. This holds
  for cards, the board README, plans, State sections, and docs. Writing about a change that
  hasn't landed (a PR body, a commit, a handoff, a report, a message) is read before it
  exists, so keep today and the change apart: "Today the verifier reports only to the lead";
  "With this change, it also comments on the PR"; never the result in the plain present. Once
  it has landed, say where ("On `main` since #70"). A prompt asking for such writing asks for
  the same.

## Building features

The main session leads a slice, as `/onward` describes: it writes the spec and acceptance
criteria, makes the technical calls, and hands each phase, in order, to a subagent defined in
`.claude/agents/`: planner, builder, and, for a card that touches stored data or the live
workout's state, verifier. It reads their summaries, screenshots, and each change's shape, and
itself makes a round's small changes. A subagent follows its definition, answers only to the
lead, and never merges.

The maintainer owns the product. The lead goes to them to align on a card before it starts, for
a product call, or to put a build in their hands, and they try every slice before it merges. A
slice with something to see goes on their phone as soon as their feedback would help, then in
rounds; a round is shown, not done, and the thorough checks run behind it, finishing after they
say it's right. Anything they throw out, or the lead finds along the way, becomes a card through
`/brief`; a small tooling or process change the lead recommends in answer to their question is
made then, in its own PR.

The maintainer's time is for the product. Tooling, CI, tests, process, the nightly retro's PR,
and a bug whose right behavior is settled are the lead's to find, card, build, verify, and merge
on its own once CI is green, never asking whether to. It checks first that the change is worth
its cost and safe to undo, and tells them in a line what landed, in plain words about the app,
never the runs, tests, or files behind it. A fix that needs a choice of look, wording, or
behavior is theirs. What reaches outside the repo or can't be undone waits for their word:
spending money, or Xcode Cloud hours beyond the plan, a `v*` tag, an account's settings,
deleting what isn't the lead's.

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
scripts/test.sh              # package and script tests on macOS, no simulator
scripts/build.sh             # app for the simulator, compact diagnostics
scripts/test.sh sim          # everything on the simulator, including snapshots
scripts/run.sh [name]        # build, install, launch, screenshot to .build/screenshots/
scripts/device.sh            # build, install, launch on the iPhone, else an install link
scripts/sim.sh <command>     # drive the simulator: shots, appearance, reset, erase, log, motion, shutdown, list
scripts/lint.sh [--fix]      # SwiftFormat, SwiftLint, US English, as CI runs them
scripts/board.sh <command>   # the private project board; run bare to list its commands
scripts/pr-check.sh <command> # the PR check's logic, run against a PR or commit
scripts/pr-media.sh <pr> <file>... # put screenshots and recordings in a PR's body
```

Reach an external service through its own CLI (`gh`, `asc`). A wrapper script or MCP server
has to earn its place; `docs/agent-tooling.md` says when, and how to build a script agents call.

Apple documentation: the `sosumi` MCP server works with Xcode closed. The `xcode` MCP server
gives live diagnostics and preview rendering, and on Xcode 27 runs headless with Xcode closed.
See `docs/agent-tooling.md`.

## Branching

`main` only moves through pull requests, which a ruleset enforces. Work in a worktree; the main
checkout stays on `main` for the nightly retro and session-start tidying.

```sh
git fetch origin main
git worktree add --no-track .claude/worktrees/<topic> -b <topic> origin/main
gh pr update-branch <topic>   # merges main in; a rebase of a pushed branch needs a denied force push
```

Open a PR with `/pr`, in any session: "PR check" fails a body without the template's lines, or
a diff that undoes a recent merge. CI must be green before a PR merges. **Merges are
squashed**: the PR title and body become the one commit on `main`, so write the body as a
commit message that is also true before the merge ("Tense tells the truth"). Notes about review
order or "as discussed" belong in a PR comment, not the body.

## Gotchas

- `-only-testing` with a misspelled identifier runs zero tests and exits 0 in raw `xcodebuild`
  and the xcode MCP's `RunSomeTests`. `scripts/test.sh` fails on it; run filtered tests
  through it.
- `plutil -extract` rewrites the file in place. Use `plutil -p` to inspect, or pass `-o -`.
