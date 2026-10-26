---
paths: ["Packages/Tests/**", "PlusPlusUITests/**"]
---

# Testing

Every test runs in the check that blocks a merge. A test that isn't worth blocking a merge is
not worth keeping, so no tier or suite runs as a report only; speed comes from cutting and
fixing tests, never from moving them out of the check.

Swift Testing (`@Test`, `#expect`, `#require`) for everything except UI automation and
performance, which stay on XCTest by Apple's own guidance.

Put a test in the cheapest tier that can hold it, and judge every test, new or old, by the
rubric below. Each tier's time is printed against its budget on every run.

## The rubric

A test earns its place when it passes A to F; a UI check also names what only the running app
shows (G), and is weighed by H and I, since it costs the most.

- **A. Unique**: it fails for a break no other test catches. One that duplicates a lower test
  goes. ([Fowler](https://martinfowler.com/articles/practical-test-pyramid.html); Khorikov,
  *Unit Testing Principles, Practices, and Patterns*, ch. 4)
- **B. Cheapest tier**: as low as it can sit and still catch that break.
  ([Fowler](https://martinfowler.com/bliki/TestPyramid.html);
  [Software Engineering at Google, ch. 11](https://abseil.io/resources/swe-book/html/ch11.html);
  [Apple](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project))
- **C. Fast**: seconds only where real time is what's tested; state set by launch argument,
  not by steps. ([Beck](https://testdesiderata.com/);
  [WWDC20 10091](https://developer.apple.com/videos/play/wwdc2020/10091/))
- **D. Deterministic**: same code, same result, in any order; no sleeps, no retries.
  ([Fowler](https://martinfowler.com/articles/nonDeterminism.html);
  [WWDC22 110361](https://developer.apple.com/videos/play/wwdc2022/110361/))
- **E. Behavioral**: it fails when behavior changes, not when code moves.
  ([Beck](https://testdesiderata.com/); [Google Testing Blog](https://testing.googleblog.com/2013/08/testing-on-toilet-test-behavior-not.html))
- **F. Specific**: its name says the guarantee, and a failure names its cause.
  ([WWDC20 10091](https://developer.apple.com/videos/play/wwdc2020/10091/);
  [Dodds](https://kentcdodds.com/blog/effective-snapshot-testing))
- **G. Predictive**: what passes would hold on the device. The only reason to pay for a UI
  test. ([Dodds](https://kentcdodds.com/blog/the-testing-trophy-and-testing-classifications))
- **H. Likely to come back**: the break is likely to return, because the code it guards is
  still changing, or the code it runs through is shared and changes for other features. High:
  among the most-changed files on `main` lately, or a queued card changes the code around it.
  Low: a one-off bug fixed at its cause and pinned by a cheaper test, or one that never reached
  `main`. A check whose feature a queued card replaces dies with it.
  ([Google Testing Blog](https://testing.googleblog.com/2020/08/code-coverage-best-practices.html):
  testing should be "a function of … how often you will need to touch/change the code";
  [Marick, *When Should a Test Be Automated?*](http://www.exampler.com/testing-com/writings/automate.pdf):
  "Automated tests produce their value after the code changes"; Beck, "How deep are your unit
  tests?": "If I don't typically make a kind of mistake … I don't test for it"; Bach,
  *Heuristic Risk-Based Testing*; Nagappan and Ball, *Use of Relative Code Churn Measures to
  Predict System Defect Density*)
- **I. Noticed in use**: the maintainer would see the break by using the app within a day, on
  a path he uses daily, and it costs only a redo. He uses it in dark, at the default text size,
  without VoiceOver, and tries every slice before it merges; nothing at AX5, nothing VoiceOver
  reads, and nothing that loses work is noticed in use.
  ([Software Engineering at Google, ch. 14](https://abseil.io/resources/swe-book/html/ch14.html):
  dogfooding finds "unanticipated behaviors", but "manual regression testing does not scale
  sublinearly"; Marick's cost of a check by hand, and John Daly's "What bugs aren't I finding
  while I'm doing that?"; `docs/principles.md`, "Reliability before novelty")

A UI check that isn't noticed in use stays, unless another test holds it (A). One that is
noticed in use stays only if it is likely to come back and a break would block other work or
lose data, or if it costs under about 2 s.

## Where each guarantee goes

Cheapest first. The tests' display names are the inventory of what each tier holds.

| Guarantee | Tier |
|---|---|
| A rule or arithmetic: the store, the launch rule, names, plans, moves, supersets, a drag's, drawer's, or pairing's math, a workout's time | Package (`WorkoutStoreTests`, `DesignSystemTests` logic): macOS and the simulator, milliseconds |
| What a saved store reopens as, and a schema upgrade on disk | Package, over an in-memory container (a second store on it is a relaunch) or a file |
| How a component looks at a moment, in dark: at rest, editing, mid-drag, at AX5 | Snapshot, through `assertThemedSnapshots` |
| What layout does over time: a live text size change, every layout pass, focus, the frame clock | Hosted view, in a `UIWindow.sceneless` |
| What only the running app shows: the real keyboard and text system, gesture arbitration with the scroll view, system chrome composed in the app (sheets, search, swipe actions, bars, dialogs), VoiceOver frames, the accessibility audit at AX5, and what a relaunch brings back | UI test |

- **A UI check proves the wire, once per gesture.** Where a gesture's variants differ only in
  arithmetic the package holds (where a row lands, which neighbor pairs, a span's ends), one
  UI check shows the gesture reaches that arithmetic, and the package holds the variants.
- **One relaunch checks every saved field at once**; the package holds each field's round
  trip. A relaunch costs 5 to 7 s on CI.
- **Rows come from `-seedExercises`**, not adds through the picker, unless the add is what's
  checked.
- **Screenshots in UI tests are kept only on failure** (`attach(named:)`).
- **Hosted and snapshot tests are main-actor work**, and `DesignSystemTests` runs them one at
  a time (the test plan's `parallelizable: false`), so each one's own time is read, and a slow
  one is named.

## Budgets

Reported on every run, never failed on: `scripts/test.sh` prints the package's, `scripts/test.sh
sim` each target's and each UI test's, and `scripts/ci-times.py <branch>` an Xcode Cloud run's.
They are defined once, in `scripts/xcresult.py`. Local is CI divided by 1.25, the ratio with
one test at a time on both, except a UI test's while `PlusPlusUITests` runs in parallel: five
clones of the simulator share the Mac, so each test runs 1.04 to 1.09 times as long as on CI
serially, and its local budget is 90 s divided by the lowest, 1.04, so a test reads over only
when it grew.

| Tier | Xcode Cloud | Local |
|---|---|---|
| Package on macOS, both runs' test time | | 10 s |
| `WorkoutStoreTests` | 10 s | 8 s |
| `DesignSystemTests` | 30 s | 24 s |
| a `DesignSystemTests` test | 2 s | 1.6 s |
| each UI test | 90 s | 72 s, 86.5 s in parallel |
| the UI tests together, wall time | 360 s | 288 s |
| a PR run, start to finish | 11 min, aiming at 4 | |

A target's budget holds its wall time. A serial target's is its tests' sum, and a parallel
Swift Testing target's its longest test's, since each is timed from their common start. A UI
target in parallel prints both: its wall time, from its first test's start to its last one's
end (the first clone's boot comes before it), and its tests' sum, their cost. Each UI test's
own time is its cost either way. App Store Connect gives no start times, so `ci-times.py`
prints that target's sum with no verdict, and the run's start to finish holds it.

A test over its budget is fixed at its cause (setup through the UI, a fixed wait, a launch, a
held main actor), or named with its time in the report that adds it. The first test of a
filtered run carries the process's warm-up, so it can read over on its own.

## Snapshots and hosted views

A snapshot draws `EditableTitleContent` from plain values, reached with `@testable import`:
`blinks: false` holds the `_` lit, a nil focus binding leaves it unfocused, and a forced
`selection` (an `NSRange`) puts the caret. A snapshot cannot show a caret the text system
placed, nor a height kept from the text size before, which is why those are hosted views. A
moment of motion is drawn through an internal initializer, as a held row is through `Rail`'s
and the drawer through `SideDrawer`'s `progress:`; a suggestion's arrival comes from
`typingFrame(of:at:)`'s values.

## UI tests

There is one UI test per launch configuration, each a series of named
`XCTContext.runActivity` checks: `RenameUITests/testRenameAtDefaultSize`,
`RowDragUITests/testDragAndDeleteRows` (the rows seeded),
`TitleWrappingUITests/testWrappedTitleAtLargestTextSize`,
`RoutineAutosaveUITests/testRoutineSurvivesRelaunch`, and
`WorkoutUITests/testWorkoutSurvivesRelaunch`. A new check joins the test for its launch only
when it names what only the running app shows (G) and the lower test that holds the rest, sets
its state up by launch argument, and keeps its test within the UI budget; otherwise it goes in
a cheaper tier. Every test launches with `-resetStore YES`, so it starts from a new routine and
not the one the last test saved, and with `-noUIKitAnimations YES`; the relaunch tests add
`-fallbackNames YES`, muscle-group names, which a test can predict where the standard names
follow the routine's fresh id; and `-seedExercises <id,id,…>` with `-seedName <name>` starts
from a routine of those built-in exercises (all `LaunchOptions`, Debug only). With UIKit's
animations off, the keyboard and sheets appear at once, and XCTest's wait for animations can't
stall (`LaunchOptions.turnsOffUIKitAnimations` says why). SwiftUI's animations still run, so a
test that reads what one moves waits for its end state; an added row is in the accessibility
tree only once it has entered. Where the caret is shows in where typing lands, so they read it
from the field's value; one check reads the drawn `_` from pixels, for the wire from the text
system's selection to it. `TitleShot.swift` reads the `_`, the title's lines, and its contrast
from pixels: a name, typed or generated, reaches further from the background than the
placeholder's gray.

Wait with `appears()`, `disappears()`, `value(becoming:)`, and, for anything else read,
`reading(_:becoming:within:)` from `Waits.swift`: XCTest's own waits spend a second before
their first check. Typing, key presses, and taps can return before the app has handled them,
so a read after one waits for the state it checks: `value(becoming:)` for the value, and
`Ink.withCursor(_:until:)` for where the `_` is. Tap a stepper key with `tapAtCenter()`:
XCTest's `tap()` goes to its top-left corner, on the edge of the row above, which closes it.
Tap anything that may still be moving, such as Add exercise just after an add, once it
`settles()`: a view takes taps where it is laid out mid-move, so a tap read from a moving
frame can land on the row arriving there. Passing locally proves nothing about this; on
Xcode Cloud it failed six runs of #70.

## Every test

Before adding a test, find the closest one that already exists. If it proves the guarantee,
don't add another; if not, say why it doesn't.

- Tests that need UIKit are wrapped in `#if canImport(UIKit) && !os(watchOS)` so `swift test`
  on macOS compiles them out; the simulator run exercises them.
- Snapshots go through `assertThemedSnapshots(of:width:)` in `DesignSystemTests`, which owns
  the explicit width, the precision, and the appearances: dark, and dark at AX5 (the image
  named `xxxl` is `accessibilityExtraExtraExtraLarge`), as users see the app, which shows only
  in dark. Light renders only in `TokenSnapshotTests`, through `includingLight`, while the light
  palette exists; light screen snapshots return with the card "Choose light, dark, or automatic
  appearance". Every pixel must match within perceptual
  0.98: a looser pixel share lets a `_` move a cell or vanish unseen. Do not call `assertSnapshot`
  directly. Re-record by deleting a suite's files, or its whole folder, under `__Snapshots__/`.
- The scheme's test plan, `PlusPlus.xctestplan`, holds five settings to keep, and it is the
  only place Xcode Cloud reads them from. `DesignSystemTests` is `parallelizable: false`, as
  above. `PlusPlusUITests` is `parallelizable: true`, so Xcode hands its classes, one long
  test each, to clones of the simulator: locally the five run in about 130 s of wall time
  against about 300 s one at a time, and Xcode deletes the clones after. It pins the app language to English (US): UIKit sizes the
  system font's line height to fit the fallback fonts for the device's preferred languages, and
  Xcode Cloud's simulators list 34 of them, so unpinned text lays out taller there. Its
  `diagnosticCollectionPolicy` is `Never`: otherwise every failing run ends with `simctl
  diagnose`, which waits out its whole 600 s timeout on a simulator. Its test timeout fails a test
  after three minutes, so a hung UI test fails rather than running on; that is twice the UI
  test's budget on Xcode Cloud.
- Display name on the attribute, stable identifier on the function:
  `@Test("An in-memory container round-trips a model") func inMemoryRoundTrip()`. The
  formatter is configured to keep it that way (see `.swiftformat`).
- No sleeping in tests. Use clocks, confirmations, or injected schedulers.
- While working, run `scripts/test.sh` and the simulator tests the change touches
  (`scripts/test.sh sim <Target/Class>`). The full simulator suite runs on Xcode Cloud for every
  PR that changes the app, so don't also run it locally. After re-recording snapshots, run only their suite again.
- A bug fix comes with a test that failed before the fix.
