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

**Last updated:** 2026-07-07
**Last known good build:** 2026-02-20 (Xcode 26.2, iPhone 17 Pro / iOS 26.2 Simulator)

⚠️ **Needs Mac validation:** The 2026-07-05→07 sessions ran in a remote Linux environment (no Xcode available). Everything compiles and passes unit tests in CI, and TestFlight now puts real builds on Dave's iPhone (see below) — device feedback has already driven two rounds of fixes. But TestFlight thumb-testing is not the #1 checklist: gesture feel, accessibility settings (Increase Contrast, full dynamic-type range), notification sound while locked, and store migration over real data (#31 — run FIRST in that session) still need a hands-on Mac/Simulator pass.

**TestFlight:** `.github/workflows/testflight.yml` (manual dispatch, any ref) archives unsigned, cloud-signs at export with an Admin-role ASC API key, and uploads to TestFlight; build number = run number. Dave installs from his phone. Latest overnight batch: build 7 (rail fixes — scroll still broken there), build 8 (real scroll fix + Dynamic Type + appearance setting), build 9 (editor restyle, unified search/swipes, components audit, cadence editor).

**Work tracking:** The v1 backlog lives in GitHub issues on `mrdavidjcole/plusplus`, feeding the user's GitHub Project board via its auto-add workflow. Changes land via PRs (self-merged once CI is green) with `Closes #N` linking; issues close on merge except where validation is explicitly pending (#1).

**What works (as of 2026-07-07, design-v2 + feedback round 1):** the app wears Dave's v2 "quiet-terminal" design end to end (issues #59–#67), now with the first device-feedback batch landed (#82–#91 minus held items, PRs #98–#105). Home: workout cards with equipment pills, Library/History/Settings header buttons, glass FAB menu. Library: curated personal catalog (add from the full catalog, custom exercises/equipment, built-in info sheets). Detail: rail visualization with superset loops and direct-manipulation drag/ring gestures (#78), swipe SUPER/DUPE/DELETE, ~time estimate + settings sheet (schedule/rest/notes), per-exercise planning sheet (steppers, wheels, rep ranges, split/merge/move, recent history). Execution: set-counter pill with elapsed, progress bar, stepper cards, weight carry-forward, superset chips, duration AUTO TIMER (pause/reset, auto-log, backgrounded notification), mitosis log animation, session overview with jump/redo, done screen with the repo history path. History: append-only cards + per-block session records (no delete affordance, per design). Settings sheet: SYNC placeholder (pending #23), appearance (system/dark/light), lb/kg, export/import. Cross-cutting since the feedback batch: Dynamic Type text styles everywhere (capped at xxLarge), adaptive light/dark palette, one SearchField and one SwipeRevealRow affordance app-wide, v2-language exercise editor with explicit REQUIRES equipment chips, per-workout cadence (days or frequency — editor only; surfacing waits on #96 design).

**Remote validation layer:** 3 XCUITest smoke tests (`PlusPlusUITests`) run on the CI simulator via the `ui-test` job (workflow_dispatch + pushes to main) and upload a `ui-screenshots` artifact — list, detail, editor, set logging, rest, complete, history are all reviewable from a browser. The app supports `--uitest-reset` (in-memory store) for clean test launches. This narrows, but does not replace, the hands-on #1 checklist.

**Targets:**
- **PlusPlus** — iOS app (deployment target iOS 26.0)
- **PlusPlusWatch** — watchOS companion app (deployment target watchOS 26.0)
- **PlusPlusKit** — pure SwiftPM package shared with the CLI and future MCP (tested on Linux in CI)
- **PlusPlusTests** — unit test target (72 tests; 87 more live in PlusPlusKit, 23 in PlusPlusCLI)
- **PlusPlusUITests** — UI smoke test target (3 flows, `PlusPlusUI` scheme, CI-only by convention)

