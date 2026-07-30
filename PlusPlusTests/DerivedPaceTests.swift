import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// #302's second half: a cardio record knows its own pace.
///
/// Distance and duration fix pace, so asking for a third number is asking
/// the user to do arithmetic on two facts the record already holds. The
/// laws being pinned here are the ones that keep that honest — an entered
/// pace wins, a derived one is never stored, and nothing that WRITES ever
/// reads the derivation.
@Suite("Derived pace on a logged effort")
struct DerivedPaceTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("derived-pace-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let erg = MetricProfile([.distance, .duration, .pace, .resistance])

    /// A logged erg piece: 500 m, and it took 2:03.
    private func makePiece(
        _ context: ModelContext,
        profile: MetricProfile? = nil,
        distance: Double? = 500,
        seconds: Int? = 123
    ) -> SetLog {
        let log = SetLog(order: 0, groupIndex: 0, setNumber: 1, exerciseName: "Probe Row")
        context.insert(log)
        log.metricProfile = profile ?? erg
        if let distance { log.setActual(.distance, to: distance) }
        log.actualDuration = seconds
        return log
    }

    @Test("A piece that logged its distance and its time reports a pace it never stored")
    func derivesFromLoggedActuals() throws {
        let context = ModelContext(try makeContainer())
        let log = makePiece(context)

        let pace = try #require(log.actual(.pace))
        #expect(abs(pace - 123) < 0.001, "500 m in 2:03 is a 2:03 split")
        // The line the record draws now says so.
        #expect(log.resultSummary(weightUnit: .lb).contains("2:03"))
        // ⚠️ And nothing was written: a stored derivation stops tracking
        // its inputs, which is the whole reason CardioTargets keeps the
        // third value out of storage one layer up.
        #expect(log.storedActual(.pace) == nil)
        #expect(log.extraActuals[.pace] == nil)
    }

    @Test("It tracks its inputs, which is what not storing it buys")
    func followsACorrection() throws {
        let context = ModelContext(try makeContainer())
        let log = makePiece(context)
        #expect(abs((log.actual(.pace) ?? 0) - 123) < 0.001)

        // You misread the console: it was 1:50, not 2:03.
        log.actualDuration = 110
        #expect(abs((log.actual(.pace) ?? 0) - 110) < 0.001, "correcting the time corrects the pace")
    }

    @Test("An entered pace is the override and the derivation stops")
    func manualEntryWins() throws {
        let context = ModelContext(try makeContainer())
        let log = makePiece(context)

        log.setActual(.pace, to: 118)
        #expect(abs((log.actual(.pace) ?? 0) - 118) < 0.001)
        // Still 118 after the inputs move: an assertion is not arithmetic.
        log.actualDuration = 200
        #expect(abs((log.actual(.pace) ?? 0) - 118) < 0.001)
    }

    @Test("Half a record derives nothing")
    func needsBothHalves() throws {
        let context = ModelContext(try makeContainer())
        #expect(makePiece(context, distance: nil).actual(.pace) == nil)
        #expect(makePiece(context, seconds: nil).actual(.pace) == nil)
        // And an exercise that doesn't track pace never grows one.
        let strength = makePiece(context, profile: MetricProfile([.distance, .duration]))
        #expect(strength.actual(.pace) == nil)
    }

    @Test("A pool splits per 100, not per 500")
    func honoursTheProfileReference() throws {
        let context = ModelContext(try makeContainer())
        let pool = MetricProfile(
            [.distance, .duration, .pace],
            distanceUnit: .meters,
            paceReference: .per100Meters
        )
        let swim = makePiece(context, profile: pool, distance: 1000, seconds: 1200)
        let pace = try #require(swim.actual(.pace))
        // 1000 m in 20:00 is a 2:00/100m swim. Read with the erg's own
        // convention — the one the distance unit alone implies — the same
        // effort prints 10:00 and reads like a different sport.
        #expect(abs(pace - 120) < 0.001)
    }

    @Test("Completing a set leaves the pace to the record instead of copying the plan")
    func completeDoesNotFreezeThePlannedPace() throws {
        let context = ModelContext(try makeContainer())
        let routine = Routine(name: "Probe Erg")
        context.insert(routine)
        let exercise = Exercise(name: "Probe Row", muscleGroup: .fullBody)
        context.insert(exercise)
        exercise.metricProfile = erg
        let group = routine.addExerciseInNewGroup(exercise, context: context)
        group.sets = 1
        let entry = try #require(group.sortedExercises.first)
        entry.durationSeconds = 120
        entry.extraTargets = [.distance: 500, .pace: 120]

        let session = WorkoutSession.start(from: routine, context: context)
        let log = try #require(session.sortedSetLogs.first)
        // It actually took longer than planned.
        log.actualDuration = 150
        session.complete(log)

        #expect(log.storedActual(.pace) == nil, "the plan's pace is not an achievement")
        let pace = try #require(log.actual(.pace))
        #expect(abs(pace - 150) < 0.001, "500 m in 2:30 is a 2:30 split, not the prescribed 2:00")
    }

    @Test("A measured pace still gets recorded — the write path reads the STORED value")
    func measurementBeatsDerivation() throws {
        let context = ModelContext(try makeContainer())
        let log = makePiece(context)
        // This is the guard on the GPS write-back in ActiveSessionView: it
        // fires on `storedActual(.pace) == nil`, and would never fire again
        // if it asked `actual(.pace)`, since a distance and a duration are
        // exactly what an outdoor run has. A meter's average is over MOVING
        // time; the derivation divides by elapsed, so the measurement is
        // the better number and has to be able to win.
        #expect(log.storedActual(.pace) == nil)
        log.setActual(.pace, to: 117)
        #expect(abs((log.actual(.pace) ?? 0) - 117) < 0.001)
    }

    @Test("Graduating a session into a routine never stores all three of the triad")
    func templateKeepsTheTriadOpen() throws {
        let context = ModelContext(try makeContainer())
        let session = WorkoutSession.startEmpty(context: context)
        let exercise = Exercise(name: "Probe Row", muscleGroup: .fullBody)
        context.insert(exercise)
        exercise.metricProfile = erg
        let log = SetLog(order: 0, groupIndex: 0, setNumber: 1, exercise: exercise, exerciseName: "Probe Row")
        context.insert(log)
        log.session = session
        log.metricProfile = erg
        log.setActual(.distance, to: 500)
        log.actualDuration = 123
        log.completedAt = Date()

        let routine = session.saveAsRoutine(named: "Probe Erg", among: [], context: context)
        let entry = try #require(routine?.sortedGroups.first?.sortedExercises.first)
        let stored = CardioTargets.triad.filter { metric in
            switch metric {
            case .duration: entry.durationSeconds != nil
            default: entry.extraTargets[metric] != nil
            }
        }
        // ⚠️ A template is a PRESCRIPTION. Three stored values is the state
        // CardioTargets exists to prevent: the sheet reads every one of
        // them as entered and evicts one on the next edit.
        #expect(stored.count <= 2, "stored triad: \(stored)")
        #expect(entry.extraTargets[.pace] == nil)
    }
}
