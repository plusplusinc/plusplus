# PlusPlus (++) — Project Instructions

Read this at the start of every session. Update it when decisions are made. Keep it accurate — a stale CLAUDE.md is worse than none.

---

## What This App Is

**PlusPlus** (`++`) is an iOS fitness tracking app with Apple Watch companion functionality. The name references the programming increment operator; the `++` mark visually resembles a dumbbell, which is intentional branding.

---

## Tech Stack

- **Language:** Swift / SwiftUI
- **Platform targets:** iOS 26+, watchOS 26+

No third-party dependencies without discussion first.

---

## Tooling: XcodeBuildMCP

XcodeBuildMCP is configured as an MCP server for this project. Use it as the primary interface for all Xcode operations — don't fall back to raw `xcodebuild` shell commands when an MCP tool exists for the job.

**What it provides:**

- **Build & run** — build for Simulator, build and launch in one step, incremental builds
- **Testing** — run tests on Simulator
- **Simulator control** — list, boot, open simulators; install, launch, and stop the app
- **Log capture** — capture runtime logs from the running app on Simulator
- **Screenshots** — capture Simulator screenshots for visual validation
- **UI automation** — tap, swipe, and interact with the running app programmatically
- **Debugging** — attach debugger, set breakpoints, run LLDB commands
- **Project introspection** — discover projects/workspaces, list schemes, show build settings
- **Clean** — remove build artifacts and derived data when needed

**How to use it for validation:**

The Simulator validation step in every task should use these tools in sequence: build → launch → navigate using UI automation → screenshot to confirm. Don't just build and consider it done — actually exercise the changed behavior in a running app.

**Log capture is part of debugging:** If something behaves unexpectedly in the Simulator, capture runtime logs before concluding. Don't guess at the cause.

**The MCP Skill:** XcodeBuildMCP ships an optional "MCP Skill" document that primes agents with detailed usage instructions. If it has been installed (via the `install-skill.sh` script), it will be available in your context. Follow its guidance on tool selection — it has opinions on which tools to prefer for which jobs.

---

## Architecture Principles

- Effective complexity management above all else — code should be easy to understand and easy to adapt
- Deep modules over shallow ones: hide significant complexity behind simple interfaces
- No premature abstraction — only abstract when duplication is real and present
- iOS-native first: start with what SwiftUI provides, customize deliberately

---

## Current State

> Update this section at the end of every session that changes the codebase.

**Last updated:** 2026-07-05
**Last known good build:** 2026-02-20 (Xcode 26.2, iPhone 17 Pro / iOS 26.2 Simulator)

⚠️ **Needs Mac validation:** The 2026-07-05 sessions ran in a remote Linux environment (no Xcode available). Everything compiles and passes unit tests in CI (see the CI decision below), but none of the 2026-07-05 UI (detail view inputs, custom exercise editor, supersets, execution flow, history) has had interactive Simulator validation. First Mac session: walk the full flow — build a workout with a superset and rep ranges, create a custom exercise with notes/video, run the workout (rest timer, backgrounding), check history — then close issue #1.

**Work tracking:** The v1 backlog lives in GitHub issues on `mrdavidjcole/plusplus`, feeding the user's GitHub Project board via its auto-add workflow. Changes land via PRs (self-merged once CI is green) with `Closes #N` linking; issues close on merge except where validation is explicitly pending (#1).

**What works (as of 2026-07-05):** create workouts; add exercises from the built-in library (27 exercises, 13 equipment items) or create custom exercises (muscle group, equipment, type, notes, video link); keyboard-free weight/reps/duration inputs with rep ranges ("15–20"); supersets (add to group / split out, rotation during execution); run a workout end to end (prefilled set logging, configurable rest countdown with a "Between Sets" row per workout, "Last time" line from prior history, finish/discard); browse and delete history with per-set detail. Dark mode default with dark/light/system toggle.

**Remote validation layer:** 3 XCUITest smoke tests (`PlusPlusUITests`) run on the CI simulator via the `ui-test` job (workflow_dispatch + pushes to main) and upload a `ui-screenshots` artifact — list, detail, editor, set logging, rest, complete, history are all reviewable from a browser. The app supports `--uitest-reset` (in-memory store) for clean test launches. This narrows, but does not replace, the hands-on #1 checklist.

**Targets:**
- **PlusPlus** — iOS app (deployment target iOS 26.0)
- **PlusPlusWatch** — watchOS companion app (deployment target watchOS 26.0)
- **PlusPlusKit** — pure SwiftPM package shared with future CLI/MCP (tested on Linux in CI)
- **PlusPlusTests** — unit test target (53 tests; 25 more live in PlusPlusKit)
- **PlusPlusUITests** — UI smoke test target (3 flows, `PlusPlusUI` scheme, CI-only by convention)