**Project structure:**
```
project.yml              # XcodeGen project definition (registers PlusPlusKit)
docs/PLATFORM.md         # Developer-platform architecture + owner TODOs
docs/AGENTS.md           # Agent quickstart: files, CLI --json, MCP server
docs/recipes/            # Copy-paste Actions for workout repos (lint, weekly report)
PlusPlusKit/             # Pure SwiftPM package (Linux-tested in CI)
  Sources/PlusPlusKit/   # MuscleGroup/ExerciseType, WorkoutMetric, RepTarget,
                         #   WorkoutSchedule (cadence + dueState, #83),
                         #   RailArrangement (detail-view gesture geometry, #78),
                         #   Interchange DTOs + codec + validator + Slug + documents,
                         #   FileLayout (repo paths) + SyncPlanner (3-way merge)
                         #   + SyncEngine/RepoStore/SyncBaseStore (sync pass, #23)
  Tests/PlusPlusKitTests/ # Metric/Units/RepTarget/Rail/Schedule/Interchange/Sync/Conformance (87)
PlusPlusCLI/             # plusplus CLI (SwiftPM exec, Linux-tested in CI)
  Sources/plusplus/      # init/lint/stats/import/export + MCP server (mcp subcommand)
  Tests/PlusPlusCLITests/
PlusPlus/                # iOS app target
  PlusPlusApp.swift      # App entry point, ModelContainer, seed data, appearance
  Notifications/
    RestNotifier.swift   # "Rest over" local notification (backgrounded only)
  Theme/
    Theme.swift          # v2 quiet-terminal palette + metrics; adaptive light/dark pairs (#59, #97)
    AppAppearance.swift  # system/dark/light setting enum (#97)
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
    Components/               # Shared v2 controls: SearchField, SwipeRevealRow +
                              #   SwipeActionButton, SheetComponents (SheetHeader/
                              #   SectionLabel/ActionButton/MetricStepperRow), SegmentedTabs
    WorkoutListView.swift     # Home screen — workout list with create/reorder/delete, history entry
    WorkoutDetailView.swift   # Workout detail — groups, inputs, superset actions, Start Workout
    MetricInput.swift         # MetricRow + RepTargetRow controls (wheel sheet + stepper)
    ActiveSessionView.swift   # Execution v2: stepper cards, auto-timer, rest, carry-forward
    SessionOverviewSheet.swift # Mid-session overview + per-block sheet (jump/redo)
    ExerciseDetailSheet.swift # Planning sheet: metrics, structure actions, recent
    LibraryView.swift         # Personal library (curation, catalog add, built-in info)
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
  InterchangeMappingTests.swift # Export/import round-trip + policies (5) = 72 app + 87 Kit + 23 CLI
PlusPlusUITests/
  SmokeTests.swift           # 3 end-to-end flows w/ screenshot attachments
.github/workflows/ci.yml # macOS CI: xcodegen + xcodebuild test (+ release.yml on v* tags,
                         #   testflight.yml manual-dispatch TestFlight upload)
.xcodebuildmcp/          # XcodeBuildMCP session config
```

`PlusPlus.xcodeproj` is generated by XcodeGen from `project.yml` and is gitignored.

**Known TODOs (tracked as GitHub issues):**
- #1 Interactive Simulator validation of the 2026-07 UI (needs a Mac session) — TestFlight covers happy-path thumb-testing, not gesture feel or accessibility settings.
- #96 Today ⊕ History unification + "diff" concept — ON HOLD awaiting a Claude Design handoff (prompt delivered to Dave 2026-07-07). #83's due-state surfacing on Home waits with it.
- #6 Watch app workout execution (currently a stub target). Needs a sync-strategy decision (WatchConnectivity vs. CloudKit) and paired-simulator testing — deliberately left for a Mac session.
- Held/deferred by Dave: #93 community workout-sharing repo ("hold for now"), #90 Apple Health ("leave for later"), #94 monetization (his decision to make).
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

