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
- **Plugin — `axiom@axiom-marketplace`** (Apple-platform skills + auditor agents; marketplace `CharlesWiltgen/Axiom`, declared in `.claude/settings.json`). **Reach for it whenever a task falls in its wheelhouse** — before hand-rolling an audit or re-deriving Apple guidance, use the matching skill/agent. Its catalog is not listed here on purpose: the session's own agent/skill listing names every one with its description, and a second copy here would only go stale. ⚠️ What that listing can NOT tell you: its knowledge skills and its reasoning/auditor agents (pure static Glob/Grep/Read) DO run in remote Linux sessions, while the Xcode/Simulator-backed tooling (`xcui`/`xclog`/`xcsym`/`xcprof`, build/run/screenshot/simulator, `/axiom:*` device commands) is inert remotely; an ephemeral remote container does NOT auto-install it from `enabledPlugins`, so the `SessionStart` hook `.claude/hooks/ensure-axiom.sh` installs it each session; and its keyword-triggered hook matches are advisory. See docs/DECISIONS.md 2026-07-13 (Axiom).
- **Docs stay true by construction where possible**: PLATFORM.md's JSON examples are executable (`DocsConformanceTests`, Linux CI). Otherwise: a PR that changes an interface touches the doc that describes it, or says why not.

---

## Architecture Principles

- Effective complexity management above all else — code should be easy to understand and easy to adapt
- Deep modules over shallow ones: hide significant complexity behind simple interfaces
- No premature abstraction — only abstract when duplication is real and present
- iOS-native first: start with what SwiftUI provides, customize deliberately

---

## Current State

> **Standing facts every session needs, plus what is in flight right now.**
> One item per line — load-bearing, not cosmetic: git merges line by line, so a section
> written as one growing paragraph makes every concurrent branch conflict. Never grow a
> line; add one.
> Everything else has a home, and putting it there is the rule, not a courtesy:
> what shipped and awaits validation → **docs/DEVICE-PASS.md**; why a thing is shaped the
> way it is → **docs/DECISIONS.md** (dated entry, same PR); a law that binds when you touch
> certain files → **.claude/rules/** (`paths:` frontmatter); a procedure → **.claude/skills/**.
> The test for living here: would a session need it BEFORE knowing what it was about to touch?

**Last updated:** 2026-08-06 · **Latest TestFlight build:** 194, from `claude/scope-segmented-control-3d` (the scope control FLAT, #557 — 193 was the same control RAISED, from the same branch, and Dave killed the 3D between the two). Both were dispatched from the BRANCH before merge, deliberately: the device pass is what decides this shape, and it decided twice in one day. ⚠️ 194 gets NO What's-New entry — 193's still describes it truthfully (tapping instead of spinning) and "it is flatter now" is mechanism the reader cannot act on. 192 was the wheel geometry fixups (#555) from main; 191 the three-tab bar + scope wheel (#554). ⚠️ 170–190 were dispatched from feature branches by parallel sessions, NOT main — the 169 line here was 21 builds stale when caught, which is why 193 is written here in its own PR rather than after the fact.
⚠️ Build number = workflow RUN number, not last-build+1 — check `actions_list` before writing a What's-New entry. It moves on a PARALLEL SESSION's dispatch from any branch, so a number read an hour ago is already stale (2026-08-02: 165–168 landed from a feature branch mid-round).

**On main, awaiting Dave's device pass:** the queue lives in
**docs/DEVICE-PASS.md** (18 items) — one line each, newest first, with the
⚠️ rider that says what to poke. It left this file on 2026-08-01: it is read
by a different person at a different moment (Dave, at device-pass time) than
the standing laws around it, and it was 8.4 KB of a 25 KB budget, growing by
one line per round with no drain until a build ships. **Read it before
touching a surface it names**, and delete an item once it has been passed.

**In flight:** `claude/scope-segmented-control-3d` — the scope wheel replaced by `ScopeSegmentedControl`, an app-DRAWN segmented control in the principal row (Dave, 2026-08-06; docs/DECISIONS.md same date). ⚠️ It shipped RAISED in build 193 and Dave flattened it the same day: both law deviations it carried (a raised cap on a non-committing control, elevation carrying the selection ground) are RETIRED, and design-grammar binds unamended again. The lesson worth keeping is why — it read as a key INSIDE A BOX beside two keys that weren't, so matching a raised neighbour never required being raised.
**Previously in flight:** nothing. The decision-sheet rounds (#503–#509) all landed on main 2026-08-01/02; the ONE build Dave asked for follows them (see the build line above). `LiveWorkoutSettings` (phone's own `HKWorkoutSession`) remains off by default.

**Org + license:** both repos live in the **plusplusinc** org, PUBLIC. App/repo **AGPL-3.0**; **PlusPlusKit + PlusPlusCLI are MIT** (the contract is meant for adoption). Actions minutes are free on public repos — macOS included.
**Branch protection** (repository ruleset): merges to main require `test`, `kit-test`, `cli-test` to PASS on the head SHA; squash is the only merge method. A cancelled required check blocks merge until re-run; only push-triggered runs satisfy the ruleset (a green `workflow_dispatch` run does not). Docs-only pushes still run CI deliberately. ⚠️ `kit-test`'s FIRST step is the agent-doc size budget — 25 KB on CLAUDE.md, 24 KB per `.claude/rules/*.md` file (split by path scope when it binds, don't raise it — 2026-07-31), and a ~2 KB line-length cap on CLAUDE.md, every rules file AND docs/DEVICE-PASS.md (which takes the LINE cap only — a queue's length tracks outstanding work, not hygiene; docs/DECISIONS.md is exempt from both: append-only, its long entries are the record). It rides an already-required job so the budget binds without a ruleset change, which means kit-test can go red for a docs reason before Swift ever runs. See the ci-status skill.

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

**Size is measured in BYTES and LINE LENGTH, never line count** (2026-07-28). Targets: whole file under **25 KB**, no single line over **~2 KB**. ⚠️ **When it binds, look for the section that GROWS, not the one that is biggest** (2026-08-01): the device-pass queue was 8.4 KB and gained a line every round with no drain until a build shipped, so three compression passes each bought a kilobyte the next rounds ate. Moving it to docs/DEVICE-PASS.md fixed the growth, not just the level. Compression is what you do to a section that is finished; relocation is what you do to one that isn't. ⚠️ The old rule read "keep this file under ~200 lines", and this file *passed* it at **371 KB in 157 lines** — 310 KB of that in ONE line, because every session prepended to the existing line instead of adding its own. Line count cannot see that; bytes can.

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
