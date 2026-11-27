import SwiftUI

/// The rest a row holds under its label between two exercises, open or not, which changes on the
/// row's own animation, so its height and the rows below move with the row. Open, under the
/// exercise just finished, as the exercise closes to its row: "Rest" in a row's name style, as
/// an exercise's name, then the time left in a large figure's style and size (`CurrentFigure`),
/// each coming in as the room has grown to hold it (`RestRoom`). There is no bar under it: Skip
/// rest, at the bottom in the key's place, fills as the rest runs, with +15 s beside it
/// (`CountKeys`). Paused, the count holds, white; Continue is in the keys' place.
///
/// Nothing in it is green: a rest looks like an active exercise. The time ticks on whole seconds
/// before `ends` on a timeline, drawing once while paused (`pausedLeft`), so nothing is written
/// per second. It reads "0:35", rounded up, so it shows the whole rest as it starts and 0:00 only
/// as it ends. Its changing digits roll down as each second goes and up on +15 s, its last change,
/// to 0:00, at once; cut, by Skip rest or held as it goes, it shows whole at once, whatever roll
/// was in flight (`figureKey(skips:)`). To VoiceOver it is one element, "Rest", its value the time
/// left in words. Shut, its count runs no timeline (`RestRoom.isShown`).
public struct RestBlock: View {
    public enum Stage: Sendable {
        case none
        case open
    }

    let stage: Stage
    /// The rest's length.
    let length: Int
    let ends: Date
    /// While paused, closing as the workout ends, or cut by Skip rest, the seconds left; nil
    /// while running.
    let pausedLeft: Double?
    /// Held by a pause, which keeps the count's figure (`figureKey(skips:)`); it stays white.
    let isPaused: Bool

    @ScaledMetric(relativeTo: CurrentFigure.textStyle) private var size = CurrentFigure.size
    @Environment(\.locale) private var locale

    public init(
        stage: Stage,
        length: Int,
        ends: Date = .distantPast,
        pausedLeft: Double? = nil,
        isPaused: Bool = false,
    ) {
        self.stage = stage
        self.length = length
        self.ends = ends
        self.pausedLeft = pausedLeft
        self.isPaused = isPaused
    }

    /// The block leaving, held at what it showed at `date`: held by its going, not a pause.
    func holding(at date: Date) -> Self {
        Self(
            stage: stage,
            length: length,
            ends: ends,
            pausedLeft: left(at: date),
        )
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

    /// The time left, its changing digits rolling as `rolls(on:to:)` says. With `turns` off, as
    /// with Reduce Motion, nothing rolls and the figure takes the update's own animation, so
    /// `turns` never goes off in the change that moves the figure (`SetRest.turnsFigure`).
    /// Always within `shown`: "Start in" reads 0:10 as it comes in and 0:01 until it goes,
    /// never 0:00. `label` names it for accessibility: "Rest", or the wait in the figures' slot
    /// it counts ("Start in", "Time left").
    func countdown(
        size: CGFloat,
        locale: Locale,
        turns: Bool,
        skips: Int,
        shown: ClosedRange<Double> = 0 ... .infinity,
        label: LocalizedStringKey = "Rest",
    ) -> some View {
        TimelineView(RestSchedule(
            ends: ends,
            isPaused: !ticks,
        )) { context in
            let seconds = Self.drawing(left(at: context.date, within: shown))
            let text = Self.text(seconds, locale: locale)
            Text(text)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                // White through a pause too, as the workout's time is (decided 2026-11-24).
                .foregroundStyle(.pp(.textPrimary))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // By its value, the figure rolls down as a second goes and up on +15 s. Only a
                // change of its own: taking every update's animation away, the figure jumped to
                // where a part going drops it while the part faded on its curve.
                .contentTransition(turns ? .numericText(value: seconds.rounded(.up)) : .identity)
                // Inside the tick's below: on +15 s both run, and the move's says last.
                .transaction(value: ends) {
                    if turns, rolls(on: .moved, to: seconds) {
                        $0.animation = SetMotion.restRoll
                    }
                }
                // Rolled, or at once. Only a figure that turns: taking a held one's animation, a
                // count at its run-out jumped to where its leaving exercise drops it.
                .transaction(value: text) {
                    if turns {
                        $0.animation = rolls(on: .tick, to: seconds) ? SetMotion.restRoll : nil
                    }
                }
                // A cut figure is a new one, put in and the old taken out at once, with any roll
                // in flight: a cut landing on a second's roll, its change at once, carried the
                // roll on to the new digits as the count went. Skip rest's holds the time left.
                .transition(.identity)
                .id(figureKey(skips: skips))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(Self.spoken(seconds, locale: locale))
        }
    }

    /// Whether the count runs: open and not held by a pause, the workout's end, or leaving.
    var ticks: Bool {
        stage == .open && pausedLeft == nil
    }

    /// Which figure shows the count: a new one, any roll in flight dropped, where a cut can land
    /// on a second's roll. Held with time left other than by a pause, as the workout ends, a timed
    /// set is logged early, or the count leaves; and on each Skip rest (`skips`, changed in the
    /// skip's own change, before the rest swaps back). A paused count keeps its figure: a roll in
    /// flight at a pause ends on it. So does one that runs out, its last roll over a second before
    /// 0:00: a new figure there, put in as the rest between sets swapped back, stood where the
    /// swap ends from its first frame, 14 pt under the count it replaced.
    func figureKey(skips: Int) -> FigureKey {
        FigureKey(isHeld: (pausedLeft ?? 0) > 0 && !isPaused, skips: skips)
    }

    struct FigureKey: Hashable {
        let isHeld: Bool
        let skips: Int
    }

    /// What changed the figure.
    enum Change {
        /// A second went by.
        case tick
        /// The rest's end moved, as on +15 s.
        case moved
    }

    /// Whether the figure rolls to `seconds` on `change`: a second going by while the count
    /// runs, and +15 s while it is open, paused included. A held count, paused, ended, or
    /// leaving, never ticks. A change to 0:00, at the run-out, is at once: rolling, 0:00 came in
    /// half a second after the dot had left. A rest cut by Skip rest never reads 0:00: it goes
    /// holding the time it had left at the tap.
    func rolls(on change: Change, to seconds: Double) -> Bool {
        guard seconds > 0 else { return false }
        return switch change {
        case .tick: ticks
        case .moved: stage == .open
        }
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
    @Environment(\.restIsAboveLabel) private var isAboveLabel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.restSkips) private var restSkips

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
        var room: CGFloat = 0

        /// The share of the room open from which a part ending at `bottom` shows whole, or
        /// `fallback` before the room is measured.
        func start(_ bottom: CGFloat, or fallback: CGFloat) -> CGFloat {
            room > 0 ? bottom / room : fallback
        }
    }

