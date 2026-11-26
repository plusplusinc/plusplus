---
paths: ["App/**", "Packages/Sources/DesignSystem/**"]
---

# SwiftUI and design system

Leaf views take plain values and closures so they preview and snapshot without a store.

- No raw colors, spacing, font sizes, or corner radii at call sites. Use `Color.pp(.token)`,
  `Font.pp*` or a `.pp*Font()` modifier, `Spacing`, and `Radius` from `DesignSystem`. If a
  token is missing, add a `ColorToken` case and its colorset. Green (`accent`) is what's
  active, and a value that went up: data, and the controls that make something
  (`makesSomething()`). Purple (`done`) is done: a finished exercise's node, the bars of
  the sets logged, and a timed set's key filling as it counts (`KeyFill`); a set still to do is `toDo`, a filled gray. A resting row shows its
  bars only once started and until finished, at its detail line's trailing end.
  Blue (`railJoin`) marks something arriving: a row joining a rail, a superset a node's drag
  just made, and a generated name typing into the title, for the moment it arrives, then gives way to the thing's own color; nothing
  rests in it. Whatever the rail draws keeps at least 3:1 on
  `background` and on `well`, where a held superset shows.
- Numbers on a row's detail line and in a sheet's values are SF Mono, set with
  `AttributedString.monoNumbers(_:font:)`; the words around them stay in the system font.
- Every font token scales with Dynamic Type: built on a `Font.TextStyle`, or sized with
  `@ScaledMetric(relativeTo:)` when the design sits between two styles.
- Let the system wrap text and measure what it laid out (a hidden copy, or the view's own
  layout); never work wraps or line counts out from character widths, which emoji, CJK, and
  glyphs SF Mono lacks break.
- The one UIKit text view is the title's (`TitleTextView`), for what `TextField` doesn't
  expose: sizing from its own layout, refusing Return before a newline lands, and placing the
  `_` from its line fragments.
- Prefer stock components for navigation, toolbars, and sheets; the system applies Liquid Glass
  there. Do not set `UIDesignRequiresCompatibility`.
- Anything that shows and hides beside or above other content (a tag, a line, a control) keeps
  its room laid out and fades, so nothing near it moves or rewraps as it comes and goes. Before
  a slice's "When it works" pass, step through the slice's state changes and look at what
  moves.
- Every tappable element other than a `Button` gets `.accessibilityAddTraits(.isButton)`;
  icon-only controls get `.accessibilityLabel`; decorative images get
  `.accessibilityHidden(true)`, but a view already `.hidden()` gets nothing more: the modifier
  gives the empty view an unlabeled element of its own. A decorative text, such as the finish's
  "++", gets an empty `accessibilityRepresentation`: marked `accessibilityHidden`, it stays in
  the tree that automation and `axe describe-ui` read, even at opacity 0.
- Motion is snappy: every animation names its curve, `.snappy` unless the code it joins names
  another, never a bare `withAnimation` or the default spring, and quicker than `.snappy`'s
  default where it answers a tap: rows going onto and off a rail use `.railChange`, and a key
  comes back from a press with `keyPressAnimation(isPressed:)`. A longer motion that has to stop
  dead, as End's shrink (`endBeat`) and a move's shift (`SetMotion.moving(_:)`), eases out on a
  timing curve: there `.snappy`'s settling tail read slow and heavy.
- With Reduce Motion, replace or drop the motion (usually with a crossfade), never the haptics:
  gate animations and transitions on `accessibilityReduceMotion`, not `sensoryFeedback`.
- Every new component gets a `#Preview` and goes through `assertThemedSnapshots`.

## Where each feature is described

How each part of the screen looks, moves, sounds, and reads to VoiceOver is in the doc comments
of the types that draw it, with its timings in named constants. Read them first, and change them
with the feature.

- Start, End, and the current exercise: `WorkoutScreen+LiveWorkout.swift`, `CurrentExercise.swift`,
  `RowLabel.swift` (`RowFocus`, `CaptionLine`, `ProgressLine`), `GrowingName`, `RailStack`, `RailEntry` (a row joining a rail).
  Their beats are `WorkoutPhase`'s `starting` and `ending`, on a log's `SequenceTask`; Start's scroll to the top waits on `ScrollBeat.settled(after:orWhen:)`.
