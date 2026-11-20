import SwiftUI

/// The rest a row holds under its label between two exercises, open or not, which changes on the
/// row's own animation, so its height and the rows below move with the row. Open, under the
/// exercise just finished, as the exercise closes to its row: "Rest" in a row's name style, as
/// an exercise's name, then the time left in a large figure's style and size (`CurrentFigure`),
/// then the bar of its progress (`RestProgress`), each coming in as the room has grown to hold it
/// (`RestRoom`). −15 s and +15 s are at the bottom, in the key's place.
///
/// Nothing in it is green: a rest looks like an active exercise. The time ticks on whole seconds
/// before `ends` on a timeline, drawing once while paused (`pausedLeft`), so nothing is written
/// per second. It reads "0:35", rounded up, so it shows the whole rest as it starts and 0:00 only
/// as it ends. To VoiceOver it is one element, "Rest", its value the time left in words.
public struct RestBlock: View {
    public enum Stage: Sendable {
        case none
        case open
    }

    let stage: Stage
    /// The rest's length.
    let length: Int
    let ends: Date
    /// While paused, or closing as the workout ends, the seconds left; nil while running.
    let pausedLeft: Double?

    @ScaledMetric(relativeTo: CurrentFigure.textStyle) private var size = CurrentFigure.size
    @Environment(\.locale) private var locale

    public init(
        stage: Stage,
        length: Int,
        ends: Date = .distantPast,
        pausedLeft: Double? = nil,
    ) {
        self.stage = stage
        self.length = length
        self.ends = ends
        self.pausedLeft = pausedLeft
    }

    /// The block held at what it showed at `date`.
    func holding(at date: Date) -> Self {
        Self(stage: stage, length: length, ends: ends, pausedLeft: left(at: date))
    }

    /// The seconds the countdown shows at `date`, kept within `shown`. Closing with a time
    /// given, as a workout ended mid-rest, it holds that time.
    func left(at date: Date, within shown: ClosedRange<Double> = 0 ... .infinity) -> Double {
        let left = pausedLeft
            ?? (stage == .open ? max(0, ends.timeIntervalSince(date)) : Double(length))
        return min(shown.upperBound, max(shown.lowerBound, left))
    }

    /// No rest: a row's room for one, closed.
    public static let closed = Self(stage: .none, length: 0)

