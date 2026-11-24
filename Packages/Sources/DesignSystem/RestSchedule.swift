import SwiftUI

/// Whole seconds counting down to `ends`, a tick as each second of the rest goes, so "0:35" turns
/// to "0:34" as a whole second has gone; one entry while paused.
struct RestSchedule: TimelineSchedule {
    let ends: Date
    let isPaused: Bool

    func entries(from startDate: Date, mode _: Mode) -> AnyIterator<Date> {
        guard !isPaused else { return AnyIterator([startDate].makeIterator()) }
        // Counted down in whole seconds from `ends`, so the last entry is `ends` itself: stepped
        // up from the first, a second at a time, it ran a hair past `ends` and the figure stayed
        // on 0:01 as the dot left.
        var secondsLeft = max(ends.timeIntervalSince(startDate).rounded(.down), 0)
        var first = true
        var settled = false
        return AnyIterator {
            if first {
                first = false
                return startDate
            }
            // One more just past `ends`, for a count that holds 0:00 after it ("Start in"
            // before its set begins): drawn at `ends` itself, it could still read 0:01.
            guard secondsLeft >= 0 else {
                guard !settled, ends > startDate else { return nil }
                settled = true
                return ends.addingTimeInterval(Self.settle)
            }
            defer { secondsLeft -= 1 }
            return ends.addingTimeInterval(-secondsLeft)
        }
    }

    /// How far past `ends` the last entry is drawn.
    private static let settle = 0.05
}

/// A countdown to VoiceOver alone, drawing nothing: `label` ("Rest", "Start in", "Time left"),
/// its time left as its value as the countdown shows it (`shown`), on the countdown's schedule,
/// for a countdown drawn inside an element that reads as one (`SetRest`).
struct SpokenRest: View {
    let block: RestBlock
    var label: LocalizedStringKey = "Rest"
    var shown: ClosedRange<Double> = 0 ... .infinity
    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(RestSchedule(
            ends: block.ends,
            isPaused: !block.ticks,
        )) { context in
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: 1)
                .accessibilityElement()
                .accessibilityLabel(Text(label))
                .accessibilityValue(RestBlock.spoken(
                    block.left(at: context.date, within: shown),
                    locale: locale,
                ))
        }
    }
}