    private static let space = "restRoom"

    /// The room under the count, so the next exercise's name stands `Spacing.lg` and a row's
    /// insets under it wherever the rest is: under a label, the row's bottom inset and the next
    /// row's top inset follow it; above a superset's first member, nothing does, and there the
    /// name sat 16 pt closer than after a rest between exercises.
    private var below: CGFloat {
        Spacing.lg + (isAboveLabel ? 2 * RailRowMetrics.verticalInset : 0)
    }

    /// Whether the room shows: open, opening, or closing. Shut, its count has no timeline.
    var isShown: Bool {
        open > 0 || block.stage == .open
    }

    var body: some View {
        room.modifier(RestRoomHeight(open: open))
    }

    /// The count, or, shut, its figure drawn once with no timeline: the room keeps its parts laid
    /// out, as Start's landing reads the rows by them (`WorkoutFinishUITests`: with the shut room
    /// drawing nothing, the list landed 32 pt high). In and out at once: the parts fade on `open`.
    @ViewBuilder private var figure: some View {
        if isShown {
            block.countdown(size: size, locale: locale, turns: !reduceMotion, skips: restSkips)
                .transition(.identity)
        } else {
            RestBlock.shutFigure(size: size, locale: locale).transition(.identity)
        }
    }

    @ViewBuilder private var room: some View {
        // From the share of the room that holds each part whole, so nothing is drawn cut off at
        // the room's bottom against the row under it: from fixed shares, the countdown came in
        // with the room a third open, half of it drawn against the first member's name.
        let word = RestRoomFade.fade(open, from: bottoms.start(bottoms.word, or: 0.2), width: 0.15)
        // The room's last part: whole by the time the room is open, however near the room's
        // bottom its own bottom sits (`RestRoomFade`). Left to its bottom alone, it stood at two
        // thirds through the rest, gray.
        let countdown = RestRoomFade.fade(
            open,
            from: bottoms.start(bottoms.countdown, or: 0.7),
            width: 0.15,
        )
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Rest")
                // Where the workout's dot waits through the rest, on the rail: level with the
                // middle of the word's capitals, standing on its baseline, not the line's box.
                // Known from the log, while the room waits to open: the pulse runs to it then.
                Color.clear
                    .frame(width: 0, height: capHeight)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    .restStop(isShown)
            }
            .font(.ppRowTitle)
            .foregroundStyle(.pp(.textPrimary))
            // The countdown reads "Rest" with its time.
            .accessibilityRepresentation { EmptyView() }
            .padding(.top, Spacing.sm)
            .modifier(BottomIn(Self.space) { bottoms.word = $0 })
            .opacity(word)
            figure
                .figureBox(size: size)
                .padding(.top, Spacing.md)
                .modifier(BottomIn(Self.space) { bottoms.countdown = $0 + SetMotion.arriveRise })
                .coming(countdown)
        }
        .padding(.bottom, below)
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { bottoms.room = $0 }
        .accessibilityHidden(block.stage != .open)
    }
}

extension EnvironmentValues {
    /// How many times Skip rest has cut a rest short, changed in the skip's own change, never
    /// an animated one: each puts in a new figure for every count (`RestBlock.figureKey(skips:)`).
    @Entry public var restSkips = 0
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
/// in or going is cut off at the room's bottom, never drawn over the next row; nothing is cut at
/// its sides, where the count's first figure stands a few points left of the column
/// (`figureBox`): clipped to the room's own width, a leading "0" or "1" was sliced flat there.
private struct RestRoomHeight: ViewModifier {
    let open: CGFloat

    func body(content: Content) -> some View {
        RestRoomLayout(open: open) { content }
            .clipShape(TopAndBottom())
    }
}

/// A rectangle as tall as its bounds and reaching a width past them on each side: a clip that cuts
/// only at the top and bottom.
private struct TopAndBottom: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: -rect.width, dy: 0))
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
