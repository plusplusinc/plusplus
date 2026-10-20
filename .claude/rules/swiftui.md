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
  active, and a value that went up.
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
  end out of view, after a scroll to the end.
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
  `Spring(duration: 0.25, bounce: 0)`, leaving a 78 pt sliver with a shadow on the drawer, and
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
  drawer hides the screen's scroll bars. The drawer is in the hierarchy only while it shows. Its places (`DrawerButtonStyle`) have no outline; the one showing sits on a `selectionFill`
  fill with continuous corners (`Radius.key`) that takes the whole row, icon and name, inset
  around the icon as around the name, and one always does. New is an action and is never
  marked: while an untouched new routine shows, it has its own row at the top of the three,
  New routine in the title's placeholder gray (`textSecondary`), its node lit and marked, above
  the two routines last opened or edited. A nested place's icon, a routine's `DrawerNode` or
  New's plus, sits in the column of the place above's icon, on the name's first line.
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
