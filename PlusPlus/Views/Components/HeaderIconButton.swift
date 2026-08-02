import SwiftUI
import PlusPlusKit

/// Which chrome a header key wears.
///
/// ⚠️ The split is by CONTAINER, and it is the same scope-by-neighbour rule the
/// search dock established (2026-08-02): a key sitting in the SYSTEM navigation
/// bar wears the system's own treatment and joins the toolbar's shared Liquid
/// Glass, while a key in the app's hand-drawn `pushedScreenChrome` band keeps
/// the raised cap, because that band IS app chrome and a bare glyph would float
/// in it with nothing to sit on.
enum HeaderKeyChrome {
    /// The app's opaque cap on a base plate — pushed headers, sheets, trays.
    case raised
    /// Bare label, no app-drawn ground. The toolbar supplies the glass, the
    /// hit target and the press feedback.
    case toolbar
}

struct HeaderIconButton: View {
    let systemImage: String
    /// Spoken VoiceOver name for the action (required — the glyph alone reads
    /// as its raw SF Symbol name, e.g. "slider horizontal 3").
    let accessibilityLabel: String
    var identifier: String?
    /// Glyph tint; defaults to the neutral header ink. The favorite star
    /// passes `Theme.accent` when lit (green = the user's own data).
    var tint: Color = Theme.textSecondary
    var chrome: HeaderKeyChrome = .raised
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if chrome == .toolbar {
                // ⚠️ NO frame, background, overlay or `.raisedKey()`. The
                // toolbar sizes and plates it, and it supplies the hit target
                // that a bare glyph in a `.frame()` would NOT have on its own
                // (ui-interaction.md's frame-is-not-a-hit-target law) — that
                // law bites only when the app draws the ground and then takes
                // it away, which is exactly what this case avoids doing.
                Image(systemName: systemImage)
            } else {
                Image(systemName: systemImage)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
            }
        }
        .modifier(RaisedUnlessToolbar(chrome: chrome))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier ?? systemImage)
    }
}

/// `.raisedKey()` only where the app draws the key. A `ButtonStyle` cannot be
/// applied conditionally inline (the two arms are different concrete types), so
/// the branch lives in a modifier.
private struct RaisedUnlessToolbar: ViewModifier {
    let chrome: HeaderKeyChrome

    func body(content: Content) -> some View {
        if chrome == .toolbar {
            content
        } else {
            content.buttonStyle(.raisedKey())
        }
    }
}
