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
  enters as a sequence of beats (`Rail`'s `arriving`): its name fades in with a small drop
  (0.12 s); then the line shoots down from the node above to the new node (0.18 s) on an
  ease-in, starting slow and landing fast, a shot rather than a slide; then the node pops in
  with a small, crisp overshoot (0.15 s) as the line lands; then the new line and node settle
  from `railJoin` to gray (0.3 s). The first row has no line, so it is name, pop, settle. With
  Reduce Motion there is no shot, no blue, and no overshoot: the line and node appear with the
  name. It enters only where it can be seen: its place opens as the picker's sheet starts down,
  and the entry plays a moment into the sheet's slide, or, when the new row has pushed the
  list's end out of view, after a scroll to the end.
- Every new component gets a `#Preview` and goes through `assertThemedSnapshots`.
- Every view, `ButtonStyle`, and `ViewModifier` declares `@ObserveHotReload private var
  hotReload` and ends its body with `.hotReloadable()`, so hot reload redraws it. Both compile
  away in Release.
