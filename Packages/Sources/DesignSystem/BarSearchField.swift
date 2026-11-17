#if os(iOS)
import SwiftUI

/// Search in the navigation bar: one bar item spanning the bar between its margins, with the
/// bar's leading button at its leading edge and a round glass search button with a magnifying
/// glass at its trailing edge. A tap splits a glass field out of the search button's glass, which
/// pulls apart to the left into its own capsule across the bar, focused, with the keyboard coming
/// up, while the button's symbol turns to an X. The X clears the search and the field merges back
/// into the button; so does the keyboard going down with nothing typed. With something typed, the
/// keyboard can go down and the field stays open on the matches. Nothing under the bar moves: a
/// large title stays below.
///
/// The leading button (++ in Exercises, Close in Add exercise) is drawn here, in its own glass,
/// for the field to cover: its leading edge covers the button as it slides over it, and uncovers
/// it as it slides back; with Reduce Motion the button crossfades. While covered, it takes no taps
/// and is hidden from VoiceOver. A button in an item of its own stayed where the bar laid it out,
/// apart from the field's item: the bar lays its items out at once, not along the motion, and an
/// item wider than its room went into a More menu.
///
/// Given a `title`, it draws the bar's inline title too, centered on the screen in the system's
/// inline title font, behind the field, and the host removes the bar's own. The field slides out
/// over the title as it fades, and back off it as it returns, on the field's own curve. The bar's
/// own title dropped out at once as the open field took its room and came back only after the
/// close.
///
/// The system's top bar search does not do this on iPhone. Its round button
/// (`.searchable(placement: .toolbar)`, `.searchToolbarBehavior(.minimize)` and a top trailing
/// `DefaultToolbarItem(kind: .search)`) opens the field above the keyboard and hides the bar.
/// Setting the hosting controller's `searchBarPlacementAllowsToolbarIntegration` to false keeps
/// the field in the bar, but on iOS 27.2 its X closed the field and it opened again by itself
/// half a second later, with or without an `isPresented` binding. Its in-bar search hid Back.
public struct BarSearchField<Leading: View>: View {
    @Binding var text: String
    let prompt: LocalizedStringKey
    /// The item's width, the bar's between its margins.
    let width: CGFloat
    /// The bar's inline title, drawn here for the field to cover; nil when the bar shows its own.
    let title: LocalizedStringKey?
    /// Where the title centers, the screen's middle, in global coordinates.
    let titleCenterX: CGFloat
    /// The bar's leading button, drawn at the item's leading edge for the field to cover. It
    /// brings its own glass (`BarGlassButtonStyle`).
    let leading: Leading

    /// `isOpen` is the host's: the bar reads its item's elements again only as the host's state
    /// changes. Kept inside the item, the open field read as closed to VoiceOver and the UI
    /// tests, and the covered button stayed in reach.
    public init(
        text: Binding<String>,
        isOpen: Binding<Bool>,
        prompt: LocalizedStringKey,
        width: CGFloat,
        title: LocalizedStringKey? = nil,
        titleCenterX: CGFloat = 0,
        @ViewBuilder leading: () -> Leading,
    ) {
        _text = text
        _isOpen = isOpen
        self.prompt = prompt
        self.width = width
        self.title = title
        self.titleCenterX = titleCenterX
        self.leading = leading()
        _hasGlass = State(initialValue: isOpen.wrappedValue)
    }

