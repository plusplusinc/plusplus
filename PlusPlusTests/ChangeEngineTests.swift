import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// The Operator change engine: resolve → tier → preview/apply → undo.
/// Every apply class gets a round trip; tier gating proves a staged
/// change touches nothing.
@MainActor
@Suite("Operator ChangeEngine")
struct ChangeEngineTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self,
            Routine.self, ExerciseGroup.self, RoutineExercise.self,
            WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("operator-engine-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @discardableResult
    private func makeExercise(
        _ name: String,
        muscle: MuscleGroup = .fullBody,
        profile: MetricProfile? = nil,
        builtIn: Bool = false,
        in context: ModelContext
    ) -> Exercise {
        let exercise = Exercise(name: name, muscleGroup: muscle, isBuiltIn: builtIn)
        context.insert(exercise)
        if let profile { exercise.metricProfile = profile }
        return exercise
    }

    private func applied(_ outcome: ChangeEngine.ChangeOutcome) throws -> ChangeEngine.AppliedChange {
        guard case .applied(let change) = outcome else {
            throw TestFailure("expected applied, got \(outcome)")
        }
        return change
    }

    private func staged(_ outcome: ChangeEngine.ChangeOutcome) throws -> ChangeEngine.ChangePreview {
        guard case .staged(let preview) = outcome else {
            throw TestFailure("expected staged, got \(outcome)")
        }
        return preview
    }

    private struct TestFailure: Error, CustomStringConvertible {
        let description: String
        init(_ text: String) { description = text }
    }

    // MARK: - Create

    @Test("Create routine with exercises, then undo deletes it")
    func createRoutineRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        makeExercise("Probe Squat", in: context)
        makeExercise("Probe Lunge", in: context)
        let engine = ChangeEngine(context: context)

        let outcome = engine.propose(ChangeSpec(
            operation: .create, entity: .routine,
            values: ChangeValues(name: "Probe Legs", scheduleDays: [2, 5], addExercises: ["Probe Squat", "Probe Lunge"])
        ))
        let change = try applied(outcome)
        #expect(change.receipt.summary == "Created Probe Legs · 2 exercises.")

        let routines = try context.fetch(FetchDescriptor<Routine>())
        #expect(routines.count == 1)
        let routine = try #require(routines.first)
        #expect(routine.schedule == .weekdays([2, 5]))
        #expect(routine.sortedGroups.count == 2)
        if case .routine(let uuid) = try #require(change.receipt.destinations.first) {
            #expect(uuid == routine.uuid)
        } else {
            Issue.record("expected a routine destination")
        }

        _ = try applied(engine.undo(change.inverse))
        #expect(try context.fetch(FetchDescriptor<Routine>()).isEmpty)
    }

    @Test("Create adopts a name that landed in targets")
    func createNameFromTargets() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let engine = ChangeEngine(context: context)
        _ = try applied(engine.propose(ChangeSpec(operation: .create, entity: .library, targets: ["Probe Hotel"])))
        let libraries = try context.fetch(FetchDescriptor<EquipmentLibrary>())
        #expect(libraries.map(\.name) == ["Probe Hotel"])
    }

    @Test("Create exercise wires gear, tracking, and defaults")
    func createExercise() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let band = Equipment(name: "Probe Band")
        context.insert(band)
        let engine = ChangeEngine(context: context)

        let outcome = engine.propose(ChangeSpec(
            operation: .create, entity: .exercise,
            values: ChangeValues(
                name: "Probe Pull-Apart", trackBy: .reps, muscleGroup: .shoulders,
                reps: 15, equipment: ["Probe Band"]
            )
        ))
        _ = try applied(outcome)
        let exercise = try #require(try context.fetch(FetchDescriptor<Exercise>()).first)
        #expect(exercise.muscleGroup == .shoulders)
        #expect(exercise.metricProfile == .repsOnly)
        #expect(exercise.defaultReps == 15)
        #expect(exercise.equipment.map(\.name) == ["Probe Band"])
    }

    // MARK: - Update basics

    @Test("Rename applies immediately; collisions are invalid")
    func renameRoutine() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Routine(name: "Probe Push", order: 0))
        context.insert(Routine(name: "Probe Pull", order: 1))
        let engine = ChangeEngine(context: context)

        _ = try applied(engine.propose(ChangeSpec(
            operation: .update, entity: .routine, targets: ["Probe Push"],
            values: ChangeValues(name: "Probe Push Day")
        )))
        let names = try context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.order)])).map(\.name)
        #expect(names == ["Probe Push Day", "Probe Pull"])

        let collision = engine.propose(ChangeSpec(
            operation: .update, entity: .routine, targets: ["Probe Pull"],
            values: ChangeValues(name: "probe push day")
        ))
        guard case .invalid(let reason) = collision else {
            Issue.record("expected invalid, got \(collision)")
            return
        }
        #expect(reason.contains("already exists"))
    }

    @Test("Schedule set and clear round-trip through undo")
    func scheduleRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "Probe Push", order: 0)
        context.insert(routine)
        let engine = ChangeEngine(context: context)

        let set = try applied(engine.propose(ChangeSpec(
            operation: .update, entity: .routine, targets: ["Probe Push"],
            values: ChangeValues(scheduleDays: [2, 4, 6])
        )))
        #expect(routine.schedule == .weekdays([2, 4, 6]))

        _ = try applied(engine.propose(ChangeSpec(
            operation: .update, entity: .routine, targets: ["Probe Push"],
            values: ChangeValues(scheduleDays: [])
        )))
        #expect(routine.schedule == .unscheduled)

        _ = try applied(engine.undo(set.inverse))
        #expect(routine.schedule == .unscheduled)
    }

    // MARK: - The stretch bulk transform (the flagship case)

    @Test("Bulk reps→duration: previews, applies with entry cascade, undoes")
    func stretchBulkTransform() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let hamstring = makeExercise("Probe Hamstring Stretch", profile: .repsOnly, in: context)
        let quad = makeExercise("Probe Quad Stretch", profile: .repsOnly, in: context)
        let neck = makeExercise("Probe Neck Stretch", profile: .repsOnly, in: context)
        let calf = makeExercise("Probe Calf Stretch", profile: .durationOnly, in: context)
        let squat = makeExercise("Probe Squat", profile: .weightReps, in: context)

        let routine = Routine(name: "Probe Mobility", order: 0)
        context.insert(routine)
        routine.addExerciseInNewGroup(hamstring, context: context)
        let entry = try #require(routine.sortedGroups.first?.sortedExercises.first)
        entry.reps = 15
        try context.save()

        var hookFired = 0
        let engine = ChangeEngine(context: context) { _ in hookFired += 1 }

        let spec = ChangeSpec(
            operation: .update, entity: .exercise,
            filter: ChangeFilter(nameContains: "stretch", trackedBy: .reps),
            values: ChangeValues(trackBy: .duration, durationSeconds: 30)
        )
        let preview = try staged(engine.propose(spec))
        #expect(preview.affectedCount == 3)
        #expect(preview.headline == "Changes 3 exercises")
        #expect(preview.lines.contains("track by duration · was reps"))
        #expect(preview.lines.contains("30 s per set"))
        #expect(preview.lines.contains("updates 1 routine entry"))
        // Staging touched nothing.
        #expect(hamstring.metricProfile == .repsOnly)
        #expect(entry.reps == 15)
        #expect(hookFired == 0)

        let change = try applied(engine.applyStaged(preview.spec))
        for converted in [hamstring, quad, neck] {
            #expect(converted.metricProfile == .durationOnly)
            #expect(converted.defaultDurationSeconds == 30)
        }
        #expect(entry.reps == nil)
        #expect(entry.durationSeconds == 30)
        // The filter's trackedBy spared the already-duration stretch and
        // the non-stretch.
        #expect(calf.metricProfile == .durationOnly)
        #expect(squat.metricProfile == .weightReps)
        #expect(hookFired == 1)

        _ = try applied(engine.undo(change.inverse))
        #expect(hamstring.metricProfile == .repsOnly)
        #expect(quad.metricProfile == .repsOnly)
        #expect(entry.reps == 15)
        #expect(entry.durationSeconds == nil)
        #expect(hookFired == 2)
    }

    // MARK: - Deletes

    @Test("Delete stages first and touches nothing until Apply")
    func deleteStagesFirst() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "Probe Push", order: 0)
        context.insert(routine)
        let engine = ChangeEngine(context: context)

        let preview = try staged(engine.propose(ChangeSpec(
            operation: .delete, entity: .routine, targets: ["Probe Push"]
        )))
        #expect(preview.headline == "Deletes 1 routine")
        #expect(try context.fetch(FetchDescriptor<Routine>()).count == 1)

        let change = try applied(engine.applyStaged(preview.spec))
        #expect(try context.fetch(FetchDescriptor<Routine>()).isEmpty)

        _ = try applied(engine.undo(change.inverse))
        let restored = try #require(try context.fetch(FetchDescriptor<Routine>()).first)
        #expect(restored.name == "Probe Push")
    }

    @Test("Deleted routine restores structure AND device identity on undo")
    func deleteRoutineRestoresStructure() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let squat = makeExercise("Probe Squat", profile: .weightReps, in: context)
        let lunge = makeExercise("Probe Lunge", profile: .repsOnly, in: context)
        let routine = Routine(name: "Probe Legs", order: 0, restSeconds: 120)
        context.insert(routine)
        let group = routine.addExerciseInNewGroup(squat, context: context)
        group.sets = 5
        routine.addExercise(lunge, to: group, context: context)
        routine.schedule = .weekdays([3])
        try context.save()
        let originalUUID = routine.uuid
        let originalCreatedAt = routine.createdAt
        let engine = ChangeEngine(context: context)

        let change = try applied(engine.applyStaged(ChangeSpec(
            operation: .delete, entity: .routine, targets: ["Probe Legs"]
        )))
        _ = try applied(engine.undo(change.inverse))

        let restored = try #require(try context.fetch(FetchDescriptor<Routine>()).first)
        #expect(restored.restSeconds == 120)
        #expect(restored.schedule == .weekdays([3]))
        // Device identity the DTO excludes comes back too: uuid keeps
        // nav resolving, createdAt keeps the due-ness anchor (#354).
        #expect(restored.uuid == originalUUID)
        #expect(restored.createdAt == originalCreatedAt)
        let restoredGroup = try #require(restored.sortedGroups.first)
        #expect(restoredGroup.sets == 5)
        #expect(restoredGroup.sortedExercises.compactMap { $0.exercise?.name } == ["Probe Squat", "Probe Lunge"])
    }

    @Test("Undo names what it could not restore instead of lying")
    func partialUndoIsHonest() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        makeExercise("Probe Curl", profile: .weightReps, in: context)
        try context.save()
        let engine = ChangeEngine(context: context)

        let change = try applied(engine.applyStaged(ChangeSpec(
            operation: .delete, entity: .exercise, targets: ["Probe Curl"]
        )))
        // A same-name exercise arrives between the delete and the undo.
        _ = try applied(engine.propose(ChangeSpec(
            operation: .create, entity: .exercise,
            values: ChangeValues(name: "Probe Curl")
        )))

        let undone = try applied(engine.undo(change.inverse))
        #expect(undone.receipt.summary == "Undone, except Probe Curl: a same-name item exists now, so it was left alone.")
        #expect(try context.fetch(FetchDescriptor<Exercise>()).count == 1)
    }

    @Test("Custom delete removes entries; built-in delete leaves the library")
    func deleteExercises() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let custom = makeExercise("Probe Custom Curl", profile: .weightReps, in: context)
        let builtIn = makeExercise("Probe Built-In Row", profile: .weightReps, builtIn: true, in: context)
        let routine = Routine(name: "Probe Arms", order: 0)
        context.insert(routine)
        routine.addExerciseInNewGroup(custom, context: context)
        try context.save()
        let engine = ChangeEngine(context: context)

        let change = try applied(engine.applyStaged(ChangeSpec(
            operation: .delete, entity: .exercise,
            targets: ["Probe Custom Curl", "Probe Built-In Row"]
        )))
        // The custom is gone and left no ghost entry behind.
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(exercises.map(\.name) == ["Probe Built-In Row"])
        #expect(builtIn.inLibrary == false)
        #expect(routine.sortedGroups.isEmpty)

        _ = try applied(engine.undo(change.inverse))
        let names = try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])).map(\.name)
        #expect(names == ["Probe Built-In Row", "Probe Custom Curl"])
        #expect(builtIn.inLibrary == true)
        #expect(routine.sortedGroups.first?.sortedExercises.compactMap { $0.exercise?.name } == ["Probe Custom Curl"])
    }

    @Test("The last library cannot be deleted")
    func lastLibraryGuard() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(EquipmentLibrary(name: "Probe Home", order: 0))
        let engine = ChangeEngine(context: context)
        let outcome = engine.propose(ChangeSpec(operation: .delete, entity: .library, targets: ["Probe Home"]))
        guard case .invalid(let reason) = outcome else {
            Issue.record("expected invalid, got \(outcome)")
            return
        }
        #expect(reason == "keep at least one library")
    }

    @Test("Library delete recreates name and membership on undo")
    func libraryDeleteRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = EquipmentLibrary(name: "Probe Home", order: 0)
        let hotel = EquipmentLibrary(name: "Probe Hotel", order: 1)
        context.insert(home)
        context.insert(hotel)
        let band = Equipment(name: "Probe Band")
        context.insert(band)
        hotel.setMembership(band, true)
        try context.save()
        let originalUUID = hotel.uuid
        let engine = ChangeEngine(context: context)

        let change = try applied(engine.applyStaged(ChangeSpec(
            operation: .delete, entity: .library, targets: ["Probe Hotel"]
        )))
        #expect(try context.fetch(FetchDescriptor<EquipmentLibrary>()).count == 1)

        _ = try applied(engine.undo(change.inverse))
        let libraries = try context.fetch(FetchDescriptor<EquipmentLibrary>(sortBy: [SortDescriptor(\.order)]))
        #expect(libraries.map(\.name) == ["Probe Home", "Probe Hotel"])
        #expect(libraries.last?.members.map(\.name) == ["Probe Band"])
        // The active-library pointer stores the uuid; the undone library
        // must come back under its ORIGINAL identity.
        #expect(libraries.last?.uuid == originalUUID)
    }

    @Test("Gear deltas edit membership without a replace, and undo restores")
    func libraryGearDeltas() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = EquipmentLibrary(name: "Probe Home", order: 0)
        context.insert(home)
        let band = Equipment(name: "Probe Band")
        let rope = Equipment(name: "Probe Rope")
        context.insert(band)
        context.insert(rope)
        home.setMembership(band, true)
        try context.save()
        let engine = ChangeEngine(context: context)

        // "add the rope" arrives in the model's casing; the receipt
        // speaks the catalog's, and the untouched member stays put.
        let change = try applied(engine.propose(ChangeSpec(
            operation: .update, entity: .library, targets: ["Probe Home"],
            values: ChangeValues(addEquipment: ["probe rope"])
        )))
        #expect(change.receipt.summary == "Probe Home: added Probe Rope.")
        #expect(home.members.map(\.name).sorted() == ["Probe Band", "Probe Rope"])

        _ = try applied(engine.undo(change.inverse))
        #expect(home.members.map(\.name) == ["Probe Band"])

        let removal = try applied(engine.propose(ChangeSpec(
            operation: .update, entity: .library, targets: ["Probe Home"],
            values: ChangeValues(removeEquipment: ["Probe Band"])
        )))
        #expect(removal.receipt.summary == "Probe Home: removed Probe Band.")
        #expect(home.members.isEmpty)
    }

    @Test("A library update naming no target lands on the ACTIVE library")
    func libraryUpdateDefaultsToActive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = EquipmentLibrary(name: "Probe Home", order: 0)
        let hotel = EquipmentLibrary(name: "Probe Hotel", order: 1)
        context.insert(home)
        context.insert(hotel)
        let rope = Equipment(name: "Probe Rope")
        context.insert(rope)
        try context.save()
        let engine = ChangeEngine(context: context)
        // The SECOND library is active (proving "active", not "first by
        // order") via the injection seam — the real resolver reads
        // process-global UserDefaults, which parallel suites race on.
        engine.activeLibrary = { all in all.first { $0.name == "Probe Hotel" } }

        // "Remove the barbell from my equipment" never names a library;
        // the spec arrives target-less and must land on the active one.
        let change = try applied(engine.propose(ChangeSpec(
            operation: .update, entity: .library,
            values: ChangeValues(addEquipment: ["Probe Rope"])
        )))
        #expect(change.receipt.summary == "Probe Hotel: added Probe Rope.")
        #expect(hotel.members.map(\.name) == ["Probe Rope"])
        #expect(home.members.isEmpty)

        // A target-less membership REPLACE stages — and the preview's
        // spec must carry the resolved library PINNED into targets, so
        // Apply hits the subject the card named even if the active
        // pointer moves between staging and tapping.
        let preview = try staged(engine.propose(ChangeSpec(
            operation: .update, entity: .library,
            values: ChangeValues(equipment: ["Probe Rope"])
        )))
        #expect(preview.spec.targets == ["Probe Hotel"])

        // A target-less DELETE stays invalid — the default is for
        // updates only.
        let outcome = engine.propose(ChangeSpec(operation: .delete, entity: .library))
        guard case .invalid = outcome else {
            Issue.record("expected invalid, got \(outcome)")
            return
        }
    }

    @Test("Replacing a library's gear list previews, names the after state, applies on confirm")
    func libraryGearReplacePreviews() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = EquipmentLibrary(name: "Probe Home", order: 0)
        context.insert(home)
        let band = Equipment(name: "Probe Band")
        let rope = Equipment(name: "Probe Rope")
        let bench = Equipment(name: "Probe Bench")
        context.insert(band)
        context.insert(rope)
        context.insert(bench)
        home.setMembership(band, true)
        home.setMembership(rope, true)
        try context.save()
        let engine = ChangeEngine(context: context)

        // A whole-list restatement removes whatever it omits, so even
        // one library previews — and the card says what the list BECOMES.
        let preview = try staged(engine.propose(ChangeSpec(
            operation: .update, entity: .library, targets: ["Probe Home"],
            values: ChangeValues(equipment: ["Probe Bench"])
        )))
        #expect(preview.headline == "Changes 1 library")
        #expect(preview.lines.contains("gear becomes Probe Bench"))
        #expect(home.members.map(\.name).sorted() == ["Probe Band", "Probe Rope"])

        let change = try applied(engine.applyStaged(preview.spec))
        #expect(home.members.map(\.name) == ["Probe Bench"])

        _ = try applied(engine.undo(change.inverse))
        #expect(home.members.map(\.name).sorted() == ["Probe Band", "Probe Rope"])
    }

    // MARK: - Supersets

    @Test("Forming a superset merges groups; undo restores the split")
    func supersetFormation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let bench = makeExercise("Probe Bench", profile: .weightReps, in: context)
        let row = makeExercise("Probe Row", profile: .weightReps, in: context)
        let routine = Routine(name: "Probe Upper", order: 0)
        context.insert(routine)
        routine.addExerciseInNewGroup(bench, context: context)
        routine.addExerciseInNewGroup(row, context: context)
        try context.save()
        let engine = ChangeEngine(context: context)

        let change = try applied(engine.propose(ChangeSpec(
            operation: .update, entity: .superset,
            targets: ["Probe Bench", "Probe Row"],
            filter: ChangeFilter(inRoutine: "Probe Upper"),
            values: ChangeValues(sets: 4)
        )))
        #expect(change.receipt.summary == "Superset: Probe Bench + Probe Row in Probe Upper.")
        #expect(routine.sortedGroups.count == 1)
        let group = try #require(routine.sortedGroups.first)
        #expect(group.isSuperset)
        #expect(group.sets == 4)
        #expect(group.sortedExercises.compactMap { $0.exercise?.name } == ["Probe Bench", "Probe Row"])

        _ = try applied(engine.undo(change.inverse))
        #expect(routine.sortedGroups.count == 2)
        #expect(routine.sortedGroups.allSatisfy { !$0.isSuperset })
    }

    @Test("Dissolving supersets splits members into solo blocks")
    func supersetDissolve() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let bench = makeExercise("Probe Bench", profile: .weightReps, in: context)
        let row = makeExercise("Probe Row", profile: .weightReps, in: context)
        let routine = Routine(name: "Probe Upper", order: 0)
        context.insert(routine)
        let group = routine.addExerciseInNewGroup(bench, context: context)
        routine.addExercise(row, to: group, context: context)
        try context.save()
        let engine = ChangeEngine(context: context)

        _ = try applied(engine.propose(ChangeSpec(
            operation: .delete, entity: .superset,
            filter: ChangeFilter(inRoutine: "Probe Upper")
        )))
        #expect(routine.sortedGroups.count == 2)
        #expect(routine.sortedGroups.allSatisfy { !$0.isSuperset })
        #expect(routine.sortedGroups.map(\.order) == [0, 1])
    }

    // MARK: - Resolution failures

    @Test("Ambiguous names come back as a question, not a guess")
    func ambiguity() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        makeExercise("Probe Press A", in: context)
        makeExercise("Probe Press B", in: context)
        let engine = ChangeEngine(context: context)
        let outcome = engine.propose(ChangeSpec(
            operation: .update, entity: .exercise, targets: ["probe press"],
            values: ChangeValues(reps: 10)
        ))
        guard case .invalid(let reason) = outcome else {
            Issue.record("expected invalid, got \(outcome)")
            return
        }
        #expect(reason.contains("matches Probe Press A, Probe Press B"))
    }

    @Test("Ambiguous superset members ask instead of restructuring on a guess")
    func supersetMemberAmbiguity() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let benchPress = makeExercise("Probe Bench Press", profile: .weightReps, in: context)
        let overheadPress = makeExercise("Probe Overhead Press", profile: .weightReps, in: context)
        let curl = makeExercise("Probe Curl", profile: .weightReps, in: context)
        let routine = Routine(name: "Probe Upper", order: 0)
        context.insert(routine)
        routine.addExerciseInNewGroup(benchPress, context: context)
        routine.addExerciseInNewGroup(overheadPress, context: context)
        routine.addExerciseInNewGroup(curl, context: context)
        try context.save()
        let engine = ChangeEngine(context: context)

        let outcome = engine.propose(ChangeSpec(
            operation: .update, entity: .superset,
            targets: ["press", "Probe Curl"],
            filter: ChangeFilter(inRoutine: "Probe Upper")
        ))
        guard case .invalid(let reason) = outcome else {
            Issue.record("expected invalid, got \(outcome)")
            return
        }
        #expect(reason.contains("press matches Probe Bench Press, Probe Overhead Press"))
        // Nothing restructured.
        #expect(routine.sortedGroups.count == 3)
    }

    @Test("A unique substring match resolves without ceremony")
    func substringResolution() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "Probe Push Day", order: 0)
        context.insert(routine)
        let engine = ChangeEngine(context: context)
        _ = try applied(engine.propose(ChangeSpec(
            operation: .update, entity: .routine, targets: ["Push"],
            values: ChangeValues(restSeconds: 60)
        )))
        #expect(routine.restSeconds == 60)
    }

    @Test("Misses suggest the closest names")
    func closestSuggestions() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Routine(name: "Probe Push Day", order: 0))
        let engine = ChangeEngine(context: context)
        // No substring relation either way, but a shared word: the miss
        // suggests instead of guessing.
        let outcome = engine.propose(ChangeSpec(
            operation: .update, entity: .routine, targets: ["Push Workout"],
            values: ChangeValues(restSeconds: 60)
        ))
        guard case .invalid(let reason) = outcome else {
            Issue.record("expected invalid, got \(outcome)")
            return
        }
        #expect(reason.contains("Closest: Probe Push Day"))
    }

    @Test("Removing an entry cleans up its emptied group and undoes")
    func removeExerciseFromRoutine() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let squat = makeExercise("Probe Squat", profile: .weightReps, in: context)
        let lunge = makeExercise("Probe Lunge", profile: .repsOnly, in: context)
        let routine = Routine(name: "Probe Legs", order: 0)
        context.insert(routine)
        routine.addExerciseInNewGroup(squat, context: context)
        routine.addExerciseInNewGroup(lunge, context: context)
        let lungeEntry = try #require(routine.sortedGroups.last?.sortedExercises.first)
        lungeEntry.reps = 12
        try context.save()
        let engine = ChangeEngine(context: context)

        let change = try applied(engine.propose(ChangeSpec(
            operation: .update, entity: .routine, targets: ["Probe Legs"],
            values: ChangeValues(removeExercises: ["Probe Lunge"])
        )))
        #expect(routine.sortedGroups.count == 1)
        #expect(routine.sortedGroups.map(\.order) == [0])

        _ = try applied(engine.undo(change.inverse))
        #expect(routine.sortedGroups.count == 2)
        let restored = try #require(routine.sortedGroups.last?.sortedExercises.first)
        #expect(restored.exercise?.name == "Probe Lunge")
        #expect(restored.reps == 12)
    }
}
