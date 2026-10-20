---
paths: ["Packages/Tests/**", "PlusPlusUITests/**"]
---

# Testing

Swift Testing (`@Test`, `#expect`, `#require`) for everything except UI automation and
performance, which stay on XCTest by Apple's own guidance.

Put a test in the cheapest tier that can hold it: package tests on macOS (milliseconds, no
simulator) before anything that needs UIKit, and snapshots before XCUITest.

What each tier holds today:

- **Package tests** hold rules: `EditableTitle`'s static functions, the frames of a suggestion
  typing in included, `RowLabel`'s detail line, `WorkoutStoreContainer`, the built-in exercises
  with their equipment lines, tags, search, and plan parts, how a plan reads on its row and to
  VoiceOver, `RoutineStore`'s saving and launch rule over an in-memory container (a relaunch is
  a second store on the same container), plans included, and on disk, a store written with an
  older schema opening under the current one, and the names: the focus, the style, the honesty
  check, and every routine of up to two built-ins in every style; moving a row to a slot, its
  Move up and Move down neighbors, and the announcement; supersets: a node's drag (ends,
  middles, the card's examples, what a press picks up), moving into and out of one, delete,
  shared rounds, VoiceOver's join and leave, normalizing, saving, the order of sets
  (`setOrder`), and a rest-made pair at the larger set count; and a rail drag's arithmetic
  (`RailDrag`): the slots, a superset's two edge slots included, where the gap goes, the dead
  band, the row a node's finger reaches, the edge scroll's speed and arming, which neighbor a
  resting card pairs with, the rest's countdown, the pair's release, a member dragged just out
  of its superset not pairing, where a row's node is read only at rest, and the room above the
  rail scrolling the list and moving to the size asked; routines' recency (`routinesByRecency`,
  opened or edited, and `withOpen`), what launch reopens, a list holding the order it was drawn
  in (`held(in:)`), and the drawer's three, in the order they were last edited; and a drawer swipe's arithmetic (`DrawerDrag`).
- **Snapshots** hold how a component looks, at rest and while editing. The title's editing look,
  `_` included, is drawn from plain values through `EditableTitleContent`, reached with
  `@testable import`, so no focus or keyboard is needed; its `blinks: false` holds the `_` lit,
  a nil focus binding leaves it unfocused, and a forced `selection` (an `NSRange`) puts the
  caret. A snapshot cannot show a caret the text system placed. A suggestion's arrival is drawn
  the same way from `typingFrame(of:at:)`'s values, so a moment of it is an image: the old name
  fading, the trail shuffling in blue, the last letter easing to white. Rows on the rail and
  Start are snapshot through the same components the routine screen composes, a generated name
  resting white over its rows included; a row swiped open is the system's, so the UI test shows
  it. The exercise sheet's content, its equipment and a `ValueRow` per value, is snapshot with
  every stepper closed and with one open; the sheet and its bar are the system's. A held row is
  drawn at a moment of its drag through `Rail`'s internal initializer, its card placed relative
  to its gap and already risen: over its own gap, with the gap moved, first in the rail,
  alone, a pair's member inside and outside its edge, a plain row inside a pair's top edge in
  its well, resting over a plain row before it pairs, paired with it in a well, and paired
  first in the list with the room above the rail; in each, the line and loops keep one shade
  past the card's edges, under its shadow. Supersets are drawn the same way: at rest,
  one alone and two next to each other, and a node's drag, its field the well, held over a span
  and pressed on an end; and a member's shared rounds in its sheet. The drawer is drawn open
  through `SideDrawer`'s internal `progress:` initializer, its places composed as `DrawerMenu`
  composes them, with a routine, Routines, and an untouched new routine's own row each marked; the Routines screen's list is
  drawn from `NameRow`. Their bars are the system's. A snapshot draws each text size fresh, so the title's height after a live text size
  change is held by `EditableTitleTextSizeTests`, which hosts `EditableTitleContent` in a window
  and changes the window's content size category, the field focused and not. Hosted the same
  way, `EditableTitleCaretTests` reads the `_` at every place of the caret against CoreText's
  layout of the same text (emoji, Chinese, a wrap at a /), and `EditableTitleFocusTests` sees
  every layout pass of the view under the title as an edit ends by Return or by giving up focus.
