import SwiftUI

/// The Messages-pattern bottom search dock (#214): a floating Liquid
/// Glass capsule field with the tab's create affordance in a glass
/// circle beside it. While the field is focused, the circle morphs
/// into ✕ — the escape hatch the header search never had (#213):
/// it unfocuses, clears the query, and hands the tab bar back.
/// Attach via `.safeAreaInset(edge: .bottom)` on the tab's list so
/// rows scroll beneath the glass and the dock rides above the
/// keyboard for free.
struct SearchDock: View {
    let prompt: String
    @Binding var text: String
    var addIdentifier: String?
    let onAdd: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.textFaint)
                TextField(prompt, text: $text)
                    .font(.system(.subheadline))
                    .autocorrectionDisabled()
                    .focused($focused)
                    // Not "searchField": CatalogBrowseScreen pushes its
                    // own SearchField over this tab, and two live copies
                    // of one identifier is a firstMatch coin flip.
                    .accessibilityIdentifier("librarySearchField")
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
            .padding(.horizontal, 14)
            .frame(height: 48)
            // The whole capsule focuses, like Messages — not just the
            // text glyphs (controls inside still win hit-testing).
            .contentShape(Capsule())
            .onTapGesture { focused = true }
            .glassEffect(.regular, in: Capsule())

            Button {
                if focused {
                    focused = false
                    text = ""
                } else {
                    onAdd()
                }
            } label: {
                Image(systemName: focused ? "xmark" : "plus")
                    .font(.system(.body, weight: .semibold))
                    // Same chrome as the glass back chevron (#224,
                    // Dave) — glass circles speak one color; green
                    // stays on in-content creation affordances.
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .glassEffect(.regular.interactive(), in: Circle())
            .animation(.easeOut(duration: 0.15), value: focused)
            .accessibilityIdentifier(focused ? "dismissSearchButton" : (addIdentifier ?? ""))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        // Pushing a detail screen must not carry the keyboard along —
        // the root (and this dock) stay alive under the push, so the
        // focused field would keep first responder with no visible
        // field and no way off (reviewer catch).
        .onDisappear { focused = false }
    }
}
