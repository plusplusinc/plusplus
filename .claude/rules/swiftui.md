---
paths: ["App/**", "Packages/Sources/DesignSystem/**"]
---

# SwiftUI and design system

Plain SwiftUI: views host presentation logic, `@Observable` stores injected through
`.environment()` host state, stateless services host side effects. No view-model class per
screen. Leaf views take plain values and closures so they preview and snapshot without a store.

- No raw colors, spacing, font sizes, or corner radii at call sites. Use `Color.pp(.token)`,
  `Font.pp*` or a `.pp*Font()` modifier, `Spacing`, and `Radius` from `DesignSystem`. If a
  token is missing, add a `ColorToken` case and its colorset. Green (`accent`) is data only.
  Blue (`railJoin`) marks something joining a rail, for the moment it joins, then gives way to
  the rail's grays; nothing rests in it.
- Every font token scales with Dynamic Type: built on a `Font.TextStyle`, or sized with
  `@ScaledMetric(relativeTo:)` when the design sits between two styles. Never a fixed size.
- Prefer stock components for navigation, toolbars, and sheets; the system applies Liquid Glass
  there. Do not set `UIDesignRequiresCompatibility`.
- Every tappable element that is not a `Button` gets `.accessibilityAddTraits(.isButton)`;
  icon-only controls get `.accessibilityLabel`; decorative images get
  `.accessibilityHidden(true)`.
- Motion is snappy: `.snappy`, never a bare `withAnimation` or the default spring, and quicker
  than its default where it answers a tap: rows going onto and off a rail use `.railChange`,
  and a key comes back from a press with `keyPressAnimation(isPressed:)`. A row added to a rail
  enters in one landing (`RailEntry`). After 0.1 s, the line grows down from the node above in
  the rail's gray (0.24 s) on a quartic ease-in from a small running start, and the row's place
  opens with it on the same curve, pushing Add exercise down exactly as far as the line grows,
  or, past the visible area, scrolling in step so the key stays put. A solid `railJoin` pulse
  leads the tip: it starts as a dot under the node above, grows from the line's width to twice
  it on a cubic ease-in, and stretches with the tip's speed, to at most a third of the gap.
  After a 0.05 s pause, in which the pulse collapses back to its dot, the node pops from it
  with a small, crisp overshoot, and the name and equipment land with it in `railJoin`, a short
  drop that stops cleanly, with a light impact haptic. After another 0.05 s pause, the node and
  text hold in blue (0.25 s), then fade to their own colors on an ease-in (0.28 s); the line is
  never blue. The first row has no line or pulse: its place opens over the same time and curve,
  then it lands. With Reduce Motion the place opens at once, nothing is blue, there is no shot,
  pulse, or overshoot, but the haptic stays, as the row lands.
  Nothing waits on it: the key, scrolling, swiping a row, and the title all work while it plays.
  It enters only where it can be seen: its place opens as the picker's sheet starts down, and
  the entry plays a moment into the sheet's slide, or, when the new row has pushed the list's
  end out of view, after a scroll to the end.
- Every new component gets a `#Preview` and goes through `assertThemedSnapshots`.
- Every view, `ButtonStyle`, and `ViewModifier` declares `@ObserveHotReload private var
  hotReload` and ends its body with `.hotReloadable()`, so hot reload redraws it. Both compile
  away in Release.