**2026-07-05 — Sync is a pure three-way merge in the Kit** — `SyncPlanner.plan(local:remote:base:)` decides writes/pulls/conflicts per template file; `FileLayout` owns all repo paths and append-only session placement. Transports (GitHub API in the app for #23, disk in the CLI) stay thin adapters. Deletions deferred: a remotely-present, locally-absent file is adopted, never deleted.

**2026-07-05 — CLI is Swift, shells out to git, never authenticates** — Swift over Go because the contract (deterministic codec, validator) already lives tested in PlusPlusKit; a second implementation would drift byte-level. Conformance fixtures in PlusPlusKitTests/Fixtures are the language-neutral spec for future ports. The CLI operates on a clone; git is transport and auth; the app (#23) is the only surface with GitHub auth.

**2026-07-05 — PlusPlusKit package holds everything platform-pure** — MuscleGroup/ExerciseType, WorkoutMetric, RepTarget, and the interchange DTOs/codec/validator live in a local SwiftPM package with no SwiftUI/SwiftData. The `kit-test` CI job runs its tests on Linux (1x minutes); if it fails, someone leaked an Apple-only dependency into the shared core. SwiftData models, mapping (InterchangeMapping), and views stay in the app.

**2026-07-06 — Session v2: cursor navigation, weight carry-forward, auto-timers** — The session model gains `cursorOrder`: `currentLog` is the cursor's log when pending, else the first pending. `jump(to:redo:)` powers Do now / Redo / Skip-to from the overview sheet (redo reopens a completed log keeping its actuals as prefill); `complete(_:)` prefills actuals, carries an edited weight forward to the remaining pending sets of the same exercise, and advances the cursor (wrapping). Timed sets run a date-based AUTO TIMER (pause stores remaining; auto-logs at zero with haptic + a `TimerNotification` for backgrounded expiry; "log now" logs elapsed). Tested in SessionNavigationTests.

**2026-07-06 — v2 "quiet-terminal" design system; dark-only** — Dave's Claude Design prototype v2 (design handoff in issues #59–#67) supersedes the 2026-02-20 system-semantic-colors decision: a fixed GitHub-dark palette (`Theme` in `PlusPlus/Theme/Theme.swift`), green accent (#3fb950/#238636) replacing indigo, monospace for data/numbers, and no light mode (appearance toggle removed). Screens must draw colors from `Theme`, never ad-hoc literals. Accessibility trade-offs (Increase Contrast, dynamic type on fixed layouts) go on the #1 Mac checklist.

**2026-07-06 — Weight numbers are unit-agnostic; the unit is a declaration, not a conversion** — `WeightUnit` (lb/kg) in the Kit owns per-unit semantics (step 5/2.5, wheel 2.5/1.25, empty-bar default 45/20); `WorkoutMetric`'s weight paths take a `weightUnit:` param defaulting to `.lb`. The app setting (`@AppStorage("weightUnit")`, Settings segmented control) changes labels/stepping/defaults only — stored numbers never convert (225 stays 225). Bundles carry an optional `units` field (absent = lb, so old files stay valid); import adopts a bundle's declared unit; CLI stats honor it. The per-file repo layout stays lb-implied until a real kg repo needs a meta file.

**2026-07-06 — Renames are new exercises; identity IS the name** — Decided on #32's option 3: no stable IDs, no rename manifest. Renaming an exercise starts a fresh identity — history and "last time" stay with the old name; sync sees a new file next to the old. The editor warns on a real rename (`ExerciseDraft.isRename`, case-only changes exempt since slug and match are unchanged). Documented in docs/PLATFORM.md. Revisit stable IDs only if this chafes in practice.

**2026-07-06 — iPhone-only for v1** — `TARGETED_DEVICE_FAMILY = 1` (issue #41). Nobody had ever seen the app on iPad and nobody rests a 13" iPad on a squat rack; it still runs letterboxed there. Revisit post-v1 only if real demand shows up.

**2026-07-06 — Rest-end notification: scheduled always, presented only when backgrounded** — Extends the date-based rest timer: `RestNotifier` schedules one local notification (stable identifier, so each rest replaces the last) at rest start, reschedules on +15 s, cancels on skip/finish/discard/natural expiry. Foreground presentation is suppressed by the delegate (the ticking RestView is already on screen) rather than by conditional scheduling — no race with backgrounding. Permission is requested at first workout start, not app launch. Fully disabled under `--uitest-reset` so the permission dialog never eats a smoke test's tap. Felt behavior (sound while locked) still needs the #1 Mac pass.

**2026-07-06 — MCP server is a CLI subcommand with one heavily-fenced mutating tool** — `plusplus mcp` hand-rolls stdio JSON-RPC (~100 lines; no third-party MCP SDK, keeping the Linux build dependency-free). Read tools return interchange DTOs / the `--json` reports verbatim — no bespoke shapes to keep in sync. `propose_program_change` is the only write: `program/**.json` paths only, clean work tree required, must lint or it's fully rolled back, commits to a fresh branch, never pushes (the CLI still never authenticates — review/push/PR is the caller's job, and the repo's lint Action recipe is the second gate).

**2026-07-06 — Sync engine is transport-blind; sessions bypass the merge entirely** — `SyncEngine` (Kit) runs one sync pass — load base → fetch remote → `SyncPlanner` → resolve conflicts (keep-mine / take-theirs / postpone) → push → save the converged base — against two tiny protocols: `RepoStore` (the GitHub adapter in the app, a fake in tests) and `SyncBaseStore` (base-snapshot persistence, answering where "base" lives: the store owned by the app, a dictionary in tests). Postponed conflicts keep their old base entry so they re-conflict next pass. Finished sessions never enter the merge: `pushSession` is append-only via `FileLayout.sessionPlacement`, idempotent on retry, and composes its own "Log: …" commit message. What remains for #23 is UI + the GitHub `RepoStore` adapter + device-flow auth.

**2026-07-06 — Duration spans to a full hour; m:ss display above a minute** — Dogfooding the real program (#29) hit the old 900 s cap with "20–30 min spin bike". `WorkoutMetric.duration` now ranges 5–3600 with a tiered wheel (5 s steps to 2 min, 15 s to 10 min, whole minutes beyond) so the picker stays usable; values ≥ 60 s render as m:ss ("25:00") with no unit suffix. The interchange validator stays permissive (duration > 0) — the format doesn't encode UI limits.

**2026-07-06 — Rail direct manipulation is a custom gesture layer; List is out of the detail view** — Issue #78 (Dave's design): two separate long-press interactions — drag a row body to rearrange, drag a rail dot's ring edge to manage superset membership (full-width blue highlight while active, so state reads around the thumb). `List` was rejected a third and final time: its drag machinery can't express grouped semantics (2026-02 Sections attempt, 2026-07-05 header-menu retreat), gives no live preview, and has an unfixable drop ambiguity at group boundaries. The detail view now uses ScrollView + rows positioned absolutely by `RailLayout`; all geometry/semantics (drop slots, ring spans, clamps) are pure `RailArrangement` logic in PlusPlusKit (Linux-tested), and commits compose the existing Workout mutations plus `placeSolo`/`reorderExercise`/directional `splitExercise`. Division of labor kills ambiguity: gaps between groups always mean "land solo", in-ring positions exist only for the dragged row's own group, joining a ring is exclusively the ring gesture. Swipe actions are a small custom `SwipeRevealRow` (List-only feature otherwise). Gesture feel is unvalidated remotely — on the #1 checklist.

**2026-07-05 — Rep ranges shift, sets stay scalar** — `reps`/`repsUpper` express "15–20"; the stepper shifts the whole range to preserve the prescribed span. Set ranges ("2–3×10") deliberately collapse to one number — the range's meaning ("stop when cooked") lives with the user, not the model.

**2026-07-06 — TestFlight via unsigned archive + cloud signing on CI (#55)** — `testflight.yml` archives with `CODE_SIGNING_ALLOWED=NO` and lets `xcodebuild -exportArchive` do ALL signing via cloud signing with an ASC API key (which must be **Admin** role — App Manager gets "Cloud signing permission error"). Injecting a signing identity at archive time fails ("conflicting provisioning settings"); dev-profile signing fails on runners (no registered device). Build number = workflow run number; placeholder ++ icons + `ITSAppUsesNonExemptEncryption: NO` satisfy validation, and the watch target needs its own icon or the upload rejects.

**2026-07-07 — Dynamic Type text styles, capped at xxLarge (#82/#98)** — All `.system(size:)` fixed sizes became text styles (`.body`, `.footnote`, etc., keeping design/weight); display numerals ≥32 pt stay fixed. Rail geometry scales via `@ScaledMetric(relativeTo: .body)` row height threaded into the Kit's `RailMetrics`. Root caps at `.xxLarge` because the fixed v2 layouts break beyond it — full accessibility sizes are a #1-checklist item, not a regression.

**2026-07-07 — Adaptive palette + appearance setting (#97; amends the dark-only call in the v2 decision)** — `Theme` colors became `Color(light:dark:)` dynamic providers (UIColor trait resolvers, so previews and sheets resolve correctly); a GitHub-light palette mirrors the dark one. `AppAppearance` (system/dark/light, default **system**) drives `.preferredColorScheme` from Settings. Stored numbers and the design language are unchanged — light mode is the same quiet terminal, inverted.

**2026-07-07 — Equipment stays to-many; the editor makes it legible (#86)** — Dave's "multi-equipment feels weird" feedback was a UI problem, not a model problem: Bench Press genuinely needs [Barbell, Bench]. The editor presents equipment as removable REQUIRES chips with a caption spelling out the semantics ("needs all of these; filtering by what you own uses it") instead of an unexplained multi-select.

**2026-07-07 — Shared v2 controls live in `Views/Components/` (#85/#88/#91)** — Once a control appears in a second view it moves to `Views/Components/` rather than being redefined or imported across screens: `SearchField` (one search affordance app-wide), `SwipeRevealRow` + `SwipeActionButton` (one swipe affordance — reveal-then-tap, uppercase mono labels; native `.swipeActions` is out), `SheetHeader`/`SheetSectionLabel`/`SheetActionButton`/`MetricStepperRow`, `SegmentedTabs`. XcodeGen's `sources: [PlusPlus]` picks the directory up automatically.

**2026-07-07 — Scroll starvation was gesture claiming, not layout (#99)** — The detail-view bug where the exercise list couldn't scroll had two layers: offset-positioned rows gave the ScrollView no real content height (#92, necessary but insufficient), and `.gesture(LongPressGesture().sequenced(DragGesture()))` on rows claimed every touch before the ScrollView's pan could run. Long-press-initiated row gestures must use `.simultaneousGesture`; the handlers already ignore events until the long-press fires, and `scrollDisabled` during an active drag prevents fighting.

**2026-07-07 — Cadence is a Kit enum; due-state is pure; surfacing waits for design (#83)** — `WorkoutSchedule`: `.weekdays(Set<Int>)` (Calendar weekday numbers) or `.frequency(times:perDays:)` anchored to the last completion (rational slots — "3× per 7 days" is due when `daysSince × times ≥ perDays` — so it doesn't drift to every-3-days). `dueState(lastCompleted:today:calendar:)` takes the clock as a parameter. Stored app-local as additive `Workout.scheduleData` JSON; NOT in the interchange format until something consumes it. The editor lives in workout settings; how "due" renders on Home belongs to the #96 design.

**2026-07-07 — Today ⊕ History + "diff" handed to Claude Design; #96 on hold** — Dave's framing: Today's workout is just a pending history entry, and a per-exercise "diff" against last time should show how you're improving (incrementing — ++ing). This collapses the Today/History tabs into one timeline and is the app's identity moment, so it gets real design exploration (prompt delivered 2026-07-07) instead of a first-pass implementation. Nav restructure/onboarding (#96) and cadence surfacing ride on the handoff.

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
