---
name: test
description: Run tests. `fast` runs the package on macOS in seconds; `sim` runs the full app scheme on the simulator, a superset of fast.
allowed-tools: Bash(scripts/test.sh:*), Bash(xcrun xcresulttool:*)
---

- `scripts/test.sh`: the package on macOS, no simulator. Seconds. Run after any change to
  `WorkoutStore`, and before every commit.
- `scripts/test.sh sim`: the app scheme on the simulator, which includes the package tests plus
  snapshot and UI tests. Run before opening or updating a PR, and after any change to
  `DesignSystem` or the app.
- `scripts/test.sh sim Target/Suite/testName()`: one test. The identifier must be verbatim; a
  typo runs zero tests and still exits 0, so check the printed total.

The simulator run writes `.build/results/test.xcresult` and prints a one-line summary plus each
failure's message. Snapshot failures attach the diff image inside the result bundle; open it with
`xcrun xcresulttool get test-results tests --path .build/results/test.xcresult` to find the
attachment, or look for `*.failed.png` next to the reference.
