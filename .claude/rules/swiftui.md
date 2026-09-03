---
paths: ["App/**", "Packages/Sources/Features/**", "Packages/Sources/DesignSystem/**"]
---

# SwiftUI and design system

Architecture is plain SwiftUI: views host presentation logic, `@Observable` stores injected
through `.environment()` host state, stateless services host side effects. No view-model class
per screen. A "screen" is a container view that owns navigation state and reads stores; leaf
views take plain values and closures so they preview and snapshot without any store.

## Liquid Glass and system components

- Two layers: the content layer is the user's data; the functional layer is navigation bars,
  tab bars, toolbars, and sheets. Liquid Glass belongs only in the functional layer, and the
  system applies it there. Never put glass behind dense text or on set rows.
- Never stack glass on glass, and never tint navigation or tab bars with a brand color.
- Prefer stock components in the functional layer. Custom UI goes where the product is: set
  logging, the rest timer, the keypad. Do not set `UIDesignRequiresCompatibility`.
- `.tabViewBottomAccessory` is the home for a live workout or rest-timer bar.

## Tokens

No raw colors, spacing, font sizes, or corner radii at call sites. Use `Color.pp*`, `Font.pp*`,
`Spacing`, `Radius`, and `TouchTarget` from `DesignSystem`. If a token is missing, add one.

- Any number that changes in place (weight, reps, a timer) uses a monospaced-digit font token.
- Primary actions use `TouchTarget.primary` (60pt), not the 44pt minimum, and sit at a fixed
  position on screen rather than inside a scrolling row. This app is used mid-set, one-handed.
- Never a modal mid-set. Inline controls only during an active workout.
- Haptics on commit actions (set logged, PR hit) through the design system, not ad hoc.
- Respect Dynamic Type: every font token is built on a `Font.TextStyle`. Never a fixed size.

## Accessibility

- Every tappable element that is not a `Button` gets `.accessibilityAddTraits(.isButton)`.
- Icon-only controls get `.accessibilityLabel`. Decorative images get `.accessibilityHidden(true)`.
- Group repeated rows with `.accessibilityElement(children: .combine)` where reading each
  child separately would be noise.
- Check color contrast against the token pairs; do not invent a new pair at a call site.
- Every new component gets a `#Preview` and snapshot coverage in light, dark, and the
  accessibility XXXL content size.
