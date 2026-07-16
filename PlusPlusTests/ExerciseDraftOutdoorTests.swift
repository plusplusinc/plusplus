import Foundation
import Testing
import PlusPlusKit
@testable import PlusPlus

/// The isOutdoor-drop bug (#378, swift-reviewer catch): the draft rebuilt
/// profiles without the flag, so ANY edit of an outdoor exercise stored an
/// explicit indoor profile and silently killed live pace + route capture.
/// Pure-logic tests (the draft is SwiftUI-free by design).
@Suite("ExerciseDraft outdoor flag")
struct ExerciseDraftOutdoorTests {
    @Test("An edit round-trips the outdoor flag instead of dropping it")
    func editKeepsOutdoor() {
        let exercise = Exercise(name: "Probe Trail Run", muscleGroup: .fullBody)
        exercise.metricProfile = MetricProfile([.distance, .duration, .pace], distanceUnit: .miles, isOutdoor: true)

        let draft = ExerciseDraft(from: exercise)
        #expect(draft.isOutdoor)
        #expect(draft.metricProfile.isOutdoor, "the rebuilt profile must carry the flag")

        draft.apply(to: exercise)
        let stored = MetricProfile.decode(from: exercise.metricsData)
        #expect(stored?.isOutdoor == true, "saving an untouched outdoor exercise must not store an indoor profile")
    }

    @Test("Dropping the last distance/pace metric drops the flag")
    func flagRequiresAFeedingMetric() {
        let draft = ExerciseDraft()
        draft.setProfile(MetricProfile([.distance, .duration, .pace], distanceUnit: .miles, isOutdoor: true))
        #expect(draft.canBeOutdoor)

        draft.toggleMetric(.distance)
        draft.toggleMetric(.pace)
        #expect(!draft.canBeOutdoor)
        // The stored flag stays latched (re-adding distance restores it),
        // but the PROFILE suppresses it — a bare isOutdoor fails
        // interchange validation and could make a repo restore throw.
        #expect(!draft.metricProfile.isOutdoor)

        draft.toggleMetric(.distance)
        #expect(draft.metricProfile.isOutdoor, "re-adding a feeding metric restores the latched flag")
    }

    @Test("Adopting a suggested or canonical profile carries the flag")
    func adoptionCarriesFlag() {
        let fresh = ExerciseDraft()
        fresh.adoptSuggestedProfile(MetricProfile([.distance, .pace], distanceUnit: .kilometers, isOutdoor: true))
        #expect(fresh.metricProfile.isOutdoor)

        let reverted = ExerciseDraft()
        reverted.setProfile(MetricProfile([.distance, .duration], distanceUnit: .miles, isOutdoor: true))
        #expect(reverted.metricProfile.isOutdoor)
    }
}