    @Binding var isOpen: Bool
    /// The item's middle in global coordinates, where the title is laid out; its offset moves it
    /// to the screen's middle. Read from the item, not the title, which its own offset moves.
    @State private var itemMidX: CGFloat = 0
    @State private var titleWidth: CGFloat = 0
    @Environment(\.displayScale) private var displayScale
    /// Whether the field has its glass: from the open's start to the close's end, hidden under
    /// the button's meanwhile.
    @State private var hasGlass: Bool
    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
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
        // resized with the field, the button jumped left and slid back. The item keeps its open
        // width throughout, and the field and button keep to its trailing edge.
        .frame(width: max(width, height), alignment: .trailing)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: {
            // Only a title reads it; without one, the item moves with every frame of a drawer.
            if title != nil {
                itemMidX = $0
            }
        }
        .background { coveredTitle }
        .background { coveredLeading }
        // The caret in green, as the list's own controls; the bar is hosted apart from the list
        // and does not take its tint.
        .tint(.pp(.accent))
        .onChange(of: isFocused) { _, focused in
            if !focused, text.isEmpty, isOpen {
                collapse()
            }
        }
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
                // The bar ignores `accessibilityHidden`: covered, it was still read out.
                .accessibilityShown(!isOpen)
        }
    }

    /// The leading button under the field: cut away where the field's capsule lies over it,
    /// along the field's own motion, so the field's leading edge covers it and uncovers it.
    /// Faded instead, it was gone before the field reached it and back while the field was still
    /// mid-bar, and the field's glass let it show through. With Reduce Motion it crossfades.
    private var coveredLeading: some View {
        leading
            .frame(maxWidth: .infinity, alignment: .leading)
            .mask { fieldCutout }
            .opacity(reduceMotion && isOpen ? 0 : 1)
            .allowsHitTesting(!isOpen)
            .accessibilityShown(!isOpen)
    }

    /// Everything in the item but the field's capsule, laid out as the field is, so it moves on
    /// the same transaction. With Reduce Motion the field does not move, and it cuts nothing.
    private var fieldCutout: some View {
        ZStack(alignment: .trailing) {
            // Past the item's bounds, which the glass's rim and shadow overhang.
            Rectangle().padding(-Spacing.lg)
            HStack(spacing: Spacing.sm) {
                Capsule()
                    .frame(width: fieldFrameWidth, height: height)
                    .offset(x: fieldOffset)
                    .opacity(reduceMotion ? 0 : 1)
                Color.clear.frame(width: height, height: height)
            }
            .blendMode(.destinationOut)
        }
        .compositingGroup()
    }

    private var fieldFrameWidth: CGFloat {
        isOpen || reduceMotion ? fieldWidth : height
    }

    private var fieldOffset: CGFloat {
        isOpen || reduceMotion ? 0 : height + Spacing.sm
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
                .accessibilityIdentifier("barSearch.field")
        }
        .padding(.horizontal, Spacing.md)
        // Laid out at its open width throughout and clipped, so the prompt never reflows as the
        // field opens and closes; it fades.
        .frame(width: fieldWidth, height: height, alignment: .leading)
        .opacity(isOpen ? 1 : 0)
        .frame(width: fieldFrameWidth, alignment: .leading)
        .clipShape(.capsule)
        // With Reduce Motion the field stays where it opens and its glass fades.
        .glassEffect(
            (reduceMotion ? isOpen : hasGlass) ? .regular.interactive() : .identity,
            in: .capsule,
        )
        .offset(x: fieldOffset)
        .allowsHitTesting(isOpen)
        .accessibilityHidden(!isOpen)
    }

    private var button: some View {
        Button(action: toggle) {
            // The symbols swap on the field's own curve, so the X lands as the field does. The
            // system's replace effect keeps its own, longer timing, and closing, it was still
            // turning the X back into the glass well after the field had gone.
            ZStack {
                symbol("magnifyingglass", isShown: !isOpen)
                symbol("xmark", isShown: isOpen)
            }
            .font(.ppBarGlyph)
            .foregroundStyle(.pp(.textPrimary))
        }
        .buttonStyle(.barGlass(width: height))
        .accessibilityLabel(isOpen ? "Close search" : "Search")
        // One identifier for both labels, so a UI test finds the button however it reads.
        .accessibilityIdentifier("barSearch.button")
    }

    private func toggle() {
        if isOpen {
            close()
        } else {
            open()
        }
    }

    private func symbol(_ name: String, isShown: Bool) -> some View {
        Image(systemName: name)
            .scaleEffect(isShown || reduceMotion ? 1 : 0.5)
            .opacity(isShown ? 1 : 0)
    }

    private var fieldWidth: CGFloat {
        max(width - height - Spacing.sm, 0)
    }

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .tapChange
    }

    private func open() {
        hasGlass = true
        withAnimation(motion) { isOpen = true }
        isFocused = true
    }

    private func close() {
        text = ""
        isFocused = false
        collapse()
    }

    private func collapse() {
        withAnimation(motion) {
            isOpen = false
        } completion: {
            if !isOpen {
                hasGlass = false
            }
        }
    }
}

/// A button in the bar's own look, drawn outside the bar's own items: its label centered in its
/// own interactive glass, as tall as the search button and `width` wide, a circle when the two
/// match, all of it taking the tap. The label keeps its own colors: the bar's style tints nothing.
public struct BarGlassButtonStyle: ButtonStyle {
    let width: CGFloat

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: max(width, height), height: height)
            .contentShape(.capsule)
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}

extension ButtonStyle where Self == BarGlassButtonStyle {
    /// `.buttonStyle(.barGlass(width: 0))`: a circle as tall as the search button.
    public static func barGlass(width: CGFloat) -> Self {
        BarGlassButtonStyle(width: width)
    }
}

#Preview {
    @Previewable @State var text = ""
    @Previewable @State var isOpen = false
    NavigationStack {
        List(0 ..< 20, id: \.self) { Text("Row \($0)") }
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    BarSearchField(
                        text: $text,
                        isOpen: $isOpen,
                        prompt: "Search",
                        width: 370,
                    ) {
                        Button("Close", systemImage: "xmark") { }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.barGlass(width: 44))
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}
#endif
