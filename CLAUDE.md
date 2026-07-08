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

## Claude Code Setup (committed in `.claude/`)

- **Skills** — `/ci-status` (check/diagnose/rerun CI from a sandbox that can't
  reach job logs), `/pr-flow` (the serialized single-branch PR workflow),
  `/testflight` (shipping a build + the entitlement mechanism and its failure
  modes). Read the matching skill BEFORE re-deriving any of that from scratch.
- **Agents** — `swift-reviewer` (adversarial review tuned to this repo's proven
  bug classes; run it on any non-trivial diff before pushing) and
  `doc-verifier` (claim-by-claim docs audit; fan out one per doc).
- **Hooks** — `docs-drift` (PostToolUse): editing interchange/CLI/workflow/
  project.yml files injects a reminder naming the doc that owns the claim.
- **Docs stay true by construction where possible**: PLATFORM.md's JSON
  examples are executable — `DocsConformanceTests` (CLI test target, runs on
  Linux CI) decodes and validates them, and fails if the schema gains fields
  the doc never mentions. For everything a test can't see, the rule is: a PR
  that changes an interface (format, CLI, targets, CI) touches the doc that
  describes it, or the PR description says why not.

---

## Architecture Principles

- Effective complexity management above all else — code should be easy to understand and easy to adapt
- Deep modules over shallow ones: hide significant complexity behind simple interfaces
- No premature abstraction — only abstract when duplication is real and present
- iOS-native first: start with what SwiftUI provides, customize deliberately

---

## Current State

> Update this section at the end of every session that changes the codebase.

