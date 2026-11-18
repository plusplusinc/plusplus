#if os(iOS)
import SwiftUI

/// Search in the navigation bar: one bar item spanning the bar between its margins, with the
/// bar's leading button at its leading edge and a round glass search button with a magnifying
/// glass at its trailing edge. A tap grows the search button's glass to the left into a field,
/// focused, with the keyboard coming up. As its leading end reaches the leading button (++ in
/// Exercises, Close in Add exercise), the two glasses join with a neck and fuse, the button's
/// label fading, and the field takes its place; at about the same moment a round piece of the
/// field's trailing end pinches off with a neck and rests where the search button was, as an X.
/// The X clears the search and runs it backward: the X runs back into the field's end, then the
/// field shrinks onto the search button, the leading button pulling out of its leading end with
/// a neck as it passes; so does the keyboard going down with nothing typed. With something
/// typed, the keyboard can go down and the field stays open on the matches. Nothing under the
/// bar moves: a large title stays below. With Reduce Motion the two ends crossfade.
///
/// The leading button is drawn here, not in an item of its own, for the field to take its place:
/// an item of its own stayed where the bar laid it out, since the bar lays its items out at once,
/// not along the motion.
///
/// Given a `title`, it draws the bar's inline title too, centered on the screen in the system's
/// inline title font, behind the field, and the host removes the bar's own. The field stretches
/// over the title as it fades, and back off it as it returns. The bar's own title dropped out at
/// once as the open field took its room.
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
    /// The beat an opening or closing is in; nil at rest, where `isOpen` says which end it is.
    @State private var beat: BarSearchStage?
    /// The wait before the next beat.
    @State private var beats: Task<Void, Never>?
    /// The leading button's width, for where the field's leading end stops before it meets it.
    @State private var leadingWidth: CGFloat = 0
    /// The glass container's spacing while an opening or closing runs; nil at rest.
    @State private var ramp: GlassSpacingRamp?
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
        // Glass shapes in one container closer than its spacing blend with a neck between them.
        // The search glass is one shape throughout, the round button closed and the field open;
        // the X's glass and the leading button's come and go beside it.
        TimelineView(.animation(paused: ramp == nil)) { context in
            GlassEffectContainer(spacing: ramp?.spacing(at: context.date) ?? Spacing.sm) {
                ZStack(alignment: .leading) {
                    if stage.showsLeading {
                        leading
                            // Comes and goes only under the field, and fuses with it as plain
                            // glass; interactive glass showed as a layer over the field's.
                            .environment(\.barGlassInteractive, stage == .closed)
                            .environment(\.barGlassLabelShown, stage.showsLeadingLabel)
                            .onGeometryChange(for: CGFloat.self, of: \.size.width) {
                                leadingWidth = $0
                            }
                            .glassEffectID(GlassID.leading, in: glass)
                            .glassEffectTransition(glassTransition)
                            // Taken into the field's end: the system's morph of a removed glass
                            // into a neighbor dropped it in one frame, and a glass union of the
                            // two held the field's motion back in Add exercise until it jumped.
                            .scaleEffect(stage.absorbsLeading ? Self.absorbedScale : 1)
                            .offset(x: stage.absorbsLeading ? leadingWidth / 2 : 0)
                            .transition(viewTransition)
                            .accessibilityShown(!isOpen)
                    }
                    searchGlass
                    if stage.showsX {
                        glyph("xmark", isShown: stage.showsXSymbol)
                            .glassEffect(.regular.interactive(stage == .open), in: .circle)
                            .glassEffectID(GlassID.x, in: glass)
                            .glassEffectTransition(glassTransition)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .transition(viewTransition)
                    }
                    button
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                // The bar sizes its item at once, not along the motion, and centers what it
                // holds: resized with the field, the button jumped left and slid back. The item
                // keeps its open width throughout.
                .frame(width: itemWidth, alignment: .leading)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: {
            // Only a title reads it; without one, the item moves with every frame of a drawer.
            if title != nil {
                itemMidX = $0
            }
        }
        .background { coveredTitle }
        // The caret in green, as the list's own controls; the bar is hosted apart from the list
        // and does not take its tint.
        .tint(.pp(.accent))
        .onChange(of: isFocused) { _, focused in
            if !focused, text.isEmpty, stage == .open {
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

    /// Where the motion is: the beat running, or the end `isOpen` rests on.
    private var stage: BarSearchStage {
        beat ?? (isOpen ? .open : .closed)
    }

    private var itemWidth: CGFloat {
        max(width, height)
    }

    /// The leading button's glass and the X's come and go only inside the field's, so nothing of
    /// them shows; with Reduce Motion each fades in or out where it is.
    private var glassTransition: GlassEffectTransition {
        reduceMotion ? .materialize : .identity
    }

    private static var absorbedScale: CGFloat {
        0.3
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
    private var searchGlass: some View {
        let (start, end) = stage.span(
            itemWidth: itemWidth,
            height: height,
            leadingWidth: leadingWidth,
        )
        return ZStack(alignment: .leading) {
            if stage.showsFieldContent {
                field
            }
            glyph("magnifyingglass", isShown: stage.showsSearchSymbol)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: end - start, height: height, alignment: .leading)
        .clipped()
        // Interactive, as the bar's buttons are, only at rest as the button: interactive glass
        // showed as a layer over another where the two met.
        .glassEffect(.regular.interactive(stage == .closed), in: .capsule)
        .glassEffectID(GlassID.search, in: glass)
        .glassEffectTransition(.materialize)
        .padding(.leading, start)
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
        // Arrives with this update, so it takes focus as it appears.
        .onAppear { isFocused = true }
    }

    /// Takes the tap over the search glass, closed, and the X's, open, which draw its symbols:
    /// drawn apart from the button, for the one to grow into the field and the other to split
    /// off it. Over the glass, the symbols were dimmed by it.
    private var button: some View {
        Button(action: toggle) {
            Color.clear
                .frame(width: height, height: height)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
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

    /// The search button's symbol, or the X's, in a circle at its glass's trailing end. They swap
    /// on the glass's own curve, so the X lands as its glass parts; the system's replace effect
    /// keeps its own, longer timing. The button's label says what it does, so they are not read.
    private func glyph(_ name: String, isShown: Bool) -> some View {
        Image(systemName: name)
            .font(.ppBarGlyph)
            .foregroundStyle(.pp(.textPrimary))
            .scaleEffect(isShown || reduceMotion ? 1 : 0.5)
            .opacity(isShown ? 1 : 0)
            .frame(width: height, height: height)
            .accessibilityShown(false)
    }

    /// The search glass grows to the left, a neck's width short of the leading button; on the
    /// next beat the field runs on over the leading button, drawn small into its end, and the
    /// field's trailing end pulls back, the X's glass parting from it.
    private func open() {
        beats?.cancel()
        guard !reduceMotion else {
            withAnimation(BarSearchTiming.crossfade) {
                isOpen = true
                beat = nil
            }
            return
        }
        let ramp = GlassSpacingRamp.opening(at: .now)
        self.ramp = ramp
        withAnimation(.tapChange) {
            isOpen = true
            beat = .growing
        }
        beats = Task {
            try? await Task.sleep(for: BarSearchTiming.growing, tolerance: .zero)
            guard !Task.isCancelled else { return }
            withAnimation(.tapChange) { beat = .splitting }
            try? await Task.sleep(for: BarSearchTiming.splitting, tolerance: .zero)
            guard !Task.isCancelled else { return }
            // The leading button goes, the field over it since the split.
            beat = nil
            await settle(ramp)
        }
    }

    /// The X's glass runs back into the field's end; then the leading button pulls out of the
    /// field's leading end, and the field shrinks back into the search button. `isOpen` turns
    /// with the leading button's return, so the bar reads it as it comes back.
    private func close() {
        text = ""
        isFocused = false
        collapse()
    }

    private func collapse() {
        beats?.cancel()
        guard !reduceMotion else {
            withAnimation(BarSearchTiming.crossfade) {
                isOpen = false
                beat = nil
            }
            return
        }
        let ramp = GlassSpacingRamp.closing(at: .now)
        self.ramp = ramp
        withAnimation(.tapChange) { beat = .covering }
        beats = Task {
            try? await Task.sleep(for: BarSearchTiming.covering, tolerance: .zero)
            guard !Task.isCancelled else { return }
            withAnimation(BarSearchTiming.shrinking) {
                isOpen = false
                beat = .shrinking
            }
            try? await Task.sleep(for: BarSearchTiming.shrunk, tolerance: .zero)
            guard !Task.isCancelled else { return }
            beat = nil
            await settle(ramp)
        }
    }

    /// Stops the timeline once the spacing is back at rest.
    private func settle(_ ramp: GlassSpacingRamp) async {
        try? await Task.sleep(until: .now + .seconds(max(ramp.end.timeIntervalSinceNow, 0)))
        guard !Task.isCancelled else { return }
        self.ramp = nil
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
