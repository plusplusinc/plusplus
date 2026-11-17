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
/// Given a `title`, it draws the bar's inline title itself, centered on the screen in the
/// system's inline title font, behind the field, and the host removes the bar's own. The field
/// slides out over the title as it fades, so the title reads as covered, and back off it as it
/// returns, on the field's own curve. The bar's own title dropped out at once as the open field
/// took its room and came back only after the close: the bar lays its items out at once, not
/// along the motion. With a title the item keeps its open width throughout, so the bar never
/// lays out again; only the button takes touches in it while closed.
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
    /// The bar's inline title, drawn here for the field to cover; nil when the bar shows its own.
    var title: LocalizedStringKey?
    /// Where the title centers, the screen's middle, in global coordinates.
    var titleCenterX: CGFloat = 0

    @State private var isOpen = false
    /// The item's middle in global coordinates, where the title is laid out; its offset moves it
    /// to the screen's middle. Read from the item, not the title, which its own offset moves.
    @State private var itemMidX: CGFloat = 0
    @State private var titleWidth: CGFloat = 0
    @Environment(\.displayScale) private var displayScale
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
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: {
            itemMidX = $0
        }
        .background { coveredTitle }
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
        isItemWide || title != nil ? max(openWidth, height) : height
    }

    /// Fades on the field's curve as the field slides over it, and back as the field leaves it;
    /// with Reduce Motion the two crossfade.
    @ViewBuilder
    private var coveredTitle: some View {
        if let title {
            Text(title)
                .font(.ppBarTitle)
                .foregroundStyle(.pp(.textPrimary))
                .lineLimit(1)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { titleWidth = $0 }
                .offset(x: titleOffset)
                .opacity(isOpen ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHidden(isOpen)
        }
    }

    /// From the item's middle to the screen's, with the title's leading edge on the pixel below,
    /// as the bar places its own: rounded to the nearest, it sat a pixel to the right.
    private var titleOffset: CGFloat {
        let leading = titleCenterX - titleWidth / 2
        return (leading * displayScale).rounded(.down) / displayScale
            - (itemMidX - titleWidth / 2)
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