**Last updated:** 2026-07-08 (late overnight: #187 default targets, #159 widget freshness, #157 island rest controls, docs truth sweep + docs-as-tests, committed .claude/ dev setup, contribution infra, the CI red-main chase ending at the pre-insert relationship-loss rule — all on PR #194, unmerged: the GitHub MCP token expired mid-session and merges/issue writes are queued in the session scratchpad)
**Last known good build:** 2026-02-20 (Xcode 26.2, iPhone 17 Pro / iOS 26.2 Simulator)

⚠️ **Needs Mac validation:** All 2026-07 sessions ran in a remote Linux environment (no Xcode). Everything compiles, passes unit tests and the UI smoke suite in CI, and TestFlight puts real builds on Dave's iPhone. The #1 Mac checklist now covers: v3 gesture feel (rail drag/ring under the UIKit recognizer), onboarding on a fresh install, the watch app on real hardware (paired-simulator or device), accessibility settings, store migration over real data (#31 — FIRST), Dynamic Island / Live Activity feel, the widget gallery pass, and the v4 surfaces: the redrawn superset rail (return-loop feel in crowded lists, border-contrast legibility in bright light), the blue selection grammar, and Dynamic Type on the new settings pages.

**Org + license:** Both repos live in the **plusplusinc** org and are **PUBLIC**. Old `mrdavidjcole/*` URLs redirect. The app (and the repo as a whole) is **AGPL-3.0**; **PlusPlusKit and PlusPlusCLI are MIT** (the contract is meant for adoption; clones inherit AGPL duties) — see the README's License section. A full-history secrets scan ran clean on both repos before the flip. Actions minutes are free on public repos (macOS included) — the old 10x-billing trigger caution is obsolete; CI triggers can widen when convenient (#160 tracks a `pull_request` trigger for fork PRs, which get zero checks today).

**Branch protection is active** (repository ruleset): merges to main require `test`, `kit-test`, and `cli-test` to PASS on the head SHA (squash is the only allowed merge method). A cancelled required check blocks merge until re-run. ci.yml's docs-only `paths-ignore` was removed for exactly this reason — a push that skips CI leaves its PR permanently unmergeable (a green `workflow_dispatch` run on the same SHA did NOT satisfy the ruleset in practice; push-triggered runs do).

**CI flake note:** the ui-test job's `app.launch()` can wedge indefinitely on a runner simulator (DebuggerLLDB errors in the log, 45-min timeout kills it). Seen once 2026-07-07; the identical commit passed in 7 min on re-dispatch. Cancel + re-dispatch once before suspecting code. The unit `test` job went ~50% red 2026-07-08 (same tree passing as a PR head and failing on main); three mechanisms were eliminated — in-memory ModelConfigurations sharing state across containers even when uniquely named (see Patterns; test stores are on-disk temp files now), and the test HOST app running its full launch stack (TipKit datastore, WCSession, notifications) under every unit run; the host is now inert when it detects the unit-test bundle. The `test` job also emits failing-test annotations on failure (`::error::` lines from xcodebuild.log) because remote agent sessions can't reach job logs or artifacts on Azure blob storage — read them via the check-runs API.

**TestFlight:** `.github/workflows/testflight.yml` (manual dispatch, any ref) archives unsigned, cloud-signs at export with an Admin-role ASC API key, and uploads; build number = run number. **Build 28** is current: build 27's contents plus PR #205 — the build-27 feedback round (#201 completion purple, #202 green creation, #203 presets die, #204 populate offer as a Today alert) and the #95 extensive catalog (157 exercises / 40 equipment, top-up seeder so existing stores receive newcomers catalog-only and un-owned). Install 28. Build 27 was: build 26's contents (PR #194 — per-exercise default targets #187, schedule-aware widgets/Siri #159, island +15s/Skip rest controls #157, the seeder relationship-loss fix; PR #196 — the `Exercise.equipment` explicit inverse) plus PR #199 — the #198 navigation feel: Liquid Glass back buttons on pushed screens, routine detail's share/settings as trailing glass circles, and full-width swipe-back (UIKit pan re-targeted at the system interactive pop; rail and swipe-row collisions vetoed at the recognizer delegates). Install 27; 25/26 are superseded. Build 24 = the Design v4 handoff (PRs #188/#190/#191/#192), the no-"due" sweep + Today card actions (#183), universal links (#156), the swipe stick-open fix, HealthKit batch (#90/#40), Claude batch (#148), catalog seeding policy + equipment self-heal (#185/#186). Build 23 = first associated-domains build; build 22 = the entitlement pipeline fix. Builds 18–21 never reached TestFlight (see the 2026-07-08 entitlements decision). Build 16 = store-recovery fix (#153: build 15 crash-looped on update-in-place installs because the #144 entity renames made old stores unreadable; the app now destroys-and-recreates on open failure — beta stopgap, 1.0 policy is #155). Build 15 = routines rename (#144) + share links (#145). ⚠️ Update-in-place is safe from build 16 onward; 15 needed a fresh install. ⚠️ Builds 17–20 shipped **without any capability entitlements** — an unsigned archive carries no `.xcent`, so the export's cloud signing had nothing to request (17's widgets couldn't read the App Group; 18/20 failed upload validation once the watch demanded healthkit). Fixed in build 22: the archive's bundles are re-signed with a throwaway **self-signed identity** to embed real entitlements before export (see the 2026-07-08 decision), and the App IDs carry HealthKit/App Groups (Dave, portal). Org Actions secrets survived the transfer.

**Vocabulary (#144):** templates are **routines**, performed things are **workouts** — `Routine`/`RoutineExercise` vs `WorkoutSession`/`SetLog`. Interchange keys renamed with no schema bump (zero external users at the time).

**plusplus.fit:** Vercel-ready (Dave's account owns the domain; static, `vercel.json`, Pages workflow retired) with the marketing page, docs, `/privacy` (public-TestFlight prerequisite), and `/r` — the client-side shared-routine viewer. Tagline is Dave's: "**The hackable workout tracker for incrementing yourself**". ⚠️ **The Vercel dashboard import hasn't happened** — Dave's 2-minute step: Add New → Project → import `plusplusinc/plusplus.fit` → preset "Other" → attach plusplus.fit. Until then nothing deploys — which also gates universal links: the AASA carries the real Team ID (WK2XVYGZU9) and the app ships the associated-domains entitlement since build 23, so https share links open the app as soon as the site serves.

**Work tracking:** The v1 backlog lives in GitHub issues on `plusplusinc/plusplus`, feeding the user's GitHub Project board via its auto-add workflow. Changes land via PRs (self-merged once CI is green — the required `test` check must PASS, see branch protection above) with `Closes #N` linking; issues close on merge except where validation is explicitly pending (#1).

**What works (as of 2026-07-07 late-night, design-v3 end to end):** the Claude Design v3 handoff shipped in one overnight arc — #114 palette, #115 nav, #124 Today+diffs, #125 schedule+onboarding, #126 watch v1, plus the #107 scroll root-cause fix and #127 gesture hardening. The app is four bottom tabs on the native iOS 26 Liquid Glass TabView (#130): Today · Routines · Exercises · Equipment. **Today** — the unified timeline: pending (due) workouts as dashed cards with per-exercise diff summaries (`+5 lb · +2 reps · 1 new · 2 =`), expandable rows, due captions ("due today" / "due since thu"), full-width Start; committed sessions below with net chips (green, up-only); rest-day/first-run timeline items and a swap-in sheet for off-schedule sessions; settings opens here. **Routines** — cards with schedule + equipment pills, header + creates; detail keeps the v2 rail (+ a share button, #145) (drag/ring gestures now on a UIKit recognizer so the list actually scrolls) with schedule/rest chips under the title. **Exercises / Equipment** — pushed detail screens forming a navigable graph (#137: equipment ⇢ exercises ⇢ routines, create-at-every-dead-end); the header + pushes CatalogBrowseScreen (#139: whole catalog listed, membership toggles, All/In-library/Not filters); built-ins editable except name, with revert-to-default (#136). **Sharing** — routine detail → `plusplus.fit/r#…` link (payload in the fragment, never on a server); `plusplus://` links open an import preview (#145). **Onboarding** — setup-as-timeline (#132): no cover screen; a fresh install's Today shows three setup steps as gated timeline entries (equipment → first workout → schedule, bottom-up like commits) that become committed-style cards when done and yield to real history at the first logged session; equipment access re-runnable from Settings → EQUIPMENT ACCESS. **Watch** — WatchConnectivity companion: plan pushed on launch/backgrounding, wrist execution (frozen step list, log/rest/haptics, watch-local rest-over notification, early exit), finished sessions sync back as append-only history with a synchronous acked import. Session records show block-level Δ vs the previous same-workout session. **Platform surfaces (#147, build 17)** — rest countdown as a Live Activity (Dynamic Island + Lock Screen, driven from RestNotifier's lifecycle so island and notification can't disagree); *Due today* and *Streak* widgets (12-week mini contribution row) reading a `WidgetSnapshot` written to the App Group (`group.com.davidcole.plusplus`) on launch/backgrounding; App Intents (StartRoutineIntent / DueTodayIntent / OpenTodayIntent + shortcut phrases — intents read the snapshot, StartRoutine posts `.plusplusStartRoutine` and RootTabView/TodayView react). **Design v4 (2026-07-08, overnight)** — blue selection grammar everywhere (`selected`/`selectedTint`/`selectedRing`; segmented tabs lost their ink fill; one motion rule: 0.15 s ease-out + selection haptics); routine settings and app settings are pushed pages (routine settings = NAME/rename tray/SCHEDULE/rest/notes tray/Delete-with-confirmation; detail header shows plain facts); the Today pending card is name+estimate / Configure capsule / muscles+gear rows / promoted diff; the superset rail redrawn (solid spine, border-colored return loop with chevrons at rest, selection-blue highlight + SUPERSET legend only while the ring gesture is live; SUPER swipe died); onboarding equipment rides the real catalog in setupMode (pinned Done bar; the preset strip died as destructive, #203); TipKit replaced the ambient captions; fresh installs seed the catalog with an EMPTY library (#185). **Build-27 feedback round (2026-07-08 morning)** — completion is PURPLE (#201: `Theme.done`, GitHub's merged pair — committed rail nodes, session pips, the finished checkmark, widget streak squares; green stays data-in-motion, blue stays selection); creation affordances are GREEN everywhere (#202); the populate offer asks from a centered alert on Today with an ask-time count (#204 — the catalog popover floated anchored to nothing); the catalog is EXTENSIVE (#95 content: 157 exercises / 40 equipment, and `loadIfNeeded` is a name-matched top-up so growth reaches existing stores — newcomers arrive catalog-only and un-owned, curation untouched).

**Remote validation layer:** 5 XCUITest smoke tests (`PlusPlusUITests`) run on the CI simulator via the `ui-test` job (workflow_dispatch + pushes to main) and upload a `ui-screenshots` artifact — list, detail, editor, set logging, rest, complete, history, the overflow-scroll regression, and the full setup-timeline onboarding flow are all reviewable from a browser. The app supports `--uitest-reset` (in-memory store) for clean test launches. This narrows, but does not replace, the hands-on #1 checklist.

**Targets:**
- **PlusPlus** — iOS app (deployment target iOS 26.0; App Group entitlement, Live Activities enabled)
- **PlusPlusWatch** — watchOS companion (WatchConnectivity, no SwiftData/HealthKit; depends on PlusPlusKit)
- **PlusPlusWidgets** — iOS widget extension (#147): Live Activity + home-screen widgets; shares `PlusPlusShared/` sources and the App Group with the app
- **PlusPlusKit** — pure SwiftPM package shared with the CLI and future MCP (tested on Linux in CI)
- **PlusPlusTests** — unit test target (72 tests; 109 more live in PlusPlusKit, 23 in PlusPlusCLI)
- **PlusPlusUITests** — UI smoke test target (5 flows, `PlusPlusUI` scheme, CI-only by convention)

**Project structure:**
```
project.yml              # XcodeGen project definition (registers PlusPlusKit)
docs/PLATFORM.md         # Developer-platform architecture + owner TODOs
docs/AGENTS.md           # Agent quickstart: files, CLI --json, MCP server
docs/recipes/            # Copy-paste Actions for workout repos (lint, weekly report)
PlusPlusKit/             # Pure SwiftPM package (Linux-tested in CI)
  Sources/PlusPlusKit/   # MuscleGroup/ExerciseType, WorkoutMetric, RepTarget,
                         #   RoutineSchedule (cadence, carried-over dueState, dueSince),
                         #   RoutineDiff (Today's diff engine, #111),
                         #   RoutineShareLink (share-link payload codec, #145),
                         #   WatchSync (watch payloads + codec, #6),
                         #   RailArrangement (detail-view gesture geometry, #78),
                         #   Interchange DTOs + codec + validator + Slug + documents,
                         #   FileLayout (repo paths) + SyncPlanner (3-way merge)
                         #   + SyncEngine/RepoStore/SyncBaseStore (sync pass, #23)
  Tests/PlusPlusKitTests/ # Metric/Units/RepTarget/Rail/Schedule/Diff/WatchSync/Interchange/Sync/Conformance (109)
PlusPlusCLI/             # plusplus CLI (SwiftPM exec, Linux-tested in CI)
  Sources/plusplus/      # init/lint/stats/import/export + MCP server (mcp subcommand)
  Tests/PlusPlusCLITests/
PlusPlus/                # iOS app target
  PlusPlusApp.swift      # App entry point, ModelContainer, seed data, appearance, watch bridge
  Watch/
    WatchBridge.swift    # Phone side of watch sync: plan push, synchronous result import
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
    Components/               # Shared controls: SearchField, SwipeRevealRow +
                              #   SwipeActionButton, SheetComponents (SheetHeader/
                              #   SectionLabel/ActionButton/MetricStepperRow), SegmentedTabs
    RootTabView.swift         # Root: native Liquid Glass TabView (4 tabs), ++ splash beat,
                              #   onOpenURL share-link handler (#145)
    TodayView.swift           # Unified timeline: pending diffs + committed cards + swap-in
                              #   + setup-as-timeline scaffold (3 gated steps, fresh installs)
    OnboardingView.swift      # SetupState + StarterSeedSheet (equipment setup rides CatalogBrowseScreen setupMode, v4 §F)
    CatalogDetailViews.swift  # Pushed ExerciseDetailScreen + EquipmentDetailScreen (#137)
    ShareImportSheet.swift    # Shared-routine import preview (#145)
    RailGestureRecognizer.swift # UIKit long-press layer for the rail (scroll-safe)
    RoutineListView.swift     # Routines tab — cards w/ schedule pills, create/reorder/delete
    RoutineDetailView.swift   # Routine detail — facts header, v4 rail (return loop), RoutineSettingsScreen + rename/notes trays
    MetricInput.swift         # MetricRow + RepTargetRow controls (wheel sheet + stepper)
    ActiveSessionView.swift   # Execution v2: stepper cards, auto-timer, rest, carry-forward
    SessionOverviewSheet.swift # Mid-session overview + per-block sheet (jump/redo)
    ExerciseDetailSheet.swift # Planning sheet: metrics, structure actions, recent
    LibraryView.swift         # ExercisesTabView + EquipmentTabView + CatalogBrowseScreen (#139)
    HistoryView.swift         # SessionRow + SessionDetailView (block Δs); standalone screen died in #109
    ExercisePickerView.swift  # Exercise picker with filter sheets, custom exercise management
    ExerciseEditorView.swift  # Create/edit custom exercises + ExerciseInfoView (notes/video)
    ExerciseDraft.swift       # Pure validation/normalization for the editor — no SwiftUI import
    ExerciseFilterState.swift # @Observable filter logic (testable, pure)
    SettingsView.swift        # SettingsScreen — pushed page (v4 §B): appearance/units/equipment/data/sync + build footer
    Components/PlusPlusTips.swift # TipKit one-time education (v4 §G)
PlusPlusWatch/           # watchOS companion (#6): WatchStore (plan cache + outbox),
  PlusPlusWatchApp.swift #   ContentView (workout list), WorkoutRunView (wrist execution),
  ...                    #   WatchRestNotifier (rest-over while suspended)
PlusPlusShared/          # PlatformShared.swift — compiled into BOTH app and widget
                         #   extension (#147): RestActivityAttributes (Live Activity),
                         #   WidgetSnapshot + App Group channel (widgets can't see SwiftData)
PlusPlusWidgets/         # PlusPlusWidgets.swift — widget extension (#147): rest Live
                         #   Activity (island + lock screen), Due today + Streak widgets,
                         #   App Intents (StartRoutine/DueToday/OpenToday + phrases)
PlusPlusTests/
  ExerciseFilterTests.swift  # Filter logic tests (9)
  SeedDataTests.swift        # Seed data integrity tests (7)
  ReindexTests.swift         # Reindex helper tests (5 + 1 placeholder)
  ExerciseDraftTests.swift   # Custom exercise validation (8)
  SupersetTests.swift        # Workout structure mutations (5)
  SessionTests.swift         # Session factory/rotation/snapshots/progress (7)
  LastPerformanceTests.swift # "Last time" lookup (6)
  InterchangeMappingTests.swift # Export/import round-trip + policies (5) = 72 app + 109 Kit + 23 CLI
PlusPlusUITests/
  SmokeTests.swift           # 5 end-to-end flows w/ screenshot attachments
.github/workflows/ci.yml # macOS CI: xcodegen + xcodebuild test (+ release.yml on v* tags,
                         #   testflight.yml manual-dispatch TestFlight upload)
.xcodebuildmcp/          # XcodeBuildMCP session config
```

`PlusPlus.xcodeproj` is generated by XcodeGen from `project.yml` and is gitignored.

**Known TODOs (tracked as GitHub issues):**
- #1 Interactive Simulator/device validation (Mac session): v3 gesture feel, onboarding fresh-install, watch on real hardware, accessibility settings, #31 store migration FIRST; now also Dynamic Island/Live Activity feel + widget gallery.
- 2026-07-07 batch, still open: store-migration policy for 1.0 (#155), Live Activity controls (#157), platform batch 2 (#158), widget snapshot freshness (#159), contribution infrastructure (#160), org-transfer cleanup remainder (#161 — CI triggers could widen further), diff share cards + contribution graph (#162), README streak-badge recipe (#163), accessibility completion (#164), Foundation Models importer (#165). Shipped overnight 2026-07-08: #156 universal links, #170–#181 (Dave's build-17 feedback + v4), #185/#186/#189.
- #187 per-exercise default targets: full implementation plan on the issue; one focused PR, next session.
- #168 full-swipe-to-commit (after #167's stick-open validates on device) · #169 intermittent scroll dead-zone (needs device repro).
- Strategy backlog #116–#123 (label `fable-token-maxing`): App Store 1.0 path, increment engine, launch plan, Live Activities/widgets, pricing analysis, community flywheel, reliability program, platform framework — detailed, prioritized, written for a future agent or Dave. All public now — Dave chose to leave them.
- #90 Apple Health un-held by Dave (2026-07-07): HKWorkoutSession on the wrist + save workouts to Health is the next app batch (#40 is its older duplicate). Still held: #93 community workout-sharing repo, #94 monetization (his decision; analysis in #120).
- Dave-side: Vercel import for plusplus.fit, public TestFlight link (site + privacy prerequisites met), App Group/associated-domains capabilities if cloud signing complains, repo settings (secret scanning, push protection), Team ID into the AASA file.
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

**2026-07-07 (night) — v3 "ink × increment green" palette; green is data, never chrome** — The Claude Design v3 handoff replaced the GitHub palette with warm ink/cream neutrals; full-chroma green survives only on data (deltas, net chips, committed nodes, next-due values, the ++ glyph). New `primaryFill`/`onPrimary` tokens carry every filled control; `accentButton`/`onAccent` died. Superset blue desaturated (3B6FB0/7FA3D0, Dave's pick) to recede behind the green.

**2026-07-07 (night) — Four bottom tabs; History and the FAB die** — RootTabView with a custom quiet-terminal bar (Canvas commit-node/cards/list/dumbbell icons): Today · Workouts · Exercises · Equipment. Creation is contextual per tab header +; settings lives on Today; LibraryView split into the two catalog tabs. Tab switching is a `switch`, so per-tab navigation state resets on switch — accepted for v3.

**2026-07-07 (night) — Today ⊕ History shipped: the timeline IS the app** — Pending (due) workouts render as dashed cards with per-exercise diffs against last performance; committed sessions sit below on the same rail. `WorkoutDiff` (Kit, pure): weight wins over reps in the summary, never-performed = new, regressions neutral (anti-shame), net chip sums positive movement only. The diff PRIOR is one real set — the top completed set's weight with THAT set's reps (mixing max-weight with last-set reps described sets that never happened).

**2026-07-07 (night) — Carried-over weekday due-ness; occurrences never stack** — A missed Thursday keeps the workout due through Friday ("due since thu") and a late completion satisfies that occurrence; the next scheduled day supersedes rather than stacks. `dueSince` feeds captions; `shortLabel` ("mon/thu", "2×/7d") is the shared pill vocabulary. Editor tabs are Off / Days / Pace with Monday-first 38 pt circles, accent-tinted selection (due-ness is data), and occupancy dots for other workouts' days.

**2026-07-07 (night) — Onboarding: equipment access IS the Equipment tab list** — Two skippable beats (preset cards + chips → Equipment.inLibrary; starter push/pull split composed slot-by-slot from owned built-ins). Ownership filters the catalog everywhere per Dave's call: hide + "show all" escape hatch + "needs X" cues; curated library rows are never hidden, only flagged. Custom-equipment deletion strips references first (the relationship has no inverse).

**2026-07-07 (night) — Watch v1 is WatchConnectivity with a frozen-plan run view; no HealthKit** — Kit `WatchSync` payloads (plan pre-expanded in rotation order; ISO 8601 deterministic JSON). Phone pushes via updateApplicationContext on launch/backgrounding; results return via transferUserInfo and import SYNCHRONOUSLY inside the delegate callback (WCSession acks on return — deferred work can permanently drop a delivered workout). The wrist freezes its step list at first render so mid-session plan pushes can't corrupt a live workout; partial sessions ship on early exit or unexpected pop; a watch-local notification carries "rest over" through suspension (no HKWorkoutSession until #90 un-defers).

**2026-07-07 (night) — Rail gestures live on a UIKit UILongPressGestureRecognizer** — Third strike on the detail scroll bug: SwiftUI's LongPressGesture starves UIScrollView's pan in ANY composition (sequenced, simultaneous, either order). A zero-size probe attaches one UIKit recognizer to the enclosing UIScrollView — the primitive system drag-to-reorder uses — reporting rail-content coordinates; geometry routes ring (x < 37) vs drag, bounded to actual row extents (RailLayout.exercise(at:) clamps to nearest BY DESIGN, so callers must bound y). Regression-tested by a 16-row seeded workout in the UI suite.

**2026-07-07 (night) — Overnight adversarial bug hunt: 3 agents, ~20 verified findings, fixed same night** — Highest-severity: staging an empty-but-scheduled workout committed a permanent 0-set session and satisfied the schedule; the diff prior described nonexistent sets; watch results could be dropped after the WCSession ack; a hold anywhere in the detail viewport hijacked the nearest row. Pattern worth keeping: hunt on fresh code with parallel reviewers told to VERIFY against the actual code before reporting, then fix in the same PRs that introduced the surface.

**2026-07-07 (day) — Native Liquid Glass TabView replaces the custom bar; HIG type/contrast/target pass (#130)** — Dave's build-10/11 feedback: the v3 custom bottom bar died in favor of the system `TabView` (`Tab(_:systemImage:value:)`) — system hit targets, accessibility, and scroll-edge treatment for free; the quiet-terminal identity lives in the content, not the chrome. Same pass bumped small text a tier toward HIG minimums, fixed `textFaint` contrast, standardized 44 pt targets (header +, day circles), and added tray headroom.

**2026-07-07 (day) — Set screen redesigned around the values (#131)** — The active-exercise screen felt empty and Log set sat dangerously close to the steppers. Weight/reps are now two big card columns center-stage (44 pt mono values opening the wheel, 56 pt −/+ buttons); Log set stands alone in a bottom dock with 28 pt of clearance.

**2026-07-07 (day) — Onboarding is the timeline: setup steps as gated commits (#132, supersedes the #125 cover and #129's land-on-Workouts)** — The Claude Design setup-as-timeline handoff: no onboarding screen at all. A fresh install lands on Today, where three setup steps render as timeline entries stacked bottom-up like commits — equipment (1 of 3), first workout (2 of 3, gated), schedule (3 of 3, gated) — ready steps as dashed pending cards with a CTA, gated steps dimmed with "needs X first", done steps as committed-style cards (green node, `date · summary`, edit ›). The scaffold yields to real history at the first logged session. Only equipment stores a flag (`SetupState`, UserDefaults) — its done-ness can't be derived; workouts and schedules are derived live, so the steps self-heal (delete your last workout and the step reopens). The equipment picker and starter-split seeder are standalone sheets shared with Settings.

**2026-07-07 (eve) — SwipeRevealRow hit-testing + session identity save (#134)** — Two tap bugs, one lesson each: `opacity(0)` does NOT remove a view from hit testing (hidden swipe actions now `allowsHitTesting(false)` and `.plain`-styled — List routes row taps into default-styled buttons); and `fullScreenCover(item:)` keys on `persistentModelID`, which CHANGES at the first save of a fresh model — `WorkoutSession.start` saves synchronously so a live session never re-presents. Same PR: per-equipment `weightStep` (Kit `stepOverride` param; smallest override among an exercise's gear wins) and the SF Symbols sweep (no pictographic glyphs in strings; typography like Δ − → stays).

**2026-07-07 (eve) — Catalog is a graph; built-ins editable except name (#136/#137/#139)** — Exercises/Equipment tabs push real detail screens (cross-links: equipment ⇢ exercises ⇢ routines; creation at every dead end); sheets survive only for create/edit forms — a rule that then made the catalog browser a pushed page too (Dave's call): CatalogBrowseScreen lists the WHOLE catalog with membership Toggles (nothing vanishes on add), All/In-library/Not filter, the picker's muscle/equipment filter sheets reused. Built-ins open in the full editor with the name locked (identity IS the name, #32) and revert-to-default backed by a SeedData definitions table.

**2026-07-07 (eve) — Routines rename, no schema bump (#144)** — Dave: templates are ROUTINES, performed things are WORKOUTS. Renamed everywhere (code, interchange keys `workouts`→`routines` and `workoutName`→`routineName`, FileLayout `program/routines`, fixtures, UI); kept WorkoutSession/SetLog/WorkoutMetric/"Workout Complete"/"Start workout". Schema stayed v1 — zero external users made it the free window. Entity renames reset local stores (accepted; data was throwaway).

**2026-07-07 (eve) — Share links carry the routine inside the URL fragment (#145, PLG #141-A)** — `RoutineShareLink` (Kit): `{share:1, units?, routine: RoutineDTO, exercises: [ExerciseDTO]}` → sorted-keys JSON → base64url behind a "0" encoding tag on `https://plusplus.fit/r#…`. Fragments never reach servers — privacy by construction — and sorted keys make identical routines produce identical links. The static viewer renders client-side; `plusplus://r#…` opens ShareImportSheet, which imports via the normal interchange policies. Explicit Info.plist now (URL types can't be INFOPLIST_KEY settings) with CFBundleVersion still `$(CURRENT_PROJECT_VERSION)` for TestFlight numbering. Universal links deferred until the associated-domains entitlement + real team ID.

**2026-07-07 (eve) — plusplus.fit hosts on Vercel** — Domain already lives in Dave's Vercel account; static + preview deploys + serverless headroom beat migrating elsewhere. `/r` viewer + `/privacy` shipped; GitHub Pages workflow retired; Dave's one-time dashboard import connects the repo.

**2026-07-07 (late eve) — Org transfer + open source: AGPL-3.0 app, MIT Kit/CLI (#154)** — Both repos moved to the `plusplusinc` org and went public (old URLs redirect). Dave's licensing call: the app under AGPL-3.0 (contribution-friendly, structurally hostile to rebranded App Store clones), PlusPlusKit + PlusPlusCLI + the conformance fixtures under MIT (the contract is meant to be adopted without copyleft obligations). A full-history secrets scan ran clean before the flip. Free public-repo Actions minutes obsolete the 10x macOS-billing caution.

**2026-07-07 (late eve) — Store recovery: destroy-and-recreate on unopenable stores (#153, build 16)** — Build 15 crash-looped for update-in-place installs (the #144 entity renames made pre-15 stores unreadable and init `fatalError`'d). The app now deletes the store files (+ -shm/-wal) and recreates on open failure, clearing the stale setup flag; the setup timeline self-heals. Beta-appropriate — data is explicitly throwaway until sync ships; the 1.0 migration policy is #155. In-memory (`--uitest-reset`) failures still fatalError: a test store that can't open is a bug, not a recovery case.

**2026-07-07 (late eve) — Platform batch 1: Live Activity, widgets, App Intents (#147 → PR #152, build 17)** — The rest countdown is a Live Activity (Dynamic Island compact/expanded/minimal + Lock Screen banner), date-based like the in-app timer and driven from RestNotifier's existing lifecycle moments so the island and the rest-over notification can never disagree. New `PlusPlusWidgets` extension target + `PlusPlusShared/` sources; widgets can't see SwiftData, so the app writes a tiny `WidgetSnapshot` to the App Group (`group.com.davidcole.plusplus`) on launch/backgrounding — the same moments the watch plan pushes. Widgets: Due today + Streak (12-week mini contribution row). App Intents: StartRoutineIntent/DueTodayIntent/OpenTodayIntent with shortcut phrases; `RoutineEntity` keys on the name (identity IS the name, #32). Extension gotcha: an empty `CFBundleVersion` makes the simulator refuse the .appex — `CURRENT_PROJECT_VERSION: 1` in project.yml, overridden by TestFlight's run number. Display-only island for now (#157 adds controls); snapshot freshness is #159.

**2026-07-07 (late eve) — Branch protection: required checks on main; ci.yml runs on every push** — A repository ruleset gates merges on `test` + `kit-test` + `cli-test` passing (squash-only). Cancelled required checks must be re-run before merge. The docs-only `paths-ignore` in ci.yml died: a docs-only push produces no runs, the ruleset waits for checks that never come, and a green `workflow_dispatch` run on the identical SHA did not satisfy it in practice — free public-repo minutes make always-run the simple correct answer. The Claude GitHub App needed installing on the plusplusinc org for API merges to work at all.

**2026-07-08 — Entitlements require a signed archive; self-signed embedding + portal capabilities (#90 fallout, builds 18–22)** — The unsigned-archive pipeline (#55) shipped NO capability entitlements: `CODE_SIGNING_ALLOWED=NO` skips the entitlements phase, so the archive carries no `.xcent` and the export's cloud signing requests nothing — silently fine for entitlement-free builds 1–16, silently broken for build 17's App Group, loudly broken (90701) once the watch's `WKBackgroundModes: workout-processing` DEMANDED healthkit in the signature. Portal capabilities alone didn't fix it (build 20: profiles carried healthkit, the request still didn't). Ad-hoc archive signing is refused for iOS/watchOS SDKs (build 19). What works (build 22): after archiving unsigned, re-sign the three bundles inside the archive with a **throwaway self-signed identity** via the codesign CLI (`-macalg sha1 -keypbe/-certpbe PBE-SHA1-3DES` on the p12 — macOS's importer can't read OpenSSL 3 defaults), embedding each target's xcodegen-generated entitlements; the export's re-sign reads those as its request and the App Store profiles (capabilities enabled in the portal by Dave) satisfy it. New capability = enable it on the App ID in the portal + entitlements file in project.yml; the workflow needs nothing new. TestFlight distribution never depended on any of this — App Store profiles carry no device list.

**2026-07-08 — No obligation vocabulary: "due" is banned from every user-facing surface (#172)** — Dave's call, sharper than a rename: a routine's presence on Today IS the statement, so nothing needs to say "due" (or any replacement). Card captions died outright, the Today header lost its "N due" tally, the *Due today* widget became **Today** (`kind` and struct names unchanged — renaming orphans installed widgets/shortcuts), Siri answers "Today: Push Day", the rest-day line shows plain calendar info ("next wed — Push Day"), and snapshot captions carry the schedule's own `shortLabel`. "Due since X" was also an anti-shame violation — that whole caption class is gone. Kit API names (`dueState`, `dueSince`) stay internal. The general rule for future copy: presence and position communicate; obligation words don't get written.

**2026-07-08 — Selection blue #62b6de: green is data, blue is UI state (#176, direction set)** — Dave picked the Claude Design blue (#62b6de, or tuned variants) as the selected/interactive color, resolving the pill-state inconsistency (white fills vs green fills) by giving each hue one job: full-chroma green stays data-only (v3 rule), blue carries selection and interactive state. Implementation rides the Design v4 handoff (per-scheme variants, text-on-blue contrast, distance from the desaturated superset blue). Companion rule, also Dave's: **the app must always feel fast and responsive to input** — selection transitions are snappy (~0.15 s), never default-slow, never absent.

**2026-07-08 — Design v4 implemented in one overnight pass (PRs #188/#190/#191/#192/#193)** — Tokens: `selected` #1A7FA8/#62B6DE + tint (12%/16%) + ring (55%); `info` retired ("new" = data green); every selectable speaks tint+content+ring with 0.15 s ease-out and selection haptics. Trays: title upper-left + primaryFill commit capsule (SSC table); pickers get the ✕ variant. Routine settings and app settings became pushed pages; text entry stays in trays (notes, rename). The superset rail: solid spine, return loop at x=3 drawn in border at rest (collapsed it's just an order map), selection-blue full-row highlight + punched SUPERSET legend only while the ring gesture is live — outside a live gesture the app has exactly one blue; SUPER swipe died. Onboarding equipment rides the real catalog (setupMode: preset strip + pinned Done + populate offer); the catalog top got the 44 pt density pass (ownership toggle moved into the equipment filter tray, list-end escape hatch). TipKit (3 one-time tips) replaced ambient captions, never configured under UI test.

**2026-07-08 — Routines rename in place; the "renames are new identities" law stays exercise-only (#189)** — Routine identity is the SwiftData reference (sessions link directly; name matching is only the broken-reference fallback), so editing `routine.name` keeps schedule anchoring and history — past sessions deliberately keep their snapshot name. Duplicate names are blocked case-insensitively. Accepted edges: Siri shortcuts pinned to the old name re-pick; an in-flight watch session imports under the old name; the future sync repo sees a new file (policy when #23 is real). Exercises are unchanged: their names ARE the history join key.

**2026-07-08 — Fresh installs seed the catalog, not the library (#185); built-in equipment self-heals (#186)** — Built-in exercises seed `inLibrary = false`; population is the user's optional call at the end of equipment setup ("Add N exercises your equipment supports?" / "Start empty"), and anything used joins the library on its own (starter seeder already did). Existing stores untouched. Separately, Dave's store surfaced Bench Press as bodyweight though the seeder is provably correct — the loss path couldn't be reproduced (seeder, name-matched import, identity-scoped deletion, editor draft all ruled out), so a one-shot UserDefaults-keyed repair restores empty-equipment built-ins from the canonical definitions table, with regression tests locking the requirements. If it recurs post-repair, there's a live repro to chase.

**2026-07-08 (late) — Exercise defaults bump from routine edits (#187)** — Exercise carries optional defaultWeight/defaultReps/defaultRepsUpper/defaultDurationSeconds; fresh routine entries prefill from them; editing targets in the planning sheet writes back (the latest prescription anywhere IS the default — Dave's call). Editor gains a DEFAULTS stepper card with Clear. Interchange fields are additive; schema stays v1.

**2026-07-08 (late) — Widgets compute, snapshots don't assert (#159)** — WidgetSnapshot carries every schedulable routine's encoded RoutineSchedule + lastCompleted; the widget extension links PlusPlusKit and computes due-ness per timeline entry (now + 7 calendar midnights), the streak rolls forward to the entry date (stale snapshots can't overstate), Siri computes at ask time. Frozen `due` list retained solely as the pre-#159 fallback.

**2026-07-08 (late) — Island rest controls run in the app's process (#157)** — +15s/Skip are LiveActivityIntents in PlusPlusShared (both targets see the type; the system executes in the app process) posting .plusplusAdjustRest; ActiveSessionView routes to the same extendRest/endRest as the on-screen buttons. Critical pairing: scheduleRestEnd no longer tears down the activity (update is background-legal, request is foreground-only — the swift-reviewer agent caught +15s destroying its own island pre-merge).

**2026-07-08 (late) — Docs are verified claims, not prose (Dave's ask)** — three parallel doc audits fixed every stale claim (watch "stub", test counts, private-repo PAT instructions, PLATFORM.md phase status and commit-message examples); PLATFORM.md's JSON examples are now EXECUTABLE (DocsConformanceTests in the CLI target decodes + validates them on Linux CI — it caught its first drift within an hour); a docs-drift PostToolUse hook names the owning doc when contract files change; the standing rule lives in CONTRIBUTING.md.

**2026-07-08 (late) — Committed .claude/ dev setup (Dave's ask)** — skills (ci-status / pr-flow / testflight), agents (swift-reviewer with the repo's proven bug classes — paid for itself on its first run; doc-verifier), the docs-drift hook. .gitignore keeps only settings.local.json out.

---

## Patterns Reference

> Add established patterns here as they emerge to avoid re-litigating decisions.

**SwiftData test containers:** ⚠️ in-memory configurations (`isStoredInMemoryOnly: true`) share state across containers in one process — **even uniquely named ones** (proved twice on CI 2026-07-08: a repair test's `bench.equipment = []` surfaced inside a different test's "fresh" container, before AND after a unique-name fix; Swift Testing runs suites and tests in parallel, so the corruption is scheduling-dependent ~50% flake). The only real isolation is a throwaway on-disk store per container:
```swift
let schema = Schema([Exercise.self, Equipment.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("mytests-\(UUID().uuidString).store")
let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
let container = try ModelContainer(for: schema, configurations: [config])
let context = ModelContext(container)
```

**SwiftData pre-insert relationship loss:** ⚠️ assigning a relationship on a model BEFORE `context.insert(model)` — including via an init parameter — when the targets are already inserted loses the assignment **nondeterministically**. This was the seeder's Bench-Press-as-bodyweight loss: #186's unreproducible field bug AND a night of ~50% CI red chased through three wrong theories (shared in-memory stores, cross-container aliasing, fixture-name collisions) before the fixture-precondition assert pinned it. Rule: **insert first, assign relationships after.** `Exercise.init(equipment:)` is only safe for containerless graphs (the SeedData definition tests). Test fixtures also use "Probe …" names instead of catalog names, so a corrupted seed can never masquerade as a fixture collision again. A repo-wide audit of remaining pre-insert assignments (RoutineExercise/ExerciseGroup mutations, session factory) is #195. The tripwire kept firing even after the pre-insert fix, so `Exercise.equipment` now carries an **explicit inverse** (`Equipment.exercises`) — unidirectional to-manys are where CoreData integrity is documented to fray, and every relationship should declare its inverse from now on.

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