    public var body: some View {
        RestRoom(
            block: self,
            size: size,
            locale: locale,
            open: stage == .open ? 1 : 0,
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The time left; with `turns` off, it changes at once rather than rolling. Always within
    /// `shown`: "Starts in" reads 0:10 as it comes in and 0:01 until it goes, never 0:00.
    /// `staysPut`, it takes no motion of the parts around it and only fades, as at End.
    func countdown(
        size: CGFloat,
        locale: Locale,
        turns: Bool = true,
        color: ColorToken = .textPrimary,
        shown: ClosedRange<Double> = 0 ... .infinity,
        staysPut: Bool = false,
    ) -> some View {
        let isOpen = stage == .open
        return TimelineView(RestSchedule(
            ends: ends,
            isPaused: pausedLeft != nil || !isOpen,
        )) { context in
            let seconds = left(at: context.date, within: shown)
            let text = Self.text(seconds, locale: locale)
            Text(text)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(.pp(color))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // A + or − turns the figure; a second going by, or the rest's end on the move's
                // delayed shift, changes it at once: on that shift, 0:00 came in half a second
                // after the dot had left. So does a − that ends the rest: turning, the figure
                // rolled down to 0:00 as it shrank away. Only a change of its own: taking every
                // update's animation away, the figure jumped to where a part going drops it
                // while the part faded on its curve.
                .contentTransition(turns ? .numericText(countsDown: true) : .identity)
                .transaction(value: ends) {
                    if isOpen, turns, seconds > 0 {
                        $0.animation = .snappy(duration: SetMotion.restGlide)
                    }
                }
                // A figure that turns only: one that never rolls, as a held count, changes at
                // once anyway, and taking the animation, a count at its run-out jumped to where
                // its leaving exercise drops it.
                .transaction(value: text) {
                    if turns {
                        $0.animation = nil
                    }
                }
                .transaction {
                    if staysPut {
                        $0.animation = nil
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rest")
                .accessibilityValue(Self.spoken(seconds, locale: locale))
        }
    }

    /// How far through the rest it is, as a bar under the countdown (`RestProgress`).
    var progress: some View {
        RestProgress(
            starts: ends.timeIntervalSinceReferenceDate - Double(length),
            length: Double(length),
            pausedLeft: pausedLeft ?? (stage == .open ? nil : Double(length)),
        )
    }

    /// "0:35", the seconds rounded up: a rest's time as the countdown and a caption show it.
    public static func text(_ seconds: Double, locale: Locale) -> String {
        Duration.seconds(seconds.rounded(.up))
            .formatted(.time(pattern: .minuteSecond).locale(locale))
    }

    /// "35 seconds", as VoiceOver hears a rest's time.
    public static func spoken(_ seconds: Double, locale: Locale) -> String {
        Duration.seconds(seconds.rounded(.up))
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide).locale(locale))
    }
}

/// A row's label with its rest under it (`RestBlock`), stacked as the rail stacks its rows, so
/// the rest moves with the label's height on every frame. The label stands at least as tall as a
/// resting row's floor (`restingLabelFloor`), the height a shrinking label stands at until its
/// shrink ends: shorter at rest, a one-line detail's label let the rest under it jump up 8 pt as
/// the shrink ended. `onRestHeight` hears the rest's height as it lays out: all the row gives back
/// as the rest closes. Before a superset's next round its rest opens above its first member's
/// label instead (`restAbove`), the row's node staying on the label's first line, so the rest
/// sits on the rail's line into the node, between the row above and the label.
public struct LabelWithRest<Label: View>: View {
    let label: Label
    let rest: RestBlock
    let restAbove: RestBlock
    let onRestHeight: (CGFloat) -> Void
    @Environment(\.restingLabelFloor) private var floor

    public init(
        label: Label,
        rest: RestBlock,
        restAbove: RestBlock = RestBlock(stage: .none, length: 0),
        onRestHeight: @escaping (CGFloat) -> Void = { _ in },
    ) {
        self.label = label
        self.rest = rest
        self.restAbove = restAbove
        self.onRestHeight = onRestHeight
    }

    public var body: some View {
        RestsAroundLabel {
            restAbove
            label.frame(minHeight: floor, alignment: .top)
            rest
                .onGeometryChange(for: CGFloat.self, of: \.size.height, action: onRestHeight)
        }
    }
}

/// A rest above, a label, and a rest below, stacked as `RailStack` stacks them, its text
/// baselines the label's: the rest above, laid out even while closed, would otherwise lend the
/// row its "Rest", and the row's node would sit on it.
private struct RestsAroundLabel: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = sizes(subviews, width: proposal.width)
        return CGSize(
            width: sizes.map(\.width).max() ?? 0,
            height: sizes.map(\.height).reduce(0, +),
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let offer = ProposedViewSize(width: bounds.width, height: nil)
        var top = bounds.minY
        for (subview, size) in zip(subviews, sizes(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX, y: top), proposal: offer)
            top += size.height
        }
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) -> CGFloat? {
        guard subviews.count == 3,
              guide == .firstTextBaseline || guide == .railNodeBaseline
        else { return nil }
        let offer = ProposedViewSize(width: bounds.width, height: nil)
        return subviews[0].sizeThatFits(offer).height + subviews[1].dimensions(in: offer)[guide]
    }

    private func sizes(_ subviews: Subviews, width: CGFloat?) -> [CGSize] {
        let offer = ProposedViewSize(width: width, height: nil)
        return subviews.map { $0.sizeThatFits(offer) }
    }
}

/// The rest drawn at a point in its opening or closing: `open` runs from 0 to 1 on the row's
/// animation, and every part's fade is worked out from it, so the parts move with the room on
/// its curve whatever the transaction, a move's, whose scroll is set with animations disabled,
/// included: an implicit `.animation(_:value:)` there was dropped, and the parts changed at once.
/// Coming in, top first, each once the room has grown enough to hold it; going, bottom first, as
/// the room starts to close (`RestRoomFade.fade(_:from:width:)`).
private struct RestRoom: View, Animatable {
    let block: RestBlock
    let size: CGFloat
    let locale: Locale
    var open: CGFloat
    /// The cap height of "Rest"'s font (`Font.ppRowTitle`), SF Pro semibold at body's size at the
    /// default text size, scaled with it.
    @ScaledMetric(relativeTo: .body) private var capHeight = Self.defaultCapHeight

