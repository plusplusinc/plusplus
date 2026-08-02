import SwiftUI
import PlusPlusKit

/// The kit switcher key: the control that names the ACTIVE equipment library
/// and opens the tray to change it.
///
/// A CONTROL, so it always shows the raw kit name even when there is only one
/// (the one-rule naming law; prose uses `EquipmentLibrary.activeNamePhrase`).
/// It rides TWO containers, and wears each one's chrome (2026-08-02): in the
/// catalog tabs' navigation bar it is a plain toolbar control that joins the
/// shared Liquid Glass, and on the PRESENTED catalog's app-drawn kit bar it
/// keeps the raised cap, because that band is app chrome.
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
    var chrome: HeaderKeyChrome = .raised
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
            // The toolbar plates and sizes its own controls; only the
            // app-drawn bar needs a cap drawn for it.
            .padding(.horizontal, chrome == .toolbar ? 0 : 12)
            .frame(height: chrome == .toolbar ? nil : 44)
            .background(switcherChrome)
        }
        .modifier(RaisedUnlessToolbarKey(chrome: chrome))
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var switcherChrome: some View {
        if chrome == .raised {
            RoundedRectangle(cornerRadius: Theme.keyRadius)
                .fill(Theme.background)
                .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
        }
    }
}

/// See `HeaderIconButton`'s twin: a `ButtonStyle` can't be applied
/// conditionally inline, so the branch lives in a modifier.
private struct RaisedUnlessToolbarKey: ViewModifier {
    let chrome: HeaderKeyChrome

    func body(content: Content) -> some View {
        if chrome == .toolbar {
            content
        } else {
            content.buttonStyle(.raisedKey())
        }
    }
}
