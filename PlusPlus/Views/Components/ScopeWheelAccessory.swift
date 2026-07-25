import SwiftUI

/// The catalog scope picker, riding in the TabView's bottom accessory.
///
/// With only two tabs — Today and Search — the three catalogs stop being tabs
/// and become a SCOPE you dial (Dave, 2026-07-25). The wheel is that dial, and
/// the accessory slot is where the system agrees to put app content next to its
/// own bar, so the chrome around it stays the platform's: hit targets,
/// Liquid Glass, scroll-edge legibility and home-indicator clearance all come
/// free, which is exactly what three rounds of hand-drawn bar kept getting
/// wrong.
///
/// The system decides the PLACEMENT and hands it down as an environment value;
/// the app only adapts to it. `.expanded` puts the accessory in its own row
/// above a full tab bar. `.inline` puts it in the bar's own row, alongside a
/// minimized bar — which with two tabs reads as the wheel sitting BETWEEN Today
/// and Search, the arrangement the hand-drawn bar existed to draw. Placement
/// follows `tabBarMinimizeBehavior`, so it is scroll-driven: this is the
/// Podcasts two-mode behaviour, not something the app can pin.
struct ScopeWheelAccessory: View {
    @Binding var scope: FindScope
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var compact: Bool { placement == .inline }

    var body: some View {
        InlineWheelPicker(
            options: FindScope.allCases.map(\.label),
            selectedIndex: Binding(
                get: { FindScope.allCases.firstIndex(of: scope) ?? 0 },
                set: { scope = FindScope.allCases[$0] }
            ),
            symbols: FindScope.allCases.map { $0.symbolName },
            identifiers: FindScope.allCases.map { "scopeWheel-\($0.rawValue)" },
            compact: compact
        )
        // Chrome that has to hold a word on one row can't grow without bound;
        // the search field is NOT capped, since its text is the user's own.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel("Catalog")
    }
}
