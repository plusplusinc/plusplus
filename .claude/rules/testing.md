---
paths: ["Packages/Tests/**"]
---

# Testing

Swift Testing (`@Test`, `#expect`, `#require`) for everything except UI automation and
performance, which stay on XCTest by Apple's own guidance.

Put a test in the cheapest tier that can hold it: package tests on macOS (milliseconds, no
simulator) before anything that needs UIKit, and snapshots before XCUITest.

- Tests that need UIKit are wrapped in `#if canImport(UIKit) && !os(watchOS)` so `swift test`
  on macOS compiles them out; the simulator run exercises them.
- Snapshots go through `assertThemedSnapshots(of:width:)` in `DesignSystemTests`, which owns
  the explicit width, the perceptual precision, and the light, dark, and XXXL appearances. Do
  not call `assertSnapshot` directly. Re-record by deleting the files under `__Snapshots__/`.
- The scheme's test action pins the app language to English (US). UIKit sizes the system font's
  line height to fit the fallback fonts for the device's preferred languages, and Xcode Cloud's
  simulators list 34 of them, so unpinned text lays out taller there. Keep that setting.
- Display name on the attribute, stable identifier on the function:
  `@Test("An in-memory container round-trips a model") func inMemoryRoundTrip()`. The
  formatter is configured to keep it that way (see `.swiftformat`).
- No sleeping in tests. Use clocks, confirmations, or injected schedulers.
- A bug fix comes with a test that failed before the fix.
