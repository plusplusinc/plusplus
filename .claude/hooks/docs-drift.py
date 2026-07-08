#!/usr/bin/env python3
"""PostToolUse hook: when contract-adjacent code changes, remind the
session which doc owns the claim. The hard gate is DocsConformanceTests
(PLATFORM.md examples must decode); this is the soft nudge for everything
a test can't see."""
import json
import sys

RULES = [
    ("PlusPlusKit/Sources/PlusPlusKit/Interchange/", "docs/PLATFORM.md documents this contract (its JSON examples are executable via DocsConformanceTests) — update it if fields, bounds, layout, or sync semantics changed."),
    ("PlusPlusCLI/Sources/", "docs/AGENTS.md and docs/recipes/ document the CLI surface — update them if subcommands, flags, --json shapes, or MCP tools changed."),
    (".github/workflows/", "CLAUDE.md (Current State + CI notes) and .claude/skills/ci-status describe the CI/TestFlight pipelines — keep them true."),
    ("project.yml", "CLAUDE.md's Targets section and README target list mirror project.yml — update them if targets or entitlements changed."),
]


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return
    path = (payload.get("tool_input") or {}).get("file_path") or ""
    for prefix, message in RULES:
        if prefix in path:
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PostToolUse",
                    "additionalContext": f"docs-drift: {message}",
                }
            }))
            return


if __name__ == "__main__":
    main()
