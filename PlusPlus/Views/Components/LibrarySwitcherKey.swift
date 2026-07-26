import SwiftUI
import PlusPlusKit

/// The kit switcher key: the control that names the ACTIVE equipment library
/// and opens the tray to change it.
///
/// A CONTROL, so it always shows the raw kit name even when there is only one
/// (the one-rule naming law; prose uses `EquipmentLibrary.activeNamePhrase`).
/// It rides the catalog tabs' navigation bar as a toolbar item that opts out of
/// the toolbar's shared glass, since it brings its own key chrome.
///
/// (This file used to hold `CatalogTabHeader` — the hand-drawn tab-root header
/// with the ++ key and large on-row title. That is DELETED as of 2026-07-26:
/// the catalog tabs wear the SYSTEM navigation bar now, because hiding it is
/// what left `.searchable` and its scope bar with nowhere to render.)

struct LibrarySwitcherKey: View {
    let name: String
    /// Distinct per call site (the same switcher now rides four surfaces), so
    /// a future smoke test visiting more than one doesn't hit a multiple-match
    /// on a shared identifier (swift review).
    var identifier: String = "librarySwitcherButton"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(name)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    // A long kit name shrinks a touch, then TRUNCATES here
                    // rather than crowding the title off the row (Dave,
                    // 2026-07-20) — the navigation bar gives the title its
                    // space first, so the switcher is what yields. NO hard
                    // `maxWidth` cap: that
                    // frame is greedy in this HStack (it competes with the
                    // Spacer) and would leave a gap before the chevron for
                    // short names like the default "main" (swift-reviewer catch).
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(.raisedKey())
        .accessibilityIdentifier(identifier)
    }
}
