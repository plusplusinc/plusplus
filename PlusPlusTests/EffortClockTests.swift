import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// The count-up effort clock lives on the session's running-time ledger.
///
/// In count-up mode the displayed elapsed IS the logged duration, so the
/// anchor's home decides what survives: a card-held anchor died on the
/// pause that unmounts the card (a 29-minute ride with one water stop
/// logged as four minutes), a view-held one still died with the process.
/// `effortAnchorSeconds` is stamped in `elapsed()` space, so both terms
/// of the subtraction read the same ledger and pauses drop out with no
/// banking anywhere.
@Suite("Effort clock")
struct EffortClockTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("effortclock-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let t0 = Date(timeIntervalSince1970: 3_000_000)

    @Test("A pause in the middle of an effort never reaches its clock")
    func pauseDropsOut() throws {
        let context = ModelContext(try makeContainer())
        let session = WorkoutSession.startEmpty(context: context)
        session.startClock(at: t0)
        session.markEffortStart(at: t0)

        // One minute in, a water stop; forty seconds held; resume.
        session.pauseClock(at: t0.addingTimeInterval(60))
        session.startClock(at: t0.addingTimeInterval(100))

        // Twenty-nine minutes of wall clock, one 40 s hold: the effort
        // ran 28:20 — and that is what the key would log.
        let reading = session.effortElapsed(at: t0.addingTimeInterval(29 * 60))
        #expect(abs(reading - (29 * 60 - 40)) < 0.001)
    }

    @Test("A later stamp starts the next effort's clock at zero")
    func restampResets() throws {
        let context = ModelContext(try makeContainer())
        let session = WorkoutSession.startEmpty(context: context)
        session.startClock(at: t0)
        session.markEffortStart(at: t0)

        // First effort ends at 5:00; a 2:00 rest; the rest-end stamp.
        session.markEffortStart(at: t0.addingTimeInterval(7 * 60))

        // Ninety seconds into round two, its clock says ninety seconds —
        // not 8:30 (no stamp) and not 3:30 (a stamp at rest START, which
        // would file the recovery as effort).
        let reading = session.effortElapsed(at: t0.addingTimeInterval(8 * 60 + 30))
        #expect(abs(reading - 90) < 0.001)
    }

    @Test("No stamp reads as the clock's own start")
    func nilAnchorIsZero() throws {
        let context = ModelContext(try makeContainer())
        let session = WorkoutSession.startEmpty(context: context)
        session.startClock(at: t0)

        #expect(session.effortAnchorSeconds == nil)
        let reading = session.effortElapsed(at: t0.addingTimeInterval(120))
        #expect(abs(reading - 120) < 0.001, "the first effort starts when the clock does")
    }

    @Test("Salvage finishes at the last real activity and banks nothing after it")
    func salvageCarriesHonestDuration() throws {
        let context = ModelContext(try makeContainer())
        let session = WorkoutSession.startEmpty(context: context, at: t0)
        session.startClock(at: t0)

        // One set logged ten minutes in; the crash comes some time
        // after, and the app is next opened days later.
        let log = SetLog(order: 0, groupIndex: 0, setNumber: 1, exerciseName: "Probe Row")
        context.insert(log)
        log.actualReps = 8
        log.completedAt = t0.addingTimeInterval(600)
        log.session = session

        // What `resolveOrphanedSessions` does to a non-empty orphan
        // (#503): finish at the last verifiable activity. The running
        // segment banks only up to that stamp — the crash-to-reopen gap
        // is not training time, and there is no editor to fix a record
        // that claimed it was.
        session.finish(at: session.lastActivityAt)

        #expect(session.endedAt == t0.addingTimeInterval(600))
        let duration = session.duration ?? 0
        #expect(abs(duration - 600) < 0.001, "banked \(duration) s; the two-day gap must not count")
    }
}
