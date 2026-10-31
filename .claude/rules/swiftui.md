---
paths: ["App/**", "Packages/Sources/DesignSystem/**"]
---

# SwiftUI and design system

Plain SwiftUI: views host presentation logic, `@Observable` stores injected through
`.environment()` host state, stateless services host side effects. No view-model class per
screen. Leaf views take plain values and closures so they preview and snapshot without a store.

- No raw colors, spacing, font sizes, or corner radii at call sites. Use `Color.pp(.token)`,
  `Font.pp*` or a `.pp*Font()` modifier, `Spacing`, and `Radius` from `DesignSystem`. If a
  token is missing, add a `ColorToken` case and its colorset. Green (`accent`) is what's
  active, and a value that went up. Purple (`done`) is done: a finished exercise's node and the
  bars of the sets logged; a set still to do is `toDo`, a filled gray. A resting row shows its
  bars only once started and until finished, at its detail line's trailing end.
  Blue (`railJoin`) marks something arriving: a row joining a rail, a superset a node's drag
  just made, and a generated name typing into the title, for the moment it arrives, then gives way to the thing's own color; nothing
  rests in it.
- Numbers on a row's detail line and in a sheet's values are SF Mono, set with
  `AttributedString.monoNumbers(_:font:)`; the words around them stay in the system font.
- Every font token scales with Dynamic Type: built on a `Font.TextStyle`, or sized with
  `@ScaledMetric(relativeTo:)` when the design sits between two styles. Never a fixed size.
- Let the system wrap text and measure what it laid out (a hidden copy, or the view's own
  layout); never work wraps or line counts out from character widths, which emoji, CJK, and
  glyphs SF Mono lacks break.
- The title's field is the one UIKit text view (`TitleTextView`, a `UITextView`), for what
  SwiftUI's `TextField` does not say: it sizes from its own layout, the same view editing and
  not, refuses Return before a newline reaches the text, and places the `_` from its line
  fragments, under the character after the caret and as wide as it. Colors, the breath, and
  the typing-in stay in SwiftUI and arrive as plain values. A touch anywhere outside it ends
  its edit as the finger comes down and still does its own thing (`onTouchDownOutsideTitle`).
  Until it has focus it takes touches whole: a tap or a long press on it starts an edit at the end of
  the name, the long press with the edit menu, as a `TextField` does; UIKit's own long press on
  a text view only moves the caret.
- Prefer stock components for navigation, toolbars, and sheets; the system applies Liquid Glass
  there. Do not set `UIDesignRequiresCompatibility`.
- Every tappable element that is not a `Button` gets `.accessibilityAddTraits(.isButton)`;
  icon-only controls get `.accessibilityLabel`; decorative images get
  `.accessibilityHidden(true)`.
- Motion is snappy: `.snappy`, never a bare `withAnimation` or the default spring, and quicker
  than its default where it answers a tap: rows going onto and off a rail use `.railChange`,
  and a key comes back from a press with `keyPressAnimation(isPressed:)`. A row added to a rail
  enters in one landing (`RailEntry`). As it is let go, the line grows down from the node above
  in the rail's gray (0.2 s) on a quartic ease-in from a running start, and the row's place
  opens with it on the same curve, pushing Add exercise down exactly as far as the line grows,
  or, past the visible area, scrolling in step so the key stays put. As the line reaches it, the
  node pops in `railJoin` from the line's tip with a small, crisp overshoot, and the name and
  equipment land with it in their own colors, a short drop that stops cleanly, with a light
  impact haptic. The node holds in blue (0.1 s) after its pop, then cools to its own color on an
  ease-out (0.3 s); the line and the text are never blue. The first row has no line: its place
  opens over the same time and curve, then it lands. With Reduce Motion the place opens at
  once, nothing is blue, there is no shot or overshoot, but the haptic stays, as the row lands.
  Nothing waits on it: the key, scrolling, swiping a row, and the title all work while it plays.
  It enters only where it can be seen: its place opens as the picker's sheet starts down, and
  the entry plays a moment into the sheet's slide, or, when the new row has pushed the list's
  end out of view, after a scroll to the end. Once Start is pressed (`isMakingRoom`), neither
  scroll runs and the row enters where it is: the end is then Start's room under the list, and
  following it took the list off the screen as Start went to land on the first exercise. The
  press also sets the scroll to where the list is: a scroll to the end leaves the position
  bound to the end, and it followed the room down.
