import Foundation
import Testing
import PlusPlusKit

@Suite("Duration tape")
struct DurationTapeTests {
    // The two tapes the app actually builds.
    let duration = DurationTape(range: 5...3600)
    let rest = DurationTape(range: 15...600)

    @Test("Offset mapping is linear from the lower bound")
    func offsetMapping() {
        #expect(duration.offset(for: 5) == 0)
        #expect(duration.offset(for: 6) == 3)
        #expect(duration.offset(for: 65) == 180)
        #expect(duration.offset(for: 3600) == duration.length)
        #expect(duration.length == 3595 * 3)
        #expect(rest.offset(for: 15) == 0)
        #expect(rest.length == 585 * 3)
    }

    @Test("Offsets round to the nearest whole second and clamp at the ends")
    func secondsAtOffset() {
        #expect(duration.seconds(atOffset: 0) == 5)
        #expect(duration.seconds(atOffset: 1.4) == 5)
        #expect(duration.seconds(atOffset: 1.6) == 6)
        // Rubber-band overshoot past either end clamps.
        #expect(duration.seconds(atOffset: -50) == 5)
        #expect(duration.seconds(atOffset: duration.length + 50) == 3600)
        #expect(rest.seconds(atOffset: -1) == 15)
    }

    @Test("Every integer second round-trips exactly — the precision contract")
    func roundTrip() {
        for s in [5, 6, 37, 97, 100, 3599, 3600] {
            #expect(duration.seconds(atOffset: duration.offset(for: s)) == s)
        }
        #expect(duration.clamped(4) == 5)
        #expect(duration.clamped(4000) == 3600)
    }

    @Test("Visible-window ticks: 5 s marks, labels at 30 s and whole minutes")
    func tickSchedule() {
        // Window covering tape offsets for ~5 s through ~70 s.
        let ticks = duration.ticks(in: 0...duration.offset(for: 70))
        #expect(ticks.map(\.seconds) == Array(stride(from: 5, through: 70, by: 5)))

        let byS = Dictionary(uniqueKeysWithValues: ticks.map { ($0.seconds, $0) })
        #expect(byS[30]?.label == "30s")
        #expect(byS[60]?.label == "1:00")
        #expect(byS[35]?.label == nil)
        #expect(byS[40]?.label == nil)
    }

    @Test("Ticks never escape the range and an empty window yields nothing")
    func tickBounds() {
        let low = rest.ticks(in: -100...0)
        #expect(low.first?.seconds == 15)
        let high = rest.ticks(in: (rest.length - 1)...(rest.length + 200))
        #expect(high.last?.seconds == 600)
        #expect(duration.ticks(in: 10...11).isEmpty)
    }

    @Test("Labels read clock-style: seconds under a minute, m:ss after")
    func labels() {
        #expect(DurationTape.label(for: 45) == "45s")
        #expect(DurationTape.label(for: 60) == "1:00")
        #expect(DurationTape.label(for: 97) == "1:37")
        #expect(DurationTape.label(for: 750) == "12:30")
        #expect(DurationTape.label(for: 3600) == "60:00")
    }

    @Test("Duration and rest are time spans; pace is a rate, reps aren't time")
    func timeSpanMetrics() {
        #expect(WorkoutMetric.duration.isTimeSpan)
        #expect(WorkoutMetric.rest.isTimeSpan)
        #expect(!WorkoutMetric.pace.isTimeSpan)
        #expect(!WorkoutMetric.reps.isTimeSpan)
    }
}
