---
paths: ["App/**", "Packages/Sources/DesignSystem/**"]
---

# SwiftUI and design system

Leaf views take plain values and closures so they preview and snapshot without a store.

- No raw colors, spacing, font sizes, or corner radii at call sites. Use `Color.pp(.token)`,
  `Font.pp*` or a `.pp*Font()` modifier, `Spacing`, and `Radius` from `DesignSystem`. If a
  token is missing, add a `ColorToken` case and its colorset. Green (`accent`) is what's
  active, and a value that went up. Purple (`done`) is done: a finished exercise's node and the
  bars of the sets logged; a set still to do is `toDo`, a filled gray. A resting row shows its
  bars only once started and until finished, at its detail line's trailing end.
  Blue (`railJoin`) marks something arriving: a row joining a rail, a superset a node's drag
  just made, and a generated name typing into the title, for the moment it arrives, then gives way to the thing's own color; nothing
  rests in it. Whatever the rail draws (line, nodes, loops, in any color) keeps at least 3:1 on
  `background` and on `well`, where a held superset shows.
- Numbers on a row's detail line and in a sheet's values are SF Mono, set with
  `AttributedString.monoNumbers(_:font:)`; the words around them stay in the system font.
- Every font token scales with Dynamic Type: built on a `Font.TextStyle`, or sized with
  `@ScaledMetric(relativeTo:)` when the design sits between two styles. Never a fixed size.
- Let the system wrap text and measure what it laid out (a hidden copy, or the view's own
  layout); never work wraps or line counts out from character widths, which emoji, CJK, and
  glyphs SF Mono lacks break.
- Text input is SwiftUI's `TextField`. The title's field is the one UIKit text view
  (`TitleTextView`), for what `TextField` doesn't expose: sizing from its own layout, refusing
  Return before a newline lands, and placing the `_` from its line fragments.
- Prefer stock components for navigation, toolbars, and sheets; the system applies Liquid Glass
  there. Do not set `UIDesignRequiresCompatibility`.
- Anything that shows and hides beside or above other content (a tag, a line, a control) keeps
  its room laid out and fades, so nothing near it moves or rewraps as it comes and goes. Before
  a round goes to the phone, step through each state change it adds and look at what moves.
- Every tappable element that is not a `Button` gets `.accessibilityAddTraits(.isButton)`;
  icon-only controls get `.accessibilityLabel`; decorative images get
  `.accessibilityHidden(true)`, but a view already `.hidden()` gets nothing more: the modifier
  gives the empty view an unlabeled element of its own.
- Motion is snappy: every animation names its curve, `.snappy` unless the code it joins names
  another, never a bare `withAnimation` or the default spring, and quicker than `.snappy`'s
  default where it answers a tap: rows going onto and off a rail use `.railChange`, and a key
  comes back from a press with `keyPressAnimation(isPressed:)`. A motion that has to land and
  stop eases out on a timing curve, not a spring, whose settling tail reads slow and heavy.
- With Reduce Motion, replace or drop the motion (usually with a crossfade), never the haptics:
  gate animations and transitions on `accessibilityReduceMotion`, not `sensoryFeedback`.
- Every new component gets a `#Preview` and goes through `assertThemedSnapshots`.

## Where each feature is described

How each part of the screen looks, moves, sounds, and reads to VoiceOver is in the doc comments
of the types that draw it, with its timings in named constants. Read them before changing a
feature, and change them with it.

- Start, End, and the current exercise: `RoutineScreen+Workout.swift`, `CurrentExercise.swift`,
  `RowLabel.swift` (`RowFocus`), `GrowingName`, `RailStack`, `RailEntry` (a row joining a rail).
- The key at the bottom and the +1: `RoutineScreen+Key.swift`, `PrimaryKeyButtonStyle.swift`,
  `PlusOneBurst`.
- Logging a set and moving on to the next exercise: `RoutineScreen+Logging.swift`, `SetMotion`,
  `RailPulse`, `SetBeat` in `RailRow.swift`.
- Dragging a row, and supersets: `RailDrag`, `RailLiftGesture`, `RailAutoscroll`, `LoopPen`
  (`LoopHeads.swift`), `RailPairing`, `RailWell.swift`, `RailRegroup`, `RailStrokes.swift`.
- The ++ drawer and the Routines screen: `SideDrawer`, `DrawerSwipe`, `DrawerMenu`,
  `DrawerButtonStyle`, `NameRow`.
- The title and a generated name typing in: `TitleTextView`, `EditableTitle+Typing.swift`,
  `SuggestionTiming`. The exercise sheet: `ValueRow`, `ExerciseSheet.swift`.

## Pitfalls

Each of these cost a round on this app; the code at the named spot works around it.

- An animated `scrollTo` in the same transaction as a layout change holds the change back until
  the scroll has nearly landed. Scroll at once and draw the content lifted by an `Animatable`
  offset that runs to 0 (`GrowthLift`).
- An offset or stroke that has to move with animating rows is an `Animatable` modifier or
  `Shape` worked out from the rows' layout, on the same transaction. A plain `.offset` runs
  ahead of the rows, and a stroke drawn from an animating row's measured size jumps to its end
  (`GrowthLift`, `KeyDrop`, `RailDrawing`).
- Stack views whose heights animate in a custom `Layout` (`RailStack`), not a `VStack`, which
  places the views below from stale heights and then jumps.
- Time the next beat from the animation's start with `Task.sleep(for:tolerance: .zero)`, not from
  `withAnimation`'s completion, which fires a few frames after the motion stops.
- A `keyframeAnimator` whose initial value follows its trigger runs from the new value to the
  new value, and the view snaps. Animate a state that flips with its trigger with
  `.animation(_:body:)` on the view that draws it. A keyframe timeline ending on a
  `MoveKeyframe` rests on the value before it.
- Words that stay the same across states stay in one `Text` whose string changes; a view-builder
  branch per state crossfades even identical words. A view that replaces another gets its own
  `.id`, or a view put back mid-transition revives the one going.
- In a view that crossfades by identity, read state into locals before the content closure;
  read through `self`, the outgoing copy redraws with the new state.
- Pass an optional view as a value (`x.map { … }`), never through an `if let` in a
  `@ViewBuilder`, which builds a view that is never nil.
- Never add or remove a toolbar item to show or hide it: keep the item and fade its content.
  The bar draws its edge effect only while the title item shows something.
- Controls in a navigation bar or `safeAreaBar` are hosted apart from the screen and ignore
  `accessibilityHidden`: behind the drawer each applies `.hiddenBehindDrawer()`, and a faded bar
  item hides from VoiceOver with an empty `accessibilityRepresentation`.
- Attach a `confirmationDialog` to the whole screen, outside the `NavigationStack`; on a button
  or the stack's content, iOS shows it as a popover with an arrow.
- `ViewThatFits` on the routine screen hung the app as the title took focus; use a small
  `Layout` (`FigureLayout`).
- A hold on a row in a scroll view is a UIKit long press (`RailLiftGesture`) outside the row's
  SwiftUI tap and swipe actions: SwiftUI's long press stops the scroll view scrolling, and
  inside a SwiftUI tap the UIKit one never begins.
- An edge swipe is a plain pan that checks where the touch came down (`DrawerSwipe`):
  `UIScreenEdgePanGestureRecognizer` never begins on the simulator's synthesized touches.
- `SensoryFeedback.alignment` plays nothing on iPhone; a tick is
  `.impact(flexibility: .rigid, intensity: 0.6)`.