- Start plays in beats, each once the last has finished (`RoutineScreen+Workout.swift`). Its key
  presses and releases as any key does, down onto its ledge and back up in 0.06 s each, easing
  out, as the scratch app's log-set key does. On the press's action, a medium impact plays, from
  the screen as `isStarting` turns on. A 0.4 s beat follows (`pressHold`, slept with no
  tolerance), a second press doing nothing; the workout's first frame takes a few more to draw, so
  the rows move about 0.5 s after the press; it is a `.task(id:)`, so the screen going away
  cancels it. Then, if the first exercise is mostly out of view, the list scrolls to its top
  (`.snappy(0.35)`) and holds 0.2 s; and the first exercise grows into the current one as the list
  carries it up under the bar, one motion (`.snappy(0.55)`, `growBeat`), while the key rides down
  off the screen with the rows below it, as far and on the same frames (`primaryKeyBar`'s `drop`).
  An animated `scrollTo` in that transaction held the growth back until it had nearly landed, so
  the list is scrolled at once, its content drawn where it was by an offset (`GrowthLift`) that
  runs to 0 with the growth. The lift and the key's drop are `Animatable` modifiers, worked out
  frame by frame with the row's layout: as plain offsets they ran ahead of the rows. The row's
  label stands at a height running from its resting height on an animated `growth`
  (`StandingHeight`), its content counted only past the end height, since new parts take their
  room at once, and nothing under the name drawn below the height it stands at (`BottomClip`). The
  current exercise is as tall as its content; Start drops the key a screen's height, so it is gone
  by the time the growth ends. The workout's key then comes up from below the screen's edge as the
  rows land, `keyReturnDelay` (0.45 s) from the growth's start, on `.smooth(0.2)`: the growth's
  completion came a few frames after the rows stopped, and the key rose after a pause. The rail
  stacks its rows in a layout of its own (`RailStack`), each row placed as its height animates:
  the rail's `VStack` held the rows below at their old places mid-growth, then let them jump. A
  resting row's label stands at least as tall as the row's minimum less its insets
  (`restingLabelFloor`): growing from its own height, its first points of growth moved nothing,
  and the rows below ran ahead and came back. End, in the bar, asks "End this workout?" in a
  confirmation dialog, as the scratch app does: Finish workout only once a set is logged
  (`Workout.offersFinish`), and Discard workout as destructive. The dialog hangs on the whole
  screen, outside the navigation stack: on End, or on the stack's content, iOS showed it as a
  popover with an arrow; there, it shows centered. Its choice runs about 0.37 s after the tap
  (simulator, two runs), and the end's motion starts there. The bar's keys fade with it
  (`barFade`, 0.2 s): End crossfades into ++ in one leading item, and the time fades out of its
  key, whose glass (`endingWorkout` holding the item) goes 0.2 s later in an animated change, the
  bar fading it; an item the bar takes out goes with its content on the frame. The small title in
  the bar is always in its item, faded in and out (0.2 s) as the large one goes under the bar or
  comes out, and shown to VoiceOver only while it shows: the bar draws its edge effect only while
  the title item has something showing, so a title taken out took the band under the bar with it,
  on the frame. The current exercise shrinks back as the rows below close up and the list scrolls
  back to its top (0.4 s, `endBeat`, on a timing curve that eases out and stops: a spring's
  settling tail felt slow and heavy), the workout's key going down out of the bottom edge as it
  fades (`barFade`). Once that lands (an `endBeat` sleep from the motion's start: the animation's
  completion came a few frames after the rows stopped), Start comes up on its own from below the
  screen's edge into place (`.smooth(0.2)`, no overshoot), unfaded, the bar holding its full room
  from the key's first frame, so the list under it doesn't move. The key's side insets are
  measured on the screen, not the key, so a key coming in has them from its first frame; measured
  on the key, it came in 16 pt from the sides and narrowed to 34 pt on the next animation, too big
  at first. The scroll is animated, not lifted: drawn lifted at the top, the title showed over the
  status bar with no edge effect under the bar. Room under the list's end, out of sight, holds the
  scroll still while the row grows or shrinks. With Reduce Motion each change is one crossfade
  (0.35 s, easing in and out), the haptic kept: the changed list is a new view (`listChanges` as
  its id, in a `ZStack` so the two overlap), fading in over the old one, which is drawn lifted by
  as far as the scroll jumps so it holds still, with what was under the bar cut away (`TopClip`);
  nothing inside the new one animates. The rows' closure reads the workout's values once, as
  values: read through `self`, the list going out redrew itself in the workout it was fading into.
  The change runs a turn of the run loop after the lift, so the old list is drawn lifted before it
  goes. The key fades in after the crossfade (0.2 s): the workout's key at Start, Start at the
  end.
- The current exercise of a workout is the row of the next set to log, the first in the routine's
  order not yet logged, grown (`RowLabel`'s `focus`, `RowFocus`): its node 14 pt in `accent`,
  pulsing in brightness within its circle on one clock, the time itself (`CurrentPulse`), which
  the bar of its current set shares, so the two never drift apart; its name from `ppRowTitle` to
  `ppCurrentTitle` (`GrowingName`: both sizes laid out once at the row's width, the one showing
  scaled from its top leading corner, so it grows as one drawn piece; a font size animated frame
  by frame reflowed the text every frame, and crossfading only where the two sizes break into
  different lines; the large one stands unscaled at rest, where it doesn't show, as scaled down
  the accessibility audit read it as clipped); which set it is on in place of the plan line
  ("Round 2 of 3" in a superset, the side set off in `textPrimary`, "Set 1 of 3 · Left", its
  numbers then without "per side"), with its set bars (`SetBars`) at the line's trailing end,
  centered on its first line, from its first set, or under it at the accessibility sizes, where
  beside it eight bars squeezed the line to nothing; its equipment as capsules; the plan's numbers
  large (104 pt SF Mono at the default size), each with what it counts beside it, or under it
  where the two don't fit the width (`FigureLayout`, not `ViewThatFits`, which sent the view graph
  round a cycle as the title took focus, and hung the app). The label is as tall as its content,
  at every text size. Start, the key's way back (below), a relaunch, a move to the next exercise,
  and Start from a routine pushed on the Routines screen land the row just under the bar
  (`currentTopSpace`, 24 pt, its own space above it), with everything above it under the bar;
  while it is landed, a change in height above it, after a text size change or a rename, lands it
  again. The current row has no swipe; its sheet's Delete stays. VoiceOver reads the row as one
  element, with no action of its own to log: the key logs.
- The screen has one key, at the bottom (`primaryKeyBar`, `RoutineScreen+Key.swift`): Start, then
  in a workout the key that logs. It is a capsule in the primary key's colors
  (`PrimaryKeyButtonStyle`, `ppPrimaryKey`, `.title3` semibold): a 56 pt face on a 4 pt ledge, its
  corners half its one-line height, kept when its label wraps at the accessibility sizes, where a
  `Capsule` went oval. Its resting face sits as far from the screen's bottom as from its sides,
  the bottom safe area, which on an iPhone 17 is concentric with the screen's corners (62 pt less
  the key's 28 pt radius is 34 pt), the ledge in the safe area below it; with no safe area below,
  the ledge stays on the screen. Nothing is drawn behind it: the bottom scroll edge effect is
  hidden, and the rows run on under the key. Its role (`KeyRole`): "Log set", or "Log left", "Log
  right", "Log last set" (`Routine.logText(for:after:)`, read from the held set, so the words
  change with the row, not before it), logging the current set at the numbers shown; while the
  current exercise is mostly out of view (`CurrentPlace.isMostlyOut`, under 40 percent showing),
  an arrow toward it and its name, wrapping rather than cut short, read "Go to current exercise"
  and the name, whose tap scrolls back to it (`.snappy(0.4)`) and logs nothing; after the last
  set, as its row closes, "Log last set" still, taking no tap; then "Finish workout", which ends
  the workout at once, as End's Finish does. A tap that would log goes back instead when the row
  is mostly out of view as it lands. The role holds while a finger is on the list (the scroll
  phase interacting or tracking) and while the list rubber-bands past its top, so it never changes
  under a thumb about to tap; once the finger lifts, it follows the row's live place as the list
  coasts (`settleKeyRole()`). Within a kind (`KeyRole.Kind`) the words change in place, in one
  `Text`: a branch per role crossfaded "Log last set" into itself as the row closed, and dimmed
  it. Across kinds the key swaps (`swapKey(_:)`): the one showing drops out of the bottom edge,
  unfaded, on `.easeIn(0.2)`, then the next rises on Start's own `.smooth(0.2)` as it clears
  (`keySwap`), one key at a time, the bar keeping its room so the list under it never moves; each
  kind is its own identity (`keyID`), so the key coming in is a fresh insertion, not the one going
  revived. A tap mid-swap does nothing; with Reduce Motion each half fades over the same 0.2 s. On
  a flick on the simulator the next key shows about 0.24 s after the lift and rests about 0.5 s
  after it. Each log plays a haptic from the screen, medium for a set and light for a side, and a
  "+1" (`PlusOneBurst`, `ppPlusOne` in `accent`) pops from the key's top edge, centered, rising 30
  pt as it grows from 0.7 to 1.25 and fades over 0.7 s, a keyframe animation played by a count
  (the logs, `primaryKeyBar`'s `plusOnes`) that rests at opacity 0; with Reduce Motion it flashes in place. It is drawn over
  the screen from the key's anchor, not in the bar, so it rises above the bar's room.
- A log that stays on the current exercise is saved at once, but shown as still to do (`heldSet`)
  for `SetMotion.heldRoll` (0.5 s, about as the +1 has risen), a `.task(id:)` on the held set, so
  the screen going away cancels it; a second tap inside it is dropped, as a double tap would be.
  As it logs, the current node shrinks to half and fades to the rail's gray (0.2 s) and rests so;
  as the beat ends, the progress line rolls word by word, only the words that change ("Set 2 of 3"
  to "Set 3 of 3" rolls the 2 alone, a side word on its own), each pushed up and out as its new
  one comes up (0.3 s), the bars with it, and the node pops back full and green on a `.bouncy`
  spring past its size (`SetBeat`). The hold is a value on the row's `RailPlace`, set by the rail
  (`Rail`'s `isSetHeld`), like the current row itself: an environment value set on a row's label
  never reached its node, a sibling inside `railRow()`. With Reduce Motion the node stays as it
  is.
- A log that moves to another exercise is one motion (`ExerciseMove`, `SetMotion`), about 1.27 s
  down the rail and 1.25 s back up a superset's loop. The node left goes to its own color at once,
  under a green blob (`RailPulse`, `PulseShape`) that is that node from the log: from 0.02 s its
  bottom is pulled out along the rail, a capsule drawn out by its speed (at most 3 times the node,
  its area kept, so it thins), joined to the node left by a neck whose sides are two curves
  touching both circles (`PulseShape.neck`) until the curves meet and it snaps, leaving the node
  in its own color, with no wobble. Its leading end joins the next node by a neck too, and landed,
  a circle the current node's size, it plops: squashing to 1.25 by 0.8 and wiggling back to round
  on a dying sine of two and a half swings through 0.35 s (`squash(at:)`), with a light haptic
  (`landings`, lighter than a set's log), the node lit under it as it lands (`isLanded`, `litID`),
  the blob dimming with the current pulse's clock so neither hand-over shows a seam. Paths are
  joined with `Path.union`, which keeps every edge antialiased; a blur-and-threshold metaball
  would have shrunk the shapes and drawn hard edges. Down the rail (`SetMotion.Way.down`) the blob
  travels 0.5 s on a quartic ease-in-out (`travelEase` 4, four times its average speed at the
  middle), slow as it pulls free and as it joins, landing 0.52 s after the log; back up a loop at
  a round's end it travels 0.42 s on an ease-out and gathers into a circle on the node (0.06 s),
  landing at 0.5 s. Either way nothing else moves until the landing has been seen: the current
  exercise's parts all still show, and the shift starts `landingHold` (0.3 s) after the landing,
  as the wiggle has mostly settled (`moving(_:)`, 0.45 s on `timingCurve(0.6, 0, 0.1, 1)`,
  starting from rest and easing hard to a stop with no overshoot). Then the parts go bottom first,
  each fading as it drops 6 pt; the row shrinks back to a resting row as the next row grows into
  the current exercise and the list scrolls it up under the bar, the scroll Start's (scrolled at
  once, drawn lifted, the lift run to 0), so the rows between and below move one way only; and the
  next row's parts come in top first, each rising 8 pt as it fades in (`exerciseMoveWay`), "Round
  2 of 3" rolling to the next round once the row shows it (`roundRoll`). The blob's keyframes end
  on a frame of nothing: a timeline ending on a `MoveKeyframe` rests on the value before it, which
  left the pulse on the node. After the workout's last planned set the row closes as the list
  settles on its end (`closing`, 0.65 s, with no pulse), the room that landed it closing on the
  same curve with the end held where it shows (`keepEndPinned`), and once it has closed the key
  swaps to Finish workout; the list ends in Add exercise, as it always does. Set bars, purple once
  done, gray to do, show on every started row until it is finished, where its node turns purple.
  With Reduce Motion a move to another exercise is one crossfade, as Start's is, with no pulse;
  the haptics stay.
- A row on a rail moves by holding and dragging (`RailDrag` holds every value). A hold of 0.4 s
  that moves under 10 pt lifts it; a press that moves first is a scroll, and a hold in the rail
  column, on the node, draws a superset instead (below). The hold is a UIKit long press (`RailLiftGesture`), put
  outside the row's tap and swipe actions: SwiftUI's long press stops a scroll view scrolling,
  and inside a SwiftUI tap, which never fails during a still hold, the UIKit one never began.
  The row rises into a card on `.snappy(0.18)` with a light impact haptic: the same row drawn
  over the rail on `surfaceRaised`, level and unscaled, a soft centered `shadow` all
  around it (blur 8, fading with the lift), no border or grip,
  its node in the text's color. The card is centered on the row, its node inset from its top and
  leading edges alike, the row's content ending that inset short of its trailing edge, with
  continuous corners of that inset plus the node's radius. It follows the finger with no
  animation. The gap moves to a new slot once the card's top passes halfway over a row, with a
  4 pt dead band, on `.snappy(0.2)`, each move a rigid impact at 0.6 (`.alignment` plays nothing
  on iPhone). While a row is held, the line is drawn once from the first node to the last, so
  rows trading places never part it, and at either end it stops at the card's node rather than
  show past the card. Within 64 pt of the top or bottom of the area between the bars the list
  scrolls (`railAutoscroll`), once the finger has gone 10 pt toward that edge since the lift (or
  to the edge, lifted nearer it), so a row held still there stays put; the speed rises as the
  square of the depth to 900 pt/s, and the card stays under the finger as the rows pass. A drop
  settles into the gap on `.snappy(0.22)`, with no haptic and no blue: nothing is arriving. A
  release over a bar, or a system cancel, sends it back on `.snappy(0.25)`. With Reduce Motion the card shows lifted at once and the gap and the
  drop jump, but the haptics stay. VoiceOver moves a row with Move up and Move down, none where
  it would do nothing, and announces the row it passed ("Moved above Plank").
- A superset on a rail is a loop beside the line (`GroupLoop`, `LoopPen`): one stroke from its
  last node back up to its first, in the line's gray (`rail`, the resting nodes' gray, at least
  3:1 on the background and on `well`), continuous corners, with a filled head in each gap between members,
  halfway between their nodes, the stroke stopping short of its tip. A superset's top and bottom
  edges are each two slots for a row moved by its body, inside (the loop wraps the gap) and,
  `edgeSlotSpread` (24 pt) further, outside, each with the reorder's tick. A row held still
  over a plain neighbor pairs with it, as an app held on another makes a folder (`RailPairing`):
  with the gap in a plain slot, the card 16 pt or more past it over the neighbor, above or
  below, staying within 6 pt for 0.5 s, the two pair with a medium impact, and the partner and
  the rows past it move out from under the card by as far as it lies over it. The pair holds
  while the card stays 8 pt or more over it, and comes apart with the reorder's tick once it
  eases back toward its gap or the gap moves. A neighbor in a superset never pairs, nor does a
  rest at the slot just outside the superset the row was lifted from, so a member dragged out
  leaves it; over a bar nothing pairs. Dropped, a rest-made pair takes the larger of its rows'
  set counts. While a row or a node is held, the superset the hold changes sits in a well
  (`RailWell.swift`), flat in `well` with no shadow, drawn by the rail under its strokes: for a
  body's drag, the one the held row is in or would be in if dropped now, wrapping the card
  where it is an end; for a node's, its field. Its top corners are concentric with the loop's
  top curve, its sides as far out from the loop's line; it fades in with the lift and out on
  the drop's transaction, and every other superset keeps its loop alone. At rest there is no
  well. Where a well first in the list would reach nearer what is above the rail than one at
  rest, the rail pads its top a frame at a time (`RailRoom`) as the list scrolls by as much,
  so the card stays under the finger while the title and tags move up. A hold on a node draws a
  superset (`Rail+Regroup.swift`, the rule in `RailRegroup`, the caller's): the press shows
  what it picked up in the well, an end's whole superset or the row alone; the drag spans from
  the anchor to the row under the finger, with the reorder's tick at each change. A drop
  commits it with a light impact; the well fades (0.1 s), then the new loop shows `railJoin`
  and cools as a new node does (`RailEntry.groupFlash()`). While anything is held, rows draw no strokes: the rail draws the
  line and every loop once, as the drop would leave them (`RailDrawing` for a node's drag,
  `HeldRailDrawing` for a body's), every end and head on a real node, the held row's at the
  card, and the card draws the same drawing over its fill and over its shadow, so the shadow never
  shades the line or a loop. Shapes animate their nodes and joins
  on the moving transaction; with Reduce Motion the rows jump, the loops crossfade (0.2 s),
  wells and room come and go at once, there is no flash, and the haptics stay. A row swiped open hides its superset's loop. VoiceOver
  reads a member's value as "In a superset with" its partners, and offers "Superset with" each
  neighbor it isn't joined to, and "Move out of superset" on a member.
- The ++ drawer (`SideDrawer`) lies under the screen, which slides right on
  `Spring(duration: 0.25, bounce: 0)`, leaving a 78 pt sliver with a light shadow on the drawer (radius 10, offset -6 pt), and
  darkens with `dim` as far as it is open. A swipe starting within 24 pt of the left edge opens
  it and a swipe left closes it, following the finger (`DrawerSwipe`, a plain pan, since the
  screen-edge recognizer never begins on synthetic touches); let go, it settles the way a flick
  of 400 pt/s goes, else to the nearer side of halfway, leaving at the finger's speed
  (`DrawerDrag`). A tap on the sliver, on the drawer's title, or VoiceOver's escape closes it.
  The haptics play the moment the drawer starts toward open or closed, as its target changes: on
  a tap, on VoiceOver's escape, or as a swipe is let go, never while the finger drags: solid at
  0.5 opening, solid at 0.7 shutting; a swipe that springs back to where it began plays
  nothing. With Reduce Motion nothing follows the finger: a 30 pt swipe decides, and only
  opacity animates: opening, the screen and its dim take their place at once, with the haptic,
  and the drawer fades in beside them (0.2 s); closing, the haptic plays as the drawer starts to
  fade out, and the screen goes back once it has. The controls in the screen's bars, hosted apart from it, ignore
  `accessibilityHidden`, so behind the open drawer each leaves VoiceOver through
  `hiddenBehindDrawer()`, which `primaryKeyBar` applies and a toolbar item applies itself; the
  drawer hides the screen's scroll bars. The drawer is in the hierarchy only while it shows. Its places (`DrawerButtonStyle`) have no outline, and all, Routines and the rows under it, set their names in one font (`ppDrawerItem`) at one minimum height (44 pt), so none reads as a heading; the one showing sits on a `selectionFill`
  fill, a `RoundedRectangle(cornerRadius: Radius.key, style: .continuous)`, under icon and
  name, with as much space to the icon's left as above and below it (the dot, for a routine,
  marked with `DrawerIconBounds`), ending 16 pt short of the drawer's trailing edge, and one
  always does. The three routines are the last opened or edited, in the order they were last
  edited (`lastEdited(first:editedAt:)`), so opening one never moves it. New is an action and is never
  marked: while an untouched new routine shows, it has its own row at the top of the three,
  New routine in the title's placeholder gray (`textSecondary`), its node lit and marked, above
  the two routines last opened or edited. A nested place's icon, a routine's `DrawerNode` or
  New's plus, sits in the column of the place above's icon, on the name's first line.
  Nothing in the drawer changes while any of it shows: `DrawerMenu` takes its rows and its mark
  from the session as it enters the hierarchy and holds them until it leaves, so a tap that
  switches routines, or a swipe, never moves or re-marks a row; the next opening once it has fully closed reads afresh. As it leaves, it reads the saved routines from the store again, so a launch read that failed or landed late is made good by the next opening.
  The Routines screen lists each routine as a `NameRow`, its name in the drawer's font
  (`ppRoutineName`, SF Pro, as it can't be edited there), with no lines between rows.
- A generated name arrives in the title on its own clock (`SuggestionTiming`, one
  `TimelineView`): the old name fades out (0.15 s), then the new one types in, a character
  every 20 ms, each letter shuffling through the name's other letters in `railJoin` for 50 ms,
  a new stand-in every 30 ms, so about two letters shuffle behind the lead, then landing and
  easing to its own color (0.16 s, ease-out). The `_` breathes in blue (a 1.8 s breath, down to
  0.4 opacity) from the fade until the last letter has eased. Every frame is worked out from
  the time since typing started (`typingFrame(of:at:)`), so nothing drifts and a snapshot can
  draw any moment. Back to New routine it crossfades (0.3 s), as does everything with Reduce
  Motion, with no blue. Editing stops it at once and opens on the final name.
- Every new component gets a `#Preview` and goes through `assertThemedSnapshots`.
- Every view, `ButtonStyle`, and `ViewModifier` declares `@ObserveHotReload private var
  hotReload` and ends its body with `.hotReloadable()`, so hot reload redraws it. Both compile
  away in Release.
