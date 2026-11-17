import DesignSystem
import SwiftUI

/// Search in the navigation bar, at its top trailing edge: a round glass button with a magnifying
/// glass, as big as Back. A tap opens a glass field out of it to the left, filling the bar up to
/// Back, focused, with the keyboard coming up, while the button's glass turns to an X. The X
/// clears the search and closes the field back into the button; so does the keyboard going down
/// with nothing typed. With something typed, the keyboard can go down and the field stays open
/// on the matches. Nothing else in the bar or under it moves: the large title stays below.
///
/// The system's top bar search does not do this on iPhone. Its round button
/// (`.searchable(placement: .toolbar)`, `.searchToolbarBehavior(.minimize)` and a top trailing
/// `DefaultToolbarItem(kind: .search)`) opens the field above the keyboard and hides the bar.
/// Setting the hosting controller's `searchBarPlacementAllowsToolbarIntegration` to false keeps
/// the field in the bar, but on iOS 27.2 its X closed the field and it opened again by itself
/// half a second later, with or without an `isPresented` binding.
struct BarSearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringKey
    /// The width the field and the button take together once open.
    let openWidth: CGFloat

    @State private var isOpen = false
    /// Whether the bar item holds the open width: from the open's start to the close's end.
    @State private var isItemWide = false
    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                field
                button
            }
        }
        // The bar sizes its item at once, not along the motion, and centers what it holds:
        // resized with the field, the button jumped left and slid back. The item takes its open
        // width before the field opens and gives it back once it has closed, and the field and
        // button keep to its trailing edge meanwhile.
        .frame(width: itemWidth, alignment: .trailing)
        // The caret in green, as the list's own controls; the bar is hosted apart from the list
        // and does not take its tint.
        .tint(.pp(.accent))
        .onChange(of: isFocused) { _, focused in
            if !focused, text.isEmpty, isOpen {
                collapse()
            }
        }
    }

    private var itemWidth: CGFloat {
        isItemWide ? max(openWidth, height) : height
    }

    private var field: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.pp(.textSecondary))
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, Spacing.md)
        // Laid out at its open width throughout and clipped, so the prompt never reflows as the
        // field opens and closes; it fades.
        .frame(width: fieldWidth, height: height, alignment: .leading)
        .opacity(isOpen ? 1 : 0)
        .frame(width: isOpen ? fieldWidth : 0, alignment: .leading)
        .clipShape(.capsule)
        // Closed to no width, the capsule's glass still drew its edge as a hairline.
        .glassEffect(isOpen ? .regular.interactive() : .identity, in: .capsule)
        .allowsHitTesting(isOpen)
        .accessibilityHidden(!isOpen)
    }

    private var button: some View {
        Button {
            if isOpen {
                close()
            } else {
                open()
            }
        } label: {
            Image(systemName: isOpen ? "xmark" : "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(.pp(.textPrimary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: height, height: height)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(isOpen ? "Close search" : "Search")
    }

    private var fieldWidth: CGFloat {
        max(openWidth - height - Spacing.sm, 0)
    }

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .snappy
    }

    private func open() {
        isItemWide = true
        withAnimation(motion) { isOpen = true }
        isFocused = true
    }

    private func close() {
        text = ""
        isFocused = false
        collapse()
    }

    /// Closes the field into the button. Should the completion come early, the narrowed item
    /// still draws the closing field past its leading edge; it only stops taking touches there.
    private func collapse() {
        withAnimation(motion) {
            isOpen = false
        } completion: {
            if !isOpen {
                isItemWide = false
            }
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    NavigationStack {
        List(0 ..< 20, id: \.self) { Text("Row \($0)") }
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    BarSearchField(text: $text, prompt: "Search", openWidth: 300)
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}