- The key at the bottom: `WorkoutKey`, `WorkoutScreen+Key.swift`,
  `PrimaryKeyButtonStyle.swift`, `PrimaryKeyBar.swift`. A finish: `WorkoutScreen+Ending.swift`, `FinishBurst`. The bar swaps the key on its own as its kind changes: its stage is
  `KeyTray`, which `KeySwap` and `KeyTravel` draw, the + riding on it.
- Logging a set and moving on to the next exercise: `WorkoutScreen+Logging.swift` (`play(_:leadingTo:)`,
  the one entry that shows a stored log), `SetMotion`, `RailPulse`, `SetBeat` in `RailRow.swift`.
  Where a workout is and what a log leads to are `LiveWorkout`'s, and where the screen is in
  showing a log `WorkoutPhase`'s, both in `WorkoutStore`; its timed beats run on the screen's
  `SequenceTask` (`WorkoutScreen+Sequence.swift`).
- Rests: `WorkoutScreen+Resting.swift`, `+RestDrawn.swift`, `RestBlock`, `SetRest`, `WorkoutRest`. "Start in"
  and a timed set's count: `WorkoutScreen+Timing.swift`, `TimedSet`; keys, `CountKeys`.
- Dragging a row, and supersets: `RailDrag`, `RailLiftGesture`, `RailAutoscroll`, `LoopPen`
  (`LoopHeads.swift`), `RailPairing`, `RailWell.swift`, `RailRegroup`, `RailStrokes.swift`.
- Drawer, Workouts: `SideDrawer`, `DrawerSwipe`, `DrawerMenu`, `DrawerButtonStyle`,
  `WorkoutsScreen`, `WorkoutRow`, `LengthSheet`, `NeedsHeader`. The drawer's mark and a way through it: `drawerMarks()`, `DrawerWay`,
  `AppSession.show(_:after:throughDrawer:markWait:)`.
- Log: `LogScreen`, `LogScreen+Tabs.swift`, `LoggedWorkoutScreen`, `DayGrid`, `LogRow`,
  `CountRow`, `PillButtonStyle`, `WorkoutLog`, `LogPeriod`. Add exercise, Customize: `ExercisePicker`, `ExerciseListView`, `CustomizeScreen`,
  `ExerciseForm`, `BarSearchField`, `FilterBar`, `ChipSheet`, `FilterButtonRow`, `CreateLabel` (both lists').
- The title and a generated name typing in: `TitleTextView`, `EditableTitle+Typing.swift`,
  `SuggestionTiming`. The exercise sheet: `ValueRow`, `ValueRuler` (`RulerScale`), `TimePiece`,
  `ExerciseSheet.swift`. The current exercise's large numbers: `CurrentFigures`, sized by
  `CurrentFigure`.

## Pitfalls

Each of these cost a round; the code at the named spot works around it.

- An animated `scrollTo` in the same transaction as a layout change holds the change back until
  the scroll has nearly landed. Scroll at once and draw the content lifted by an `Animatable`
  offset that runs to 0 (`GrowthLift`).
- An offset or stroke that has to move with animating rows is an `Animatable` modifier or
  `Shape` worked out from the rows' layout, on the same transaction. A plain `.offset` runs
  ahead of the rows, and a stroke drawn from an animating row's measured size jumps to its end
  (`GrowthLift`, `RailDrawing`).
- A state set inside `withAnimation` already holds its end value; what is drawn mid-animation
  only an `Animatable` sees. To read it back, record it from a modifier that draws with it: an
  `Animatable` modifier that only passes its content through has its body skipped
  (`DrawerSlide`).
- Stack views whose heights animate in a custom `Layout` (`RailStack`), not a `VStack`, which
  places the views below from stale heights and then jumps.
- Time the next beat from the animation's start with `Task.sleep(for:tolerance: .zero)`, not from
  `withAnimation`'s completion, which fires a few frames after the motion stops. A logged set's
  beats sleep to deadlines from the sequence's start (`beat(until:)`).
- Enter a logged set's `WorkoutPhase` in the tap's own transaction, never with animations
  disabled: disabled, the last set's room went at once and the list jumped to its top
  (`play(_:leadingTo:)`).
- A value that has to change inside a motion's animated transaction is state of its own, not
  derived: derived from the phase, the close's room went to the landing and back to 0 in one
  turn, never changed inside the close's animation, and the list jumped (`closingRoomTop`). So is
  one that a disabled transaction ahead of the motion changes the phase under: derived,
  `isMakingRoom` flipped in End's disabled set-back, not in its shrink, and an End that took over
  a sequence lost its room for a frame.
- Never clear state that must hold for a motion from `withAnimation`'s completion: in about 2 of
  50 of Start's grows SwiftUI ran it 12 to 28 ms in, before the first frame. Change a count on the motion's own animation
  and read the animated value against its target (`listResizes(_:)`).
- Compare recordings frame by frame from the second run after an install: the first's ran
  0.42 s late.
- A `keyframeAnimator` whose initial value follows its trigger runs from the new value to the
  new value, and the view snaps. Animate a state that flips with its trigger with
  `.animation(_:body:)` on the view that draws it. A keyframe timeline ending on a
  `MoveKeyframe` rests on the value before it.
- Words that stay the same across states stay in one `Text` whose string changes; a view-builder
  branch per state crossfades even identical words. A view that replaces another gets its own
  `.id`, or a view put back mid-transition revives the one going.
- A view that goes away and comes back within one update is drawn back before any `onChange`
  reaction runs, and with the `@State` it had: a reaction that then changes what it draws lands
  outside the animation that brought it back, and it pops. Draw the update from state that is
  already right, as `KeyTray`'s `away` is while the screen has the key out of sight.
- A change made in a reaction can share its update with another, and run under that one's
  animation, none included: the key's turn stood it at rest at once beside Pause. A motion with
  its own pace sets it where it is drawn (`transaction(value:)`, `keySwap`).
- In a view that crossfades by identity, read state into locals before the content closure;
  read through `self`, the outgoing copy redraws with the new state.
- Pass an optional view as a value (`x.map { … }`), never through an `if let` in a
  `@ViewBuilder`, which builds a view that is never nil.
- Never add or remove a toolbar item to show or hide it: keep the item and fade its content.
  The bar draws its edge effect only while the title item shows something.
- Controls in a navigation bar or `safeAreaBar` are hosted apart from the screen and ignore
  `accessibilityHidden`: behind the drawer each applies `.hiddenBehindDrawer()`, and a faded bar
  item hides from VoiceOver with `accessibilityShown(_:)`. A bar item's elements update only
  with its host's state, so their state lives there (`BarSearchField`'s `isOpen`). A
  `TimelineView` in a navigation bar item looped layout with a count,
  stalling it: the time key ticks from a task (`WorkoutTimeKey`).
