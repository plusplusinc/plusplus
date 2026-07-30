import Foundation
import Testing
@testable import PlusPlusKit

@Suite("Cardio hero")
struct CardioHeroTests {
    private let run = MetricProfile([.distance, .duration, .pace], distanceUnit: .miles, isOutdoor: true)
    private let erg = MetricProfile([.distance, .duration, .pace, .resistance])
    private let spin = MetricProfile([.duration, .distance, .resistance, .power, .cadence], distanceUnit: .miles)

    private func targets(_ values: [WorkoutMetric: Double]) -> (WorkoutMetric) -> Double? {
        { values[$0] }
    }

    /// What the phone can read with no location fix: the clock, and only
    /// the clock.
    private let indoors: Set<WorkoutMetric> = [.duration]
    private let underGPS: Set<WorkoutMetric> = [.duration, .distance, .pace]

    @Test("Rep work is not a continuous effort and keeps its stage")
    func repWorkOptsOut() {
        #expect(CardioHero.resolve(profile: .weightReps, target: targets([:]), measurable: indoors) == nil)
        #expect(CardioHero.resolve(profile: .repsOnly, target: targets([.reps: 10]), measurable: indoors) == nil)
    }

    @Test("A distance target under GPS counts down the distance")
    func distanceHero() throws {
        let r = try #require(CardioHero.resolve(
            profile: run, target: targets([.distance: 5, .pace: 540]), measurable: underGPS
        ))
        #expect(r.hero == .progress(metric: .distance, target: 5))
        #expect(r.unmeasurableTarget == nil)
        #expect(!r.hero.isClock)
    }

    @Test("A targeted timed effort still counts down, exactly as before")
    func durationHero() throws {
        let r = try #require(CardioHero.resolve(
            profile: spin, target: targets([.duration: 2700]), measurable: indoors
        ))
        #expect(r.hero == .progress(metric: .duration, target: 2700))
        #expect(r.hero.isClock)
        #expect(r.hero.countsDown)
    }

    @Test("A prescribed indoor distance keeps its stage and gets no apology")
    func indoorTargetIsSelfReported() throws {
        // A 4 x 500 m erg piece was ALWAYS read off the console. Nothing
        // was lost, so nothing degrades and nothing apologises — the
        // stage stays exactly as it was. Before this split, the same
        // resolution printed "no gps fix" beside a rowing machine, and
        // beside a swimming pool.
        let r = try #require(CardioHero.resolve(
            profile: erg, target: targets([.distance: 500]), measurable: indoors
        ))
        #expect(r.hero == .selfReported(metric: .distance, target: 500))
        #expect(!r.hero.isClock)
        #expect(r.unmeasurableTarget == nil)

        // A pool swim is indoors too, and a calorie target on an air bike
        // is the same shape.
        let pool = MetricProfile([.distance, .duration, .pace], distanceUnit: .yards, paceReference: .per100Yards)
        let swim = try #require(CardioHero.resolve(
            profile: pool, target: targets([.distance: 1000]), measurable: indoors
        ))
        #expect(swim.unmeasurableTarget == nil)
        #expect(!swim.hero.isClock)
    }

    @Test("Losing the fix degrades a distance hero to the clock, and says so")
    func degradesAndExplains() throws {
        let r = try #require(CardioHero.resolve(
            profile: run, target: targets([.distance: 5, .pace: 540]), measurable: indoors
        ))
        // Nothing can watch five miles indoors, so the clock takes over —
        // and the screen has the reason to print rather than silently
        // showing a different number than the one you asked for.
        #expect(r.hero == .elapsed)
        #expect(r.unmeasurableTarget == .distance)
    }

    @Test("A distance-and-duration prescription falls back to the duration, not to zero")
    func fallsBackToTheOtherTarget() throws {
        let r = try #require(CardioHero.resolve(
            profile: run, target: targets([.distance: 5, .duration: 2700]), measurable: indoors
        ))
        // Distance outranks duration and is unwatchable, but the duration
        // target is right there and the clock can watch it.
        #expect(r.hero == .progress(metric: .duration, target: 2700))
        #expect(r.unmeasurableTarget == nil)
    }

    @Test("An open-ended run under GPS watches the distance climb")
    func openEndedUnderGPS() throws {
        let r = try #require(CardioHero.resolve(profile: run, target: targets([:]), measurable: underGPS))
        #expect(r.hero == .measured(.distance))
        #expect(!r.hero.isClock)
    }

    @Test("An open-ended indoor effort counts up, which is the whole point")
    func openEndedIndoors() throws {
        // The two shapes quick start creates: a run with no prescription,
        // and a studio ride that deliberately ships without one. Both had
        // NO clock before this — a card reading "—" and a Log key.
        for profile in [run, erg, spin] {
            let r = try #require(CardioHero.resolve(profile: profile, target: targets([:]), measurable: indoors))
            #expect(r.hero == .elapsed)
            #expect(r.hero.isClock)
            #expect(!r.hero.countsDown)
            #expect(r.unmeasurableTarget == nil)
        }
    }

    @Test("A calorie target is self-reported, not an apology")
    func calorieTarget() throws {
        let bike = MetricProfile([.calories, .duration, .resistance])
        let r = try #require(CardioHero.resolve(
            profile: bike, target: targets([.calories: 300]), measurable: indoors
        ))
        // The bike's console counts the calories. Nothing here ever did,
        // so there is nothing to say sorry for.
        #expect(r.hero == .selfReported(metric: .calories, target: 300))
        #expect(r.unmeasurableTarget == nil)
    }

    @Test("A zero or negative target is not a target")
    func zeroTarget() throws {
        let r = try #require(CardioHero.resolve(
            profile: run, target: targets([.distance: 0]), measurable: underGPS
        ))
        // Zero miles is not something to close on; the live reading wins
        // and nothing is reported as stranded.
        #expect(r.hero == .measured(.distance))
        #expect(r.unmeasurableTarget == nil)
    }

    @Test("The chain always terminates")
    func alwaysTerminates() {
        // Every combination of the profiles and target sets the app can
        // produce resolves to something: a hero that can be absent is not
        // a hero, and the set screen has no other big number to show.
        let profiles = [run, erg, spin, MetricProfile([.duration]), MetricProfile([.calories, .duration])]
        let targetSets: [[WorkoutMetric: Double]] = [
            [:], [.distance: 5], [.duration: 600], [.pace: 540],
            [.distance: 5, .duration: 600], [.calories: 200],
        ]
        for profile in profiles {
            for values in targetSets {
                for measurable in [indoors, underGPS] {
                    #expect(CardioHero.resolve(profile: profile, target: targets(values), measurable: measurable) != nil)
                }
            }
        }
    }
}
