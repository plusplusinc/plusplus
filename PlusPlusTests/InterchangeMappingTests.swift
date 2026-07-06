import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("Interchange mapping")
struct InterchangeMappingTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, Workout.self, ExerciseGroup.self,
            WorkoutExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Custom exercise + superset workout + one finished session.
    private func populate(_ context: ModelContext) throws {
        let band = Equipment(name: "Resistance Band", isBuiltIn: true)
        context.insert(band)

        let pulses = Exercise(
            name: "Band Pulses", muscleGroup: .shoulders, equipment: [band],
            notes: "Shoulder flexed to 90°.", videoURL: "https://youtu.be/x"
        )
        let yRaise = Exercise(name: "Y Raise", muscleGroup: .shoulders)
        context.insert(pulses)
        context.insert(yRaise)

        let workout = Workout(name: "Shoulder PT", restSeconds: 60, notes: "Keep it under an hour.")
        context.insert(workout)
        let superset = workout.addExerciseInNewGroup(yRaise, context: context)
        superset.sets = 3
        workout.addExercise(pulses, to: superset, context: context)
        superset.sortedExercises[0].weight = 5
        superset.sortedExercises[0].reps = 10
        superset.sortedExercises[1].reps = 15
        superset.sortedExercises[1].repsUpper = 20

        let session = WorkoutSession.start(
            from: workout, context: context,
            at: Date(timeIntervalSince1970: 1_000_000)
        )
        for log in session.sortedSetLogs {
            log.actualReps = log.targetRepsLower
            log.actualWeight = log.targetWeight
            log.completedAt = Date(timeIntervalSince1970: 1_000_100)
        }
        session.finish(at: Date(timeIntervalSince1970: 1_002_000))
        try context.save()
    }

    @Test("Export → import into a fresh store reproduces the library")
    func roundTripAcrossStores() throws {
        let source = ModelContext(try makeContainer())
        try populate(source)

        let bundle = try InterchangeMapping.exportBundle(context: source)
        let encoded = try InterchangeCodec.encode(bundle)
        let decoded = try InterchangeCodec.decode(ExportBundle.self, from: encoded)

        let destination = ModelContext(try makeContainer())
        let summary = try InterchangeMapping.importBundle(decoded, context: destination)

        #expect(summary.exercisesCreated == 2)
        #expect(summary.workoutsCreated == 1)
        #expect(summary.sessionsAdded == 1)

        let workouts = try destination.fetch(FetchDescriptor<Workout>())
        #expect(workouts.count == 1)
        let workout = try #require(workouts.first)
        #expect(workout.name == "Shoulder PT")
        #expect(workout.restSeconds == 60)
        #expect(workout.notes == "Keep it under an hour.")
        #expect(workout.sortedGroups.count == 1)
        let group = try #require(workout.sortedGroups.first)
        #expect(group.isSuperset)
        #expect(group.sets == 3)
        #expect(group.sortedExercises.map { $0.exercise?.name } == ["Y Raise", "Band Pulses"])
        #expect(group.sortedExercises[1].reps == 15)
        #expect(group.sortedExercises[1].repsUpper == 20)

        let exercises = try destination.fetch(FetchDescriptor<Exercise>())
        let pulses = try #require(exercises.first { $0.name == "Band Pulses" })
        #expect(pulses.notes == "Shoulder flexed to 90°.")
        #expect(pulses.equipment.map(\.name) == ["Resistance Band"])

        let sessions = try destination.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.sortedSetLogs.count == 6)
        #expect(sessions.first?.sortedSetLogs.first?.actualReps == 10)
    }

    @Test("Re-importing the same bundle is idempotent for history")
    func importIsIdempotentForSessions() throws {
        let context = ModelContext(try makeContainer())
        try populate(context)

        let bundle = try InterchangeMapping.exportBundle(context: context)
        let summary = try InterchangeMapping.importBundle(bundle, context: context)

        #expect(summary.sessionsAdded == 0)
        #expect(summary.sessionsSkipped == 1)
        #expect(summary.exercisesUpdated == 2)
        #expect(summary.exercisesCreated == 0)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1, "History must never duplicate on re-import")
    }

    @Test("Workout import replaces structure rather than duplicating")
    func workoutReplacement() throws {
        let context = ModelContext(try makeContainer())
        try populate(context)

        var bundle = try InterchangeMapping.exportBundle(context: context)
        // Simulate an external edit: drop the superset down to one exercise.
        bundle = ExportBundle(
            exercises: bundle.exercises,
            workouts: [
                WorkoutDTO(name: "Shoulder PT", restSeconds: 90, groups: [
                    .init(sets: 4, exercises: [.init(exercise: "Y Raise", reps: 12)])
                ])
            ],
            sessions: []
        )

        let summary = try InterchangeMapping.importBundle(bundle, context: context)
        #expect(summary.workoutsReplaced == 1)

        let workouts = try context.fetch(FetchDescriptor<Workout>())
        #expect(workouts.count == 1)
        let workout = try #require(workouts.first)
        #expect(workout.restSeconds == 90)
        #expect(workout.notes == nil, "A replacing DTO without notes clears them")
        #expect(workout.sortedGroups.count == 1)
        #expect(workout.sortedGroups[0].sets == 4)
        #expect(!workout.sortedGroups[0].isSuperset)
        #expect(workout.sortedGroups[0].sortedExercises[0].reps == 12)
    }

    @Test("Invalid bundles are rejected with the validator's issues")
    func invalidBundleRejected() throws {
        let context = ModelContext(try makeContainer())
        let bad = ExportBundle(
            exercises: [],
            workouts: [WorkoutDTO(name: "Bad", restSeconds: 5, groups: [])],
            sessions: []
        )
        #expect(throws: InterchangeMapping.ImportError.self) {
            try InterchangeMapping.importBundle(bad, context: context)
        }
    }

    @Test("Unknown equipment referenced by an imported exercise is created")
    func equipmentCreatedOnDemand() throws {
        let context = ModelContext(try makeContainer())
        let bundle = ExportBundle(
            exercises: [
                ExerciseDTO(name: "Sled Push", muscleGroup: .fullBody, exerciseType: .weightReps, equipment: ["Sled"])
            ],
            workouts: [],
            sessions: []
        )
        try InterchangeMapping.importBundle(bundle, context: context)

        let equipment = try context.fetch(FetchDescriptor<Equipment>())
        #expect(equipment.map(\.name) == ["Sled"])
        #expect(equipment.first?.isBuiltIn == false)
    }
}
