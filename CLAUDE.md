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

**Remote is the PRIMARY surface** (Dave, 2026-07-31): most development happens from the Claude iOS app, Mac sessions are rare. Treat the remote path — CI verification, `ui-screenshots` artifacts, device passes via TestFlight — as the default workflow; don't park work on "next Mac session" unless it genuinely needs the Simulator. (Deliberate: no checked-in `.mcp.json` for XcodeBuildMCP — a project-scoped entry would fail-load in every remote session; Mac sessions configure it locally.)

---

## Claude Code Setup (committed)

- **Skills** — `/ci-status` (check/diagnose/rerun CI from a sandbox that can't reach job logs), `/pr-flow` (the parallel feature-branch PR workflow), `/testflight` (shipping a build + the entitlement mechanism and its failure modes), `/voice` (the brand voice — read BEFORE writing any user-facing copy). Read the matching skill BEFORE re-deriving any of that from scratch.
- **Agents** — `swift-reviewer` (adversarial review tuned to this repo's proven bug classes; run it on any non-trivial diff before pushing, layered with the built-in `/code-review`), `copy-reviewer` (voice/copy-law audit; run it on any diff touching user-facing strings), and `doc-verifier` (claim-by-claim docs audit; fan out one per doc).
- **Subagent model economy** (Dave, 2026-07-17): when launching subagents, assess which models will do an excellent job at the task and pick the cheapest of those — don't throw the top-tier model at tasks a lower model can do. Explorations and mechanical sweeps → Sonnet or Haiku; design and adversarial-review passes where quality genuinely diverges → the top tier; repo agents keep their frontmatter-pinned models.
- **Rules** (`.claude/rules/`) — path-scoped patterns: `swiftdata.md`, `testing.md`, `ui-interaction.md`, `app-surfaces.md` (surface map), `design-grammar.md` (color/keys/tags/motion/copy laws), `navigation.md` (tab bar/search/scroll laws). They load when you read matching files; skim them anyway before big app work.
- **Hooks** — `docs-drift` (PostToolUse): editing interchange/CLI/workflow/project.yml files injects a reminder naming the doc that owns the claim. `protect-generated` (PreToolUse): blocks Edit/Write inside generated `.xcodeproj` bundles (edit project.yml + regenerate instead).
- **Permissions** — `.claude/settings.json` carries a shared allowlist (swift test/build, read-only + branch-workflow git, read-only GitHub MCP tools) so routine verification doesn't prompt — matters most from the phone. Extend it when a safe call keeps prompting; never allowlist merges, dispatches, or force pushes.
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

**Last updated:** 2026-08-01 · **Latest TestFlight build:** 162, from main (this device-pass round; 160/161 also from main, 159 from the cardio branch).
⚠️ Build number = workflow RUN number, not last-build+1 — check `actions_list` before writing a What's-New entry.

**On main, awaiting Dave's device pass** (reasoning in docs/DECISIONS.md under the dated entry):

- Record round (#506): history carries MONTH landmarks (pinned `Section` headers — ⚠️ NOT the issue's stale sticky-`visualEffect` hint; navigation.md) and each completed set prints a faint `target:` line in FLAT ink (ALWAYS when one exists — appearing only on a miss would BE the judgment); b6 is HELD BACK, premise disproved (DECISIONS); ⚠️ device pass: month header under the pull
- Build-158 feedback — ONE indoor-bike row (the activity noun wins; the equipment keeps "Stationary Bike") and the week strip's reserved space draws the SPINE; ⚠️ dropping a seed definition never removes a row a store already has, so `mergeIndoorBikeExercises` RENAMES the old one (a rename keeps routines and logs), deleting only an unreferenced duplicate
- Quick start round (#505): sessions NAMED for their sport (Q9-A), guarded by an explicit `isQuickStart` marker + ONE shared completion pool (`WorkoutSession.completions` — review found FOUR drifted copies; rail/icon/widget/recap agree by construction now), the Δ header + net chip gate on a shared exercise (b7), the anytime entry reveals once the KIT is settled (Q25-A), and "Train freestyle" completes the schedule step as a first-class choice (Q26-A, own flag, tab icon included); Q5-B was DELIVERED by #502's panels (DECISIONS); ⚠️ fresh-install device pass
- Live logging round (#504): the metric card's big value wears `MetricStepperRow`'s outlined-input chrome (full-width, ≥52 pt — the most-tapped value read as a readout), a DONE BlockBar segment is a correction DOOR (tap presents values + explicit confirm in the block's noun, never a jump — Q8-B; law in design-grammar), `HoldRepeatKey` echoes its repeat (raised fill + data-green stroke), and a self-reported cardio duration scrub opens AT the session's own elapsed (suggestion, never a write); ⚠️ segment taps + hold echo are XCUITest-invisible — device pass
- Workout lifecycle correctness (#503): EVERY finish door routes through the recap now (the exit dialog's Finish was the one that skipped it — no diff tally, no landing, no green→purple conversion), Continue posts the landing exactly once, salvage's honest-duration anchor gained its tripwire test, and the single-effort commit key SLIDES (`SlideToFinishKey` — law in design-grammar; assistive access activates directly, XCUITest via the `--uitest-reset` tap door); ⚠️ the slide is device-pass only
- Routine detail's in-kit chip opens the PIECE (2026-08-01): its detail sheet, not the catalog (#470's sheet was stackless — dead row taps); Bodyweight tag inert; ⚠️ device pass: chip → detail sheet, cross-links push in it
- Health single-writer rule (#519; Dave's rule verbatim: a watch involved in the session writes Health; otherwise the phone) — the wrist saves its HK session whenever it LOGGED (`wristLogged`: measured this process OR journaled watch-origin logs), whatever closed the session; the phone skips BOTH its writers when `LiveMirror.watchParticipated` (own registry key, marked on `.logSet` ops only — a glance's rest ops must not stand the phone down — window-free), and the result import's registry clear is `phoneIsAuthoring`-guarded so an early wrist exit can't erase the fact before the phone's finish reads it; ⚠️ accepted edges + reasoning in docs/DECISIONS.md (latest); wrist behavior is device-pass only
- Today's rail is DATE-FIRST (dates out of cards, node centered on the date row, never a bare date row) and quick start is its ANYTIME entry — solid node + dashed-shell `AnytimeCard`, WRAPPING keys that MORPH into config panels (chrome-only `matchedGeometryEffect`), band = FACTS pinned as the timeline's first SECTION HEADER (a top `safeAreaInset` costs the large title — #521's class, proven here too; it hands off to the month landmarks), Train = Start empty / Pick a routine; ⚠️ device pass: title at rest, rack at AX sizes, morph feel, the PULL
- The facet row is PINNED as the list's ONE section header on tab roots (2026-08-01, third mount: the `safeAreaInset` desynced the large title #521, list-content scrolled away) — a header over every row pins for the whole scroll, touching neither safe area nor nav bar; ⚠️ cost: MINE/CATALOG labels stop pinning; presented/picker keep the inset; ⚠️ device pass: chips pinned AND the large title working
- Watch↔phone repair program (#515–#518, #520; per-stage entries in docs/DECISIONS.md): the assessment's verdict was "sound model, half-finished implementation" — salvage/import/journal data loss closed, one identity on the wire, the phone gains reducer discipline + pause/steps ops, the wrist RENDERS the reducer (resume, both-devices handoff, rest parity), wrist quick start; ⚠️ wrist behavior is XCUITest-invisible end to end — the whole program rides the device pass
- Design-law audit + decision sheet (#501; docs/DECISIONS.md): five law docs verified claim-by-claim, typography law added, recheck tags on OS-bug laws; Dave answered 26 decisions + 28 bulk approvals — implementation rounds tracked as #503–#509
- Design-review round on #482 — ONE facet grammar (KIND leads the exercises facets), a finished session's noun is a SNAPSHOT (`summaryWorkUnit`), the count-up clock anchors on the session's ledger (`effortAnchorSeconds` — survives pause AND process death), `isSingleEffort` is cardio-gated, count-of-one holds everywhere, picks follow renames
- Catalog expansion round — 345 exercises (+88, every audit gap), Foam Roller, 50 templates (+8), authored pattern/mechanic/laterality columns, hidden search synonyms (`CatalogSearchSynonyms`: "erg"→rower, "rdl"), and the FACET ROW RETURNS (single-select Menu chips per scope, reverses 2026-07-25 — laws rewritten in design-grammar/navigation); ⚠️ device pass pending: popover feel, synonym search feel (the filter-row/large-title clash failed and is fixed — 2026-08-01 item)
- Keyboard dismissal is a shared law now — `View.keyboardGround(clearing:)` covers routine settings + the exercise editor; the four traps (load-bearing scroll exit, thin ground catchment, sibling headers, AX-invisible) are verbatim in ui-interaction.md; ⚠️ `pushedScreenChrome`'s band still has NO ground — own round; device pass pending
- Routine detail round 2 — target tokens wear direction ink (`increaseInk` green / `decreaseInk` gentle brick — new BrandPalette pair; ⚠️ plain `accent` fails AA as caption text on light `surface`), rail rows size to CONTENT (`RailLayout.build(rowHeights:)`; heights from UIFont metrics via a PURE width read), pauses are two noun-under-number cells, muscle tags cap at 2+N, the pinned band draws a hairline shelf, rail leading 20→12, empty prev prints "—"; ⚠️ prev KEEPS its plan-stable source (Dave, told the full mechanism: "don't change the source") — don't re-litigate from the same observation; ⚠️ device pass pending — every rail gesture reads the new per-row geometry (#474)
- One effort is not a repetition: a single-effort session's commit key says "Finish workout" and ENDS it (`WorkoutSession.isSingleEffort`), and the control that DIVIDES an effort falls back to `WorkUnit.divider` (rounds) so a walk is never offered SETS; ⚠️ it keys on the SESSION (a run then core work must advance, not finish), it is CARDIO-gated (one ad-hoc bench set keeps the Add-or-Finish ask — law 9), it is live so adding an exercise takes the ending back, and the async finish RE-READS it rather than trusting log time
- Cardio prescriptions are TWO of distance/duration/pace with the third DERIVED and never stored (`CardioTargets` — a stored derived distance would silently turn "30 min at 9:00/mi" into an odometer), and swimming ships in yards at /100yd now that `PaceReference` splits the denominator off the unit; ⚠️ one triad slot always stays empty, so entering a third evicts pace-then-duration, and every target write goes through the sheets' `writeTarget`
- One modality resolves the Health type, the work-unit noun and the estimate (`SessionModality`/`WorkUnit` — a bike ride filed as strength training before), and heart rate is a logged fact per SET on every workout; ⚠️ the wrist records what it MEASURED, never its targets, and a count of one prints no kicker, no block bar and no island progress

**In flight:** the decision-sheet implementation rounds (#504–#509). ONE TestFlight build follows once they land (Dave's call, 2026-08-01) — build 159 predates the whole 2026-08-01 run, #502's Today loop included. `LiveWorkoutSettings` (phone's own `HKWorkoutSession`) remains off by default.

**Org + license:** both repos live in the **plusplusinc** org, PUBLIC. App/repo **AGPL-3.0**; **PlusPlusKit + PlusPlusCLI are MIT** (the contract is meant for adoption). Actions minutes are free on public repos — macOS included.
**Branch protection** (repository ruleset): merges to main require `test`, `kit-test`, `cli-test` to PASS on the head SHA; squash is the only merge method. A cancelled required check blocks merge until re-run; only push-triggered runs satisfy the ruleset (a green `workflow_dispatch` run does not). Docs-only pushes still run CI deliberately. ⚠️ `kit-test`'s FIRST step is the agent-doc size budget — 25 KB on CLAUDE.md, 24 KB per `.claude/rules/*.md` file (split by path scope when it binds, don't raise it — 2026-07-31), and a ~2 KB line-length cap on CLAUDE.md AND every rules file (docs/DECISIONS.md is exempt: append-only, its long entries are the record). It rides an already-required job so the budget binds without a ruleset change, which means kit-test can go red for a docs reason before Swift ever runs. See the ci-status skill.

**CI flakes + the remote validation layer:** moved to `.claude/rules/testing.md` (2026-08-01). The one-liner: re-run ui-test ONCE before suspecting code; job logs ARE API-reachable, only artifacts aren't.

**TestFlight:** `.github/workflows/testflight.yml` (manual dispatch, any ref). ⚠️ Build number = workflow RUN number — check `actions_list` BEFORE writing the What's-New entry. Mechanism, entitlements, and every failure mode: the testflight skill + docs/DECISIONS.md appendix.

**Vocabulary + voice:** templates are **routines**, performed things are **workouts** (#144); the equipment set is a **kit** (default `main`, tab labeled Kit); "gear"/"own"/"have access to" retired; no obligation words (#172); anti-shame. The FULL laws live in `.claude/skills/voice/SKILL.md` (read before ANY user-facing string) and design-grammar.md's equipment section (interchange paths frozen there); history in docs/DECISIONS.md 2026-07-11/17.

**plusplus.fit:** LIVE on Vercel (`plusplusinc/plusplus.fit`); deploy = merge to the site repo's main (the Vercel MCP file-upload path is broken remotely). Tagline: "A hackable workout tracker for incrementing yourself" — the site still carries the older "The …" wording and needs a site PR.

**Work tracking:** backlog = GitHub issues on `plusplusinc/plusplus` (auto-added to Dave's project board). Changes land via PRs, self-merged once required checks are green, `Closes #N` linking. **The expected output of any implementation session is a PR — open it without being asked** (Dave, 2026-07-11); never leave finished work sitting on a branch.

**Targets:**
- **PlusPlus** — iOS app (iOS 26.1; App Group, Live Activities)
- **PlusPlusWatch** — watchOS companion (WatchConnectivity; depends on PlusPlusKit)
- **PlusPlusWidgets** — widget extension: Live Activity + Today/Streak widgets + App Intents
- **PlusPlusKit** — pure SwiftPM package, Linux-tested (the platform contract)
- **PlusPlusTests / PlusPlusUITests** — ~150 app unit tests + 10 UI smoke flows; 616 Kit + 26 CLI tests run on Linux (counts verified 2026-08-01, watch repair round)

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

**Known TODOs:** the issue tracker is the backlog — don't mirror it here.
- Strategy backlog #116–#123 (`fable-token-maxing`); held by Dave: #93 community sharing, #94 monetization
- Dave-side: public TestFlight link, repo settings hardening, plusplus.fit stale-copy archive
- Deliberate non-features: per-workout rest only (interval blocks carry group overrides); set ranges collapse to one number

---

## Decisions Log

Lives in **docs/DECISIONS.md** — append-only, same format (**Date — Decision — Reason**). Add an entry there for every architectural or significant implementation decision, in the same PR as the change. Standing laws that every session needs regardless of task stay in this file; everything else (including the reasoning behind current shapes) is in the log — read it before re-litigating anything.

---

## Patterns Reference

Split into path-scoped rules in `.claude/rules/` (they auto-load when you touch matching files): `swiftdata.md` (container/relationship laws), `testing.md` (test isolation + red-first bug fixes, XCUITest blind spots), `ui-interaction.md` (swipe/gesture laws), `design-grammar.md` (color/keys/tags/motion/copy), `navigation.md` (tab bar/search/scroll), `app-surfaces.md` (surface map). Add new patterns to the matching rule file — or a new one — not here.

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

**Uncertain scope → plan first**: when the shape of the change isn't obvious (new surface, cross-target work, anything touching the interchange), explore and propose a plan before editing — plan mode, or a short written plan in-thread. Small clear fixes skip this.

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
