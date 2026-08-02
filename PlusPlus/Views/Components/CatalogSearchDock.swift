import SwiftUI

/// The catalog search affordance: a key floating above the tab bar that morphs
/// in place into a field (Dave, 2026-08-02).
///
/// **This replaced the SEARCH TAB.** The bar carried five tabs, the fifth
/// wearing `Tab(role: .search)` purely to host a field, and hosting it cost the
/// app a hand-built `.principal` toolbar row for the scope control (seven
/// builds, six placements), a set of title/spacing/margin exceptions on one
/// surface, and a standing ban on state-writing geometry reads anywhere in the
/// `TabView` subtree. Four tabs and a floating key delete all of it: the tab bar
/// IS the scope control, because the tabs stay on screen while you search.
///
/// ⚠️ **It mounts as a bottom `safeAreaInset` INSIDE each catalog tab's
/// `NavigationStack`** (`CatalogScopeView.listBody`), and every part of that
/// sentence is load-bearing:
///
/// - **It rises with the keyboard**, because a `safeAreaInset` participates in
///   SwiftUI's keyboard safe-area avoidance and nothing in this chain opts out
///   with `.ignoresSafeArea(.keyboard)`. ⚠️ Being inside the stack is NOT what
///   buys that — say it correctly or the next session moves this somewhere that
///   looks equivalent and isn't. `tabViewBottomAccessory` is the counter-example
///   precisely because it OPTS OUT: it does not rise (builds 137–139, 144),
///   which is what buried the old scope control, and it also refuses
///   app-authored animation (138), so the morph would not survive there either.
///   Do not move this into it.
/// - **A `safeAreaInset`, not an overlay**, so the list's scroll content is
///   inset by the dock's height and the last row can clear the key. An overlay
///   would leave the final row permanently under it.
/// - **On the stack's ROOT content**, so it does not apply to
///   `navigationDestination` screens. That is how the key hides the moment you
///   push a detail, with no flag and no at-root signal to thread.
///
/// ⚠️ **It is the app's ONE Liquid Glass surface, and that is a scoped
/// exception Dave took deliberately** (2026-08-02): a glass CIRCLE that morphs
/// into a glass CAPSULE, i.e. the native search-tab look this replaced. Three
/// standing laws bend for it and only for it — icon keys are r11 rounded
/// squares (2026-07-19, an all-circles round was reverted), controls are
/// rounded rects not capsules (2026-07-20), and key chrome is app-drawn over
/// Liquid Glass (build 42). **The reason is the NEIGHBOUR**: this dock floats
/// directly above the system tab bar, which is glass, so it matches what it
/// sits against rather than chrome most of a screen away. Nothing else in the
/// app moves — `SearchFieldBody`'s other three mounts sit among app-drawn keys
/// and keep the r11 opaque anatomy.
///
/// The morph is therefore the SYSTEM's, not the anytime card's: a
/// `GlassEffectContainer` plus a shared `glassEffectID`, which is the same
/// mechanism the search-role tab used to expand out of the bar. ⚠️ Do NOT
/// reach back for `matchedGeometryEffect` here — it cannot fluidly reshape
/// glass, and the two would fight over the same geometry.
///
/// The anatomy inside the glass is the app's own search grammar, unchanged: an
/// in-field `delete.left` CLEAR that empties the query and keeps you typing,
/// and a separate `xmark` COLLAPSE key that clears AND closes, sitting exactly
/// where the magnifier was. `xmark` means "collapse the search" here as
/// everywhere, which is why a sheet never dismisses with one.
struct CatalogSearchDock: View {

    /// The shared id for the travelling ground. Lives here because
    /// `SearchFieldBody` (the expanded half) defaults to it.
    static let chromeID = "catalogSearchChrome"

    /// Key diameter, matching the field's own height so the open row sits on
    /// one baseline. Sized UP from the app's 44 pt icon key (Dave, build 171:
    /// "a bit bigger, to match native") — the system's bottom search field and
    /// its separated circle are around this, and 50 also keeps the tap target
    /// clear of the HIG floor at every Dynamic Type size.
    static let keySize: CGFloat = 50

    /// The query, owned by `RootTabView` and shared by all three catalogs
    /// (Dave, 2026-08-02): typing "bench" on Routines and tapping Exercises
    /// keeps the query. Honest because the field is visible on every tab that
    /// can be narrowed, which is what the "a stale invisible query reads as
    /// data loss" law actually asks for.
    @Binding var query: String
    /// Open/closed, also owned by the root — so search survives a tab switch,
    /// and survives a trip to Today (where the dock does not render) rather
    /// than silently dropping what you typed.
    @Binding var isOpen: Bool
    /// What the field says it searches. Per-scope, so the prompt names the
    /// catalog the tab is already on.
    let scope: FindScope

    @Namespace private var morph
    /// One-shot focus intent (#233): armed before the field exists, consumed
    /// by its `onAppear`. A focus request made before the view exists is
    /// silently dropped.
    @State private var wantsFocus = false

