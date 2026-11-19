import SwiftUI

/// The rest a row holds under its label, in one of three stages, which change on the row's own
/// animation, so its height and the rows below move with the row:
/// - **Line**: under the current exercise, the rest that will follow it, one quiet line in the
///   progress line's style, "Rest 1:30".
/// - **Open**: under the exercise just finished, the line grown in place into the rest: the
///   length goes as the exercise's own parts go, and under "Rest" the time left comes in, in
///   bold SF Mono at about half the figures' size (`RestFigure`), then the bar of its progress
///   (`RestProgress`) and −15 s and +15 s, as the next exercise's parts come in (`RestRoom`).
/// - **None**: no room.
///
/// "Rest" is one `Text` through every stage, so it never crossfades. Nothing in it is green: a
/// rest looks like an active exercise. The time ticks on whole seconds before `ends` on a
/// timeline, drawing once while paused (`pausedLeft`), so nothing is written per second. It reads
/// "0:35", rounded up, so it shows the whole rest as it starts and 0:00 only as it ends. To
/// VoiceOver the open rest is one element, "Rest", its value the time left in words, and the two
/// buttons; the line is "Rest", its value the length.
public struct RestBlock: View {
    public enum Stage: Sendable {
        case none
        case line
        case open
    }

    let stage: Stage
    /// The rest's length, which the line shows.
    let length: Int
    let ends: Date
    /// While paused, the seconds left; nil while running.
    let pausedLeft: Double?
    let onShorten: () -> Void
    let onExtend: () -> Void

    @ScaledMetric(relativeTo: CurrentFigure.textStyle) private var size = RestFigure.size
    @Environment(\.locale) private var locale

    public init(
        stage: Stage,
        length: Int,
        ends: Date = .distantPast,
        pausedLeft: Double? = nil,
        onShorten: @escaping () -> Void = { },
        onExtend: @escaping () -> Void = { },
    ) {
        self.stage = stage
        self.length = length
        self.ends = ends
        self.pausedLeft = pausedLeft
        self.onShorten = onShorten
        self.onExtend = onExtend
    }

    public var body: some View {
        RestRoom(
            block: self,
            size: size,
            locale: locale,
            line: stage == .none ? 0 : 1,
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
            let left = isOpen
                ? pausedLeft ?? max(0, ends.timeIntervalSince(context.date)) : Double(length)
            Text(Self.text(left, locale: locale))
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(.pp(.textPrimary))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // A + or − turns the figure; a second going by, or the rest's end on the move's
                // delayed shift, changes it at once: on that shift, 0:00 came in half a second
                // after the dot had left.
                .contentTransition(turns ? .numericText(countsDown: true) : .identity)
                .animation(
                    isOpen && turns ? .snappy(duration: SetMotion.restGlide) : nil,
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
            ends: ends.timeIntervalSinceReferenceDate,
            starts: ends.timeIntervalSinceReferenceDate - Double(length),
            pausedLeft: stage == .open ? pausedLeft : Double(length),
        )
    }

    var buttons: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onShorten) { Text(AttributedString.monoNumbers(
                "−15 s",
                font: .ppButton,
            )) }
            .accessibilityLabel("Shorten rest by 15 seconds")
            Button(action: onExtend) { Text(AttributedString.monoNumbers(
                "+15 s",
                font: .ppButton,
            )) }
            .accessibilityLabel("Extend rest by 15 seconds")
        }
        .buttonStyle(RestStepStyle())
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
/// the shrink ended.
public struct LabelWithRest<Label: View>: View {
    let label: Label
    let rest: RestBlock
    @Environment(\.restingLabelFloor) private var floor

    public init(label: Label, rest: RestBlock) {
        self.label = label
        self.rest = rest
    }

    public var body: some View {
        RailStack {
            label.frame(minHeight: floor, alignment: .top)
            rest
        }
    }
}

