import Foundation
import Testing
@testable import PlusPlusKit

@Suite("Pace reference")
struct PaceReferenceTests {
    @Test("Every unit keeps the convention it used to imply")
    func unitDefaultsAreUnchanged() {
        // The whole point of splitting the denominator out is that nothing
        // already in the app moves. These four are the pre-swimming values,
        // asserted literally rather than through the new type.
        #expect(DistanceUnit.meters.paceLabel == "/500m")
        #expect(DistanceUnit.meters.paceReferenceMeters == 500)
        #expect(DistanceUnit.meters.paceRange == 60...300)
        #expect(DistanceUnit.meters.paceDefault == 120)
        #expect(DistanceUnit.meters.paceWheelStep == 1)

        #expect(DistanceUnit.kilometers.paceLabel == "/km")
        #expect(DistanceUnit.kilometers.paceReferenceMeters == 1000)
        #expect(DistanceUnit.kilometers.paceRange == 120...1200)
        #expect(DistanceUnit.kilometers.paceDefault == 360)
        #expect(DistanceUnit.kilometers.paceWheelStep == 5)

        #expect(DistanceUnit.miles.paceLabel == "/mi")
        #expect(abs(DistanceUnit.miles.paceReferenceMeters - 1609.344) < 0.000_001)
        #expect(DistanceUnit.miles.paceRange == 180...1800)
        #expect(DistanceUnit.miles.paceDefault == 600)
        #expect(DistanceUnit.miles.paceWheelStep == 5)
    }

    @Test("Yards is the pool's unit and splits per hundred")
    func yards() {
        #expect(DistanceUnit.yards.symbol == "yd")
        #expect(DistanceUnit.yards.paceLabel == "/100yd")
        #expect(abs(DistanceUnit.yards.paceReferenceMeters - 91.44) < 0.000_001)
        // A length of a short-course pool, both as the stride and the floor.
        #expect(DistanceUnit.yards.step == 25)
        #expect(DistanceUnit.yards.range.lowerBound == 25)
        // Splits are dialed to the second, like an erg's and unlike a road pace.
        #expect(DistanceUnit.yards.paceWheelStep == 1)
        // US denomination, so a speed dial beside it reads in mph.
        #expect(DistanceUnit.yards.speedLabel == "mph")
        #expect(abs(DistanceUnit.yards.metersPerUnit - 0.9144) < 0.000_001)
    }

    @Test("A profile's own reference overrides its unit's convention")
    func profileOverride() {
        // The case the whole type exists for: a metric pool is denominated
        // in meters exactly like an erg, and splits per 100, not per 500.
        let pool = MetricProfile([.distance, .duration, .pace],
                                 distanceUnit: .meters,
                                 paceReference: .per100Meters)
        #expect(pool.paceLabel == "/100m")
        #expect(pool.paceReferenceMeters == 100)
        #expect(pool.resolvedPaceReference == .per100Meters)
        // The distance unit itself is untouched — a declaration, never a
        // conversion, and the reference does not change what 2000 means.
        #expect(pool.distanceUnit == .meters)

        let erg = MetricProfile([.distance, .duration, .pace], distanceUnit: .meters)
        #expect(erg.paceLabel == "/500m")
        #expect(erg.resolvedPaceReference == .per500Meters)
    }

    @Test("Absent decodes to absent, and an unknown one falls back rather than bricking")
    func codec() throws {
        let pool = MetricProfile([.distance, .pace], distanceUnit: .yards, paceReference: .per100Yards)
        let round = try #require(MetricProfile.decode(from: pool.encoded()))
        #expect(round.paceReference == .per100Yards)

        // A profile written before this type carries no key at all, and must
        // decode byte-for-byte to what it always meant.
        let legacy = #"{"distanceUnit":"m","isOutdoor":false,"metrics":["distance","pace"]}"#
        let decoded = try #require(MetricProfile.decode(from: Data(legacy.utf8)))
        #expect(decoded.paceReference == nil)
        #expect(decoded.paceLabel == "/500m")

        // A denominator a future build invents must not take the profile
        // down with it — the unit's convention is the honest fallback.
        let future = #"{"distanceUnit":"m","metrics":["pace"],"paceReference":"per_furlong"}"#
        let tolerant = try #require(MetricProfile.decode(from: Data(future.utf8)))
        #expect(tolerant.paceReference == nil)
        #expect(tolerant.contains(.pace))
    }

    @Test("A swim's prescription derives against its own denominator")
    func derivationUsesTheReference() throws {
        let pool = MetricProfile([.distance, .duration, .pace],
                                 distanceUnit: .yards,
                                 paceReference: .per100Yards)
        // 1000 yards at 1:40 per 100 is sixteen forty.
        let seconds = CardioTargets.estimatedSeconds(profile: pool) { metric in
            switch metric {
            case .distance: 1000
            case .pace: 100
            default: nil
            }
        }
        #expect(seconds == 1000)

        // Read against the ERG's convention instead, the same numbers
        // collapse to about three minutes — a thousand-yard swim
        // advertised as a warm-up. That is the bug the reference prevents,
        // and it is why the denominator had to stop riding the unit.
        let asIfErg = try? #require(CardioTargets.derive(
            .duration, distance: 1000, durationSeconds: nil, paceSeconds: 100,
            unit: .yards, paceReference: .per500Meters
        ))
        #expect((asIfErg ?? 0) < 200)
    }

    @Test("Every reference is positive and dialable")
    func wellFormed() {
        for reference in PaceReference.allCases {
            #expect(reference.meters > 0)
            #expect(reference.range.lowerBound > 0)
            #expect(reference.range.contains(reference.defaultValue))
            #expect(reference.wheelStep > 0)
            #expect(reference.label.hasPrefix("/"))
        }
    }
}
