# Agent tooling

## XcodeBuildMCP

Configured in `.mcp.json`, run on demand via `npx`. It gives structured build errors, simulator
control, and UI automation, which beats parsing `xcodebuild` output. Approve the server when
Claude Code prompts on first use.

## Skills

Deliberately **not** installed for you. Skills are third-party code that runs with your agent's
context and permissions, and Paul Hudson's index is explicit that listing "is _not_ an
endorsement". Read one before you install it.

Recommended starting set, from <https://github.com/twostraws/swift-agent-skills>:

| Skill | Why |
| --- | --- |
| Swift Testing | We use `@Test`/`#expect` exclusively; most training data is XCTest. |
| Swift Concurrency | Strict concurrency is on everywhere and the failure modes are subtle. |
| SwiftUI Pro | Broad SwiftUI idiom coverage. |
| SwiftData Expert | CloudKit's schema constraints are unforgiving and easy to violate. |

## On Axiom

[Axiom](https://github.com/CharlesWiltgen/Axiom) was considered and skipped. It is 273 skills, 42
agents, and 17 commands tracking Apple's OS 27 beta — a large unvetted surface area for a project
this size, and its beta tracking is a poor fit for an app targeting shipping iOS 26.

Worth revisiting once the app is larger, particularly its diagnostic tools (`xclog`, `xcsym`,
`xcprof`), which solve problems we do not have yet.