- Attach a `confirmationDialog` outside the `NavigationStack`; inside, iOS shows a popover with
  an arrow, so a pushed screen's goes on its button (`ExerciseForm`).
- A horizontal scroll view's offset set before the room around its content is laid out stays on
  the content it showed as the room arrives: the ruler's line sat half its width past the value.
  Place a value by a scroll anchor, a fraction of the content (`RulerScale.anchor(of:)`), which
  holds at any width, and set offsets only once laid out.
- A scroll view laid out while hidden (opacity 0) gets its UIKit view only when it first draws,
  which starts at an offset from an earlier layout pass, not SwiftUI's current one: the AX5
  sheet's weight ruler opened on 29 under 25 lb. Build it only while it shows
  (`ValueRuler.shown(_:)`).
- A lazy stack laid out again at a new text size puts back the scroll
  offset it had over the scroll anchor. Give it an identity per size (`.id(spacing)`).
- A scroll asked from `onScrollGeometryChange` to a content's new end can stop at the old end:
  the growth is reported before the scroll view takes it. Following only growths, the list
  rested short of its end; follow every change short of the end
  once the following has begun (`keepEndInView`, `EndFollow`).
- A sheet's `.height` detent measures inside its safe area: grow it by the content's overflow
  alone (`ExerciseSheet.fit(_:)`). A floating one gets that room, as a safe area.
- `ViewThatFits` on the workout screen hung the app as the title took focus; use a small
  `Layout` (`FigureLayout`).
- A hold on a row in a scroll view is a UIKit long press (`RailLiftGesture`) outside the row's
  SwiftUI tap and swipe actions: SwiftUI's long press stops the scroll view scrolling, and
  inside a SwiftUI tap the UIKit one never begins.
- An edge swipe is a plain pan that checks where the touch came down (`DrawerSwipe`):
  `UIScreenEdgePanGestureRecognizer` never begins on the simulator's synthesized touches.
- `SensoryFeedback.alignment` plays nothing on iPhone; a tick is
  `.impact(flexibility: .rigid, intensity: 0.6)`.