    var body: some View {
        // ⚠️ `GlassEffectContainer` is what makes the two shapes ONE morphing
        // surface — it is not a performance wrapper here, it is the mechanism.
        // Without it the shared `glassEffectID` has no container to morph
        // within and the swap is a hard cut.
        GlassEffectContainer(spacing: 10) {
            if isOpen {
                openField
                    .zIndex(1)
            } else {
                HStack(spacing: 0) {
                    // Trailing seat, so the key sits above the RIGHTMOST tab
                    // and the collapse key lands back on this exact spot.
                    // ⚠️ The Spacer is INSIDE the container's row rather than
                    // a layer over the list: rows scroll under this inset and
                    // stay visible through the empty side, so a full-width
                    // hit-testing layer here would be a standing dead column
                    // (ui-interaction.md), invisible to XCUITest.
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                    searchKey
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // No band behind the dock: glass IS the ground, and the `.soft` bottom
        // scroll edge effect keeps rows legible under it. A solid strip here
        // would be the full-width slab build 148 killed, one row higher.
        .padding(.bottom, 6)
    }

    private var openField: some View {
        // Default `HStack` spacing would crowd two glass shapes; 10 matches
        // the container's own spacing so they read as one group without
        // merging into a single blob.
        HStack(spacing: 10) {
            SearchFieldBody(
                config: HeaderSearchConfig(
                    text: $query,
                    // What the scope SEARCHES, not what its tab is called
                    // ("Search equipment", not "Search kit").
                    prompt: "Search \(scope.searchNoun)",
                    identifier: "catalogDockSearchField"
                ),
                wantsFocus: $wantsFocus,
                glass: SearchFieldGlass(namespace: morph)
            )
            closeKey
        }
    }

    /// The collapse key: clears the query AND closes, landing exactly where the
    /// magnifier was. A glass circle, like the key it replaces on screen —
    /// `HeaderIconButton` is not reusable here for the same reason the search
    /// key is not (see below).
    private var closeKey: some View {
        Button {
            query = ""
            withAnimation(Theme.Anim.selection) { isOpen = false }
        } label: {
            glassGlyph("xmark")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close search")
        .accessibilityIdentifier("catalogDockCloseButton")
    }

    /// The collapsed key. Built here rather than reusing `HeaderIconButton`
    /// because that component IS the app's opaque r11 raised-key anatomy, which
    /// is exactly what this one control does not wear — and because its ground
    /// has to carry the `glassEffectID` that pairs it with the field.
    ///
    /// ⚠️ No `.raisedKey()`, and nothing to compensate for. A raised key is
    /// 48 pt tall (`RaisedKeyStyle` pads the bottom by its 4 pt travel to leave
    /// room for the plate), which used to seat the field low beside it. Glass
    /// has no plate, so every shape here is one flat `Self.keySize` and the row
    /// lines up on its own. `.interactive()` supplies the press response the
    /// plate used to.
    private var searchKey: some View {
        Button {
            wantsFocus = true
            withAnimation(Theme.Anim.selection) { isOpen = true }
        } label: {
            glassGlyph("magnifyingglass")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
        .accessibilityIdentifier("catalogSearchToggle")
    }

    /// One glass circle carrying a glyph — the dock's key anatomy, shared by
    /// the magnifier and the collapse ✕ so they are visibly the same object in
    /// two states. Sized to the system search field it imitates, which is why
    /// it is `keySize` rather than the app's 44 pt icon key.
    ///
    /// ⚠️ **`.contentShape(Circle())` IS THE HIT TARGET, and it is not
    /// optional** (Dave, build 171: taps on the ✕ "click whatever's behind it,
    /// as if it were pointer-events: none"). A `.frame()` around an `Image` is
    /// LAYOUT SPACE, not content, and SwiftUI hit tests the content — so
    /// without this the tappable area is the glyph's own strokes and every
    /// near-miss falls through to the list, or sideways onto the in-field
    /// clear key, where it reads as "the ✕ does nothing". ⚠️ `.glassEffect`
    /// does NOT restore it: it is a rendering effect, not a view, which is
    /// exactly how `HeaderIconButton` differs — that one fills its frame with
    /// an opaque `.background(_:in:)`, and a real background view IS
    /// hit-testable. Swapping the opaque ground for glass silently took the
    /// hit target with it.
    ///
    /// ⚠️ Only the MAGNIFIER carries the `glassEffectID`. The field takes the
    /// same id when open, so the pair morphs; giving the ✕ that id too would
    /// claim the id twice in one frame and leave the container with two
    /// candidate shapes for one surface.
    private func glassGlyph(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(.title3, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: Self.keySize, height: Self.keySize)
            .glassEffect(.regular.interactive(), in: Circle())
            .glassEffectID(systemImage == "magnifyingglass" ? Self.chromeID : "\(Self.chromeID)-close", in: morph)
            // ⚠️ OUTERMOST, deliberately: `.contentShape` defines the hit
            // region of the view it wraps, so applied under `.glassEffect` it
            // could be re-composed away by whatever that adds. Last modifier
            // means the finished circle is the hit target, full stop.
            .contentShape(Circle())
    }
}
