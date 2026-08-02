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
/// The anatomy is the app's one search-field grammar, unchanged: an in-field
/// `delete.left` CLEAR that empties the query and keeps you typing, and a
/// separate `xmark` COLLAPSE key that clears AND closes, sitting exactly where
/// the magnifier was. `xmark` means "collapse the search" here as everywhere,
/// which is why a sheet never dismisses with one.
///
/// The morph follows the anytime card (design-grammar, 2026-08-01): the CHROME
/// travels via `matchedGeometryEffect`, the contents crossfade. Never match the
/// content views — text reflows mid-flight — and never a measured flip.
struct CatalogSearchDock: View {

    /// The shared id for the travelling ground. Lives here because
    /// `SearchFieldBody` (the expanded half) defaults to it.
    static let chromeID = "catalogSearchChrome"

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
        // ⚠️ A ZStack with explicit transitions and a zIndex, NOT a bare
        // `Group { if/else }` — the anytime card's shape, and for its reasons.
        // A plain branch swap leaves both matched shapes inserted in the same
        // frame with nothing saying which draws on top, so the outgoing
        // magnifier can paint over the incoming field mid-morph.
        ZStack(alignment: .topTrailing) {
            if isOpen {
                openField
                    .zIndex(1)
                    .transition(.opacity)
            } else {
                searchKey
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // No band behind the dock: both states bring their own opaque chrome,
        // so the `.soft` bottom scroll edge effect keeps doing its job under
        // them. A solid strip here would be the full-width slab build 148
        // killed, one row higher.
        .padding(.bottom, 6)
    }

    private var openField: some View {
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
                morph: morph
            )
            // ⚠️ The field is 44 pt tall and a raised key is 48 — `RaisedKeyStyle`
            // pads the bottom by its 4 pt travel to leave room for the plate, so
            // a centred `HStack` seats the field's cap 2 pt BELOW the key's.
            // Match the padding and the two line up, at rest and at the end of
            // the morph. (The retired `.principal` scope row carried exactly
            // this compensation for exactly this reason.)
            .padding(.bottom, 4)
            HeaderIconButton(
                systemImage: "xmark",
                accessibilityLabel: "Close search",
                identifier: "catalogDockCloseButton"
            ) {
                query = ""
                withAnimation(Theme.Anim.selection) { isOpen = false }
            }
        }
    }

    /// The collapsed key, seated at the trailing edge so it sits above the
    /// RIGHTMOST tab and the collapse key lands back on this exact spot.
    ///
    /// Built here rather than reusing `HeaderIconButton` for one reason: its
    /// ground has to carry the `matchedGeometryEffect` that pairs it with the
    /// field. Everything else — 44 pt cap, r11, `Theme.background` fill,
    /// `borderStrong` stroke, raised travel — is that component's anatomy, kept
    /// identical so the dock key reads as one of the app's icon keys.
    ///
    /// ⚠️ Trailing ALIGNMENT, never an `HStack` + `Spacer`. The dock is a
    /// `safeAreaInset`, so list rows scroll under it and stay visible through
    /// the empty side of this row — and a spacer there is a standing full-width
    /// layer over live rows, which is the hit-testing-ghost class XCUITest
    /// cannot see (ui-interaction.md).
    ///
    /// ⚠️ The FILL differs between the two states on purpose (a key wears
    /// `background`, a field wears `surface`) and that is fine: geometry is
    /// what the effect matches, and the two grounds crossfade as the branches
    /// swap.
    private var searchKey: some View {
        Button {
            wantsFocus = true
            withAnimation(Theme.Anim.selection) { isOpen = true }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Theme.keyRadius)
                        .fill(Theme.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.keyRadius)
                                .strokeBorder(Theme.borderStrong)
                        )
                        .matchedGeometryEffect(id: Self.chromeID, in: morph)
                )
        }
        .buttonStyle(.raisedKey())
        .accessibilityLabel("Search")
        .accessibilityIdentifier("catalogSearchToggle")
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
