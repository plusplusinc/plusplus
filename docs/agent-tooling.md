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

There is deliberately no build in a `Stop` hook. `Stop` fires after every response, so a build
there taxes "what does this function do?" with a minute of compiling. The `/pr` skill and CI
are the gates.

## Rules

`.claude/rules/*.md` carry the detail that would bloat `CLAUDE.md`. Each has a `paths:` list and
loads only when a matching file is read: Swift conventions, SwiftUI and the design system,
SwiftData and CloudKit constraints, testing.

## MCP servers (`.mcp.json`)

- **sosumi** (`https://sosumi.ai/mcp`): Apple documentation, HIG, and WWDC transcripts as
  Markdown. Works with Xcode closed. Apple's own docs site renders client-side and returns
  nothing to a plain fetch, which is why this exists.
- **xcode** (`xcrun mcpbridge`): Apple's MCP server, shipped in Xcode 26.3+. Live diagnostics,
  symbol lookup, build settings, and SwiftUI preview rendering without booting a simulator.
  One-time setup: Xcode ▸ Settings ▸ Intelligence ▸ Model Context Protocol ▸ enable "Allow
  external agents to use Xcode tools". It only serves tools while Xcode has this project open;
  with Xcode closed the server shows as failed at startup, which is harmless.

Not configured: [XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP), which adds
accessibility-tree UI automation. Add it per developer if and when the agent needs to drive the UI.

## Plugins

`swift-lsp` from the official marketplace is enabled in `.claude/settings.json`. SourceKit-LSP
indexes the Swift packages with no configuration, giving go-to-definition, references, and
diagnostics. It does not understand the `.xcodeproj`, which is fine because nearly all code
lives in packages.

## Parallel work

`claude --worktree <name>` gives an agent its own checkout under `.claude/worktrees/`.
DerivedData is already isolated per worktree because `scripts/common.sh` keys it to the
checkout. Two or three concurrent iOS worktrees is the practical ceiling on one machine; create
a dedicated simulator per worktree with `xcrun simctl create` and set `PLUSPLUS_SIMULATOR`.

## Permissions

`.claude/settings.json` pre-approves the scripts, read-only `xcodebuild`, `git`, and `gh`
commands, and `simctl`, with the destructive `simctl` subcommands, notarization, force pushes,
and local signing config denied. The scripts are the gate for building, testing, and linting,
so raw `xcodebuild build`, `swiftlint`, and friends prompt.
