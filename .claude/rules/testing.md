---
paths: ["**/Tests/**", "**/*Tests.swift", "**/*Tests/**"]
---

# Testing

Swift Testing (`@Test`, `#expect`, `#require`) for everything except UI automation and
performance, which stay on XCTest by Apple's own guidance.

Put a test in the cheapest tier that can hold it:

| Tier | Where | Cost |
| --- | --- | --- |
| Pure logic | `WorkoutCoreTests` | ~1ms, no simulator |
| Storage | `WorkoutStoreTests`, in-memory container | ~15ms, no simulator |
| Feature behavior | `FeaturesTests`, fake stores | ~1ms, no simulator |
| Rendering | snapshot tests in the owning package | simulator |
| Core flows | `PlusPlusUITests` (XCUITest) | simulator, slow |

- Tests that need UIKit are wrapped in `#if canImport(UIKit) && !os(watchOS)` so `swift test`
  on macOS compiles them out and stays fast; the simulator run exercises them.
- Snapshots: always give the view an explicit width; `.sizeThatFits` proposes zero width and
  `Text` truncates to nothing. Compare with `perceptualPrecision: 0.98`. Record light, dark, and
  accessibility XXXL. Re-record by deleting the file under `__Snapshots__/` and re-running.
- Display name on the attribute, stable identifier on the function:
  `@Test("An in-memory container round-trips a model") func inMemoryRoundTrip()`. Never
  backtick raw-identifier test names: `#function` feeds snapshot file names and `-only-testing`
  identifiers, and both become unusable when the function is a sentence.
- No sleeping in tests. Use clocks, confirmations, or injected schedulers.
- A bug fix comes with a test that failed before the fix.
- Take `-only-testing` identifiers verbatim from the result bundle or `xcodebuild
  -enumerate-tests`; a misspelled identifier silently runs zero tests and exits 0.
