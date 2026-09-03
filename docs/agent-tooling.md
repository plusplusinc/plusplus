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

Two `PostToolUse` hooks in `.claude/settings.json` run on every file an agent edits:

- `format-swift.sh`: SwiftFormat, then SwiftLint `--fix`. Remaining violations are returned to
  the agent to fix immediately. Under a second per file.
- `check-us-english.sh`: flags British spellings using the same wordlist as CI.

There is deliberately no build in a `Stop` hook. `Stop` fires after every response, so a build
there taxes "what does this function do?" with a minute of compiling. The `/pr` skill and CI
are the gates.

## Rules

`.claude/rules/*.md` carry the detail that would bloat `CLAUDE.md`. Each has a `paths:` list and
loads only when a matching file is read: Swift conventions, SwiftUI and the design system,
SwiftData and CloudKit constraints, testing.

## Subagents

- `architecture-guardian`: read-only. Checks layering, concurrency annotations, tokens, and the
  pbxproj against the rules, with file:line evidence. Run before a PR.
- `accessibility-auditor`: fixes mechanical accessibility gaps (labels, traits, hit sizes,
  fixed fonts) and reports the judgment calls. Run after any new screen or component.

## MCP servers (`.mcp.json`)

- **sosumi** (`https://sosumi.ai/mcp`): Apple documentation, HIG, and WWDC transcripts as
  Markdown. Works with Xcode closed. Apple's own docs site renders client-side and returns
  nothing to a plain fetch, which is why this exists.
- **xcode** (`xcrun mcpbridge`): Apple's MCP server, shipped in Xcode 26.3+. Live diagnostics,
  symbol lookup, build settings, and SwiftUI preview rendering without booting a simulator.
  One-time setup: Xcode ▸ Settings ▸ Intelligence ▸ Model Context Protocol ▸ enable "Allow
  external agents to use Xcode tools". It only serves tools while Xcode has this project open;
  with Xcode closed the server shows as failed at startup, which is harmless.

Optional, not configured: [XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP) adds
accessibility-tree UI automation (`snapshot_ui`, `tap`, `type_text`) that is cheaper than
screenshot loops. Add it per developer when you want the agent driving the UI:

```sh
claude mcp add XcodeBuildMCP -s user -e XCODEBUILDMCP_SENTRY_DISABLED=true \
  -- npx -y xcodebuildmcp@latest mcp
```

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

`.claude/settings.json` pre-approves the scripts, `xcodebuild`, `swift`, most `simctl`
subcommands, and read-only `git` and `gh` commands. It denies `simctl erase` and `delete`,
`altool`, `notarytool`, force pushes, and reading `Config/Local.xcconfig` or signing material.