- **UI tests** hold only what needs the real keyboard, text system, frames, or a relaunch:
  typing, Return, arrows, taps, range selection, the keyboard's edge, scrolling as the keyboard
  rises, nothing moving as an edit ends by Return or a touch outside the title, and VoiceOver
  frames; the exercise picker, system chrome composed in the app, which has
  no test target: adding, searching, swiping to delete, and the accessibility audit at AX5,
  the exercise sheet with a stepper open included; stepping a value in the sheet; dragging a row, which needs
  real touches and the scroll view: a drag, a drop in place, a release over Start, the edge
  scroll, a press that scrolls, and at AX5; a node's drag drawing, shrinking, parting, and
  merging supersets, a body's carrying a row into and out of one, a drop without a rest only
  moving, a rest pairing, a nudge and rest pairing in place, a member dragged just out and
  resting leaving unpaired, a rest-made pair taking the larger set count (and keeping it across
  a relaunch, in `RoutineAutosaveUITests`), and a join at AX5 under the audit; the drawer opened
  by ++ and the edge swipe and closed by the sliver and a swipe left, switching routines with the
  one showing marked, a new one's row included, opening counting across a relaunch, and the Routines screen's list and
  drill-in, popped by the chevron and the edge swipe, and both under the audit at AX5, read from each row's VoiceOver value; and what the app saved, seen only by
  quitting and launching again, a dragged row's place and a superset's shared rounds included. Each launch costs about 9 s on
  CI, so there is one UI test per launch configuration:
  `RenameUITests/testRenameAtDefaultSize`,
  `TitleWrappingUITests/testWrappedTitleAtLargestTextSize`, and
  `RoutineAutosaveUITests/testRoutineSurvivesRelaunch`, which relaunches eight times. A new
  check extends the test for its launch as a named `XCTContext.runActivity`; a new test needs a
  launch argument no existing test uses, or a test that would run past XCTest's three-minute
  allowance on CI (about 1.2 times its local time), which is why the drag and delete checks
  are `RenameUITests/testDragAndDeleteRows`. Every test launches with `-resetStore YES`, so it
  starts from a new routine and not the one the last test saved, and with `-noUIKitAnimations
  YES`, and the relaunch test with `-fallbackNames YES`, muscle-group names, which a test can
  predict where the standard names follow the routine's fresh id (all `LaunchOptions`, Debug
  only). With UIKit's animations off, the keyboard and sheets appear at once, and XCTest's wait
  for animations can't stall (`LaunchOptions.turnsOffUIKitAnimations` says why). SwiftUI's
  animations still run, so a test that reads what one moves waits for its end
  state; an added row is in the accessibility tree only once it has entered. Where the caret is shows in where typing lands, so they read it
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

Before adding a test, find whether one already proves the guarantee. If one does, don't add
another.

- Tests that need UIKit are wrapped in `#if canImport(UIKit) && !os(watchOS)` so `swift test`
  on macOS compiles them out; the simulator run exercises them.
- Snapshots go through `assertThemedSnapshots(of:width:)` in `DesignSystemTests`, which owns
  the explicit width, the precision, and the light, dark, and AX5 appearances (the image named
  `xxxl` is `accessibilityExtraExtraExtraLarge`). Every pixel must match within perceptual
  0.98: a looser pixel share lets a `_` move a cell or vanish unseen. Do not call `assertSnapshot`
  directly. Re-record by deleting a suite's files, or its whole folder, under `__Snapshots__/`.
- The scheme's test plan, `PlusPlus.xctestplan`, holds three settings to keep, and it is the
  only place Xcode Cloud reads them from. It pins the app language to English (US): UIKit sizes the
  system font's line height to fit the fallback fonts for the device's preferred languages, and
  Xcode Cloud's simulators list 34 of them, so unpinned text lays out taller there. Its
  `diagnosticCollectionPolicy` is `Never`: otherwise every failing run ends with `simctl
  diagnose`, which waits out its whole 600 s timeout on a simulator. Its test timeout fails a test
  after three minutes, so a hung UI test fails rather than running on; that is more than twice the
  slowest UI test's time on Xcode Cloud.
- Display name on the attribute, stable identifier on the function:
  `@Test("An in-memory container round-trips a model") func inMemoryRoundTrip()`. The
  formatter is configured to keep it that way (see `.swiftformat`).
- No sleeping in tests. Use clocks, confirmations, or injected schedulers.
- While working, run `scripts/test.sh` and the simulator tests the change touches
  (`scripts/test.sh sim <Target/Class>`). The full simulator suite is Xcode Cloud's PR check,
  so don't also run it locally. After re-recording snapshots, run only their suite again.
- A bug fix comes with a test that failed before the fix.
