import DesignSystem
import SwiftUI

/// A search field for the navigation bar's middle, in line with Back: a glass capsule as tall as
/// Back, with a magnifying glass, the prompt, and, while searching (the keyboard up or something
/// typed), an X that clears the search and closes the keyboard. The bar stays as it is while
/// searching, so nothing above or below
/// the field moves as search opens and closes.
///
/// It stands in for `.searchable` where the field has to sit beside Back above a large title:
/// on iPhone the system's `.toolbarPrincipal` placement draws the field under the title, and its
/// search item in the top bar (`DefaultToolbarItem(kind: .search, placement: .topBarTrailing)`)
/// is a button whose field, on iOS 27, hid the bar and never showed, even over a plain `List`.
struct BarSearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringKey

    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.pp(.textSecondary))
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            Button {
                text = ""
                isFocused = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.pp(.textSecondary))
            }
            .accessibilityLabel("Close search")
            // Kept laid out and faded, so the field's text never shifts as it comes and goes.
            .opacity(isSearching ? 1 : 0)
            .disabled(!isSearching)
        }
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity, minHeight: height)
        .contentShape(.capsule)
        .onTapGesture { isFocused = true }
        .glassEffect(.regular.interactive(), in: .capsule)
        // The caret in green, as the list's own controls; the bar is hosted apart from the list
        // and does not take its tint.
        .tint(.pp(.accent))
    }

    private var isSearching: Bool {
        isFocused || !text.isEmpty
    }
}

#Preview {
    @Previewable @State var text = ""
    NavigationStack {
        List(0 ..< 20, id: \.self) { Text("Row \($0)") }
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BarSearchField(text: $text, prompt: "Search")
                }
            }
    }
}
