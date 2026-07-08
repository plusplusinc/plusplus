import SwiftUI

/// The one search affordance (#85): magnifier, field, clear button, in
/// the v2 control style. Used by the exercise picker, the Library, and
/// the catalog sheet so search reads identically everywhere. The
/// "searchField" identifier is what the smoke tests type into.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    /// Screens sitting on Theme.background use the surface fill; sheets
    /// sitting on Theme.surface invert to the background fill.
    var fill: Color = Theme.surface

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(.footnote))
                .foregroundStyle(Theme.textFaint)
            TextField(prompt, text: $text)
                .font(.system(.subheadline))
                .autocorrectionDisabled()
                .accessibilityIdentifier("searchField")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textFaint)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
    }
}
