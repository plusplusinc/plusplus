---
paths: ["Packages/Tests/**", "PlusPlusUITests/**"]
---

# Testing

Swift Testing (`@Test`, `#expect`, `#require`) for everything except UI automation and
performance, which stay on XCTest by Apple's own guidance.

Put a test in the cheapest tier that can hold it: package tests on macOS (milliseconds, no
simulator) before anything that needs UIKit, and snapshots before XCUITest.

What each tier holds today:

- **Package tests** hold rules: `EditableTitle`'s static functions, `WorkoutStoreContainer`, the
  built-in exercises with their equipment lines and search, and where a swiped row settles.
- **Snapshots** hold how a component looks, at rest and while editing. The title's editing look,
  `_` included, is drawn from plain values through `EditableTitleContent`, reached with
  `@testable import`, so no focus or keyboard is needed; its `blinks: false` holds the `_` lit,
  and its field gets a selection that ignores writes, since an unfocused field writes its own
  back. A snapshot cannot show a caret the text system placed. Rows on the rail, Start, and a
  row swiped open are snapshot through the same components the routine screen composes.
- **UI tests** hold only what needs the real keyboard, text system, or frames: typing, Return,
  arrows, taps, range selection, the keyboard's edge, scrolling as the keyboard rises, and
  VoiceOver frames; and the exercise picker, system chrome composed in the app, which has no
  test target: adding, searching, swiping to delete, and the accessibility audit at AX5. Each
  launch costs about 9 s on CI, so there is one UI test per launch configuration:
  `RenameUITests/testRenameAtDefaultSize` and
  `TitleWrappingUITests/testWrappedTitleAtLargestTextSize`. A new check extends the test for
  its launch as a named `XCTContext.runActivity`; a new test needs a launch argument no
  existing test uses. Where the caret is shows in where typing lands, so they read it from the
  field's value; one check reads the drawn `_` from pixels, for the wire from the text system's
  selection to it. `TitleShot.swift` reads the `_` and the title's lines from pixels.
  Wait with `appears()`, `disappears()`, `value(becoming:)`, and, for anything else read,
  `reading(_:becoming:within:)` from `Waits.swift`: XCTest's own waits spend a second before
  their first check. Typing, key presses, and taps can return before the app has handled them,
  so a read after one waits for the state it checks: `value(becoming:)` for the value, and
  `Ink.withCursor(_:until:)` for where the `_` is.

Before adding a test, find whether one already proves the guarantee. If one does, don't add
another.

- Tests that need UIKit are wrapped in `#if canImport(UIKit) && !os(watchOS)` so `swift test`
  on macOS compiles them out; the simulator run exercises them.
- Snapshots go through `assertThemedSnapshots(of:width:)` in `DesignSystemTests`, which owns
  the explicit width, the precision, and the light, dark, and AX5 appearances (the image named
  `xxxl` is `accessibilityExtraExtraExtraLarge`). Every pixel must match within perceptual
  0.98: a looser pixel share lets a `_` move a cell or vanish unseen. Do not call `assertSnapshot`
  directly. Re-record by deleting a suite's files, or its whole folder, under `__Snapshots__/`.
- The scheme's test plan, `PlusPlus.xctestplan`, holds two settings to keep, and it is the only
  place Xcode Cloud reads them from. It pins the app language to English (US): UIKit sizes the
  system font's line height to fit the fallback fonts for the device's preferred languages, and
  Xcode Cloud's simulators list 34 of them, so unpinned text lays out taller there. Its
  `diagnosticCollectionPolicy` is `Never`: otherwise every failing run ends with `simctl
  diagnose`, which waits out its whole 600 s timeout on a simulator.
- Display name on the attribute, stable identifier on the function:
  `@Test("An in-memory container round-trips a model") func inMemoryRoundTrip()`. The
  formatter is configured to keep it that way (see `.swiftformat`).
- No sleeping in tests. Use clocks, confirmations, or injected schedulers.
- While working, run `scripts/test.sh` and the simulator tests the change touches
  (`scripts/test.sh sim <Target/Class>`). The full simulator suite is Xcode Cloud's PR check,
  so don't also run it locally. After re-recording snapshots, run only their suite again.
- A bug fix comes with a test that failed before the fix.
