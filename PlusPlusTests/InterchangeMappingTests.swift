import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("Interchange mapping")
struct InterchangeMappingTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("interchangemapping-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Custom exercise + superset routine + one finished session.
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

        let routine = Routine(name: "Shoulder PT", restSeconds: 60, notes: "Keep it under an hour.")
        context.insert(routine)
        let superset = routine.addExerciseInNewGroup(yRaise, context: context)
        superset.sets = 3
        routine.addExercise(pulses, to: superset, context: context)
        superset.sortedExercises[0].weight = 5
        superset.sortedExercises[0].reps = 10
        superset.sortedExercises[1].reps = 15
        superset.sortedExercises[1].repsUpper = 20

        let session = WorkoutSession.start(
            from: routine, context: context,
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

        let bundle = try InterchangeMapping.exportBundle(context: source, units: .kg)
        let encoded = try InterchangeCodec.encode(bundle)
        let decoded = try InterchangeCodec.decode(ExportBundle.self, from: encoded)
        #expect(decoded.units == .kg, "The declared unit survives the round trip")

        let destination = ModelContext(try makeContainer())
        let summary = try InterchangeMapping.importBundle(decoded, context: destination)

        #expect(summary.exercisesCreated == 2)
        #expect(summary.routinesCreated == 1)
        #expect(summary.sessionsAdded == 1)

        let routines = try destination.fetch(FetchDescriptor<Routine>())
        #expect(routines.count == 1)
        let routine = try #require(routines.first)
        #expect(routine.name == "Shoulder PT")
        #expect(routine.restSeconds == 60)
        #expect(routine.notes == "Keep it under an hour.")
        #expect(routine.sortedGroups.count == 1)
        let group = try #require(routine.sortedGroups.first)
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

    @Test("Library membership travels: adopted built-ins export and restore (#328)")
    func libraryMembershipRoundTrips() throws {
        let source = ModelContext(try makeContainer())
        // An un-customized built-in the user adopted (the populate offer, or a
        // manual add). Built-ins default inLibrary = true.
        let adopted = Exercise(name: "Probe Adopted", muscleGroup: .core, isBuiltIn: true)
        // An un-customized built-in still catalog-only (not in the library).
        let catalogOnly = Exercise(name: "Probe Catalog", muscleGroup: .core, isBuiltIn: true)
        catalogOnly.inLibrary = false
        source.insert(adopted)
        source.insert(catalogOnly)
        try source.save()

        // Export ships the adopted one but not the catalog-only one — the #328
        // fix (was: only customs + edited built-ins, dropping the library).
        let bundle = try InterchangeMapping.exportBundle(context: source)
        let exported = Set(bundle.exercises.map(\.name))
        #expect(exported.contains("Probe Adopted"), "An in-library built-in must export")
        #expect(!exported.contains("Probe Catalog"), "A catalog-only built-in must not export")

        // Membership restores on import into a fresh store.
        let dest = ModelContext(try makeContainer())
        _ = try InterchangeMapping.importBundle(bundle, context: dest)
        let imported = try dest.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "Probe Adopted" })
        )
        #expect(imported.first?.inLibrary == true)
    }

    /// The new-phone story: a source store's equipment libraries and
    /// gear config survive export → import into a fresh store, and the
    /// libraries carry their exact membership (customs included).
    @Test("Export → import reproduces equipment libraries and gear config")
    func equipmentLibrariesRoundTripAcrossStores() throws {
        let source = ModelContext(try makeContainer())
        let barbell = Equipment(name: "Barbell", isBuiltIn: true)
        barbell.weightStep = 2.5
        let rig = Equipment(name: "Probe Garage Rig", isBuiltIn: false)
        source.insert(barbell)
        source.insert(rig)
        let home = EquipmentLibrary(name: "Home", order: 0)
        let hotel = EquipmentLibrary(name: "Hotel", order: 1)
        source.insert(home)
        source.insert(hotel)
        home.equipment = [barbell, rig]
        hotel.equipment = []   // bodyweight-only travel is a real library
        try source.save()

        let bundle = try InterchangeMapping.exportBundle(context: source)
        #expect(bundle.equipmentLibraries?.map(\.name) == ["Home", "Hotel"])
        #expect(bundle.equipment?.contains { $0.name == "Barbell" && $0.weightStep == 2.5 } == true)

        let destination = ModelContext(try makeContainer())
        let summary = try InterchangeMapping.importBundle(bundle, context: destination)
        #expect(summary.librariesCreated == 2)
        #expect(summary.equipmentConfigured >= 1)

        let libraries = try destination.fetch(FetchDescriptor<EquipmentLibrary>())
        let importedHome = try #require(libraries.first { $0.name == "Home" })
        #expect(importedHome.memberNames == ["Barbell", "Probe Garage Rig"], "membership and the custom both land")
        let importedHotel = try #require(libraries.first { $0.name == "Hotel" })
        #expect(importedHotel.members.isEmpty, "an empty library round-trips as empty")

        let importedBarbell = try #require(
            (try destination.fetch(FetchDescriptor<Equipment>())).first { $0.name == "Barbell" }
        )
        #expect(importedBarbell.weightStep == 2.5, "gear config restores")
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

    @Test("Routine import replaces structure rather than duplicating")
    func routineReplacement() throws {
        let context = ModelContext(try makeContainer())
        try populate(context)

        var bundle = try InterchangeMapping.exportBundle(context: context)
        // Simulate an external edit: drop the superset down to one exercise.
        bundle = ExportBundle(
            exercises: bundle.exercises,
            routines: [
                RoutineDTO(name: "Shoulder PT", restSeconds: 90, groups: [
                    .init(sets: 4, exercises: [.init(exercise: "Y Raise", reps: 12)])
                ])
            ],
            sessions: []
        )

        let summary = try InterchangeMapping.importBundle(bundle, context: context)
        #expect(summary.routinesReplaced == 1)

        let routines = try context.fetch(FetchDescriptor<Routine>())
        #expect(routines.count == 1)
        let routine = try #require(routines.first)
        #expect(routine.restSeconds == 90)
        #expect(routine.transitionSeconds == 15, "Absent transitionSeconds (a pre-#369 file) means the app default")
        #expect(routine.notes == nil, "A replacing DTO without notes clears them")
        #expect(routine.sortedGroups.count == 1)
        #expect(routine.sortedGroups[0].sets == 4)
        #expect(!routine.sortedGroups[0].isSuperset)
        #expect(routine.sortedGroups[0].sortedExercises[0].reps == 12)
    }

    @Test("Invalid bundles are rejected with the validator's issues")
    func invalidBundleRejected() throws {
        let context = ModelContext(try makeContainer())
        let bad = ExportBundle(
            exercises: [],
            routines: [RoutineDTO(name: "Bad", restSeconds: 5, groups: [])],
            sessions: []
        )
        #expect(throws: InterchangeMapping.ImportError.self) {
            try InterchangeMapping.importBundle(bad, context: context)
        }
    }

    /// The prevention mechanism (see the INTERCHANGE FIELD CENSUS in
    /// InterchangeMapping.swift): a full graph with EVERY exported field
    /// set to a distinctive non-default value must survive
    /// export → encode → decode → import into a fresh store, field for
    /// field. A new model field that isn't threaded through the mapping
    /// (and isn't a documented EXCLUDED field) fails this loudly instead
    /// of silently dropping user data on a new-phone restore.
    @Test("Every exported field survives a full export → import round trip")
    func fullGraphRoundTripPreservesEveryContentField() throws {
        let source = ModelContext(try makeContainer())

        // ── Equipment: custom gear with a weight step and a metric profile.
        let rower = Equipment(name: "Probe Rower", isBuiltIn: false)
        rower.weightStep = 1.25
        source.insert(rower)
        rower.suggestedProfile = MetricProfile([.distance, .pace], distanceUnit: .miles)

        // ── Exercise: every default + profile + membership field set.
        let row = Exercise(
            name: "Probe Row", muscleGroup: .back, equipment: [rower],
            notes: "Drive with the legs.", videoURL: "https://youtu.be/probe"
        )
        source.insert(row)
        row.metricProfile = MetricProfile([.weight, .reps, .duration, .distance], distanceUnit: .miles, isOutdoor: true)
        row.defaultWeight = 60
        row.defaultReps = 8
        row.defaultRepsUpper = 12
        row.defaultDurationSeconds = 90
        row.defaultHeartRateTargetData = InterchangeMapping.encodeHeartRate(.zone(.zone3))
        row.extraDefaults = [.distance: 2000, .pace: 300]
        // A second exercise removed from the library: inLibrary must
        // round-trip its non-default `false`.
        let retired = Exercise(name: "Probe Retired", muscleGroup: .chest)
        retired.inLibrary = false
        source.insert(retired)

        // ── Routine: notes + schedule + a superset block with an override.
        let routine = Routine(name: "Probe Routine", restSeconds: 75, transitionSeconds: 25, notes: "Under an hour.")
        source.insert(routine)
        routine.schedule = .weekdays([1, 3, 5])
        let block = routine.addExerciseInNewGroup(row, context: source)
        block.sets = 4
        block.restSecondsOverride = 120
        routine.addExercise(retired, to: block, context: source)
        let entry = block.sortedExercises[0]
        entry.weight = 60
        entry.reps = 8
        entry.repsUpper = 12
        entry.durationSeconds = 90
        entry.heartRateTarget = .range(lowerBPM: 120, upperBPM: 140)
        entry.extraTargets = [.distance: 500]

        // ── Library membership.
        let home = EquipmentLibrary(name: "Probe Home", order: 0)
        source.insert(home)
        home.equipment = [rower]

        // ── Session: every summary + set field, including actuals & clock.
        let session = WorkoutSession(routineName: "Probe Routine",
                                     startedAt: Date(timeIntervalSince1970: 2_000_000), restSeconds: 75)
        source.insert(session)
        session.accumulatedSeconds = 930    // active duration, excludes pauses
        session.averageHeartRate = 145
        session.maxHeartRate = 172
        // GPS run summary (#378). routeData itself is deliberately absent
        // here: it exports as the .gpx sidecar in the repo layout, not a
        // bundle field (see the census) — its round-trip is the sync
        // layer's to prove.
        session.runDistanceMeters = 5023.4
        session.runMovingSeconds = 1712
        session.runElevationGainMeters = 46.5
        let log = SetLog(
            order: 0, groupIndex: 0, setNumber: 1, exercise: row,
            exerciseName: "Probe Row", exerciseType: .duration,
            targetWeight: 60, targetRepsLower: 8, targetRepsUpper: 12, targetDuration: 90,
            targetHeartRateData: InterchangeMapping.encodeHeartRate(.range(lowerBPM: 120, upperBPM: 140))
        )
        log.metricProfile = MetricProfile([.weight, .reps, .duration, .distance], distanceUnit: .miles, isOutdoor: true)
        log.restSecondsOverride = 120
        log.actualWeight = 62.5
        log.actualReps = 11
        log.actualDuration = 88
        log.extraTargets = [.distance: 500]
        log.extraActuals = [.distance: 512]
        log.completedAt = Date(timeIntervalSince1970: 2_000_100)
        log.session = session
        source.insert(log)
        session.endedAt = Date(timeIntervalSince1970: 2_001_000)
        try source.save()

        // Round trip through the wire format into a fresh store.
        let bundle = try InterchangeMapping.exportBundle(context: source, units: .kg)
        let decoded = try InterchangeCodec.decode(ExportBundle.self, from: try InterchangeCodec.encode(bundle))
        let dest = ModelContext(try makeContainer())
        _ = try InterchangeMapping.importBundle(decoded, context: dest)

        // ── Equipment.
        let importedRower = try #require(
            (try dest.fetch(FetchDescriptor<Equipment>())).first { $0.name == "Probe Rower" }
        )
        #expect(importedRower.weightStep == 1.25)
        #expect(importedRower.suggestedProfile?.metrics == [.distance, .pace])
        #expect(importedRower.suggestedProfile?.distanceUnit == .miles)

        // ── Exercise.
        let importedExercises = try dest.fetch(FetchDescriptor<Exercise>())
        let importedRow = try #require(importedExercises.first { $0.name == "Probe Row" })
        #expect(importedRow.muscleGroup == .back)
        #expect(importedRow.equipment.map(\.name) == ["Probe Rower"])
        #expect(importedRow.notes == "Drive with the legs.")
        #expect(importedRow.videoURL == "https://youtu.be/probe")
        #expect(importedRow.defaultWeight == 60)
        #expect(importedRow.defaultReps == 8)
        #expect(importedRow.defaultRepsUpper == 12)
        #expect(importedRow.defaultDurationSeconds == 90)
        #expect(InterchangeMapping.decodeHeartRate(importedRow.defaultHeartRateTargetData) == .zone(.zone3))
        #expect(importedRow.metricProfile.metrics == [.weight, .reps, .distance, .duration])
        #expect(importedRow.metricProfile.distanceUnit == .miles)
        #expect(importedRow.metricProfile.isOutdoor == true, "the outdoor flag rides the explicit profile (#378)")
        #expect(importedRow.extraDefaults == [.distance: 2000, .pace: 300])
        #expect(importedRow.inLibrary == true)
        let importedRetired = try #require(importedExercises.first { $0.name == "Probe Retired" })
        #expect(importedRetired.inLibrary == false, "library removal round-trips")

        // ── Routine + block + entry.
        let importedRoutine = try #require(
            (try dest.fetch(FetchDescriptor<Routine>())).first { $0.name == "Probe Routine" }
        )
        #expect(importedRoutine.restSeconds == 75)
        #expect(importedRoutine.transitionSeconds == 25)
        #expect(importedRoutine.notes == "Under an hour.")
        #expect(importedRoutine.schedule == .weekdays([1, 3, 5]))
        let importedBlock = try #require(importedRoutine.sortedGroups.first)
        #expect(importedBlock.sets == 4)
        #expect(importedBlock.restSecondsOverride == 120)
        let importedEntry = try #require(importedBlock.sortedExercises.first { $0.exercise?.name == "Probe Row" })
        #expect(importedEntry.weight == 60)
        #expect(importedEntry.reps == 8)
        #expect(importedEntry.repsUpper == 12)
        #expect(importedEntry.durationSeconds == 90)
        #expect(importedEntry.heartRateTarget == .range(lowerBPM: 120, upperBPM: 140))
        #expect(importedEntry.extraTargets == [.distance: 500])

        // ── Library membership.
        let importedHome = try #require(
            (try dest.fetch(FetchDescriptor<EquipmentLibrary>())).first { $0.name == "Probe Home" }
        )
        #expect(importedHome.memberNames == ["Probe Rower"])

        // ── Session + set log.
        let importedSession = try #require(
            (try dest.fetch(FetchDescriptor<WorkoutSession>())).first { $0.routineName == "Probe Routine" }
        )
        #expect(importedSession.restSeconds == 75)
        #expect(importedSession.averageHeartRate == 145)
        #expect(importedSession.maxHeartRate == 172)
        #expect(importedSession.duration == 930, "active-clock duration survives")
        #expect(importedSession.runDistanceMeters == 5023.4)
        #expect(importedSession.runMovingSeconds == 1712)
        #expect(importedSession.runElevationGainMeters == 46.5)
        let importedLog = try #require(importedSession.sortedSetLogs.first)
        #expect(importedLog.order == 0)
        #expect(importedLog.groupIndex == 0)
        #expect(importedLog.setNumber == 1)
        #expect(importedLog.exerciseName == "Probe Row")
        #expect(importedLog.targetWeight == 60)
        #expect(importedLog.targetRepsLower == 8)
        #expect(importedLog.targetRepsUpper == 12)
        #expect(importedLog.targetDuration == 90)
        #expect(importedLog.targetHeartRate == .range(lowerBPM: 120, upperBPM: 140))
        #expect(importedLog.restSecondsOverride == 120)
        #expect(importedLog.actualWeight == 62.5)
        #expect(importedLog.actualReps == 11)
        #expect(importedLog.actualDuration == 88)
        #expect(importedLog.extraTargets == [.distance: 500])
        #expect(importedLog.extraActuals == [.distance: 512])
        #expect(importedLog.completedAt == Date(timeIntervalSince1970: 2_000_100))
        #expect(importedLog.metricProfile.metrics == [.weight, .reps, .distance, .duration])
        #expect(importedLog.metricProfile.distanceUnit == .miles, "the set's own distance unit snapshots, not the exercise's")
        #expect(importedLog.metricProfile.isOutdoor == true, "the set snapshot carries outdoor-ness (#378)")
    }

    /// Byte-stability guard: `WorkoutSession.start` writes `metricsData` on
    /// every set, so a naive export would emit a `metrics` array on classic
    /// weight/reps sets too — a determinism regression against pre-snapshot
    /// files. A set whose profile is exactly what its `exerciseType` implies
    /// must export WITHOUT `metrics`/`distanceUnit`.
    @Test("A classic weight/reps set exports no redundant profile snapshot")
    func classicSetOmitsDerivableProfile() throws {
        let context = ModelContext(try makeContainer())
        try populate(context)   // Y Raise / Band Pulses: plain weightReps sets

        let bundle = try InterchangeMapping.exportBundle(context: context)
        let sets = bundle.sessions.flatMap(\.sets)
        #expect(!sets.isEmpty)
        let metricsAllAbsent = sets.allSatisfy { $0.metrics == nil }
        let unitAllAbsent = sets.allSatisfy { $0.distanceUnit == nil }
        #expect(metricsAllAbsent, "derivable profiles stay absent")
        #expect(unitAllAbsent)
    }

    @Test("Unknown equipment referenced by an imported exercise is created")
    func equipmentCreatedOnDemand() throws {
        let context = ModelContext(try makeContainer())
        let bundle = ExportBundle(
            exercises: [
                ExerciseDTO(name: "Sled Push", muscleGroup: .fullBody, exerciseType: .weightReps, equipment: ["Sled"])
            ],
            routines: [],
            sessions: []
        )
        try InterchangeMapping.importBundle(bundle, context: context)

        let equipment = try context.fetch(FetchDescriptor<Equipment>())
        #expect(equipment.map(\.name) == ["Sled"])
        #expect(equipment.first?.isBuiltIn == false)
    }
}
