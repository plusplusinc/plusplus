#if os(iOS)
import SwiftUI

/// Search in the navigation bar: one bar item spanning the bar between its margins, with the
/// bar's leading button at its leading edge and a round glass search button with a magnifying
/// glass at its trailing edge. A tap turns the leading button (Close, in Add exercise) into a
/// glass field across the bar, focused, with the keyboard coming up: the
/// system's glass morph stretches the button's glass to the right into the field's capsule, its
/// label blurring into the field's, while the search button's symbol turns to an X. The field's
/// trailing end runs on into the search button's glass, the two fused for a moment, and pulls
/// back off it to rest. The X clears the search and runs it backward: the field's end meets the
/// search button, then the field shrinks back into the leading button; so does the keyboard going
/// down with nothing typed. With something typed, the keyboard can go down and the field stays
/// open on the matches. Nothing under the bar moves: a large title stays below. With Reduce
/// Motion the button and the field crossfade.
///
/// The leading button is drawn here, not in an item of its own, for the field to take its place:
/// an item of its own stayed where the bar laid it out, apart from the field's item, since the
/// bar lays its items out at once, not along the motion, and an item wider than its room went into
/// a More menu. A mask cutting the button away under the field's edge, and later its glass
/// absorbed into the field's as the field slid over it, read as the field covering the button
/// rather than taking it over.
///
/// Given a `title`, it draws the bar's inline title too, centered on the screen in the system's
/// inline title font, behind the field, and the host removes the bar's own. The field stretches
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
    /// The bar's leading button, drawn at the item's leading edge for the field to take over. It
    /// brings its own glass (`BarGlassButtonStyle`).
    let leading: Leading

    /// `isOpen` is the host's: the bar reads its item's elements again only as the host's state
    /// changes. Kept inside the item, the open field read as closed to VoiceOver and the UI
    /// tests.
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
    }

    @Binding var isOpen: Bool
    /// Whether the field's glass reaches on into the search button's, fused with it.
    @State private var meetsButton = false
    /// The wait before the field's end pulls back off the search button, or before the field
    /// goes once its end has met it.
    @State private var meeting: Task<Void, Never>?
    @Namespace private var glass
    /// The item's middle in global coordinates, where the title is laid out; its offset moves it
    /// to the screen's middle. Read from the item, not the title, which its own offset moves.
    @State private var itemMidX: CGFloat = 0
    @State private var titleWidth: CGFloat = 0
    @Environment(\.displayScale) private var displayScale
    @FocusState private var isFocused: Bool
    /// Set by the tap that opens the field, for it to take focus as it appears; not when it
    /// appears again as the host comes back from a pushed screen, keyboard down.
    @State private var focusesOnAppear = false

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        // The leading button leaves as the field arrives, in one transaction, and the two share a
        // glass ID, so the container morphs one's glass into the other's. The container's spacing
        // matches the gap, so at rest the field and the search button stay apart, and blend while
        // the field's end reaches into the button.
        GlassEffectContainer(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                if isOpen {
                    field
                } else {
                    leading
                        .glassEffectID(GlassID.leading, in: glass)
                        .glassEffectTransition(glassTransition)
                    Spacer(minLength: 0)
                }
                button
            }
            // The bar sizes its item at once, not along the motion, and centers what it holds:
            // resized with the field, the button jumped left and slid back. The item keeps its
            // open width throughout, and the field and button keep to its trailing edge.
            .frame(width: max(width, height), alignment: .trailing)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: {
            // Only a title reads it.
            if title != nil {
                itemMidX = $0
            }
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

    /// Fades on the field's curve as the field stretches over it, and back as the field leaves it;
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

    /// The system's morph between the leading button and the field; with Reduce Motion each one's
    /// glass fades in or out where it is.
    private var glassTransition: GlassEffectTransition {
        reduceMotion ? .materialize : .matchedGeometry
    }

    /// How far the field's glass reaches past its own end while it meets the search button: over
    /// the gap and into the button's glass.
    private var meetingReach: CGFloat {
        meetsButton ? Spacing.sm + Self.meetingOverlap : 0
    }

    private static var meetingOverlap: CGFloat {
        10
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
                .accessibilityShown(false)
            TextField(prompt, text: $text)
                .focused($isFocused)
                .submitLabel(.search)
                // As the system's search field: a search matches either case, and a capital
                // at the start only takes a Shift to undo.
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(Text(prompt))
                .accessibilityIdentifier("barSearch.field")
        }
        .padding(.horizontal, Spacing.md)
        .frame(width: fieldWidth + meetingReach, height: height, alignment: .leading)
        // Not `interactive()`: with it, the field came in whole, with no morph and no transition
        // at all, in the bar or out of it.
        .glassEffect(.regular, in: .capsule)
        .glassEffectID(GlassID.leading, in: glass)
        .glassEffectTransition(glassTransition)
        // Laid out at its own width, so the reach runs under the button without moving it.
        .padding(.trailing, -meetingReach)
        // Arrives with this update, so it takes focus as it appears.
        .onAppear {
            if focusesOnAppear {
                focusesOnAppear = false
                isFocused = true
            }
        }
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
            // The button's label says what it does; the symbols, one of them faded out, were
            // read as images of their own.
            .accessibilityShown(false)
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

    /// The field arrives already reaching into the search button, so the morph runs its end into
    /// the button's glass; once it has arrived, it pulls back to rest.
    private func open() {
        meeting?.cancel()
        focusesOnAppear = true
        withAnimation(motion) {
            isOpen = true
            meetsButton = !reduceMotion
        }
        guard !reduceMotion else { return }
        meeting = Task {
            try? await Task.sleep(for: Self.arrival, tolerance: .zero)
            guard !Task.isCancelled else { return }
            withAnimation(motion) { meetsButton = false }
        }
    }

    /// How long the field's end takes to reach the search button, on `tapChange`.
    private static var arrival: Duration {
        .seconds(0.22)
    }

    /// The field shrinking back into the leading button. It starts slowly, so the field's end
    /// pulls off the search button's glass rather than snapping off it: on `tapChange`, whose
    /// spring starts fast, the two parted between one frame and the next.
    private static var closing: Animation {
        .easeInOut(duration: 0.28)
    }

    /// How long the field's end takes to meet the search button before the field goes. The field
    /// leaves the hierarchy at once, so its end has to be in the button's glass first.
    private static var meetingBeforeClose: Duration {
        .seconds(0.04)
    }

    private func close() {
        text = ""
        isFocused = false
        collapse()
    }

    private func collapse() {
        meeting?.cancel()
        guard !reduceMotion else {
            withAnimation(motion) { isOpen = false }
            return
        }
        withAnimation(motion) { meetsButton = true }
        meeting = Task {
            try? await Task.sleep(for: Self.meetingBeforeClose, tolerance: .zero)
            guard !Task.isCancelled else { return }
            withAnimation(Self.closing) {
                isOpen = false
                meetsButton = false
            }
        }
    }
}

/// The glass the leading button and the field share, so the container morphs one into the other.
private nonisolated enum GlassID: Hashable {
    case leading
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
            .navigationTitle("Add exercise")
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