/// The rest drawn at a point in its change of stage: `line` and `open` run from 0 to 1 on the
/// row's animation, and every part's fade is worked out from them, so the parts move with the
/// room on its curve whatever the transaction, a move's, whose scroll is set with animations
/// disabled, included: an implicit `.animation(_:value:)` there was dropped, and the parts
/// changed at once. Coming in, top first, each once the room has grown enough to hold it; going,
/// bottom first, as the room starts to close (`fade(_:from:)`).
private struct RestRoom: View, Animatable {
    let block: RestBlock
    let size: CGFloat
    let locale: Locale
    var line: CGFloat
    var open: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(line, open) }
        set { (line, open) = (newValue.first, newValue.second) }
    }

    var body: some View {
        let lineShown = Self.fade(line, from: 0.5)
        RestRoomLayout(line: line, open: open) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Rest")
                Text(AttributedString.monoNumbers(
                    " " + RestBlock.text(Double(block.length), locale: locale),
                    font: .ppCurrentProgress,
                ))
                .opacity(1 - Self.fade(open, from: 0, width: 0.25))
            }
            .font(.ppCurrentProgress)
            .foregroundStyle(.pp(.textSecondary))
            .opacity(lineShown)
            .padding(.top, Spacing.sm)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest")
            .accessibilityValue(RestBlock.spoken(Double(block.length), locale: locale))
            .accessibilityHidden(block.stage != .line)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                block.countdown(size: size, locale: locale)
                    .opacity(Self.fade(open, from: 0.4))
                    .offset(y: (1 - Self.fade(open, from: 0.4)) * SetMotion.arriveRise)
                block.progress
                    .opacity(Self.fade(open, from: 0.45))
                    .offset(y: (1 - Self.fade(open, from: 0.45)) * SetMotion.arriveRise)
                block.buttons
                    .opacity(Self.fade(open, from: 0.55))
                    .offset(y: (1 - Self.fade(open, from: 0.55)) * SetMotion.arriveRise)
            }
            .padding(.top, Spacing.xxs)
            .padding(.bottom, Spacing.md)
            .accessibilityHidden(block.stage != .open)
        }
        // Mid-change, what is coming in or going is cut off at the room's bottom, never drawn
        // over the next row.
        .clipped()
    }

    /// How far a part has faded in at `share` of the room's change: from 0 at `start` to 1
    /// `width` later.
    static func fade(_ share: CGFloat, from start: CGFloat, width: CGFloat = 0.3) -> CGFloat {
        min(max((share - start) / width, 0), 1)
    }
}

/// The line over the open rest's body, each as tall as its share: `line` and `open` run from 0
/// to 1 on the row's animation, so the room grows and closes on its curve, every row below
/// moving with it. Both are measured afresh on every pass, as `RailStack` does.
private struct RestRoomLayout: Layout {
    let line: CGFloat
    let open: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(
            width: proposal.width,
            height: nil,
        )) }
        let lineHeight = sizes.first?.height ?? 0
        let openHeight = sizes.dropFirst().first?.height ?? 0
        return CGSize(
            width: proposal.width ?? sizes.map(\.width).max() ?? 0,
            height: lineHeight * line + openHeight * open,
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let offer = ProposedViewSize(width: bounds.width, height: nil)
        let lineHeight = subviews.first?.sizeThatFits(offer).height ?? 0
        subviews.first?.place(at: bounds.origin, proposal: offer)
        subviews.dropFirst().first?.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + lineHeight * line),
            proposal: offer,
        )
    }
}

/// The rest's progress: a thin bar with round ends, as wide as the text column, whose fill, in the
/// countdown's own color over a quiet gray track, runs left to right at one rate for the rest's
/// length, full at 0:00. Drawn, not a `ProgressView`: the linear style takes neither a track color
/// nor a height, and its fill jumps when its value changes. `ends` is animatable, so + and −,
/// which move it on the glide's animation (`SetMotion.restGlide`), glide the fill back or on
/// rather than jumping it; `starts` stays put through them. Paused, it holds at `pausedLeft`.
/// Hidden from VoiceOver: the countdown says the time left.
struct RestProgress: View, Animatable {
    var ends: Double
    let starts: Double
    let pausedLeft: Double?

    @ScaledMetric(relativeTo: .body) private var height = Self.height

    /// The bar's height, a little thicker than the rail's line.
    static let height: CGFloat = 4

    var animatableData: Double {
        get { ends }
        set { ends = newValue }
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
        let total = ends - starts
        guard total > 0 else { return 1 }
        let left = pausedLeft ?? (ends - now)
        return CGFloat(min(max(1 - left / total, 0), 1))
    }
}

/// −15 s and +15 s: outlined capsules, 44 pt tall, in the text's own colors.
private struct RestStepStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.pp(.textPrimary))
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 44)
            .background(Capsule().strokeBorder(Color.pp(.borderStrong), lineWidth: 1))
            .contentShape(.capsule)
            .opacity(configuration.isPressed ? 0.5 : 1)
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
        RestBlock(stage: .line, length: 90)
        RestBlock(stage: .open, length: 90, ends: .now.addingTimeInterval(35))
    }
    .padding()
    .background(Color.pp(.background))
}
