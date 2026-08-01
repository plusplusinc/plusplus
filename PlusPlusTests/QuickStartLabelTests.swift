import Foundation
import Testing
import PlusPlusKit
@testable import PlusPlus

/// A quick-start key is a command, so it wears the imperative — "Run",
/// never "Running" (Dave, build 159).
@Suite("Quick-start labels")
struct QuickStartLabelTests {
    private func builtIn(_ name: String) -> Exercise {
        Exercise(name: name, muscleGroup: .fullBody, exerciseType: .duration, isBuiltIn: true)
    }

    @Test("Every gerund-named built-in speaks a verb")
    func builtInsSpeakVerbs() {
        #expect(QuickStartLabel.text(for: builtIn("Running")) == "Run")
        #expect(QuickStartLabel.text(for: builtIn("Walking")) == "Walk")
        #expect(QuickStartLabel.text(for: builtIn("Hiking")) == "Hike")
        #expect(QuickStartLabel.text(for: builtIn("Cycling")) == "Ride")
        #expect(QuickStartLabel.text(for: builtIn("Indoor Cycling")) == "Spin")
        #expect(QuickStartLabel.text(for: builtIn("Rowing")) == "Row")
        #expect(QuickStartLabel.text(for: builtIn("Pool Swim")) == "Swim")
        #expect(QuickStartLabel.text(for: builtIn("Open Water Swim")) == "Swim open water")
    }

    @Test("The authored labels are UNIQUE, so built-in picks never collide")
    func authoredLabelsAreUnique() {
        let names = ["Running", "Treadmill Run", "Walking", "Hiking", "Cycling",
                     "Indoor Cycling", "Rowing", "Pool Swim", "Open Water Swim"]
        let labels = names.map { QuickStartLabel.text(for: builtIn($0)) }
        #expect(Set(labels).count == labels.count)
    }

    @Test("A custom falls back to its modality's verb, and a verbless one keeps its name")
    func customFallsBack() {
        // A bare cardio profile derives the generic family, which has no
        // verb of its own — the name stands. A noun key beats a wrong verb.
        let custom = Exercise(name: "Probe Intervals", muscleGroup: .fullBody, exerciseType: .duration)
        custom.metricProfile = MetricProfile([.distance, .duration, .pace])
        #expect(QuickStartLabel.text(for: custom) == "Probe Intervals")

        // The console machines with no imperative keep their names too.
        let elliptical = builtIn("Elliptical")
        #expect(QuickStartLabel.text(for: elliptical) == "Elliptical")
    }
}
