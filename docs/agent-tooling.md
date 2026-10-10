# Agent tooling

How Claude Code (and Xcode's own agent, which reads the same `AGENTS.md`) is wired into this
repo. Everything here is committed and shared; per-developer overrides go in
`.claude/settings.local.json`, which is gitignored.

## Scripts and skills

`scripts/` is the single source of truth for building, testing, linting, and running. The
project skills in `.claude/skills/` wrap them with the judgment an agent needs (what to check in
a screenshot, when `fast` is enough). Xcode Cloud runs `scripts/lint.sh` too, so the agent, a
human, and CI cannot disagree about what "clean" means.

## Hooks

One `PostToolUse` hook, `.claude/hooks/on-edit.sh`, runs `scripts/lint.sh --fix` on every file
an agent edits and returns remaining findings to the agent. Because it is the same script CI
runs, nothing the hook accepts can fail later.

A second `PostToolUse` hook, `.claude/hooks/refresh-sim.sh`, runs in the background and keeps
the simulator's app matching the main checkout, leaving edits that hot reload can apply to the
app (its header says which). In a linked worktree it does nothing, so an agent never installs on
the maintainer's simulator. At `Stop` and `SubagentStop` it runs again with `--report`,
asynchronously, and wakes the agent when the app no longer builds or crashed since the last
turn, once per crash. The `/pr` skill and CI are still the gates.

A `SessionStart` hook runs `scripts/tidy.sh` in the background from the main checkout, logging
to `.build/tidy.log`. It removes worktrees and local branches whose work has landed: their tip is
in `main` or in a merged PR. Merges are squashed, so git alone can't tell a branch is done.
Agents' worktrees with commits outlive the agent, and nothing else removes them.

## Rules

`.claude/rules/*.md` carry the detail that would bloat `CLAUDE.md`. Each has a `paths:` list and
loads only when a matching file is read: Swift conventions, SwiftUI and the design system,
SwiftData and CloudKit constraints, testing.

## MCP servers (`.mcp.json`)

- **sosumi** (`https://sosumi.ai/mcp`): Apple documentation, HIG, and WWDC transcripts as
  Markdown. Works with Xcode closed. Apple's own docs site renders client-side and returns
  nothing to a plain fetch, which is why this exists.
- **xcode** (`xcrun mcpbridge`): Apple's MCP server. Live diagnostics, symbol lookup, build
  settings, and SwiftUI preview rendering without booting a simulator. On Xcode 27 it runs
  headless: with Xcode ▸ Settings ▸ Intelligence ▸ "Allow external agents to use Xcode tools"
  set to Always, a background Xcode Service answers with Xcode closed. A new agent session is
  not approved until it calls XcodeOpenWorkspace on `PlusPlus.xcodeproj`, which may ask the
  maintainer to approve it; pass the returned workspace identifier to the other tools.

Not configured: [XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP). It was assessed
and rejected: it duplicates the scripts for the agent only, needs Node, and costs about sixty
tools of context. The tap-and-describe layer is [AXe](https://github.com/cameroncooke/AXe),
installed by hand on the maintainer's Mac; it is not in the `Brewfile`, so `brew bundle` does
not get it, and `/run` records what it is good for and where it is unreliable.

## Plugins

`swift-lsp` from the official marketplace is enabled in `.claude/settings.json`. SourceKit-LSP
indexes the Swift packages with no configuration, giving go-to-definition, references, and
diagnostics. It does not understand the `.xcodeproj`, which is fine because nearly all code
lives in packages.

## Routines

The retro (`.claude/skills/retro/SKILL.md`) runs in Anthropic's cloud, not on a developer
machine: a routine at https://claude.ai/code/routines clones `main` at 10:00 UTC each day,
exits at once unless a merge is waiting for its retro, and opens at most one PR covering every
merge since the last one. It never merges. The routine's prompt only picks the merges and
hands them to the skill, so changing the retro means changing the skill, not the routine.

## Parallel work

`claude --worktree <name>` gives an agent its own checkout under `.claude/worktrees/`.
DerivedData is already isolated per worktree because `scripts/common.sh` keys it to the
checkout. Two or three concurrent iOS worktrees is the practical ceiling on one machine; create
a dedicated simulator per worktree with `xcrun simctl create` and set `PLUSPLUS_SIMULATOR`.

The feature subagents in `.claude/agents/` share one such simulator, "PlusPlus Team", and run
one at a time, because each phase needs the last one's files. Agent teams, Claude Code's
experimental parallel mode, stay off; the lead proposes one only for work that is genuinely
parallel: a review through several lenses, debugging with competing hypotheses, or slices that
touch disjoint files.

## Permissions

`.claude/settings.json` pre-approves the scripts, read-only `xcodebuild`, `git`, `gh`, and `asc`
commands (plus `asc xcode-cloud run`; see `docs/ci.md`), and `simctl`, with `simctl erase`,
uploads and notarization, and force pushes denied. The scripts are the gate for building,
testing, and linting, so raw `xcodebuild build`, `swiftlint`, and friends prompt.
