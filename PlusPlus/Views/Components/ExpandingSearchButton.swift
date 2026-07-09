import SwiftUI

/// Catalog search, take three (#233): a top-right circular magnifier
/// that expands in place into a field + ✕. It lives in the toolbar's
/// TRAILING slot, so expansion can cover the inline title but can
/// never reach the back chevron (leading slot) — Dave's constraint by
/// construction. ✕ clears, unfocuses, and collapses. Library views
/// have no search at all; this appears only on catalog surfaces.
struct ExpandingSearchButton: View {
    let prompt: String
    @Binding var text: String
    var identifier: String = "searchField"

    @State private var expanded = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            if expanded {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textFaint)
                    TextField(prompt, text: $text)
                        .font(.system(.subheadline))
                        .autocorrectionDisabled()
                        .focused($focused)
                        .frame(minWidth: 130, maxWidth: 200)
                        .accessibilityIdentifier(identifier)
                }
                // Focus is requested from the field's own appearance —
                // requesting it in the button action targets a view not
                // yet installed and is silently dropped (reviewer catch).
                .onAppear { focused = true }
                Button {
                    text = ""
                    focused = false
                    withAnimation(.easeOut(duration: 0.15)) { expanded = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.footnote, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("dismissSearchButton")
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { expanded = true }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(.body, weight: .semibold))
                }
                .accessibilityIdentifier("\(identifier)Toggle")
            }
        }
        // A push while focused must not strand the keyboard (the #213
        // lesson, inherited from the dock this control replaces).
        .onDisappear { focused = false }
    }
}
