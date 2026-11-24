import SwiftUI

/// One countdown carried from a rest between exercises to the next exercise's "Start in" as the
/// rest gives way at 0:05, so the two read as one timer: a figure drawn over the rows for the
/// length of the move, ticking on the rest's own end, placed between the leaving and arriving
/// slots' frames as they move (`CarriedSlot`), while the rows' own figures are hidden
/// (`figureCarried`). Only the words change, in the rows: "Rest" goes with its room, "Start in"
/// comes in with the slot.
public struct FigureCarry: Equatable, Sendable {
    /// When the rest, and so its "Start in", reaches 0:00.
    public let ends: Date
    /// Which carry this is: each runs its own way from the leaving slot.
    public let run: Int

    public init(ends: Date, run: Int) {
        self.ends = ends
        self.run = run
    }
}

/// The two places the carried figure runs between.
public enum CarriedSlot: Hashable, Sendable {
    /// The rest's countdown, in its closing room.
    case leaving
    /// The next exercise's "Start in" countdown, in its figures' slot.
    case arriving
}

private struct CarriedSlotAnchors: PreferenceKey {
    static let defaultValue: [CarriedSlot: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [CarriedSlot: Anchor<CGRect>],
        nextValue: () -> [CarriedSlot: Anchor<CGRect>],
    ) {
        value.merge(nextValue()) { first, _ in first }
    }
}

extension EnvironmentValues {
    /// Whether a figure is carried over the rows: the slots' own figures are hidden meanwhile.
    @Entry public var figureCarried = false
}

extension View {
    /// Marks this countdown's figure as `slot`'s, when `isOn`: its frame read for the carried
    /// figure, and itself hidden while one is carried.
    func carriedSlot(_ slot: CarriedSlot, isOn: Bool = true) -> some View {
        modifier(CarriedSlotMark(slot: slot, isOn: isOn))
    }

    /// Draws `carry`'s figure over this content, between the slots marked in it.
    public func carryingFigure(_ carry: FigureCarry?) -> some View {
        overlayPreferenceValue(CarriedSlotAnchors.self) { anchors in
            if let carry {
                GeometryReader { proxy in
                    CarriedFigure(
                        ends: carry.ends,
                        from: anchors[.leaving].map { proxy[$0] },
                        to: anchors[.arriving].map { proxy[$0] },
                    )
                }
                .id(carry.run)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct CarriedSlotMark: ViewModifier {
    let slot: CarriedSlot
    let isOn: Bool
    @Environment(\.figureCarried) private var isCarried

    func body(content: Content) -> some View {
        if isOn {
            content
                .anchorPreference(key: CarriedSlotAnchors.self, value: .bounds) { [slot: $0] }
                .opacity(isCarried ? 0 : 1)
        } else {
            content
        }
    }
}

/// The carried figure, running on the move's curve from where the rest's figure stood on screen
/// as the move began to where the "Start in" figure will stand once the list's lift has run out
/// (`listLift`), so it travels once, straight, while the rows close, open, and shift around it.
/// The progress is set as it appears: one set in the same update as the move's own change would
/// be drawn at its end from the first frame.
private struct CarriedFigure: View {
    let ends: Date
    let from: CGRect?
    let to: CGRect?
    @State private var progress: CGFloat = 0
    /// Where the rest's figure stood on screen as the carry began, in the list's unlifted space.
    @State private var start: CGRect?
    @Environment(\.listLift) private var lift

    var body: some View {
        CarriedFigurePlace(
            ends: ends,
            from: start ?? from?.offsetBy(dx: 0, dy: lift),
            to: to,
            progress: progress,
        )
        .onAppear {
            start = from?.offsetBy(dx: 0, dy: lift)
            withAnimation(SetMotion.aroundRest(.down)) { progress = 1 }
        }
    }
}

/// The carried figure `progress` of the way from `from`, a place on screen, to `to`, the
/// arriving slot's place in the list once unlifted, drawn inside the lift with it taken back out,
/// so the lift's run on its own curve never moves the figure. With one place unknown, it stands
/// at the other.
private struct CarriedFigurePlace: View, Animatable {
    let ends: Date
    let from: CGRect?
    let to: CGRect?
    var progress: CGFloat

    @ScaledMetric(relativeTo: CurrentFigure.textStyle) private var size = CurrentFigure.size
    @Environment(\.locale) private var locale
    @Environment(\.listLift) private var lift

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        if let rect = place {
            RestBlock(stage: .open, length: 0, ends: ends)
                .countdown(size: size, locale: locale, turns: true, skips: 0)
                .figureBox(size: size)
                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                .offset(x: rect.minX, y: rect.minY - lift)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var place: CGRect? {
        switch (from, to) {
        case let (from?, to?):
            CGRect(
                x: from.minX + (to.minX - from.minX) * progress,
                y: from.minY + (to.minY - from.minY) * progress,
                width: to.width,
                height: to.height,
            )
        case let (from?, nil): from
        case let (nil, to?): to
        case (nil, nil): nil
        }
    }
}

extension EnvironmentValues {
    /// How far the list is drawn below where it is scrolled to, as its lift runs to 0, on each
    /// frame (`GrowthLift`).
    @Entry public var listLift: CGFloat = 0
}
