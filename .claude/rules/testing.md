---
paths: ["Packages/Tests/**", "PlusPlusUITests/**"]
---

# Testing

Swift Testing (`@Test`, `#expect`, `#require`) for everything except UI automation and
performance, which stay on XCTest by Apple's own guidance.

Put a test in the cheapest tier that can hold it: package tests on macOS (milliseconds, no
simulator) before anything that needs UIKit, and snapshots before XCUITest.

What each tier holds today:

- **Package tests** hold rules: `EditableTitle`'s static functions and `WorkoutStoreContainer`.
- **Snapshots** hold how a component looks at rest. They cannot show the editing state, since
  `EditableTitle`'s focus is private, or a caret the text system placed.
- **UI tests** hold only what needs the real keyboard, text system, or frames: typing, Return,
  arrows, taps, range selection, the keyboard's edge, scrolling as the keyboard rises, and
  VoiceOver frames. Each launch costs about 9 s on CI, so there is one UI test per launch
  configuration: `RenameUITests/testRenameAtDefaultSize` and
  `TitleWrappingUITests/testWrappedTitleAtLargestTextSize`. A new check extends the test for
  its launch as a named `XCTContext.runActivity`; a new test needs a launch argument no
  existing test uses. `TitleShot.swift` reads the drawn `_` and the title's lines from pixels.
  Wait with `appears()` and `disappears()` from `Waits.swift`: XCTest's own waits spend a
  second before their first check.

Before adding a test, find whether one already proves the guarantee. If one does, don't add
another.

- Tests that need UIKit are wrapped in `#if canImport(UIKit) && !os(watchOS)` so `swift test`
  on macOS compiles them out; the simulator run exercises them.
- Snapshots go through `assertThemedSnapshots(of:width:)` in `DesignSystemTests`, which owns
  the explicit width, the perceptual precision, and the light, dark, and AX5 appearances (the
  image named `xxxl` is `accessibilityExtraExtraExtraLarge`). Do
  not call `assertSnapshot` directly. Re-record by deleting the files under `__Snapshots__/`.
- The scheme's test action pins the app language to English (US). UIKit sizes the system font's
  line height to fit the fallback fonts for the device's preferred languages, and Xcode Cloud's
  simulators list 34 of them, so unpinned text lays out taller there. Keep that setting.
- Display name on the attribute, stable identifier on the function:
  `@Test("An in-memory container round-trips a model") func inMemoryRoundTrip()`. The
  formatter is configured to keep it that way (see `.swiftformat`).
- No sleeping in tests. Use clocks, confirmations, or injected schedulers.
- While working, run `scripts/test.sh` and the simulator tests the change touches
  (`scripts/test.sh sim <Target/Class>`, then check the total). The full simulator suite is
  Xcode Cloud's PR check, so don't also run it locally. After re-recording snapshots, run only
  their suite again.
- A bug fix comes with a test that failed before the fix.
