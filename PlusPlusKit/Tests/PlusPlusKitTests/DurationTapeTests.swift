import Foundation
import Testing
import PlusPlusKit

@Suite("Metric tape")
struct MetricTapeTests {
    // The duration/rest tapes the app builds, via the metric factory so the
    // strides under test are the ones production uses.
    let duration = WorkoutMetric.duration.scrubberTape()!.tape
    let rest = WorkoutMetric.rest.scrubberTape()!.tape

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

    @Test("Offsets round to the nearest whole unit and clamp at the ends")
    func unitAtOffset() {
        #expect(duration.unit(atOffset: 0) == 5)
        #expect(duration.unit(atOffset: 1.4) == 5)
        #expect(duration.unit(atOffset: 1.6) == 6)
        // Rubber-band overshoot past either end clamps.
        #expect(duration.unit(atOffset: -50) == 5)
        #expect(duration.unit(atOffset: duration.length + 50) == 3600)
        #expect(rest.unit(atOffset: -1) == 15)
    }

    @Test("Every whole unit round-trips exactly — the precision contract")
    func roundTrip() {
        for s in [5, 6, 37, 97, 100, 3599, 3600] {
            #expect(duration.unit(atOffset: duration.offset(for: s)) == s)
        }
        #expect(duration.clamped(4) == 5)
        #expect(duration.clamped(4000) == 3600)
    }

    @Test("Visible-window ticks: 5 s marks, labels at 30 s and whole minutes")
    func tickSchedule() {
        // Window covering tape offsets for ~5 s through ~70 s.
        let ticks = duration.ticks(in: 0...duration.offset(for: 70))
        #expect(ticks.map(\.unit) == Array(stride(from: 5, through: 70, by: 5)))

        let byUnit = Dictionary(uniqueKeysWithValues: ticks.map { ($0.unit, $0) })
        #expect(byUnit[30]?.isLabeled == true)
        #expect(byUnit[60]?.isLabeled == true)
        #expect(byUnit[35]?.isLabeled == false)
        #expect(byUnit[40]?.isLabeled == false)
    }

    @Test("Ticks never escape the range and an empty window yields nothing")
    func tickBounds() {
        let low = rest.ticks(in: -100...0)
        #expect(low.first?.unit == 15)
        let high = rest.ticks(in: (rest.length - 1)...(rest.length + 200))
        #expect(high.last?.unit == 600)
        #expect(duration.ticks(in: 10...11).isEmpty)
    }

    @Test("The transition tape starts at zero — 0s is a legal pick (no countdown)")
    func transitionTape() {
        let transition = WorkoutMetric.transition.scrubberTape()!.tape
        #expect(transition.offset(for: 0) == 0)
        #expect(transition.unit(atOffset: -10) == 0)
        #expect(transition.ticks(in: 0...30).first?.unit == 0)
    }

    // MARK: - Distance

    @Test("Metered distance scrubs in whole meters, marks every 25, labels every 250")
    func meterTape() {
        let (quantum, tape) = WorkoutMetric.distance.scrubberTape(distanceUnit: .meters)!
        #expect(quantum == 1)
        #expect(tape.range == 25...50000)
        // A hand-set 425 m sled course round-trips exactly.
        #expect(tape.unit(atOffset: tape.offset(for: 425)) == 425)
        let ticks = tape.ticks(in: tape.offset(for: 25)...tape.offset(for: 300))
        #expect(ticks.map(\.unit) == Array(stride(from: 25, through: 300, by: 25)))
        let byUnit = Dictionary(uniqueKeysWithValues: ticks.map { ($0.unit, $0) })
        #expect(byUnit[250]?.isLabeled == true)
        #expect(byUnit[275]?.isLabeled == false)
    }

    @Test("Mile/kilometer distance scrubs in hundredths, so 3.14 mi is reachable")
    func mileTape() {
        let (quantum, tape) = WorkoutMetric.distance.scrubberTape(distanceUnit: .miles)!
        #expect(quantum == 0.01)
        #expect(tape.range == 25...10000)      // 0.25…100 mi in hundredths
        // 3.14 mi → unit 314, and it round-trips.
        #expect(tape.unit(atOffset: tape.offset(for: 314)) == 314)
        // Labels land on the 0.25 grid (units 25, 50, 75, 100 = 0.25…1.0).
        let ticks = tape.ticks(in: tape.offset(for: 25)...tape.offset(for: 100))
        let byUnit = Dictionary(uniqueKeysWithValues: ticks.map { ($0.unit, $0) })
        #expect(byUnit[25]?.isLabeled == true)
        #expect(byUnit[50]?.isLabeled == true)
        #expect(byUnit[30]?.isLabeled == false)

        let km = WorkoutMetric.distance.scrubberTape(distanceUnit: .kilometers)!
        #expect(km.quantum == 0.01)
        #expect(km.tape.range == 25...10000)
    }

    @Test("Calories scrub per-calorie across the whole 1…2000 range")
    func calorieTape() {
        let (quantum, tape) = WorkoutMetric.calories.scrubberTape()!
        #expect(quantum == 1)
        #expect(tape.range == 1...2000)
        #expect(tape.unit(atOffset: tape.offset(for: 137)) == 137)
    }

    // MARK: - Classification

    @Test("Labels read clock-style: seconds under a minute, m:ss after")
    func labels() {
        #expect(DurationTape.label(for: 45) == "45s")
        #expect(DurationTape.label(for: 60) == "1:00")
        #expect(DurationTape.label(for: 97) == "1:37")
        #expect(DurationTape.label(for: 750) == "12:30")
        #expect(DurationTape.label(for: 3600) == "60:00")
        #expect(DurationTape.label(for: 0) == "0s")
    }

    @Test("Duration, rest, and transition are time spans; pace is a rate, reps aren't time")
    func timeSpanMetrics() {
        #expect(WorkoutMetric.duration.isTimeSpan)
        #expect(WorkoutMetric.rest.isTimeSpan)
        #expect(WorkoutMetric.transition.isTimeSpan)
        #expect(!WorkoutMetric.pace.isTimeSpan)
        #expect(!WorkoutMetric.reps.isTimeSpan)
    }

    @Test("Tape scrubbing covers time spans plus distance and calories; wheels keep the rest")
    func tapeScrubberMetrics() {
        for m in [WorkoutMetric.duration, .rest, .transition, .distance, .calories] {
            #expect(m.usesTapeScrubber)
            #expect(m.scrubberTape(distanceUnit: .miles) != nil)
        }
        for m in [WorkoutMetric.weight, .reps, .pace, .speed, .incline, .power, .rpe] {
            #expect(!m.usesTapeScrubber)
            #expect(m.scrubberTape() == nil)
        }
        // Distance and calories aren't time spans, so their readout is
        // number-plus-unit, not clock text.
        #expect(!WorkoutMetric.distance.isTimeSpan)
        #expect(!WorkoutMetric.calories.isTimeSpan)
    }
}
