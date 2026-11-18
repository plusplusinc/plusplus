#if os(iOS)
import SwiftUI

/// Search in the navigation bar: one bar item spanning the bar between its margins, with the
/// bar's leading button at its leading edge and a round glass search button with a magnifying
/// glass at its trailing edge. A tap grows the search button's glass to the left into a field,
/// focused, with the keyboard coming up. As its leading end reaches the leading button (++ in
/// Exercises, Close in Add exercise), the two glasses join with a neck and fuse, the button's
/// label fading and its glass shrinking into the field's end; at about the same moment a round
/// piece of the field's trailing end pinches off with a neck and rests where the search button
/// was, as an X. It is one motion on one curve (`BarSearchMotion`, `BarSearchTiming`), with no
/// beats between. The X clears the search and runs the same motion back; so does the keyboard
/// going down with nothing typed. With something typed, the keyboard can go down and the field
/// stays open on the matches. Nothing under the bar moves: a large title stays below. With Reduce
/// Motion the two ends crossfade.
///
/// The leading button is drawn here, not in an item of its own, for the field to take its place:
/// an item of its own stayed where the bar laid it out, since the bar lays its items out at once,
/// not along the motion.
///
/// Given a `title`, it draws the bar's inline title too, centered on the screen in the system's
/// inline title font, behind the field, and the host removes the bar's own. The title fades as the
/// field's end crosses it, and back as it returns. The bar's own title dropped out at once as the
/// open field took its room.
///
/// The system's top bar search does not do this on iPhone: its round button opens the field
/// above the keyboard and hides the bar. Kept in the bar (the hosting controller's
/// `searchBarPlacementAllowsToolbarIntegration` false), on iOS 27.2 its X closed the field and it
/// opened again half a second later. Its in-bar search hid Back.
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
    /// tests. It turns at the tap, both ways.
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
        // From its first frame where the host has it, as a snapshot of the open field does.
        _progress = State(initialValue: isOpen.wrappedValue ? 1 : 0)
        self.prompt = prompt
        self.width = width
        self.title = title
        self.titleCenterX = titleCenterX
        self.leading = leading()
    }

    @Binding var isOpen: Bool
    /// 0 closed, 1 open; set in the tap's animation, and drawn along it by `BarSearchProgress`.
    @State private var progress: CGFloat
    /// The leading button's width, for where the field's leading end meets it.
    @State private var leadingWidth: CGFloat = 0
    @Namespace private var glass
    /// The item's middle in global coordinates, where the title is laid out; its offset moves it
    /// to the screen's middle. Read from the item, not the title, which its own offset moves.
    @State private var itemMidX: CGFloat = 0
    @State private var titleWidth: CGFloat = 0
    @Environment(\.displayScale) private var displayScale
    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        BarSearchProgress(progress: progress, isReduced: reduceMotion) { progress in
            let motion = BarSearchMotion(
                progress: progress,
                itemWidth: itemWidth,
                height: height,
                leadingWidth: leadingWidth,
            )
            return glasses(motion)
                .background { coveredTitle(motion) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: {
            // Only a title reads it; without one, the item moves with every frame of a drawer.
            if title != nil {
                itemMidX = $0
            }
        }
        // The caret in green, as the list's own controls; the bar is hosted apart from the list
        // and does not take its tint.
        .tint(.pp(.accent))
        .onChange(of: isFocused) { _, focused in
            if !focused, text.isEmpty, isOpen {
                move(open: false)
            }
        }
    }

    /// Glass shapes in one container closer than its spacing blend with a neck between them. The
    /// search glass is one shape throughout, the round button closed and the field open; the X's
    /// glass and the leading button's come and go beside it, at rest and under the field. All
    /// three are plain glass while the motion runs: interactive glass showed as a layer where two
    /// met. Each stops being interactive at the tap, not as the motion leaves its end: the press's
    /// own bounce held the search glass where it was for about 0.12 s before it grew.
    private func glasses(_ motion: BarSearchMotion) -> some View {
        let isClosed = !isOpen && motion.progress == 0
        return GlassEffectContainer(spacing: motion.spacing) {
            ZStack(alignment: .leading) {
                if motion.showsLeading {
                    leading
                        .environment(\.barGlassInteractive, isClosed)
                        .environment(\.barGlassLabelOpacity, motion.leadingLabelOpacity)
                        // Taken in by the field's leading end: the system's morph of a removed
                        // glass into a neighbor dropped it in one frame, a glass union of the two
                        // held the field's motion back in Add exercise until it jumped, and drawn
                        // smaller under the field it showed through as a darker blob.
                        .environment(\.barGlassWidth, motion.leadingGlassWidth)
                        .onGeometryChange(for: CGFloat.self, of: \.size.width) {
                            leadingWidth = $0
                        }
                        .glassEffectID(GlassID.leading, in: glass)
                        .glassEffectTransition(glassTransition)
                        .transition(viewTransition)
                        .accessibilityShown(!isOpen)
                }
                searchGlass(motion)
                if motion.showsX {
                    glyph("xmark", shown: motion.xSymbol)
                        // Narrower than a circle while it fills in behind the field's end.
                        .frame(width: itemWidth - motion.xStart, alignment: .trailing)
                        .clipped()
                        .glassEffect(
                            .regular.interactive(isOpen && motion.progress == 1),
                            in: .capsule,
                        )
                        .glassEffectID(GlassID.x, in: glass)
                        .glassEffectTransition(glassTransition)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(viewTransition)
                }
                button
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            // The bar sizes its item at once, not along the motion, and centers what it holds:
            // resized with the field, the button jumped left and slid back. The item keeps its
            // open width throughout.
            .frame(width: itemWidth, alignment: .leading)
        }
    }

    /// Fades as the field's end crosses it, and back as the end leaves it; with Reduce Motion the
    /// two crossfade.
    @ViewBuilder
    private func coveredTitle(_ motion: BarSearchMotion) -> some View {
        if let title {
            Text(title)
                .font(.ppBarTitle)
                .foregroundStyle(.pp(.textPrimary))
                .lineLimit(1)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { titleWidth = $0 }
                .offset(x: titleOffset)
                .opacity(reduceMotion ? (isOpen ? 0 : 1) : motion.titleOpacity)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.isHeader)
                // The bar ignores `accessibilityHidden`: covered, it was still read out.
                .accessibilityShown(!isOpen)
        }
    }

    private var itemWidth: CGFloat {
        max(width, height)
    }

    /// The leading button's glass and the X's come and go only inside the field's, so nothing of
    /// them shows; with Reduce Motion each fades in or out where it is.
    private var glassTransition: GlassEffectTransition {
        reduceMotion ? .materialize : .identity
    }

    private var viewTransition: AnyTransition {
        reduceMotion ? .opacity : .identity
    }

    /// From the item's middle to the screen's, with the title's leading edge on the pixel below,
    /// as the bar places its own: rounded to the nearest, it sat a pixel to the right.
    private var titleOffset: CGFloat {
        let leading = titleCenterX - titleWidth / 2
        return (leading * displayScale).rounded(.down) / displayScale
            - (itemMidX - titleWidth / 2)
    }

    /// The search button's glass, which grows into the field's and back. With Reduce Motion it is
    /// a new glass at each end, so the two crossfade rather than move.
    private func searchGlass(_ motion: BarSearchMotion) -> some View {
        ZStack(alignment: .leading) {
            // From the tap that opens it, for it to take focus at once, until the search glass is
            // back to the button. Read by VoiceOver while it closes too: hidden with
            // `accessibilityShown`, whose representation is a second copy of the field, the two
            // shared one focus and neither took it.
            if isOpen || motion.progress > 0 {
                field
                    .opacity(reduceMotion ? 1 : motion.fieldOpacity)
            }
        }
        .frame(width: motion.searchEnd - motion.searchStart, height: height, alignment: .leading)
        // At the glass's own trailing end: in the stack, the field's open width carried it past
        // the glass's end as the field closed, and it was clipped away.
        .overlay(alignment: .trailing) {
            glyph("magnifyingglass", shown: motion.searchSymbolOpacity)
        }
        .clipped()
        // Interactive, as the bar's buttons are, only at rest as the button.
        .glassEffect(.regular.interactive(!isOpen && motion.progress == 0), in: .capsule)
        .glassEffectID(GlassID.search, in: glass)
        .glassEffectTransition(.materialize)
        .padding(.leading, motion.searchStart)
        .id(reduceMotion && isOpen)
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
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: max(itemWidth - height - Spacing.sm, 0), alignment: .leading)
        .transition(.opacity)
        // Arrives with the tap, so it takes focus as it appears.
        .onAppear { isFocused = true }
    }

    /// Takes the tap over the search glass, closed, and the X's, open, which draw its symbols:
    /// drawn apart from the button, for the one to grow into the field and the other to split
    /// off it. Over the glass, the symbols were dimmed by it.
    private var button: some View {
        Button {
            if isOpen {
                text = ""
                isFocused = false
            }
            move(open: !isOpen)
        } label: {
            Color.clear
                .frame(width: height, height: height)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOpen ? "Close search" : "Search")
        // One identifier for both labels, so a UI test finds the button however it reads.
        .accessibilityIdentifier("barSearch.button")
    }

    /// The search button's symbol, or the X's, in a circle at its glass's trailing end, growing
    /// and fading in along the motion. The button's label says what it does, so they are not
    /// read.
    private func glyph(_ name: String, shown: CGFloat) -> some View {
        Image(systemName: name)
            .font(.ppBarGlyph)
            .foregroundStyle(.pp(.textPrimary))
            .scaleEffect(reduceMotion ? 1 : 0.5 + 0.5 * shown)
            .opacity(shown)
            .frame(width: height, height: height)
            .accessibilityShown(false)
    }

    private func move(open: Bool) {
        guard open != isOpen else { return }
        withAnimation(reduceMotion ? BarSearchTiming.crossfade : BarSearchTiming.moving) {
            isOpen = open
            progress = open ? 1 : 0
        }
    }
}

/// Draws `BarSearchField` at every frame of its motion from the progress the animation has
/// reached, the container's spacing included: the container takes its spacing only as set in an
/// update, not along an animation, and here every frame is an update. With Reduce Motion it
/// offers nothing to animate, so the progress lands at once and the field's ends crossfade.
private struct BarSearchProgress<Content: View>: View, Animatable {
    var progress: CGFloat
    let isReduced: Bool
    let content: (CGFloat) -> Content

    var animatableData: CGFloat {
        get { isReduced ? 0 : progress }
        set {
            if !isReduced {
                progress = newValue
            }
        }
    }

    var body: some View {
        content(progress)
    }
}

/// The glass shapes that come and go, each with an identity of its own for the container.
private nonisolated enum GlassID: Hashable {
    case leading
    case search
    case x
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
