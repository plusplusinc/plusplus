import Foundation
import Testing
@testable import PlusPlusKit

@Suite("CardioTargets — the two-of-three law")
struct CardioTargetsTests {
    private let run = MetricProfile([.distance, .duration, .pace], distanceUnit: .miles)
    private let erg = MetricProfile([.distance, .duration, .pace, .resistance], distanceUnit: .meters)

    private func bag(_ values: [WorkoutMetric: Double]) -> (WorkoutMetric) -> Double? {
        { values[$0] }
    }

    // MARK: - Applicability

    @Test("The law engages only where two of the triad are tracked")
    func applicability() {
        #expect(CardioTargets.applies(to: run))
        #expect(CardioTargets.applies(to: erg))
        // A plank, a curl, a bare distance carry — nothing to derive.
        #expect(!CardioTargets.applies(to: .durationOnly))
        #expect(!CardioTargets.applies(to: .weightReps))
        #expect(!CardioTargets.applies(to: MetricProfile([.distance])))
    }

    // MARK: - Derivation

    @Test("Distance and pace give duration: 5 mi at 9:00 is 45 minutes")
    func durationFromDistanceAndPace() throws {
        let seconds = try #require(CardioTargets.derive(
            .duration, distance: 5, durationSeconds: nil, paceSeconds: 540, unit: .miles
        ))
        #expect(abs(seconds - 2700) < 0.001)
    }

    @Test("Duration and pace give distance")
    func distanceFromDurationAndPace() throws {
        let miles = try #require(CardioTargets.derive(
            .distance, distance: nil, durationSeconds: 1800, paceSeconds: 540, unit: .miles
        ))
        #expect(abs(miles - (1800.0 / 540.0)) < 0.0001)
    }

    @Test("Distance and duration give pace")
    func paceFromDistanceAndDuration() throws {
        let pace = try #require(CardioTargets.derive(
            .pace, distance: 5, durationSeconds: 2700, paceSeconds: nil, unit: .miles
        ))
        #expect(abs(pace - 540) < 0.001)
    }

    @Test("Meters denominate pace per 500, not per meter")
    func ergReference() throws {
        // 2000 m at a 2:00 split is four 500s: eight minutes.
        let seconds = try #require(CardioTargets.derive(
            .duration, distance: 2000, durationSeconds: nil, paceSeconds: 120, unit: .meters
        ))
        #expect(abs(seconds - 480) < 0.001)

        let split = try #require(CardioTargets.derive(
            .pace, distance: 2000, durationSeconds: 480, paceSeconds: nil, unit: .meters
        ))
        #expect(abs(split - 120) < 0.001)
    }

    @Test("Derivation round-trips through all three metrics")
    func roundTrip() throws {
        for unit in DistanceUnit.allCases {
            let distance = unit == .meters ? 2000.0 : 5.0
            let pace = unit.paceDefault
            let duration = try #require(CardioTargets.derive(
                .duration, distance: distance, durationSeconds: nil, paceSeconds: pace, unit: unit
            ))
            let backToDistance = try #require(CardioTargets.derive(
                .distance, distance: nil, durationSeconds: duration, paceSeconds: pace, unit: unit
            ))
            let backToPace = try #require(CardioTargets.derive(
                .pace, distance: distance, durationSeconds: duration, paceSeconds: nil, unit: unit
            ))
            #expect(abs(backToDistance - distance) < 0.0001)
            #expect(abs(backToPace - pace) < 0.0001)
        }
    }

    @Test("Missing, zero and non-finite inputs derive nothing rather than an infinity")
    func degenerateInputs() {
        #expect(CardioTargets.derive(.duration, distance: 5, durationSeconds: nil, paceSeconds: nil, unit: .miles) == nil)
        #expect(CardioTargets.derive(.duration, distance: 0, durationSeconds: nil, paceSeconds: 540, unit: .miles) == nil)
        #expect(CardioTargets.derive(.distance, distance: nil, durationSeconds: 1800, paceSeconds: 0, unit: .miles) == nil)
        #expect(CardioTargets.derive(.pace, distance: 5, durationSeconds: 0, paceSeconds: nil, unit: .miles) == nil)
        // A metric outside the triad is never derivable.
        #expect(CardioTargets.derive(.weight, distance: 5, durationSeconds: 1800, paceSeconds: nil, unit: .miles) == nil)
    }

    // MARK: - Which one is derived

    @Test("The derived metric is whichever of the triad is unset")
    func derivedMetric() {
        #expect(CardioTargets.derivedMetric(profile: run, stored: bag([.distance: 5, .pace: 540])) == .duration)
        #expect(CardioTargets.derivedMetric(profile: run, stored: bag([.duration: 1800, .pace: 540])) == .distance)
        #expect(CardioTargets.derivedMetric(profile: run, stored: bag([.distance: 5, .duration: 2700])) == .pace)
    }

    @Test("Fewer than two stored derives nothing")
    func notEnoughToDeriveFrom() {
        #expect(CardioTargets.derivedMetric(profile: run, stored: bag([.distance: 5])) == nil)
        #expect(CardioTargets.derivedMetric(profile: run, stored: bag([:])) == nil)
        // All three stored (a pre-law store): nothing reads as derived,
        // and the next edit evicts one.
        #expect(CardioTargets.derivedMetric(profile: run, stored: bag([.distance: 5, .duration: 2700, .pace: 540])) == nil)
    }

    @Test("A profile tracking only two of the triad derives the tracked one")
    func partialTriad() {
        // Cycling tracks distance and duration but speed, not pace.
        let bike = MetricProfile([.distance, .duration, .speed], distanceUnit: .miles)
        #expect(CardioTargets.applies(to: bike))
        #expect(CardioTargets.derivedMetric(profile: bike, stored: bag([.distance: 12])) == .duration)
        #expect(CardioTargets.derivedMetric(profile: bike, stored: bag([.distance: 12, .duration: 3600])) == nil)
    }

    // MARK: - Eviction

    @Test("Entering a third value evicts pace first")
    func evictsPace() {
        #expect(CardioTargets.evicted(
            entering: .duration, profile: run, stored: bag([.distance: 5, .pace: 540])
        ) == .pace)
        #expect(CardioTargets.evicted(
            entering: .distance, profile: run, stored: bag([.duration: 1800, .pace: 540])
        ) == .pace)
    }

    @Test("With pace absent, duration makes room — distance ends the effort")
    func evictsDuration() {
        #expect(CardioTargets.evicted(
            entering: .pace, profile: run, stored: bag([.distance: 5, .duration: 2700])
        ) == .duration)
    }

    @Test("Nothing is evicted when there is room, or when the edit is an edit")
    func noEvictionNeeded() {
        #expect(CardioTargets.evicted(entering: .pace, profile: run, stored: bag([.distance: 5])) == nil)
        #expect(CardioTargets.evicted(entering: .distance, profile: run, stored: bag([:])) == nil)
        // Already stored: this is a value change, not a new third.
        #expect(CardioTargets.evicted(entering: .distance, profile: run, stored: bag([.distance: 5, .pace: 540])) == nil)
        // Outside the triad: weight never displaces a cardio target.
        #expect(CardioTargets.evicted(entering: .weight, profile: run, stored: bag([.distance: 5, .pace: 540])) == nil)
    }

    // MARK: - The driver must not move

    @Test("A DERIVED distance must never hijack a duration-driven set")
    func derivedValueNeverDrivesExecution() {
        // "30 minutes at 9:00/mi". Distance is derivable (3.33 mi) and
        // outranks duration in the driver's priority order — so if it were
        // ever written to storage, the set screen would switch to a
        // distance-driven odometer and the user's half-hour would vanish.
        let stored: [WorkoutMetric: Double] = [.duration: 1800, .pace: 540]
        #expect(CardioTargets.derivedMetric(profile: run, stored: bag(stored)) == .distance)

        // The driver reads STORED targets only, and there is no distance
        // among them, so duration keeps the set.
        #expect(run.driver(targets: bag(stored)) == .duration)

        // Sanity: an actually-stored distance does take it, which is the
        // behavior the law is protecting from an accidental write.
        #expect(run.driver(targets: bag([.distance: 5, .pace: 540])) == .distance)
    }

    // MARK: - Estimates

    @Test("A distance-and-pace prescription estimates honestly")
    func estimateFromDistanceAndPace() {
        // The bug this fixes: Routine.estimatedSeconds charged a flat 45 s
        // for any non-duration set, so a five-mile run read "45 seconds".
        #expect(CardioTargets.estimatedSeconds(profile: run, stored: bag([.distance: 5, .pace: 540])) == 2700)
        #expect(CardioTargets.estimatedSeconds(profile: erg, stored: bag([.distance: 2000, .pace: 120])) == 480)
    }

    @Test("A stored duration wins, and an open-ended effort estimates nothing")
    func estimateFallbacks() {
        #expect(CardioTargets.estimatedSeconds(profile: run, stored: bag([.duration: 1200])) == 1200)
        // Stored duration beats the derivable one rather than recomputing.
        #expect(CardioTargets.estimatedSeconds(profile: run, stored: bag([.duration: 1200, .distance: 5, .pace: 540])) == 1200)
        // Just go: no honest number exists, so none is invented.
        #expect(CardioTargets.estimatedSeconds(profile: run, stored: bag([:])) == nil)
        #expect(CardioTargets.estimatedSeconds(profile: run, stored: bag([.distance: 5])) == nil)
    }
}

@Suite("DistanceUnit — meters both ways")
struct DistanceUnitConversionTests {
    @Test("meters(from:) inverts value(fromMeters:)")
    func inverse() {
        for unit in DistanceUnit.allCases {
            let value = 3.5
            #expect(abs(unit.value(fromMeters: unit.meters(from: value)) - value) < 0.000_001)
        }
    }

    @Test("Known conversions")
    func known() {
        #expect(DistanceUnit.meters.meters(from: 500) == 500)
        #expect(DistanceUnit.kilometers.meters(from: 5) == 5000)
        #expect(abs(DistanceUnit.miles.meters(from: 1) - 1609.344) < 0.000_001)
    }
}
