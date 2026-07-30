# PlusPlus (++) — Project Instructions

Read this at the start of every session. Update it when facts change — a stale CLAUDE.md is worse than none. The full architectural record lives in **docs/DECISIONS.md** (append new decisions there); directory-scoped patterns live in **.claude/rules/** and load automatically when you touch matching files.

---

## What This App Is

**PlusPlus** (`++`) is an iOS fitness tracking app with Apple Watch companion functionality. The name references the programming increment operator; the `++` mark visually resembles a dumbbell, which is intentional branding.

---

## Tech Stack

- **Language:** Swift / SwiftUI
- **Platform targets:** iOS 26.1+ (raised from 26.0 on 2026-07-25 for `tabViewBottomAccessory(isEnabled:)`), watchOS 26+

No third-party dependencies without discussion first.

---

## Tooling

**XcodeBuildMCP** (Mac sessions) is the primary interface for all Xcode operations — build, test, Simulator control, log capture, screenshots, UI automation, debugging. Don't fall back to raw `xcodebuild` when an MCP tool exists. Validation means build → launch → drive the changed flow via UI automation → screenshot; capture runtime logs before guessing at any unexpected behavior.

**Remote (Linux) sessions** have no Xcode/Simulator — CI verifies app targets (see the ci-status skill). The Kit/CLI suites DO run locally: `./scripts/install-swift.sh`, add `$HOME/.swift/usr/bin` to PATH, `swift test` in `PlusPlusKit/` / `PlusPlusCLI/`.

---

## Claude Code Setup (committed)

- **Skills** — `/ci-status` (check/diagnose/rerun CI from a sandbox that can't reach job logs), `/pr-flow` (the parallel feature-branch PR workflow), `/testflight` (shipping a build + the entitlement mechanism and its failure modes), `/voice` (the brand voice — read BEFORE writing any user-facing copy). Read the matching skill BEFORE re-deriving any of that from scratch.
- **Agents** — `swift-reviewer` (adversarial review tuned to this repo's proven bug classes; run it on any non-trivial diff before pushing, layered with the built-in `/code-review`), `copy-reviewer` (voice/copy-law audit; run it on any diff touching user-facing strings), and `doc-verifier` (claim-by-claim docs audit; fan out one per doc).
- **Subagent model economy** (Dave, 2026-07-17): when launching subagents, assess which models will do an excellent job at the task and pick the cheapest of those — don't throw the top-tier model at tasks a lower model can do. Explorations and mechanical sweeps → Sonnet or Haiku; design and adversarial-review passes where quality genuinely diverges → the top tier; repo agents keep their frontmatter-pinned models.
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

> **Bounded section — one item per line, newest first, ~15 lines max.**
> One-item-per-line is load-bearing, not cosmetic: git merges line by line, so a section
> written as one growing paragraph makes every concurrent branch conflict. Keep items short
> and let them land on their own lines.
> Detail goes in **docs/DECISIONS.md** (dated entry, same PR); durable laws go in
> **.claude/rules/** (path-scoped). Delete an item once it has shipped and been validated —
> this section tracks what is live now, not what happened.

**Last updated:** 2026-07-30 · **Latest TestFlight build:** 157, from main.
⚠️ Build number = workflow RUN number, not last-build+1 — check `actions_list` before writing a What's-New entry.

**On main, awaiting Dave's device pass** (reasoning in docs/DECISIONS.md under the dated entry):

- Routine detail round 2 — target tokens wear direction ink (`increaseInk` green / `decreaseInk` gentle brick — new BrandPalette pair; ⚠️ plain `accent` fails AA as caption text on light `surface`), rail rows size to CONTENT (`RailLayout.build(rowHeights:)`; heights from UIFont metrics via a PURE width read), pauses are two noun-under-number cells, muscle tags cap at 2+N, the pinned band draws a hairline shelf, rail leading 20→12, empty prev prints "—"; ⚠️ prev KEEPS its plan-stable source (Dave, told the full mechanism: "don't change the source") — don't re-litigate from the same observation; ⚠️ device pass pending — every rail gesture reads the new per-row geometry (#474)
- Cardio push (#472–#481, one build) — a cardio effort has a HERO now (`CardioHero`: progress toward a target the device can measure RIGHT NOW → a target only the console can show you → the best live reading → elapsed counting up), an untargeted one gets a count-up clock where it had none, and quick start puts a sport one tap behind Today's play key; ⚠️ the count-up ANCHOR lives on `ActiveSessionView` and banks across pause, because pausing UNMOUNTS the timer card and in that mode the displayed elapsed IS the logged duration
- Cardio prescriptions are TWO of distance/duration/pace with the third DERIVED and never stored (`CardioTargets` — a stored derived distance would silently turn "30 min at 9:00/mi" into an odometer), and swimming ships in yards at /100yd now that `PaceReference` splits the denominator off the unit; ⚠️ one triad slot always stays empty, so entering a third evicts pace-then-duration, and every target write goes through the sheets' `writeTarget`
- One modality resolves the Health type, the work-unit noun and the estimate (`SessionModality`/`WorkUnit` — a bike ride filed as strength training before), and heart rate is a logged fact per SET on every workout; ⚠️ the wrist records what it MEASURED, never its targets, and a count of one prints no kicker, no block bar and no island progress
- Routine detail device pass (build 157) — spec-table labels are a fixed COLUMN (a greedy label pushed values to the far edge AND squeezed them), a hairline draws the header's gutter, ledger cells break at the load separator not by word wrap, rail rows are `.top`-aligned so the node lands on the name's first line, and `railNodeY` is the SCREEN's (the landing FX place against it too); ⚠️ `SheetHeader` has NO padding of its own — every tray supplies 18 (#471)
- Routine detail rebuilt — system large title (collapses natively), estimate column + spec table (schedule · **pauses** merging rest+transition · kit), rows print `target` beside `prev`; the node sits on the name's FIRST line, not the row's middle (#470)
- Entrance flash — a leading gutter mark on the row BACKGROUND, never a ring in an overlay; ⚠️ the owning surface must hold the arrival id for `RowEntranceFlash.totalDuration` or the fade is cut off (#468)
- In-sheet drill-in is a `NavigationStack`, never a stage slide; ⚠️ the HOST owns the stack, and a growing detent rides `path.count` (#466)
- Muscle groups — multi-select on an exercise; ⚠️ ordered list, `muscleGroups[0]` IS `muscleGroup`; nil means follow the catalog (#463)
- Horizontal ticker — takes every MEASURED metric; ⚠️ the law is **a measured quantity scrubs, an enumerated scale wheels** (only resistance and RPE keep the wheel). Trays agree on top row, height and elevation (#462)
- Colour audit — one selection look (tinted ground + ring + bright text, never a solid fill), kit names wear the data-tag treatment, `BrandPalette` is the single hue source, WCAG pass (#461)
- Set screen — says "prev:", prints no delta, its bar carries the state grammar, one column; the rail's swipe law is DUPE leads / DELETE trails (#460)
- Today — the pull's answer renders in the gap the pull opens; the week strip is a sticky band inside the scroll (#455, #459)
- Rest — a dial, not take-it-or-leave-it (`−15s · +15s · Skip`, no primary key on the screen); Pause works mid-rest (#457)
- Scroll — the intermittent dead scroll fixed by guarding the gesture's *claim*, not its effect (#458)

**In flight:** `claude/plusplus-cardio-workouts-whh64j` — the cardio integration branch, open as one PR into main, awaiting Dave's device pass. PR 10 of that plan (the phone originating its own `HKWorkoutSession`) is deliberately NOT started; the PR body says why.

**Org + license:** both repos live in the **plusplusinc** org, PUBLIC. App/repo **AGPL-3.0**; **PlusPlusKit + PlusPlusCLI are MIT** (the contract is meant for adoption). Actions minutes are free on public repos — macOS included.
**Branch protection** (repository ruleset): merges to main require `test`, `kit-test`, `cli-test` to PASS on the head SHA; squash is the only merge method. A cancelled required check blocks merge until re-run; only push-triggered runs satisfy the ruleset (a green `workflow_dispatch` run does not). Docs-only pushes still run CI deliberately. ⚠️ `kit-test`'s FIRST step is the agent-doc size budget — 25 KB on CLAUDE.md, and a ~2 KB line-length cap on CLAUDE.md AND every `.claude/rules/*.md` (docs/DECISIONS.md is exempt: append-only, its long entries are the record). It rides an already-required job so the budget binds without a ruleset change, which means kit-test can go red for a docs reason before Swift ever runs. See the ci-status skill.

**CI flakes:** ui-test has two known flavors — `app.launch()` wedging on a runner simulator, and exit-65 runs where the identical tree passes on re-run. Re-run once before suspecting code. (The swipe test's synthesized-drag flake, #273/#274 — the degraded-runner signature that used to need a two-re-run budget — was fixed 2026-07-15: `testSwipeRevealActionSurvivesRelease` now reveals through `revealDelete`, which waits for the action to be hittable and re-drags to absorb runner jitter, so a dropped drag no longer fails the run.) All four jobs surface failing-test names as `::error::` annotations readable via the check-runs API (remote sessions can't reach job logs on Azure).

**TestFlight:** `.github/workflows/testflight.yml` (manual dispatch, any ref) archives unsigned, re-signs bundles with a throwaway self-signed identity to embed entitlements, cloud-signs at export (Admin-role ASC API key), uploads. ⚠️ Build number = workflow RUN number, not last-build+1 — check `actions_list` for the latest run number BEFORE writing the What's-New entry. New capability = enable on the App ID in the portal + entitlements file in project.yml. Full genealogy + failure modes: docs/DECISIONS.md appendix + the testflight skill.

**Vocabulary (#144) + voice:** templates are **routines**, performed things are **workouts** — `Routine`/`RoutineExercise` vs `WorkoutSession`/`SetLog`. Never write obligation words ("due") on user-facing surfaces (#172); regressions render neutral (anti-shame). Equipment is **availability, not ownership** (2026-07-11): what gear you "have" is membership in the ACTIVE `EquipmentLibrary` (one active, device-local pointer); copy says "have", never "own" (kept only for data ownership + "My equipment" selection-possessives) and never "have access to" (retired 2026-07-17). The user-facing term for an equipment library is **"kit"**, default kit **`main`** (in-app rename landed 2026-07-17 with the equipment-catalog redesign; the **tab itself is labeled "Kit"** as of 2026-07-20; the interchange path stays `equipment-libraries`). The word **"gear" is retired from user-facing copy** (2026-07-20): use **kit** for the your-set sense and **equipment** for the single-item / catalog sense ("Equipment catalog" keeps its name). Libraries + gear config are in the interchange (`program/equipment/`, `program/equipment-libraries/` — paths frozen); the active pointer is not (device state). **The full brand voice is `.claude/skills/voice/SKILL.md`** — read it before writing ANY user-facing string. See docs/DECISIONS.md 2026-07-11 + 2026-07-17.

**plusplus.fit:** LIVE on Vercel, connected to `plusplusinc/plusplus.fit` — pushes to its main deploy production, PRs get previews. AASA serves the real Team ID; the app ships associated domains. Deploy by merging to the site repo's main (the Vercel MCP's file-upload path is broken from remote sessions). Tagline: "A hackable workout tracker for incrementing yourself" (was "The …"; softened 2026-07-17 — the marketing site still carries the old wording and needs a `plusplus.fit` PR to match).

**Work tracking:** backlog = GitHub issues on `plusplusinc/plusplus` (auto-added to Dave's project board). Changes land via PRs, self-merged once required checks are green, `Closes #N` linking. **The expected output of any implementation session is a PR — open it without being asked** (Dave, 2026-07-11); never leave finished work sitting on a branch.

**Remote validation layer:** 9 XCUITest smoke flows (`ui-test` job: dispatch + main pushes) upload a `ui-screenshots` artifact reviewable from a browser — includes the onboarding timeline, welcome flow, template-detail open, swipe-release regression contracts, and the mascot form-demo sheet.

**Targets:**
- **PlusPlus** — iOS app (iOS 26.1; App Group, Live Activities)
- **PlusPlusWatch** — watchOS companion (WatchConnectivity; depends on PlusPlusKit)
- **PlusPlusWidgets** — widget extension: Live Activity + Today/Streak widgets + App Intents
- **PlusPlusKit** — pure SwiftPM package, Linux-tested (the platform contract)
- **PlusPlusTests / PlusPlusUITests** — ~146 app unit tests + 9 UI smoke flows; 442 Kit + 26 CLI tests run on Linux (counts verified 2026-07-23, mascot scale-out round)

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

This file holds only what EVERY session needs: identity, stack, workflow, current state, standing laws. Everything else has a home — decisions in docs/DECISIONS.md, directory-scoped patterns in .claude/rules/ (use `paths:` frontmatter), procedures in .claude/skills/. If a section grows past its usefulness-per-line, move it to the right home and leave a pointer.

**Size is measured in BYTES and LINE LENGTH, never line count** (2026-07-28). Targets: whole file under **25 KB**, no single line over **~2 KB**. ⚠️ The old rule read "keep this file under ~200 lines", and this file *passed* it at **371 KB in 157 lines** — 310 KB of that in ONE line, because every session prepended to the existing line instead of adding its own. Line count cannot see that; bytes can.

⚠️ **That one line was also the merge-conflict engine, and this is the part worth remembering.** Git merges line by line. Because every PR rewrote the same line (`1 insertion, 1 deletion` on every commit for months), *any* two concurrent branches conflicted on it — always, by construction, with a 310 KB hunk and no internal structure to resolve against. **One item per line is what makes concurrent branches mergeable.** Never grow a line; add one.

- Prose belongs where it can be found later: a decision → docs/DECISIONS.md (dated, append-only, one entry per PR); a law that applies when touching certain files → .claude/rules/ with `paths:` frontmatter. Both survived the 2026-07-28 audit intact — every distinctive law then in Current State already had a home in one of them, which is why deleting the section lost nothing.
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
