---
name: build
description: Build the app for the iPhone simulator with compact diagnostics. Use before claiming any Swift change compiles.
allowed-tools: Bash(scripts/build.sh:*), Bash(xcrun xcresulttool:*)
---

Run `scripts/build.sh` (Debug by default, `scripts/build.sh Release` for release settings).

It uses a stable derived-data path under `.build/`, so incremental builds stay warm, and pipes
through xcbeautify so output is short. On failure it prints one line per error from the result
bundle at `.build/results/build.xcresult`; line numbers are already 1-based.

Fix the first error first. Swift's later errors are frequently consequences of the first one.
Do not add `@unchecked Sendable`, force unwraps, or `nonisolated` to make a concurrency error go
away; read `.claude/rules/swift.md` and fix the isolation properly.

Never claim a change builds without having run this.
