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
  Blue (`railJoin`) marks something arriving: a row joining a rail, and a generated name typing
  into the title, for the moment it arrives, then gives way to the thing's own color; nothing
  rests in it.
- Numbers on a row's detail line and in a sheet's values are SF Mono, set with
  `AttributedString.monoNumbers(_:font:)`; the words around them stay in the system font.
- Every font token scales with Dynamic Type: built on a `Font.TextStyle`, or sized with
  `@ScaledMetric(relativeTo:)` when the design sits between two styles. Never a fixed size.
- Let the system wrap text and measure what it laid out (a hidden copy, or the view's own
  layout); never work wraps or line counts out from character widths, which emoji, CJK, and
  glyphs SF Mono lacks break. The title still counts monospaced cells, assuming every character
  is one cell wide, in two places: its `_` finds its place that way
  (`cursorCell(at:in:columns:)`), and its line count is the larger of that count and a hidden
  copy's measured lines (#79).
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
  that moves under 10 pt lifts it; a press that moves first is a scroll, and one in the rail
  column, on the node, lifts nothing. The hold is a UIKit long press (`RailLiftGesture`), put
  outside the row's tap and swipe actions: SwiftUI's long press stops a scroll view scrolling,
  and inside a SwiftUI tap, which never fails during a still hold, the UIKit one never began.
  The row rises into a card on `.snappy(0.18)` with a light impact haptic: the same row drawn
  over the rail on `surfaceRaised`, scaled 1.03 and turned −0.6°, no shadow, border, or grip,
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
