import SwiftUI
import PlusPlusKit

struct HeaderIconButton: View {
    let systemImage: String
    /// Spoken VoiceOver name for the action (required — the glyph alone reads
    /// as its raw SF Symbol name, e.g. "slider horizontal 3").
    let accessibilityLabel: String
    var identifier: String?
    /// Glyph tint; defaults to the neutral header ink. The favorite star
    /// passes `Theme.accent` when lit (green = the user's own data).
    var tint: Color = Theme.textSecondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(.raisedKey())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier ?? systemImage)
    }
}
