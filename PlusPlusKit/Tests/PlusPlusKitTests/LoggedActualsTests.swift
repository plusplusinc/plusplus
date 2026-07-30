import Foundation
import Testing
@testable import PlusPlusKit

@Suite("LoggedActuals — what a device may honestly claim")
struct LoggedActualsTests {
    @Test("An unmeasured distance is dropped, never inherited from the plan")
    func unmeasuredDistanceIsNotInvented() {
        // The bug: an erg piece planned at 500 m, logged on a wrist that
        // measures nothing indoors, recorded 500 m as though it happened.
        let actuals = LoggedActuals.extras(planned: [.distance: 500, .resistance: 5])
        #expect(actuals[.distance] == nil)
        // The damper is something the user SET, so it carries.
        #expect(actuals[.resistance] == 5)
    }

    @Test("A measurement wins over the plan, short or long")
    func measurementWins() {
        let short = LoggedActuals.extras(
            planned: [.distance: 500, .pace: 120],
            measured: [.distance: 412, .pace: 128]
        )
        #expect(short[.distance] == 412)
        #expect(short[.pace] == 128)

        let long = LoggedActuals.extras(
            planned: [.distance: 5],
            measured: [.distance: 5.4]
        )
        #expect(long[.distance] == 5.4)
    }

    @Test("Settings and counts the user asserted carry forward")
    func assertedValuesCarry() {
        let actuals = LoggedActuals.extras(
            planned: [.resistance: 7, .incline: 2.5, .cadence: 90, .rpe: 8]
        )
        #expect(actuals[.resistance] == 7)
        #expect(actuals[.incline] == 2.5)
        #expect(actuals[.cadence] == 90)
        #expect(actuals[.rpe] == 8)
    }

    @Test("A degenerate measurement is not recorded")
    func degenerateMeasurementIgnored() {
        // Standing still for a whole piece measures zero metres, which is
        // not a distance — the same positive-measurement gate the run
        // summary applies (#378).
        let zero = LoggedActuals.extras(planned: [.distance: 500], measured: [.distance: 0])
        #expect(zero[.distance] == nil)
        let broken = LoggedActuals.extras(planned: [.distance: 500], measured: [.distance: .nan])
        #expect(broken[.distance] == nil)
    }

    @Test("Nothing planned and nothing measured records nothing")
    func empty() {
        #expect(LoggedActuals.extras(planned: [:]).isEmpty)
    }

    @Test("Per-effort pace comes from that effort's own numbers")
    func perEffortPace() throws {
        // 500 m in 2:03 is a 2:03 split, not the session average.
        let split = try #require(LoggedActuals.pace(distance: 500, elapsedSeconds: 123, unit: .meters))
        #expect(abs(split - 123) < 0.001)

        let mile = try #require(LoggedActuals.pace(distance: 2, elapsedSeconds: 1100, unit: .miles))
        #expect(abs(mile - 550) < 0.001)
    }

    @Test("Pace needs both halves and refuses to divide by nothing")
    func paceDegenerate() {
        #expect(LoggedActuals.pace(distance: nil, elapsedSeconds: 600, unit: .miles) == nil)
        #expect(LoggedActuals.pace(distance: 3, elapsedSeconds: nil, unit: .miles) == nil)
        #expect(LoggedActuals.pace(distance: 0, elapsedSeconds: 600, unit: .miles) == nil)
        #expect(LoggedActuals.pace(distance: 3, elapsedSeconds: 0, unit: .miles) == nil)
    }
}
