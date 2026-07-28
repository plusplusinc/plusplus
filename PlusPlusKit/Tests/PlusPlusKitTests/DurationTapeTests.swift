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

    // MARK: - The measured metrics (2026-07-28)

    @Test("Weight scrubs at half a pound — finer than a microplate, so 137.5 is exact")
    func weightTape() {
        let (quantum, tape) = WorkoutMetric.weight.scrubberTape(weightUnit: .lb)!
        #expect(quantum == 0.5)
        #expect(tape.range == 0...2000)
        // 137.5 lb → unit 275, round-tripping through the tape geometry.
        #expect(tape.unit(atOffset: tape.offset(for: 275)) == 275)
        // Marks on the wheel's old microplate grid (2.5 lb), labels every
        // 10 lb.
        let ticks = tape.ticks(in: tape.offset(for: 0)...tape.offset(for: 40))
        #expect(ticks.map(\.unit) == Array(stride(from: 0, through: 40, by: 5)))
        let byUnit = Dictionary(uniqueKeysWithValues: ticks.map { ($0.unit, $0) })
        #expect(byUnit[20]?.isLabeled == true)   // 10 lb
        #expect(byUnit[25]?.isLabeled == false)  // 12.5 lb

        // Kilos address quarters, so a 61.25 kg stack is reachable too.
        let (kgQuantum, kgTape) = WorkoutMetric.weight.scrubberTape(weightUnit: .kg)!
        #expect(kgQuantum == 0.25)
        #expect(kgTape.range == 0...4000)
        #expect(kgTape.unit(atOffset: kgTape.offset(for: 245)) == 245)

        // Assist spans its own (smaller) ceiling at the same grain.
        let assist = WorkoutMetric.assistance.scrubberTape(weightUnit: .lb)!
        #expect(assist.quantum == 0.5)
        #expect(assist.tape.range == 0...1000)
    }

    @Test("Reps scrub whole, one mark each, labeled every 5")
    func repsTape() {
        let (quantum, tape) = WorkoutMetric.reps.scrubberTape()!
        #expect(quantum == 1)
        #expect(tape.range == 1...100)
        let ticks = tape.ticks(in: tape.offset(for: 1)...tape.offset(for: 12))
        #expect(ticks.map(\.unit) == Array(1...12))
        let byUnit = Dictionary(uniqueKeysWithValues: ticks.map { ($0.unit, $0) })
        #expect(byUnit[10]?.isLabeled == true)
        #expect(byUnit[11]?.isLabeled == false)
    }

    @Test("Height follows its unit system: whole inches, or whole centimetres to 180")
    func heightTape() {
        let inches = WorkoutMetric.height.scrubberTape(weightUnit: .lb)!
        #expect(inches.quantum == 1)
        #expect(inches.tape.range == 1...72)
        #expect(inches.tape.ticks(in: inches.tape.offset(for: 1)...inches.tape.offset(for: 6)).count == 6)

        let cm = WorkoutMetric.height.scrubberTape(weightUnit: .kg)!
        #expect(cm.quantum == 1)
        #expect(cm.tape.range == 5...180)
    }

    @Test("Pace scrubs per SECOND on the road too — a 7:58 mile was unpickable on the 5 s wheel")
    func paceTape() {
        let (quantum, tape) = WorkoutMetric.pace.scrubberTape(distanceUnit: .miles)!
        #expect(quantum == 1)
        #expect(tape.range == 180...1800)
        // 7:58 /mi = 478 s, exactly reachable.
        #expect(tape.unit(atOffset: tape.offset(for: 478)) == 478)
        // Erg splits get the finer tape: a mark per second.
        let erg = WorkoutMetric.pace.scrubberTape(distanceUnit: .meters)!
        #expect(erg.tape.range == 60...300)
        #expect(erg.tape.ticks(in: erg.tape.offset(for: 120)...erg.tape.offset(for: 125)).count == 6)
    }

    @Test("Speed and incline scrub in tenths, marked on the half")
    func speedAndInclineTapes() {
        let (quantum, tape) = WorkoutMetric.speed.scrubberTape(distanceUnit: .miles)!
        #expect(quantum == 0.1)
        #expect(tape.range == 5...150)          // 0.5…15.0 mph in tenths
        #expect(tape.unit(atOffset: tape.offset(for: 63)) == 63)  // 6.3 mph
        let byUnit = Dictionary(uniqueKeysWithValues:
            tape.ticks(in: tape.offset(for: 50)...tape.offset(for: 70)).map { ($0.unit, $0) })
        #expect(byUnit[60]?.isLabeled == true)  // 6.0 mph
        #expect(byUnit[65]?.isLabeled == false) // 6.5 mph

        let incline = WorkoutMetric.incline.scrubberTape()!
        #expect(incline.quantum == 0.1)
        #expect(incline.tape.range == 0...150)  // 0…15 % in tenths
    }

    @Test("Power and cadence scrub whole across their full ranges")
    func powerAndCadenceTapes() {
        let power = WorkoutMetric.power.scrubberTape()!
        #expect(power.quantum == 1)
        #expect(power.tape.range == 5...1500)
        #expect(power.tape.unit(atOffset: power.tape.offset(for: 247)) == 247)

        let cadence = WorkoutMetric.cadence.scrubberTape()!
        #expect(cadence.quantum == 1)
        #expect(cadence.tape.range == 10...220)
        #expect(cadence.tape.unit(atOffset: cadence.tape.offset(for: 83)) == 83)
    }

    // MARK: - Classification

    @Test("Every measured metric scrubs; only the enumerated scales keep a wheel")
    func tapeScrubberMetrics() {
        for m in [WorkoutMetric.duration, .rest, .transition, .distance, .calories,
                  .weight, .assistance, .reps, .height, .pace, .speed, .incline,
                  .power, .cadence] {
            #expect(m.usesTapeScrubber, "\(m) should scrub")
            #expect(m.scrubberTape(weightUnit: .kg, distanceUnit: .miles) != nil)
        }
        // Machine resistance is 30 numbered levels and RPE is a subjective
        // 1–10 rating: their values ARE the list, so a ruler would claim a
        // precision that isn't there.
        for m in [WorkoutMetric.resistance, .rpe] {
            #expect(!m.usesTapeScrubber, "\(m) should wheel")
            #expect(m.scrubberTape() == nil)
        }
        // Distance and calories aren't time spans, so their readout is
        // number-plus-unit, not clock text.
        #expect(!WorkoutMetric.distance.isTimeSpan)
        #expect(!WorkoutMetric.calories.isTimeSpan)
    }

    @Test("Every metric: usesTapeScrubber iff scrubberTape is non-nil (the two switches can't drift)")
    func scrubberSwitchParity() {
        for m in WorkoutMetric.allCases {
            for weight in WeightUnit.allCases {
                for unit in DistanceUnit.allCases {
                    let parity = m.usesTapeScrubber
                        == (m.scrubberTape(weightUnit: weight, distanceUnit: unit) != nil)
                    #expect(parity, "\(m) disagrees for \(weight)/\(unit)")
                }
            }
        }
    }

    @Test("Every tape spans its metric's whole range, at a legal stride, with the marks on grid")
    func tapesAreWellFormed() {
        for m in WorkoutMetric.allCases {
            for weight in WeightUnit.allCases {
                for unit in DistanceUnit.allCases {
                    guard let (quantum, tape) = m.scrubberTape(weightUnit: weight, distanceUnit: unit) else { continue }
                    // The tape reaches exactly as far as the steppers and
                    // the wheel do — no metric can scrub past its own
                    // ceiling or stop short of it.
                    let bounds = m.range(weightUnit: weight, distanceUnit: unit)
                    #expect(Double(tape.range.lowerBound) * quantum == bounds.lowerBound, "\(m) low bound")
                    #expect(Double(tape.range.upperBound) * quantum == bounds.upperBound, "\(m) high bound")
                    // Labels sit ON the minor grid, or a labeled mark could
                    // never be drawn.
                    #expect(tape.labelStride % tape.minorStride == 0, "\(m) stride")
                    // The first mark is inside the range: a tape whose
                    // lower bound is off-grid would open with no tick under
                    // the caret.
                    let first = tape.ticks(in: 0...tape.offset(for: tape.range.lowerBound + tape.labelStride)).first
                    #expect(first != nil, "\(m) has no opening tick")
                    // A whole unit is addressable everywhere on the tape —
                    // the precision contract the wheel could not keep.
                    let mid = (tape.range.lowerBound + tape.range.upperBound) / 2
                    #expect(tape.unit(atOffset: tape.offset(for: mid)) == mid, "\(m) mid round-trip")
                }
            }
        }
    }
}