**Project structure:**
```
project.yml              # XcodeGen project definition (registers PlusPlusKit)
docs/PLATFORM.md         # Developer-platform architecture + owner TODOs
PlusPlusKit/             # Pure SwiftPM package (Linux-tested in CI)
  Sources/PlusPlusKit/   # MuscleGroup/ExerciseType, WorkoutMetric, RepTarget,
                         #   Interchange DTOs + deterministic codec + validator + Slug
  Tests/PlusPlusKitTests/ # Metric/RepTarget/Interchange tests (17)
PlusPlusCLI/             # plusplus CLI (SwiftPM exec, Linux-tested in CI)
  Sources/plusplus/      # lint/stats/import/export over the repo layout
  Tests/PlusPlusCLITests/
PlusPlus/                # iOS app target
  PlusPlusApp.swift      # App entry point, ModelContainer, seed data, appearance
  Theme/
    AppAppearance.swift  # Dark/Light/System enum, persisted via @AppStorage
  Interchange/
    InterchangeMapping.swift # SwiftData models ↔ DTOs, import policies
  Models/
    Exercise.swift       # Exercise @Model (incl. notes/videoURL); enums now in Kit
    Equipment.swift      # Equipment @Model
    Workout.swift        # Workout @Model, reindex + structure mutations (supersets)
    ExerciseGroup.swift  # ExerciseGroup @Model (superset container)
    WorkoutExercise.swift # WorkoutExercise @Model (join table, reps/repsUpper range)
    WorkoutSession.swift # WorkoutSession + SetLog @Models, session factory w/ superset rotation
    SeedData.swift       # Built-in exercises/equipment seeder
  Views/
    WorkoutListView.swift     # Home screen — workout list with create/reorder/delete, history entry
    WorkoutDetailView.swift   # Workout detail — groups, inputs, superset actions, Start Workout
    MetricInput.swift         # MetricRow + RepTargetRow controls (wheel sheet + stepper)
    ActiveSessionView.swift   # Execution: set logging, rest countdown, finish/discard
    HistoryView.swift         # Completed sessions list + per-set session detail
    ExercisePickerView.swift  # Exercise picker with filter sheets, custom exercise management
    ExerciseEditorView.swift  # Create/edit custom exercises + ExerciseInfoView (notes/video)
    ExerciseDraft.swift       # Pure validation/normalization for the editor — no SwiftUI import
    ExerciseFilterState.swift # @Observable filter logic (testable, pure)
    SettingsView.swift        # Settings tray (appearance, data export/import)
PlusPlusWatch/           # watchOS app target (stub — #6)
  PlusPlusWatchApp.swift
  ContentView.swift
  Assets.xcassets/
PlusPlusTests/
  ExerciseFilterTests.swift  # Filter logic tests (9)
  SeedDataTests.swift        # Seed data integrity tests (7)
  ReindexTests.swift         # Reindex helper tests (5 + 1 placeholder)
  ExerciseDraftTests.swift   # Custom exercise validation (8)
  SupersetTests.swift        # Workout structure mutations (5)
  SessionTests.swift         # Session factory/rotation/snapshots/progress (7)
  LastPerformanceTests.swift # "Last time" lookup (6)
  InterchangeMappingTests.swift # Export/import round-trip + policies (5) = 53 app + 25 Kit
PlusPlusUITests/
  SmokeTests.swift           # 3 end-to-end flows w/ screenshot attachments
.github/workflows/ci.yml # macOS CI: xcodegen + xcodebuild test
.xcodebuildmcp/          # XcodeBuildMCP session config
```

`PlusPlus.xcodeproj` is generated by XcodeGen from `project.yml` and is gitignored.

**Known TODOs (tracked as GitHub issues):**
- #1 Interactive Simulator validation of all 2026-07-05 UI (needs a Mac session).
- #6 Watch app workout execution (currently a stub target). Needs a sync-strategy decision (WatchConnectivity vs. CloudKit) and paired-simulator testing — deliberately left for a Mac session.
- Rest is configurable per workout (15–600s); per-exercise override deferred until per-workout proves insufficient.
- Set ranges ("2–3×10") collapse to a single sets number by design; revisit only if it chafes.

---

## Decisions Log

> Record architectural and significant implementation decisions as they're made.
> Format: **Date — Decision — Reason**

**2026-02-19 — Use XcodeGen for project generation** — Declarative YAML (`project.yml`) is far cleaner for source control than Xcode's binary `.pbxproj`. The `.xcodeproj` is gitignored and regenerated from `project.yml` via `xcodegen generate`.

**2026-02-19 — Equipment as SwiftData model, not enum** — "Machine" is too broad; users who have a leg press don't necessarily have a lat pulldown. Specific equipment items enable filtering by what users actually own. Exercise→Equipment is to-many (Bench Press needs [Barbell, Bench]).

