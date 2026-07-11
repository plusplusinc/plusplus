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
- **Plugin** — `axiom@axiom-marketplace` at project scope (Apple-dev skills/agents; its macOS tools stay inert remotely; treat its keyword-triggered hook matches as advisory).
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

**Last updated:** 2026-07-11. **Build 46** on TestFlight (flexible metrics #304 + heart rate #297, over build 45's catalog-navigation fix #293 and the Quiet Arcade rounds #283/#287). Merged after the 46 dispatch, riding the NEXT build: PR #306 (Today details UX — two-stage start tray, navigating week-ahead cards, "Do it again" on session records, one-action rest-day card, inline superset tip) and PR #310 (welcome-screen refinement — de-gitted copy, SF Symbol rows, pinned dots/primary key; no-em-dashes copy rule in app-surfaces.md). Update-in-place is safe from build 16 onward. plusplus.fit LIVE; universal links ON.

⚠️ **Needs Mac validation** (#1 owns the checklist; all 2026-07 work shipped from remote Linux sessions — compiles, passes CI suites, runs on Dave's phone via TestFlight, but hands-on feel is unvalidated): newest first — the equipment-libraries round (the switcher tray's tap-to-switch → tab-list re-render behind it; the catalog equipment TOGGLE now writes active-library membership via a to-many mutation [confirm the onboarding toggle still flips 0↔1 live — reactivity through `@Query [EquipmentLibrary]`, not the old `inLibrary` Bool]; the amber unavailable-gear pills on routine cards; store migration folding real data into "Home"; the GEAR facet naming the active library) — the Today-details round's finger-only surfaces (upcoming card's inner Start vs card navigation — exactly one must fire per tap; start-tray stage slide + detent growth; inline superset tip layout shift), cardio/interval set screens + planning-sheet metric rows (flexible metrics), live HR surfaces + welcome flow on real hardware (simulators produce no HR samples), Quiet Arcade press feel/flourishes/warm-charcoal pass, v3/v4 gesture feel (rail drag/ring), watch on real hardware, store migration over real data (#31 — FIRST), Dynamic Island/Live Activity feel, widget gallery, accessibility settings, hero-zoom + swipe-back composition, search/dock affordances.

**Org + license:** both repos live in the **plusplusinc** org, PUBLIC. App/repo **AGPL-3.0**; **PlusPlusKit + PlusPlusCLI are MIT** (the contract is meant for adoption). Actions minutes are free on public repos — macOS included.

**Branch protection** (repository ruleset): merges to main require `test`, `kit-test`, `cli-test` to PASS on the head SHA; squash is the only merge method. A cancelled required check blocks merge until re-run; only push-triggered runs satisfy the ruleset (a green `workflow_dispatch` run does not). Docs-only pushes still run CI deliberately.

**CI flakes:** ui-test has two known flavors — `app.launch()` wedging on a runner simulator, and exit-65 runs where the identical tree passes on re-run. Re-run once before suspecting code; budget TWO re-runs when the failure is the swipe test's step-3 re-reveal alone (the degraded-runner signature, #273/#274). All four jobs surface failing-test names as `::error::` annotations readable via the check-runs API (remote sessions can't reach job logs on Azure).

**TestFlight:** `.github/workflows/testflight.yml` (manual dispatch, any ref) archives unsigned, re-signs bundles with a throwaway self-signed identity to embed entitlements, cloud-signs at export (Admin-role ASC API key), uploads. ⚠️ Build number = workflow RUN number, not last-build+1 — check `actions_list` for the latest run number BEFORE writing the What's-New entry. New capability = enable on the App ID in the portal + entitlements file in project.yml. Full genealogy + failure modes: docs/DECISIONS.md appendix + the testflight skill.

**Vocabulary (#144):** templates are **routines**, performed things are **workouts** — `Routine`/`RoutineExercise` vs `WorkoutSession`/`SetLog`. Never write obligation words ("due") on user-facing surfaces (#172); regressions render neutral (anti-shame). Equipment is **availability, not ownership** (2026-07-11): what gear you "have" is membership in the ACTIVE `EquipmentLibrary` (Home/Hotel/…, one active, device-local pointer); copy says "have"/"in library", never "own" (kept only for data ownership + "My equipment" selection-possessives). Libraries + gear config are in the interchange (`program/equipment/`, `program/equipment-libraries/`); the active pointer is not (device state). See docs/DECISIONS.md 2026-07-11.

**plusplus.fit:** LIVE on Vercel, connected to `plusplusinc/plusplus.fit` — pushes to its main deploy production, PRs get previews. AASA serves the real Team ID; the app ships associated domains. Deploy by merging to the site repo's main (the Vercel MCP's file-upload path is broken from remote sessions). Tagline: "The hackable workout tracker for incrementing yourself".

**Work tracking:** backlog = GitHub issues on `plusplusinc/plusplus` (auto-added to Dave's project board). Changes land via PRs, self-merged once required checks are green, `Closes #N` linking. **The expected output of any implementation session is a PR — open it without being asked** (Dave, 2026-07-11); never leave finished work sitting on a branch.

**Remote validation layer:** 8 XCUITest smoke flows (`ui-test` job: dispatch + main pushes) upload a `ui-screenshots` artifact reviewable from a browser — includes the onboarding timeline, welcome flow, template-detail open, and swipe-release regression contracts.

**Targets:**
- **PlusPlus** — iOS app (iOS 26.0; App Group, Live Activities)
- **PlusPlusWatch** — watchOS companion (WatchConnectivity; depends on PlusPlusKit)
- **PlusPlusWidgets** — widget extension: Live Activity + Today/Streak widgets + App Intents
- **PlusPlusKit** — pure SwiftPM package, Linux-tested (the platform contract)
- **PlusPlusTests / PlusPlusUITests** — ~105 app unit tests + 8 UI smoke flows; 182 Kit + 26 CLI tests run on Linux (counts verified 2026-07-10)

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
- #1 interactive Mac validation (the checklist above) — #31 store migration FIRST
- Open batch: #155 1.0 store-migration policy, #157 Live Activity controls, #158 platform batch 2, #160/#161 contribution/CI-trigger widening, #162 diff share cards, #163 README streak recipe, #164 accessibility completion, #165 Foundation Models importer, #168 full-swipe-to-commit, #169 scroll dead-zone (needs device repro), #295 Health metrics batch 2 (waits on a trends-surface design pass)
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
