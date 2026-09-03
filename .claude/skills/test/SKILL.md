---
name: test
description: Run tests, cheapest tier first. `fast` runs package tests on macOS in seconds; `sim` runs the full app scheme on the simulator; `all` runs both.
allowed-tools: Bash(scripts/test.sh:*), Bash(xcrun xcresulttool:*)
---

- `scripts/test.sh` or `scripts/test.sh fast`: every package test that runs on macOS. Seconds.
  Run this after any change to `WorkoutCore` or `WorkoutStore`, and before every commit.
- `scripts/test.sh sim`: the app scheme on the simulator, which includes the package test
  targets plus snapshot and UI tests. Run this before opening or updating a PR, and after any
  change to `DesignSystem` or `Features`.
- `scripts/test.sh sim Target/Suite/testName()`: one test. The identifier must be verbatim; a
  typo runs zero tests and still exits 0, so check the printed total.
- `scripts/test.sh all`: both tiers.

The simulator run writes `.build/results/test.xcresult` and prints a one-line summary plus each
failure's message. Snapshot failures attach the diff image inside the result bundle; open it with
`xcrun xcresulttool get test-results tests --path .build/results/test.xcresult` to find the
attachment, or look for `*.failed.png` next to the reference.

Add a package to `FAST_PACKAGES` in `scripts/test.sh` when it grows a test target.