**2026-02-19 — ExerciseGroup as superset container** — Every exercise lives in a group, even solo ones. A group with >1 exercise is a superset. This avoids a separate "superset" concept and makes the data model uniform.

**2026-02-19 — Filter state as @Observable class** — `ExerciseFilterState` is a plain `@Observable` class, not a SwiftData model. Takes an array parameter instead of running queries — keeps filter logic pure and testable without a ModelContainer.

**2026-02-19 — Order management via `order: Int` + reindex helpers** — SwiftData relationships are unordered. Every ordered collection uses an `order: Int` property with `sortedX` computed properties and `reindexX()` methods called after every mutation. Sorted properties filter `isDeleted` objects.

**2026-02-20 — Dark mode default with user toggle** — `@AppStorage("appearance")` defaults to `.dark`. Applied via `.preferredColorScheme()` at app root.

**2026-02-20 — System semantic colors over custom color scales** — Use Apple's semantic colors (`.primary`, `.secondary`, `.label`, `.systemBackground`, etc.) for all UI chrome. They handle dark mode, Increase Contrast accessibility, Liquid Glass (iOS 26), and future OS changes automatically. Use built-in `Color.indigo` for brand accent. Custom color scales (Radix, etc.) fight the platform on iOS.

**2026-07-05 — Keyboard-free metric input (stepper + wheel picker)** — The `.number`-formatted TextFields had janky cursor behavior, and gym data entry shouldn't need a keyboard at all. `WorkoutMetric` (enum in `MetricInput.swift`) owns all value semantics — step size, wheel granularity (2.5 lb for weight so microplates are reachable), range, default-from-nil, formatting — as pure, tested logic; `MetricRow` renders it. Stepping an empty value lands on a sensible default (45 lb / 10 reps / 30 sec) instead of zero.

**2026-07-05 — Group actions via header menu, not EditButton** — With exercises as rows inside per-group Sections, `onMove`/`onDelete` on a ForEach of Sections doesn't produce usable edit controls. Groups are reordered/deleted via an ellipsis menu in each section header (Move Up / Move Down / Delete); individual exercises use swipe-to-delete, and deleting a group's last exercise deletes the group.

**2026-07-05 — Work tracked as GitHub issues, board synced via auto-add** — Remote Claude sessions can create/close issues but cannot touch the GitHub Projects board directly (no Projects v2 API in the toolset). The project board's "Auto-add to project" workflow ingests repo issues automatically; issue state drives board state.

