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
            .padding(.horizontal, 14)
            .frame(height: 48)
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
                    // Green only while it creates (#202); the escape
                    // hatch is neutral chrome.
                    .foregroundStyle(focused ? Theme.textPrimary : Theme.accent)
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
    }
}
