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

    public var body: some View {
        RestRoom(
            block: self,
            size: size,
            locale: locale,
            open: stage == .open ? 1 : 0,
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The time left; with `turns` off, it changes at once rather than rolling.
    func countdown(size: CGFloat, locale: Locale, turns: Bool = true) -> some View {
        let isOpen = stage == .open
        return TimelineView(RestSchedule(
            ends: ends,
            isPaused: pausedLeft != nil || !isOpen,
        )) { context in
            // Closing with a time given, as a workout ended mid-rest, it holds that time.
            let left = pausedLeft
                ?? (isOpen ? max(0, ends.timeIntervalSince(context.date)) : Double(length))
            Text(Self.text(left, locale: locale))
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(.pp(.textPrimary))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // A + or − turns the figure; a second going by, or the rest's end on the move's
                // delayed shift, changes it at once: on that shift, 0:00 came in half a second
                // after the dot had left. So does a − that ends the rest: turning, the figure
                // rolled down to 0:00 as it shrank away.
                .contentTransition(turns ? .numericText(countsDown: true) : .identity)
                .animation(
                    isOpen && turns && left > 0 ? .snappy(duration: SetMotion.restGlide) : nil,
                    value: ends,
                )
                .transaction { $0.animation = nil }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rest")
                .accessibilityValue(Self.spoken(left, locale: locale))
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

    /// "0:35", the seconds rounded up.
    static func text(_ seconds: Double, locale: Locale) -> String {
        Duration.seconds(seconds.rounded(.up))
            .formatted(.time(pattern: .minuteSecond).locale(locale))
    }

    /// "35 seconds".
    static func spoken(_ seconds: Double, locale: Locale) -> String {
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
/// the room starts to close (`fade(_:from:)`).
private struct RestRoom: View, Animatable {
    let block: RestBlock
    let size: CGFloat
    let locale: Locale
    var open: CGFloat
    /// The cap height of "Rest"'s font (`Font.ppRowTitle`), SF Pro semibold at body's size at the
    /// default text size, scaled with it.
    @ScaledMetric(relativeTo: .body) private var capHeight = UIFont
        .systemFont(
            ofSize: UIFont.preferredFont(
                forTextStyle: .body,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: .large),
            ).pointSize,
            weight: .semibold,
        ).capHeight

    var animatableData: CGFloat {
        get { open }
        set { open = newValue }
    }

    var body: some View {
        let countdown = Self.fade(open, from: 0.4)
        let bar = Self.fade(open, from: 0.5)
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
            .opacity(Self.fade(open, from: 0.2))
            .padding(.top, Spacing.sm)
            block.countdown(size: size, locale: locale)
                .figureBox(size: size)
                .padding(.top, Spacing.md)
                .opacity(countdown)
                .offset(y: (1 - countdown) * SetMotion.arriveRise)
            block.progress
                .padding(.top, Spacing.md)
                .opacity(bar)
                .offset(y: (1 - bar) * SetMotion.arriveRise)
        }
        .padding(.bottom, Spacing.lg)
        .accessibilityHidden(block.stage != .open)
        .modifier(RestRoomHeight(open: open))
    }

    /// How far a part has faded in at `share` of the room's change: from 0 at `start` to 1
    /// `width` later.
    static func fade(_ share: CGFloat, from start: CGFloat, width: CGFloat = 0.3) -> CGFloat {
        min(max((share - start) / width, 0), 1)
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

/// The rest's progress: a thin bar with round ends, as wide as the text column, whose fill, in the
/// countdown's own color over a quiet gray track, runs left to right at one rate for the rest's
/// length, full at 0:00. Drawn, not a `ProgressView`: the linear style takes neither a track color
/// nor a height, and its fill jumps when its value changes. `length` is animatable, so + and −,
/// which change it on the glide's animation (`SetMotion.restGlide`), glide the fill back or on
/// rather than jumping it; `starts` stays put through them. Not the end: as a rest opened, the
/// line's end, the distant past, ran to the rest's on the open's curve, and the bar drew full
/// until it got there. Paused, it holds at `pausedLeft`. Hidden from VoiceOver: the countdown
/// says the time left.
struct RestProgress: View, Animatable {
    let starts: Double
    var length: Double
    let pausedLeft: Double?

    @ScaledMetric(relativeTo: .body) private var height = Self.height

    /// The bar's height, a little thicker than the rail's line.
    static let height: CGFloat = 4

    var animatableData: Double {
        get { length }
        set { length = newValue }
    }

    var body: some View {
        // Frame by frame, so the fill runs on steadily rather than stepping each second.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: pausedLeft != nil)) { context in
            let share = share(at: context.date.timeIntervalSinceReferenceDate)
            Capsule()
                .fill(.pp(.borderStrong))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.pp(.textPrimary))
                            .frame(width: max(proxy.size.width * share, share > 0 ? height : 0))
                    }
                }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    /// The share of the rest gone at `now`, from 0 to 1.
    private func share(at now: Double) -> CGFloat {
        guard length > 0 else { return 1 }
        let left = pausedLeft ?? (starts + length - now)
        return CGFloat(min(max(1 - left / length, 0), 1))
    }
}

/// Whole seconds counting down to `ends`, a tick as each second of the rest goes, so "0:35" turns
/// to "0:34" as a whole second has gone; one entry while paused.
private struct RestSchedule: TimelineSchedule {
    let ends: Date
    let isPaused: Bool

    func entries(from startDate: Date, mode _: Mode) -> AnyIterator<Date> {
        guard !isPaused else {
            var once = true
            return AnyIterator {
                defer { once = false }
                return once ? startDate : nil
            }
        }
        // Counted down in whole seconds from `ends`, so the last entry is `ends` itself: stepped
        // up from the first, a second at a time, it ran a hair past `ends` and the figure stayed
        // on 0:01 as the dot left.
        var secondsLeft = max(ends.timeIntervalSince(startDate).rounded(.down), 0)
        var first = true
        return AnyIterator {
            if first {
                first = false
                return startDate
            }
            guard secondsLeft >= 0 else { return nil }
            defer { secondsLeft -= 1 }
            return ends.addingTimeInterval(-secondsLeft)
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        RestBlock(stage: .open, length: 90, ends: .now.addingTimeInterval(35))
    }
    .padding()
    .background(Color.pp(.background))
}
