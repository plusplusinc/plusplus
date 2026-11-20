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

/// A rest's countdown to VoiceOver alone, drawing nothing: "Rest", its time left as its value, on
/// the countdown's schedule, for a rest drawn inside an element that reads as one (`SetRest`).
struct SpokenRest: View {
    let block: RestBlock
    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(RestSchedule(
            ends: block.ends,
            isPaused: block.pausedLeft != nil || block.stage != .open,
        )) { context in
            let left = block.pausedLeft ?? max(0, block.ends.timeIntervalSince(context.date))
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: 1)
                .accessibilityElement()
                .accessibilityLabel("Rest")
                .accessibilityValue(RestBlock.spoken(left, locale: locale))
        }
    }
}
