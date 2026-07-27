import Foundation
import Testing
@testable import PlusPlusKit

@Suite("Prescription")
struct PrescriptionTests {
    private let lifting = MetricProfile([.weight, .reps])
    private let assisted = MetricProfile([.assistance, .reps])
    private let rowing = MetricProfile([.distance, .duration], distanceUnit: .meters)
    private let running = MetricProfile([.distance, .duration, .pace], distanceUnit: .miles)

    private func texts(_ runs: [PrescriptionRun]) -> String {
        runs.map(\.text).joined()
    }

    // MARK: - Shape

    @Test("A lifting block reads sets, reps and load")
    func liftingBlock() {
        let runs = Prescription.blockRuns(
            target: RoutineDiff.Target(name: "Bench Press", sets: 3, weight: 135, reps: 8),
            profile: lifting
        )
        #expect(texts(runs) == "3×8 @ 135 lb")
        #expect(runs == [
            PrescriptionRun("3", .sets),
            PrescriptionRun("×"),
            PrescriptionRun("8", .metric(.reps)),
            PrescriptionRun(" @ "),
            PrescriptionRun("135 lb", .metric(.weight)),
        ])
    }

    @Test("Separators carry no field, so they are never lit")
    func separatorsAreUntagged() {
        let runs = Prescription.blockRuns(
            target: RoutineDiff.Target(name: "Bench Press", sets: 3, weight: 135, reps: 8),
            profile: lifting
        )
        #expect(runs.filter { $0.field == nil }.map(\.text) == ["×", " @ "])
    }

    @Test("A rep range renders as a range")
    func repRange() {
        let runs = Prescription.blockRuns(
            target: RoutineDiff.Target(name: "Row", sets: 4, weight: 95, reps: 8, repsUpper: 10),
            profile: lifting
        )
        #expect(texts(runs) == "4×8–10 @ 95 lb")
    }

    @Test("An inverted rep range collapses to the single number")
    func invertedRepRange() {
        // RepTarget drops an upper at or below the lower; the raw column can
        // hold one after a hand-edited import.
        let runs = Prescription.blockRuns(
            target: RoutineDiff.Target(name: "Row", sets: 3, weight: 95, reps: 10, repsUpper: 8),
            profile: lifting
        )
        #expect(texts(runs) == "3×10 @ 95 lb")
    }

    @Test("No load emits no dangling separator")
    func bodyweightBlock() {
        let runs = Prescription.blockRuns(
            target: RoutineDiff.Target(name: "Push-Up", sets: 3, reps: 12),
            profile: MetricProfile([.reps])
        )
        #expect(texts(runs) == "3×12")
        #expect(runs.last?.field == .metric(.reps))
    }

    @Test("A zero weight is not a load")
    func zeroWeightIsOmitted() {
        let runs = Prescription.blockRuns(
            target: RoutineDiff.Target(name: "Push-Up", sets: 3, weight: 0, reps: 12),
            profile: lifting
        )
        #expect(texts(runs) == "3×12")
    }

    @Test("A cardio block reads rounds times the work target")
    func cardioBlock() {
        let runs = Prescription.blockRuns(
            target: RoutineDiff.Target(name: "Rowing", sets: 4, extras: [.distance: 500], distanceUnit: .meters),
            profile: rowing
        )
        #expect(texts(runs) == "4× 500 m")
        #expect(runs.last?.field == .metric(.distance))
    }

    @Test("An empty prescription renders nothing at all")
    func emptyBlock() {
        #expect(Prescription.blockRuns(
            target: RoutineDiff.Target(name: "Unknown"),
            profile: lifting
        ).isEmpty)
    }

    // MARK: - Assistance as a negative load

    @Test("Assistance renders as a negative load, in the app's weight unit")
    func assistanceIsNegative() {
        let target = RoutineDiff.Target(name: "Assisted Pull-Up", sets: 3, reps: 6, extras: [.assistance: 25])
        #expect(texts(Prescription.blockRuns(target: target, profile: assisted)) == "3×6 @ −25 lb")
        #expect(texts(Prescription.blockRuns(target: target, profile: assisted, weightUnit: .kg)) == "3×6 @ −25 kg")
    }

    @Test("Assistance reaches the card at all")
    func assistanceIsNotDropped() {
        // The regression this closes: the previous formatter appended a load
        // by reading the WEIGHT column, but an assisted profile stores its
        // load in the extras bag, so the exercise rendered a bare "3×6".
        let runs = Prescription.blockRuns(
            target: RoutineDiff.Target(name: "Assisted Pull-Up", sets: 3, reps: 6, extras: [.assistance: 25]),
            profile: assisted
        )
        #expect(runs.contains { $0.field == .metric(.assistance) })
    }

    @Test("Assistance takes the load slot even when a weight is stored")
    func assistanceOutranksAStrandedWeight() {
        // Pre-profile assisted prescriptions lived in the weight column; the
        // bag wins so the slot never shows two loads.
        let runs = Prescription.blockRuns(
            target: RoutineDiff.Target(name: "Assisted Pull-Up", sets: 3, weight: 40, reps: 6, extras: [.assistance: 25]),
            profile: assisted
        )
        #expect(texts(runs) == "3×6 @ −25 lb")
    }

    @Test("A signed assist value cannot render a double minus")
    func assistanceNormalizesItsSign() {
        #expect(Prescription.text(for: .metric(.assistance), value: -25) == "−25 lb")
    }

    // MARK: - Field text

    @Test("Sets render as a bare count")
    func setsText() {
        #expect(Prescription.text(for: .sets, value: 4) == "4")
    }

    @Test("Every other metric defers to its own formatter")
    func metricTextMatchesDisplayText() {
        #expect(Prescription.text(for: .metric(.weight), value: 135) == WorkoutMetric.weight.displayText(135))
        #expect(Prescription.text(for: .metric(.pace), value: 720, distanceUnit: .miles)
            == WorkoutMetric.pace.displayText(720, distanceUnit: .miles))
    }

    // MARK: - The two columns line up

    @Test("An unmoved prescription renders identically on both sides")
    func columnsAlignWhenNothingMoved() {
        // The property the ledger leans on: identical characters sit above
        // each other, so the token that differs is the only thing that moves.
        let target = RoutineDiff.Target(name: "Bench Press", sets: 3, weight: 135, reps: 8)
        let prior = RoutineDiff.Prior(sets: 3, weight: 135, reps: 8)
        #expect(
            Prescription.blockRuns(target: target, profile: lifting)
                == Prescription.blockRuns(prior: prior, profile: lifting)
        )
        #expect(RoutineDiff.changedFields(target: target, prior: prior).isEmpty)
    }

    @Test("A moved load differs in exactly the load run")
    func onlyTheMovedRunDiffers() {
        let target = RoutineDiff.Target(name: "Bench Press", sets: 3, weight: 135, reps: 8)
        let prior = RoutineDiff.Prior(sets: 3, weight: 130, reps: 8)
        let staged = Prescription.blockRuns(target: target, profile: lifting)
        let last = Prescription.blockRuns(prior: prior, profile: lifting)

        #expect(staged.count == last.count)
        let differing = zip(staged, last).filter { $0.0 != $0.1 }
        #expect(differing.count == 1)
        #expect(differing.first?.0.field == .metric(.weight))
        // And the diff engine agrees about which run to light.
        #expect(RoutineDiff.changedFields(target: target, prior: prior) == [.metric(.weight)])
    }

    @Test("The prior column never renders a rep range")
    func priorHasNoRange() {
        // An actual is one count. Passing a range through would make the
        // columns disagree about what a performance can even be.
        let runs = Prescription.blockRuns(
            prior: RoutineDiff.Prior(sets: 3, weight: 95, reps: 9),
            profile: lifting
        )
        #expect(texts(runs) == "3×9 @ 95 lb")
    }

    @Test("A run prescription states its driver")
    func runningBlock() {
        let runs = Prescription.blockRuns(
            target: RoutineDiff.Target(name: "Running", sets: 1, extras: [.distance: 1, .pace: 720], distanceUnit: .miles),
            profile: running
        )
        #expect(texts(runs) == "1× 1 mi")
    }
}
