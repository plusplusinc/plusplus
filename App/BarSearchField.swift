import DesignSystem
import SwiftUI

/// Search in the navigation bar, at its top trailing edge: a round glass button with a magnifying
/// glass, as big as ++. A tap splits a glass field out of the button's glass, which pulls apart
/// to the left into its own capsule filling the bar up to ++, focused, with the keyboard coming
/// up, while the button's symbol turns to an X. The X clears the search and the field merges back
/// into the button; so does the keyboard going down with nothing typed. With something typed, the
/// keyboard can go down and the field stays open on the matches. Nothing else in the bar or under
/// it moves: the large title stays below.
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
        // Closed, the field's glass is a circle under the button's; opening pulls it out to the
        // left, and the container blends the two shapes while they are near, so the field splits
        // off the button and merges back into it. The container's spacing matches the gap, so at
        // rest the two stay apart. The container's own morph (`glassEffectID` with an inserted
        // field) only materialized the field in place here, in a bar item.
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

    private var hasFieldGlass: Bool {
        reduceMotion ? isOpen : isItemWide
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
        .frame(width: isOpen || reduceMotion ? fieldWidth : height, alignment: .leading)
        .clipShape(.capsule)
        // Its glass is there only from the open's start to the close's end, hidden under the
        // button's meanwhile. With Reduce Motion the field stays where it opens and its glass
        // fades.
        .glassEffect(hasFieldGlass ? .regular.interactive() : .identity, in: .capsule)
        .offset(x: isOpen || reduceMotion ? 0 : height + Spacing.sm)
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
            // The symbols swap on the field's own curve, so the X lands as the field does. The
            // system's replace effect keeps its own, longer timing, and closing, it was still
            // turning the X back into the glass well after the field had gone.
            ZStack {
                symbol("magnifyingglass", isShown: !isOpen)
                symbol("xmark", isShown: isOpen)
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.pp(.textPrimary))
            .frame(width: height, height: height)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(isOpen ? "Close search" : "Search")
    }

    private func symbol(_ name: String, isShown: Bool) -> some View {
        Image(systemName: name)
            .scaleEffect(isShown || reduceMotion ? 1 : 0.5)
            .opacity(isShown ? 1 : 0)
    }

    private var fieldWidth: CGFloat {
        max(openWidth - height - Spacing.sm, 0)
    }

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .tapChange
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

    /// Merges the field back into the button. Should the completion come early, the narrowed item
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
