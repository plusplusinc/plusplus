---
name: test
description: Run tests. `fast` runs the package on macOS and the scripts' own tests in seconds; `sim` runs the full app scheme on the simulator, the package tests included.
allowed-tools: Bash(scripts/test.sh:*), Bash(xcrun xcresulttool:*)
---

- `scripts/test.sh`: the package on macOS, no simulator, then the scripts' own tests (the night
  runner's gates, the CI times' parsing), which nothing else runs. Seconds. Run after any change
  to `WorkoutStore` or a script, and before every commit.
- `scripts/test.sh sim`: the app scheme on the simulator, which includes the package tests plus
  snapshot and UI tests. Xcode Cloud runs this on every PR that changes the app, so run it
  locally only to reproduce a CI failure. After a change to `DesignSystem` or the app, run the
  affected suites instead, as in the next line.
- `scripts/test.sh sim Target/Suite/testName()`: one test. The identifier must be verbatim; a
  typo matches no tests, and the run fails.

The simulator run writes `.build/results/test.xcresult` and prints a one-line summary plus each
failure's message. Every run, fast or sim, then prints its times against the budgets in
`.claude/rules/testing.md`, saying OVER BUDGET where one is over; it never fails on them. Snapshot failures attach the diff image inside the result bundle; open it with
`xcrun xcresulttool get test-results tests --path .build/results/test.xcresult` to find the
attachment, or look for `*.failed.png` next to the reference.
