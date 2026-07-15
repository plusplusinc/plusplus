# PlusPlus (++) — Project Instructions

Read this at the start of every session. Update it when facts change — a stale CLAUDE.md is worse than none. The full architectural record lives in **docs/DECISIONS.md** (append new decisions there); directory-scoped patterns live in **.claude/rules/** and load automatically when you touch matching files.

---

## What This App Is

**PlusPlus** (`++`) is an iOS fitness tracking app with Apple Watch companion functionality. The name references the programming increment operator; the `++` mark visually resembles a dumbbell, which is intentional branding.

---

## Tech Stack

- **Language:** Swift / SwiftUI
- **Platform targets:** iOS 26+, watchOS 26+

No third-party dependencies without discussion first.

---

## Tooling

**XcodeBuildMCP** (Mac sessions) is the primary interface for all Xcode operations — build, test, Simulator control, log capture, screenshots, UI automation, debugging. Don't fall back to raw `xcodebuild` when an MCP tool exists. Validation means build → launch → drive the changed flow via UI automation → screenshot; capture runtime logs before guessing at any unexpected behavior.

**Remote (Linux) sessions** have no Xcode/Simulator — CI verifies app targets (see the ci-status skill). The Kit/CLI suites DO run locally: `./scripts/install-swift.sh`, add `$HOME/.swift/usr/bin` to PATH, `swift test` in `PlusPlusKit/` / `PlusPlusCLI/`.

---

## Claude Code Setup (committed)

- **Skills** — `/ci-status` (check/diagnose/rerun CI from a sandbox that can't reach job logs), `/pr-flow` (the parallel feature-branch PR workflow), `/testflight` (shipping a build + the entitlement mechanism and its failure modes). Read the matching skill BEFORE re-deriving any of that from scratch.
- **Agents** — `swift-reviewer` (adversarial review tuned to this repo's proven bug classes; run it on any non-trivial diff before pushing, layered with the built-in `/code-review`) and `doc-verifier` (claim-by-claim docs audit; fan out one per doc).
- **Rules** (`.claude/rules/`) — path-scoped patterns: `swiftdata.md`, `testing.md`, `ui-interaction.md`, `app-surfaces.md` (surface map + design grammar). They load when you read matching files; skim them anyway before big app work.
- **Hooks** — `docs-drift` (PostToolUse): editing interchange/CLI/workflow/project.yml files injects a reminder naming the doc that owns the claim.
- **Plugin — `axiom@axiom-marketplace`** (Apple-platform skills + auditor agents; marketplace `CharlesWiltgen/Axiom`, declared in `.claude/settings.json`): a large library covering accessibility, SwiftUI layout/nav/architecture, concurrency, performance, memory, Core Data / SwiftData, testing, crashes, HIG/design/typography, shipping, HealthKit… **Reach for it whenever a task falls in its wheelhouse** — before hand-rolling an audit or re-deriving Apple guidance, use the matching skill/agent (accessibility → `accessibility-auditor` + `axiom-accessibility`; Dynamic Type / layout → `swiftui-layout-auditor` + `axiom-design`'s typography/hig refs; HealthKit → `axiom-health`; a review → the relevant `*-auditor`). Its knowledge skills AND reasoning/auditor agents (pure static Glob/Grep/Read) DO load and run in remote Linux sessions; only the Xcode/Simulator-backed tooling (`xcui`/`xclog`/`xcsym`/`xcprof`, build/run/screenshot/simulator, `/axiom:*` device commands) is inert remotely. ⚠️ An ephemeral remote container does NOT auto-install it from `enabledPlugins`; the `SessionStart` hook `.claude/hooks/ensure-axiom.sh` installs it each session (baked into the cached container). Treat its keyword-triggered hook matches as advisory. See docs/DECISIONS.md 2026-07-13 (Axiom).
- **Docs stay true by construction where possible**: PLATFORM.md's JSON examples are executable (`DocsConformanceTests`, Linux CI). Otherwise: a PR that changes an interface touches the doc that describes it, or says why not.

---

## Architecture Principles

- Effective complexity management above all else — code should be easy to understand and easy to adapt
- Deep modules over shallow ones: hide significant complexity behind simple interfaces
- No premature abstraction — only abstract when duplication is real and present
- iOS-native first: start with what SwiftUI provides, customize deliberately

---

## Current State

> Keep this section current and SHORT. Session-by-session history belongs in docs/DECISIONS.md entries; build genealogy in its appendix.

**Last updated:** 2026-07-15. **In flight (PR #372, `claude/3d-exercise-mascot-k0hb06`; Build 80 dispatched from the branch — NOT merged, shipped for on-device validation):** the 3D exercise mascot prototype — a code-defined RealityKit bot (primitives only, zero assets; the face IS the ++ mark: two "+" eyes that blink plus-to-minus, squeeze with the authored `effort` channel on hard phases, and droop through an end-of-set tired beat; 4-finger cartoon hands) demonstrates form on 5 exercises (Squat, Deadlift, Push-Up, Dumbbell Curl, Plank). ALL pose/keyframe/face math is in `PlusPlusKit/Mascot/` (no simd — Linux-validated: 307 Kit tests green, ~37 new invariant checks incl. FK planted-feet/floor/symmetry), rendered by `PlusPlus/Views/Mascot/` (first `import RealityKit` in the repo; Euler→quat order pinned to Kit's `Mat3` by a parity test). Animations key on the exercise NAME (`MascotMoves`, the `builtInProfilesByName` pattern) — no model column, no migration, no interchange change. Surfaces: FORM section (live inline preview card → orbit + amber-synced-cues demo sheet) on `ExerciseDetailScreen` + `ExerciseDetailSheet`; frozen (static pose + step-through) under Reduce Motion / `--uitest-reset`; new smoke flow `testExerciseSheetShowsFormDemo` (9 flows now). ⚠️ Needs on-device validation: the two flagged RealityKit unknowns (`.orbit` vs supplied camera; viewport background transparency — fallbacks staged), animation quality, materials both schemes, scroll perf. Scale-out to the other ~250 moves is the follow-up. See docs/DECISIONS.md 2026-07-15 (mascot). **In flight (`claude/first-open-view-tweaks-ro0oyt`, PR open — NOT merged, needs on-device validation):** first-open reworked. A cold open now ALWAYS opens on the `++` mark (`WelcomeView.swift` renamed its struct to `IntroView`, fusing the splash + first-launch welcome; `RootTabView` shows it on every cold open, `introShowsWelcome` = `!welcomeSeen` picks settle-into-welcome vs hold-then-dissolve). The splash `++` and the welcome `++` are ONE glyph moved + scaled (`matchedGeometryEffect(.position)` + `scaleEffect`, font can't animate). The "Start building" key gained a `chevron.right` and equal side/bottom insets + bigger radius for a concentric feel; tapping it plays an "ignition" beat (green commit-wipe L→R, label → "let's go", chevron takeoff, `.success`, then a dive-to-Today). All motion is on-device-only (inert under UI test); `welcomeStartButton` id + "PlusPlus" text unchanged so `testWelcomeFlow` still passes. See docs/DECISIONS.md 2026-07-15 (first-open). **In flight (PR #361, `claude/first-screen-messaging-jexos2`; Build 78 dispatched from the branch — NOT merged, shipped for on-device validation):** onboarding trimmed to ONE welcome screen (the mechanics tour + the up-front Health screen removed); the Apple Health ask is now a contextual first-workout primer (`HealthStartPrimer` in `Views/Components/`, gated ONCE for every start path via `HealthStartGate` — Today/routine-detail/"Do it again"/Siri; "Not now" = the Settings-reversible off switch, `HealthSyncCoordinator.disable()`). It also adds `activeEnergyBurned` to the read set and shows a per-workout calorie line on the session record (queried LIVE from Health, deliberately not persisted → no migration/interchange change). Welcome copy settled: NO second line (the tagline stands alone), CTA "Start building". Wider Health-data prioritization: request ONLY what a surface uses; Tier-2 fitness-trend reads (resting HR, VO2 max, HR recovery, bodyweight) filed on #295 to ride a future trends surface with one batched contextual ask. ⚠️ Every HealthKit path is inert under UI test / absent on CI — NEEDS on-device validation. See docs/DECISIONS.md 2026-07-15. **Build 77** shipped from the `claude/store-migration-uuid-decoupling` branch (#358 + #359, both MERGED to main, on-device validated by Dave): the **1.0 store-migration policy (#155)** + the **"proper" tray-flicker fix**. (1) #155 (`AppSchema.swift`): the container opens `Schema(versionedSchema: AppSchemaV1.self)` + `AppMigrationPlan` instead of destroy-and-recreate; an unopenable store is now **copied aside raw** (`StoreRecovery.backUpAndReset` → `Documents/RecoveredStore-…`, Files-visible) with a one-shot anti-shame alert (`SetupState.storeWasReset`), NEVER a silent wipe. (2) Tray flicker fixed structurally: `Routine`/`ExerciseGroup`/`RoutineExercise` gained a stable `uuid` (`UUID?`, device-local, EXCLUDED from interchange), and ALL routine-family presentation/nav now keys on it (`ModelRefs.swift`: `RoutineRef`/`IdentifiedUUID`, resolved via `ModelContext.routine(uuid:)`) so `persistentModelID`'s temp→permanent swap can never re-key an open sheet/push. Exercise/Equipment nav deliberately stays on `persistentModelID`. **Three hard-won migration/nav lessons** (all in `.claude/rules/swiftdata.md` + `ui-interaction.md`): a snapshot `VersionedSchema` sharing an entity name with a live `@Model` crashes migration → use lightweight-add + a launch backfill (`SeedData.backfillModelUUIDsIfNeeded`); a `= UUID()` PROPERTY default is stamped by migration as ONE shared constant across all rows (build 75 bug: every routine opened the same one) → mint in `init`, leave the property defaultless, backfill ENFORCES uniqueness; and a `NavigationLink(value:)` pushing an unregistered type is a SILENT dead tap, not a compile error (build 76→77 bug: Today cards didn't open) → every push keys on `uuid`, needs a device pass since `ui-test` is skipped on branch builds. Builds 75/76 were pre-merge validation rounds that caught the shared-uuid then the dead-tap bug; build 77 is clean. Kit unaffected; app targets green in macOS CI. Closes #155. See docs/DECISIONS.md 2026-07-14 (#155 / tray-flicker). Older builds: **Build 74** shipped from main (#354, MERGED, VALID in TestFlight): the routine-scheduling fix — a just-added routine no longer shows as due on the wrong day. Due-ness is anchored to when a routine joined the library (`Routine.createdAt`, passed as the Kit's `addedOn`), so a scheduled day before it joined never counts as missed; and `RoutineSchedule.DueState` splits `.due` (scheduled TODAY, green, one-click Start) from `.missed(since:)` (a past scheduled day lapsed within the 6-day window). Today gained an amber **CARRIED OVER** lane (tap-to-open, off today's date), future/upcoming cards lost their inline Start (reserved for today), committed cards gained a purple check seal. Widget snapshot threads the same anchor. Kit 269→270 green on Linux. ⚠️ NEEDS on-device validation (the amber lane, the killed future Start, the check seal). Reviewer-flagged polish riding the NEXT build (open follow-up PR): `dueSince` today-wins, rest-day item yields to carried-over work, missed-lane per-card recompute removed. See docs/DECISIONS.md 2026-07-14 (#354). Older builds: **Build 70** dispatched from PR #345's branch (`claude/healthkit-heart-rate-pace-ugytjh`, NOT yet merged — shipped for on-device validation): live outdoor-run pace — GPS pace + distance shown beside live heart rate, all three framed as target · live actual (actual accents when meeting target). Kit `LivePaceMeter` (pure, 261-test-green) + `MetricProfile.isOutdoor`; phone `RunLocationMonitor` (BACKGROUND `CLLocationManager`, so a pocketed run tracks) engaged only for outdoor exercises in `ActiveSessionView`, auto-fills logged distance/pace actuals; watch runs an `.running`/`.outdoor` `HKWorkoutSession` collecting `distanceWalkingRunning`. Seeds Running/Walking outdoor. `isOutdoor` stays out of the interchange (v1). Background location = Info.plist only (`UIBackgroundModes:[location]` + usage strings), NO entitlement/portal change. App targets green in macOS CI. ⚠️ **Every GPS/CoreLocation path is on-device-only — NOT exercisable remotely; needs on-device validation** (iPhone locked/pocketed + Apple Watch). See docs/DECISIONS.md 2026-07-12 (outdoor-run pace). **Build 69** dispatched from main (#343 — GitHub connect-flow tweaks on #340, MERGED): step changes in the `GitHubSyncTray` wizard now SLIDE (the `SwapInSheet` ZStack idiom, `.selection` spring, Continue right-to-left / Back reverses) instead of swapping instantly; the Authorize step + the create-repo fallback open in an in-app `SFSafariViewController` (auto-dismissed once connected), while Install stays EXTERNAL on purpose (`SFSafariViewController` can't hand a universal link back to the app, so an in-app install would forfeit the post-install auto-return); the reveal's GitHub trigger shows the trailing status word again (green "connected" / red "disconnected" / gray none). Confirmed with Dave the GitHub App has expiring user tokens OFF (a serverless device-flow app can't refresh them anyway), so the earlier "token expired" was a one-off manual disconnect, not a bug. App targets green in macOS CI; NEEDS on-device validation (the slide, the in-app browser, the live device flow, the post-install auto-return). See docs/DECISIONS.md 2026-07-12 (#343). Older builds: **Build 68** dispatched from main (#340 — GitHub connect flow redesign, MERGED): the two-surface GitHub sync (light `SyncTray` → pushed `GitHubConnectScreen`) collapsed into ONE `GitHubSyncTray` with a guided three-step wizard (Create repo in GitHub → Install on GitHub → Connect this app), exactly one enabled primary at a time, non-terminal steps advanced by a quiet "Done? Continue" (+ STEP n OF 3 / Back). Create-repo tries the GitHub app first (`UIApplication.open(github.com/new, universalLinksOnly:)`) and falls back to `github.new` in an in-app `SFSafariViewController` (new `SafariView`). Reveal triggers reworked: GitHub + Calendar rows dropped the word "sync" and sit under a shared SYNC header; the GitHub dot is green (connected) / gray (never connected) / red + "disconnected" (a connect attempt failed or a live connection expired/broke), driven by a NEW persisted `faulted` flag (`GitHubSyncSettings.connectionFaulted`) — the memory an expired-and-cleared token can't provide; NOT set on a `BootstrapError` (repo-not-installed = unfinished, not broken), red gated on `.disconnected` so unconfigured never shows red. Post-install auto-return + reconnect open the tray already on the authorize step. `GitHubConnectScreen.swift` deleted. App targets green in macOS CI; NEEDS on-device validation (the SFSafari fallback, the GitHub-app deep link, the live device flow, the post-install redirect — none exercisable remotely). See docs/DECISIONS.md 2026-07-12 (#340). Older builds: **Build 67** shipped from main (#338 — superset landing v2, MERGED, on-device approved by Dave): the routine-detail superset create→static landing redrawn to Dave's design handoff. The settled return-loop now strokes in an OPAQUE warm gray (`Theme.supersetLoop` #7C786F) — fixing the translucent-blue self-overlap artifact where the Canvas sub-paths compounded alpha and read blotchy; blue is now the MOMENT OF CREATING only (live ring highlight + the landing animation). The create animation is one continuous four-phase sequence off a single linear clock (`supersetLanding.progress` 0→1 over 1.30 s): Reshape (field settles onto the loop, right edge held) → Snap (right edge sweeps left into the line) → Pulse (a `plusLighter` spark travels bottom→top firing each chevron) → Fade (loop crossfades blue→gray). Built as lockstep `Animatable` views — field = `UnevenRoundedRectangle`, spark = radial-gradient `Canvas`, per-row loop/chevron/fade in `RailGlyph` — all reading one `@State`, so one `withAnimation(.linear)` drives them together (no `TimelineView`/`Date`). Growing an existing superset keeps its gray loop through the reshape; a fresh pair reveals. Build 66 was the pre-merge branch preview of identical code. App targets green in macOS CI. See docs/DECISIONS.md 2026-07-12 (#338). Older builds: **Build 63** dispatched from PR #337's branch (`claude/plus-button-redesign-m8aonj`, NOT yet merged — shipped for on-device validation): the ++ button redesign (the slide-to-reveal drawer replacing the pushed AppMenuScreen/SettingsScreen — the whole TabView slides right + scales to uncover an app-level `RevealSurface`; Settings folded in, the active `EquipmentLibrary` promoted to a hero card, GitHub + Calendar sync as parallel rows, rare things as tiles→trays; every existing feature preserved not simplified). App targets green in macOS CI; NEEDS on-device validation (reveal motion, the native tab-bar transform, tray behavior, drag-to-close — none exercisable remotely). Edge-drag-to-OPEN deferred (conflicts with full-width swipe-back). See docs/DECISIONS.md 2026-07-12 (#337). Older builds: **Build 61** dispatched from PR #335's branch (`claude/workout-calendar-sync-x3xmxr`, NOT yet merged — shipped from the branch for on-device validation): calendar sync (#333 — opt-in, scheduled fixed-weekday routines written to a dedicated "++ Workouts" EventKit calendar as recurring events, each with a `plusplus.fit/start/<name>` deep link that starts that workout via the existing `.plusplusStartRoutine` pathway; EventKit covers Apple AND Google [any account added in iOS Settings is a writable source] so no dependency/server/OAuth; full calendar access = Info.plist usage string only, NO entitlement/portal change; one idempotent reconcile on foreground/background diffs desired-vs-managed events so delete/reschedule/retime/unschedule/toggle-off all just work; deleting the calendar is a real off-switch [passive reconcile never resurrects it]; global 07:00 default time, debounced; frequency-mode + per-routine time deferred). Kit 251 green on Linux; app targets green in macOS CI; NEEDS on-device validation (EventKit unavailable remotely). plusplus.fit `/start/*` AASA + fallback page shipped to prod (#333 site PR merged). **Needs on-device check:** turn on in Settings → CALENDAR, confirm events land in Apple/Google calendar, tapping one starts the routine, and deleting the "++ Workouts" calendar turns the feature off. See docs/DECISIONS.md 2026-07-12 (#333). **Bugfix in flight (#346, PR open):** build-71 on-device found a duplicate-"++ Workouts"-calendar bug (relied on `EKCalendar.calendarIdentifier`, which Apple documents a full sync loses); fixed by keying calendar identity on the TITLE, consolidating strays, and removing all title-matched calendars on disable. Needs on-device re-check. Older builds: **Build 55** dispatched from PR #329's branch (`claude/github-integration-1nk2vs`): the GitHub sync feature end to end (#23 — device-flow connect, `RetryingHTTPClient` for the -1005, install-then-authorize UX) plus the interchange export-completeness pass (export = your library #328, and the full field audit: routine schedule, heart-rate targets, session HR + active duration, per-set profile snapshot, with a field-census + completeness-test guard). Older builds: **Build 48** from PR #312 (equipment libraries: per-location gear as a named `EquipmentLibrary`, one active at a time, tray switcher, own→have language sweep, libraries + gear config in the interchange for new-phone restore) — archived before the #313–#316 merge, so it does NOT contain them. Over build 47 (Today-details UX #306 + welcome refinement #310) and 46 (flexible metrics #304 + heart rate #297). Now on main and riding the NEXT build: the stretches/mobility catalog (#313 — 26 built-in stretches on existing primitives, static holds `.duration` / dynamic drills reps, Dynamic Warm-Up + Full Body Stretch recovery routines), Today-layout tweaks (#314), busted-superset-display fixes (#315/#316). **In flight (#322, PR open):** live-mirror FOUNDATION — a Kit CRDT-lite op log/reducer (`LiveSession`) for interchangeable phone/watch workouts (phone = durable record, custody mobile, LWW+opId, watch journals in-progress), the phone/watch adapters that emit + converge, a WHOLE-SESSION Live Activity (working↔resting), and REMOVAL of the phone rest/timer local notifications + their permission prompt (rest cue is now watch haptics + the island). Deferred to follow-ups: watch-screen live-reflecting phone edits, both-open session join, jump/redo cursor ops. Needs 2-device Mac validation. See docs/DECISIONS.md 2026-07-11 (#322). ⚠️ Build number = testflight RUN number. Update-in-place is safe from build 16 onward. plusplus.fit LIVE; universal links ON.

**Org + license:** both repos live in the **plusplusinc** org, PUBLIC. App/repo **AGPL-3.0**; **PlusPlusKit + PlusPlusCLI are MIT** (the contract is meant for adoption). Actions minutes are free on public repos — macOS included.

**Branch protection** (repository ruleset): merges to main require `test`, `kit-test`, `cli-test` to PASS on the head SHA; squash is the only merge method. A cancelled required check blocks merge until re-run; only push-triggered runs satisfy the ruleset (a green `workflow_dispatch` run does not). Docs-only pushes still run CI deliberately.

**CI flakes:** ui-test has two known flavors — `app.launch()` wedging on a runner simulator, and exit-65 runs where the identical tree passes on re-run. Re-run once before suspecting code. (The swipe test's synthesized-drag flake, #273/#274 — the degraded-runner signature that used to need a two-re-run budget — was fixed 2026-07-15: `testSwipeRevealActionSurvivesRelease` now reveals through `revealDelete`, which waits for the action to be hittable and re-drags to absorb runner jitter, so a dropped drag no longer fails the run.) All four jobs surface failing-test names as `::error::` annotations readable via the check-runs API (remote sessions can't reach job logs on Azure).

**TestFlight:** `.github/workflows/testflight.yml` (manual dispatch, any ref) archives unsigned, re-signs bundles with a throwaway self-signed identity to embed entitlements, cloud-signs at export (Admin-role ASC API key), uploads. ⚠️ Build number = workflow RUN number, not last-build+1 — check `actions_list` for the latest run number BEFORE writing the What's-New entry. New capability = enable on the App ID in the portal + entitlements file in project.yml. Full genealogy + failure modes: docs/DECISIONS.md appendix + the testflight skill.

**Vocabulary (#144):** templates are **routines**, performed things are **workouts** — `Routine`/`RoutineExercise` vs `WorkoutSession`/`SetLog`. Never write obligation words ("due") on user-facing surfaces (#172); regressions render neutral (anti-shame). Equipment is **availability, not ownership** (2026-07-11): what gear you "have" is membership in the ACTIVE `EquipmentLibrary` (Home/Hotel/…, one active, device-local pointer); copy says "have"/"in library", never "own" (kept only for data ownership + "My equipment" selection-possessives). Libraries + gear config are in the interchange (`program/equipment/`, `program/equipment-libraries/`); the active pointer is not (device state). See docs/DECISIONS.md 2026-07-11.

**plusplus.fit:** LIVE on Vercel, connected to `plusplusinc/plusplus.fit` — pushes to its main deploy production, PRs get previews. AASA serves the real Team ID; the app ships associated domains. Deploy by merging to the site repo's main (the Vercel MCP's file-upload path is broken from remote sessions). Tagline: "The hackable workout tracker for incrementing yourself".

**Work tracking:** backlog = GitHub issues on `plusplusinc/plusplus` (auto-added to Dave's project board). Changes land via PRs, self-merged once required checks are green, `Closes #N` linking. **The expected output of any implementation session is a PR — open it without being asked** (Dave, 2026-07-11); never leave finished work sitting on a branch.

**Remote validation layer:** 9 XCUITest smoke flows (`ui-test` job: dispatch + main pushes) upload a `ui-screenshots` artifact reviewable from a browser — includes the onboarding timeline, welcome flow, template-detail open, swipe-release regression contracts, and the mascot form-demo sheet.

**Targets:**
- **PlusPlus** — iOS app (iOS 26.0; App Group, Live Activities)
- **PlusPlusWatch** — watchOS companion (WatchConnectivity; depends on PlusPlusKit)
- **PlusPlusWidgets** — widget extension: Live Activity + Today/Streak widgets + App Intents
- **PlusPlusKit** — pure SwiftPM package, Linux-tested (the platform contract)
- **PlusPlusTests / PlusPlusUITests** — ~146 app unit tests + 9 UI smoke flows; 307 Kit + 26 CLI tests run on Linux (counts verified 2026-07-15)

**Project structure** (annotated per-file map lives in the directories themselves; these are the load-bearing locations):
```
project.yml              # XcodeGen definition; PlusPlus.xcodeproj is generated + gitignored
docs/                    # PLATFORM.md (interchange contract), AGENTS.md, DECISIONS.md, recipes/
PlusPlusKit/             # Pure Kit: metrics vocabulary + profiles, schedules, diffs,
                         #   share links, WatchSync, HeartRate, RailArrangement,
                         #   interchange DTOs/codec/validator, FileLayout, SyncEngine
PlusPlusCLI/             # plusplus CLI: init/lint/stats/import/export + MCP server
PlusPlus/                # iOS app: PlusPlusApp entry, Models/ (SwiftData @Models + SeedData
                         #   + RoutineCatalog), Views/ (one file per screen; shared controls
                         #   in Views/Components/), Theme/, Health/, Watch/ (bridge),
                         #   Notifications/, Interchange/ (model↔DTO mapping)
PlusPlusWatch/           # Wrist app: WatchStore (plan cache + outbox), WorkoutRunView
PlusPlusShared/          # Compiled into app AND widgets: Live Activity attrs, WidgetSnapshot
PlusPlusWidgets/         # Widget extension + App Intents
PlusPlusTests/ PlusPlusUITests/  # unit + smoke suites
claude-plugin/           # The SHIPPED product plugin for users' workout repos (MCP + skills)
scripts/install-swift.sh # Linux toolchain for remote sessions
.github/workflows/       # ci.yml (4 jobs), testflight.yml, release.yml
```

**Known TODOs (tracked as GitHub issues):**
- Open batch: #157 Live Activity controls, #158 platform batch 2, #160/#161 contribution/CI-trigger widening, #162 diff share cards, #163 README streak recipe, #164 accessibility completion, #165 Foundation Models importer, #168 full-swipe-to-commit, #169 scroll dead-zone (needs device repro), #295 Health metrics batch 2 (waits on a trends-surface design pass)
- Flexible-metrics follow-ons, deliberately not shipped: AMRAP #298, EMOM #299, pyramids #300, drop sets #301, count-up stopwatch #302
- Strategy backlog #116–#123 (`fable-token-maxing`): written for a future agent or Dave
- Held by Dave: #93 community sharing repo, #94 monetization; un-held: #90 Apple Health (shipped through HR batch)
- Dave-side: public TestFlight link, repo settings hardening, plusplus.fit stale-copy archive
- Deliberate: per-workout rest only (per-exercise deferred; interval blocks now carry group overrides); set ranges collapse to one number

---

## Decisions Log

Lives in **docs/DECISIONS.md** — append-only, same format (**Date — Decision — Reason**). Add an entry there for every architectural or significant implementation decision, in the same PR as the change. Standing laws that every session needs regardless of task stay in this file; everything else (including the reasoning behind current shapes) is in the log — read it before re-litigating anything.

---

## Patterns Reference

Split into path-scoped rules in `.claude/rules/` (they auto-load when you touch matching files): `swiftdata.md` (container/relationship laws), `testing.md` (test isolation, XCUITest blind spots), `ui-interaction.md` (swipe/navigation/gesture laws), `app-surfaces.md` (surface map + design grammar). Add new patterns to the matching rule file — or a new one — not here.

---

## CLAUDE.md Hygiene

This file holds only what EVERY session needs: identity, stack, workflow, current state, standing laws. Everything else has a home — decisions in docs/DECISIONS.md, directory-scoped patterns in .claude/rules/ (use `paths:` frontmatter), procedures in .claude/skills/. Target: keep this file under ~200 lines; if a section grows past its usefulness-per-line, move it to the right home and leave a pointer.

- Nested CLAUDE.md files in subdirectories load lazily and are appropriate once a directory accumulates genuinely local conventions — not before.
- `CLAUDE.local.md` at the project root is gitignored — personal machine-specific config goes there.
- Same approval rule as always: suggest structural changes to this file at end of session; don't restructure without Dave's sign-off.

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
3. **Validate in Simulator** — use XcodeBuildMCP to launch the app, drive the affected flow via UI automation, and capture a screenshot confirming the result. Complete flows end-to-end. Capture runtime logs if anything looks off.

If any step fails, fix it before reporting completion.

**Remote (Linux) sessions:** XcodeBuildMCP and the Simulator are unavailable — CI is the verifier for app targets (see the ci-status skill). But Kit/CLI changes MUST run locally first: `./scripts/install-swift.sh`, add `$HOME/.swift/usr/bin` to PATH, then `swift test` in `PlusPlusKit/` and/or `PlusPlusCLI/` before pushing. A CI round-trip costs ~10 min; the local run costs seconds.

### End-of-Session Summary

- What was built
- Decisions made (append to docs/DECISIONS.md; flag anything that changes THIS file)
- Known issues or follow-on tasks
- Build / test / Simulator validation status
