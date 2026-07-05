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

⚠️ **Needs Mac validation:** The 2026-07-05 session ran in a remote Linux environment (no Xcode available), so the workout detail view rebuild (issue #1) was written and pushed but NOT built, tested, or Simulator-validated. First session on a Mac: `xcodegen generate`, build, run the test suite (30 tests expected), and Simulator-validate the detail view flow end-to-end before closing issue #1.

**Work tracking:** The v1 backlog lives in GitHub issues #1–#6 on `mrdavidjcole/plusplus`, feeding the user's GitHub Project board via its auto-add workflow. Reference issue numbers in commits and close issues only after validation.

Chunk 1 complete: data model + workout builder. Users can create workouts, add exercises from a built-in library (27 exercises, 12 equipment items), set weight/reps/duration per exercise, manage set counts, and reorder/delete exercise groups.

The workout detail view was stripped to a flat exercise-name list in `1d5930e` (Feb 28) and rebuilt on 2026-07-05 with keyboard-free inputs: each weight/reps/duration line is a `MetricRow` — tap the value for a wheel picker (big jumps), use the stepper for fine adjustment. Group management uses swipe-to-delete on exercise rows plus a per-group header menu (Move Up / Move Down / Delete); deleting a group's last exercise removes the group.

Dark mode is the default. Users can toggle appearance (dark/light/system) via a settings tray.

**Targets:**
- **PlusPlus** — iOS app (deployment target iOS 26.0)
- **PlusPlusWatch** — watchOS companion app (deployment target watchOS 26.0)
- **PlusPlusTests** — unit test target (30 tests)

**Project structure:**
```
project.yml              # XcodeGen project definition
PlusPlus/                # iOS app target
  PlusPlusApp.swift      # App entry point, ModelContainer, seed data, appearance
  Theme/
    AppAppearance.swift  # Dark/Light/System enum, persisted via @AppStorage
  Models/
    Exercise.swift       # MuscleGroup enum, ExerciseType enum, Exercise @Model
    Equipment.swift      # Equipment @Model
    Workout.swift        # Workout @Model with reindexGroups()
    ExerciseGroup.swift  # ExerciseGroup @Model (superset container)
    WorkoutExercise.swift # WorkoutExercise @Model (join table)
    SeedData.swift       # Built-in exercises/equipment seeder
  Views/
    WorkoutListView.swift     # Home screen — workout list with create/reorder/delete
    WorkoutDetailView.swift   # Workout detail — exercise groups with set/rep/weight inputs
    MetricInput.swift         # WorkoutMetric enum (pure input logic) + MetricRow control
    ExercisePickerView.swift  # Exercise picker with filter sheets (muscle group + equipment)
    ExerciseFilterState.swift # @Observable filter logic (testable, pure)
    SettingsView.swift        # Settings tray (appearance toggle)
PlusPlusWatch/           # watchOS app target
  PlusPlusWatchApp.swift
  ContentView.swift
  Assets.xcassets/
PlusPlusTests/
  ExerciseFilterTests.swift  # Filter logic tests (9 tests)
  SeedDataTests.swift        # Seed data integrity tests (7 tests)
  ReindexTests.swift         # Reindex helper tests (5 tests + 1 placeholder)
  WorkoutMetricTests.swift   # Metric stepping/clamping/formatting tests (8 tests, 30 total)
.xcodebuildmcp/          # XcodeBuildMCP session config
```

`PlusPlus.xcodeproj` is generated by XcodeGen from `project.yml` and is gitignored.

**Known TODOs (tracked as GitHub issues):**
- #2 Superset creation UI — the data model supports supersets (multiple exercises in one ExerciseGroup), but there's no UI to create them yet. Each exercise currently gets its own group.
- #3/#4 Workout execution — WorkoutSession data model, then the active session UI (set logging, rest timer).
- #5 Workout history view.
- #6 Watch app workout execution (currently a stub target).

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