    private static let defaultCapHeight: CGFloat = {
        #if canImport(UIKit)
        UIFont.systemFont(
            ofSize: UIFont.preferredFont(
                forTextStyle: .body,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: .large),
            ).pointSize,
            weight: .semibold,
        ).capHeight
        #else
        12
        #endif
    }()

    var animatableData: CGFloat {
        get { open }
        set { open = newValue }
    }

    /// Each part's bottom in the room, and the room's height, open: a part comes in only once
    /// the room has grown past it, and has gone by the time the room, closing, reaches it.
    @State private var bottoms = Bottoms()

    private struct Bottoms: Equatable {
        var word: CGFloat = 0
        var countdown: CGFloat = 0
        var bar: CGFloat = 0
        var room: CGFloat = 0

        /// The share of the room open from which a part ending at `bottom` shows whole, or
        /// `fallback` before the room is measured.
        func start(_ bottom: CGFloat, or fallback: CGFloat) -> CGFloat {
            room > 0 ? bottom / room : fallback
        }
    }

    private static let space = "restRoom"

    var body: some View {
        // From the share of the room that holds each part whole, so nothing is drawn cut off at
        // the room's bottom against the row under it: from fixed shares, the countdown came in
        // with the room a third open, half of it drawn against the first member's name.
        let word = RestRoomFade.fade(open, from: bottoms.start(bottoms.word, or: 0.2), width: 0.15)
        let countdown = RestRoomFade.fade(
            open,
            from: bottoms.start(bottoms.countdown, or: 0.7),
            width: 0.15,
        )
        let bar = RestRoomFade.fade(open, from: bottoms.start(bottoms.bar, or: 0.85), width: 0.1)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Rest")
                // Where the workout's dot waits through the rest, on the rail: level with the
                // middle of the word's capitals, standing on its baseline, not the line's box.
                // Known from the log, while the room waits to open: the pulse runs to it then.
                Color.clear
                    .frame(width: 0, height: capHeight)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    .restStop(open > 0 || block.stage == .open)
            }
            .font(.ppRowTitle)
            .foregroundStyle(.pp(.textPrimary))
            // The countdown reads "Rest" with its time.
            .accessibilityRepresentation { EmptyView() }
            .padding(.top, Spacing.sm)
            .modifier(BottomIn(Self.space) { bottoms.word = $0 })
            .opacity(word)
            block.countdown(size: size, locale: locale)
                .figureBox(size: size)
                .padding(.top, Spacing.md)
                .modifier(BottomIn(Self.space) { bottoms.countdown = $0 + SetMotion.arriveRise })
                .coming(countdown)
            block.progress
                .padding(.top, Spacing.md)
                .modifier(BottomIn(Self.space) { bottoms.bar = $0 + SetMotion.arriveRise })
                .coming(bar)
        }
        .padding(.bottom, Spacing.lg)
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { bottoms.room = $0 }
        .accessibilityHidden(block.stage != .open)
        .modifier(RestRoomHeight(open: open))
    }
}

/// Hears a view's bottom edge in a named space.
private struct BottomIn: ViewModifier {
    let space: String
    let action: (CGFloat) -> Void

    init(_ space: String, action: @escaping (CGFloat) -> Void) {
        self.space = space
        self.action = action
    }

    func body(content: Content) -> some View {
        content.onGeometryChange(
            for: CGFloat.self,
            of: { $0.frame(in: .named(space)).maxY },
            action: action,
        )
    }
}

/// The open rest's room, `open` of its height: run from 0 to 1 on the row's animation, so the
/// room grows and closes on its curve, every row below moving with it. Mid-change, what is coming
/// in or going is cut off at the room's bottom, never drawn over the next row.
private struct RestRoomHeight: ViewModifier {
    let open: CGFloat

    func body(content: Content) -> some View {
        RestRoomLayout(open: open) { content }
            .clipped()
    }
}

/// Its one subview from the top, `open` of its own height tall, measured afresh on every pass,
/// as `RailStack` does.
private struct RestRoomLayout: Layout {
    let open: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(ProposedViewSize(
            width: proposal.width,
            height: nil,
        )) ?? .zero
        return CGSize(width: proposal.width ?? size.width, height: size.height * open)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        subviews.first?.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: nil),
        )
    }
}

#Preview {
    VStack(alignment: .leading) {
        RestBlock(stage: .open, length: 90, ends: .now.addingTimeInterval(35))
    }
    .padding()
    .background(Color.pp(.background))
}