**2026-07-05 — GitHub Actions macOS CI as the remote-session verification path** — Remote Claude sessions run on Linux: no Xcode, no Simulator, and the sandbox network policy blocks installing a Swift toolchain (download.swift.org and Docker Hub's CDN are unreachable). `.github/workflows/ci.yml` runs `xcodegen generate` + `xcodebuild test` on a `macos-26` runner for pushes to `main` and `claude/**` (plus manual dispatch). This verifies compilation and the unit test suite; it does NOT replace interactive Simulator validation (UI automation + screenshots), which still requires a local Mac session. Note: macOS runner minutes bill at 10x on private repos — keep triggers narrow. A shared `PlusPlus` scheme is defined in `project.yml` because `xcodebuild test` requires one.

**2026-07-05 — PT program as v1 acceptance scenario** — The user's shoulder-PT prescription (band work, external rotations, rep ranges like 3×15–20, form notes, a reference video link) is the concrete bar for v1: issues #7 (custom exercises + notes/video) and #8 (rep/set ranges) exist because the current model can't represent it.

**2026-07-05 — Sessions snapshot, never reference-only** — `WorkoutSession`/`SetLog` copy the workout name, exercise name/type, and targets at start time; the `workout`/`exercise` references are conveniences that may go stale. History must survive template edits and deletions. Tested explicitly.

**2026-07-05 — Superset execution order is strict rotation** — A group with exercises [A, B] and 3 sets expands to A1 B1 A2 B2 A3 B3 at session start (one flat, pre-ordered SetLog list). The execution UI just walks `nextPendingLog`; it holds no ordering logic of its own.

**2026-07-05 — Rest timer is date-based, not tick-based** — The countdown stores an end `Date` and renders via `TimelineView`; backgrounding or suspension can't drift it. Fixed 90s default with +15s/skip for v1.

**2026-07-05 — UI smoke tests + screenshot artifacts as the remote validation layer** — With no Mac available for days, XCUITests on the CI simulator exercise the real flows and export screenshots reviewable from any browser. Gated to `workflow_dispatch` + main pushes to control 10x macOS minute billing; dispatch the workflow on a branch (`actions_run_trigger` / the Actions UI) to run them pre-merge. First hands-on Mac session still owns #1.

**2026-07-05 — Watch sync will be WatchConnectivity, not CloudKit (planned)** — Full plan lives in issue #6 comments: Codable plan/result payloads (`updateApplicationContext` for template pushes, `transferUserInfo` for finished sessions), no SwiftData on the wrist for v1, HKWorkoutSession for runtime. CloudKit rejected for v1: iCloud dependency, opaque debugging, network-at-the-gym requirement.

**2026-07-05 — Developer platform: repo-as-backend, format-as-contract (see docs/PLATFORM.md)** — First niche is developers; training data lives as versioned JSON, eventually synced to a private GitHub repo the user owns (GitHub App + device flow, no PlusPlus server). The interchange format (schema v1, deterministic serialization for clean diffs) is the API contract for app export/import, repo sync, the CLI, and agents. Phases tracked in issues #20–#25.

**2026-07-05 — CLI is Swift, shells out to git, never authenticates** — Swift over Go because the contract (deterministic codec, validator) already lives tested in PlusPlusKit; a second implementation would drift byte-level. Conformance fixtures in PlusPlusKitTests/Fixtures are the language-neutral spec for future ports. The CLI operates on a clone; git is transport and auth; the app (#23) is the only surface with GitHub auth.

**2026-07-05 — PlusPlusKit package holds everything platform-pure** — MuscleGroup/ExerciseType, WorkoutMetric, RepTarget, and the interchange DTOs/codec/validator live in a local SwiftPM package with no SwiftUI/SwiftData. The `kit-test` CI job runs its tests on Linux (1x minutes); if it fails, someone leaked an Apple-only dependency into the shared core. SwiftData models, mapping (InterchangeMapping), and views stay in the app.

**2026-07-05 — Rep ranges shift, sets stay scalar** — `reps`/`repsUpper` express "15–20"; the stepper shifts the whole range to preserve the prescribed span. Set ranges ("2–3×10") deliberately collapse to one number — the range's meaning ("stop when cooked") lives with the user, not the model.

---

## Patterns Reference

> Add established patterns here as they emerge to avoid re-litigating decisions.

**SwiftData in-memory testing:**
```swift
let schema = Schema([Exercise.self, Equipment.self, Workout.self, ExerciseGroup.self, WorkoutExercise.self])
let config = ModelConfiguration(isStoredInMemoryOnly: true)
let container = try ModelContainer(for: schema, configurations: [config])
let context = ModelContext(container)
```

**Seed data access for testing:** `SeedData.makeBuiltInExercisesForTesting(equipment:)` exposes internal exercise creation. Production code uses `SeedData.loadIfNeeded(context:)`.

**`#Predicate` macro:** Requires `import Foundation` in addition to `import SwiftData`.

**`#expect` with `allSatisfy`:** Extract result to a local variable first: `let allMatch = items.allSatisfy(\.prop); #expect(allMatch)`. Direct inline call causes macro expansion issues.

---

## CLAUDE.md Hygiene

This root CLAUDE.md is the source of truth for project-wide decisions. As the codebase grows, subdirectory-level CLAUDE.md files are appropriate when a directory has enough established patterns or context to warrant it — not before.

**When to create a nested CLAUDE.md:**

- A subdirectory has accumulated enough specific patterns that they'd be noise at the root level
- A module has conventions that differ meaningfully from the rest of the project
- The root doc is growing large enough that splitting improves signal-to-noise

**How they load:**

Nested CLAUDE.md files are loaded lazily — only when Claude Code is actually working in that subtree. So they don't burn context on unrelated sessions, which makes them cheap to create once patterns are established.

**How to maintain them:**

- Nested docs inherit from the root — don't repeat root-level decisions
- Keep them focused on what's specific to that directory
- Same hygiene rules apply: suggest additions at end of session, don't modify without approval

**CLAUDE.local.md:**

A  at the project root is automatically gitignored and meant for your personal local preferences — sandbox URLs, local test data, dev shortcuts that shouldn't be in source control. Use it instead of cluttering the main project doc with machine-specific config.

**What should stay at the root:**

- Architecture principles
- Cross-cutting decisions
- The decisions log and patterns reference
- Session discipline

---

## Session Discipline

Start each session with:

```txt
Task: [one sentence]
Context: [what already exists that's relevant]
Done when: [specific, testable completion criteria]
```

### Before Marking Any Task Complete

1. **Build successfully** — use XcodeBuildMCP's build tool; no errors or warnings introduced by your changes
2. **Run relevant tests** — if tests exist for the modified area, run them via XcodeBuildMCP and confirm they pass
3. **Validate in Simulator** — use XcodeBuildMCP to launch the app, use UI automation tools to navigate to the affected screen and interact with what you built, then capture a screenshot confirming the result. Complete flows end-to-end. Capture runtime logs if anything looks off.

If any step fails, fix it before reporting completion.

### End-of-Session Summary

- What was built
- Decisions made (flag any that should be added to this file)
- Known issues or follow-on tasks
- Build / test / Simulator validation status
