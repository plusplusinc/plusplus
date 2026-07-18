import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// Operator's read side: digest formatting and stat math, all against
/// real fetches (no model involved).
@MainActor
@Suite("Operator data service")
struct OperatorDataServiceTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self,
            Routine.self, ExerciseGroup.self, RoutineExercise.self,
            WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("operator-data-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Fixed clock + UTC calendar so results don't depend on the machine.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        DateComponents(calendar: calendar, year: year, month: month, day: day, hour: hour).date!
    }

    private func service(_ context: ModelContext, today: Date) -> OperatorDataService {
        OperatorDataService(context: context, calendar: calendar, today: { today })
    }

    private func finishedSession(_ name: String, on day: Date, in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(routineName: name, startedAt: day)
        session.endedAt = day.addingTimeInterval(1800)
        context.insert(session)
        return session
    }

    // MARK: - find_items

    @Test("Routine digest lists name, size, schedule, estimate")
    func routineDigest() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let squat = Exercise(name: "Probe Squat", muscleGroup: .quads)
        context.insert(squat)
        let routine = Routine(name: "Probe Legs", order: 0)
        context.insert(routine)
        routine.addExerciseInNewGroup(squat, context: context)
        routine.schedule = .weekdays([2, 5])
        context.insert(Routine(name: "Probe Arms", order: 1))

        let digest = service(context, today: date(2026, 7, 15)).findItems(kind: .routine)
        let lines = digest.split(separator: "\n").map(String.init)
        #expect(lines[0] == "2 of 2 routines:")
        // Schedule text is shortLabel, THE shared schedule vocabulary.
        #expect(lines[1].hasPrefix("Probe Legs · 1 exercise · mon/thu · ~"))
        #expect(lines[2] == "Probe Arms · 0 exercises · no schedule · ~5 min")
    }

    @Test("Exercise digest filters by muscle and favorites")
    func exerciseDigest() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let curl = Exercise(name: "Probe Curl", muscleGroup: .biceps)
        context.insert(curl)
        // A favorited exercise carries the "favorite" tag in the digest.
        curl.isFavorite = true
        let stretch = Exercise(name: "Probe Neck Stretch", muscleGroup: .shoulders)
        context.insert(stretch)
        stretch.metricProfile = .durationOnly

        let all = service(context, today: date(2026, 7, 15)).findItems(kind: .exercise)
        #expect(all.contains("Probe Curl · biceps · weight and reps · favorite"))
        #expect(all.contains("Probe Neck Stretch · shoulders · duration"))

        let filtered = service(context, today: date(2026, 7, 15)).findItems(kind: .exercise, muscleGroup: .biceps)
        #expect(filtered.contains("Probe Curl"))
        #expect(!filtered.contains("Neck"))

        let favorites = service(context, today: date(2026, 7, 15)).findItems(kind: .exercise, favoritesOnly: true)
        #expect(favorites.contains("Probe Curl"))
        #expect(!favorites.contains("Neck"))
    }

    @Test("No matches reads honestly")
    func noMatches() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let digest = service(context, today: date(2026, 7, 15)).findItems(kind: .routine, nameContains: "pilates")
        #expect(digest == "no matches for \"pilates\" in routines")
    }

    @Test("A typo'd fragment still finds its item")
    func fuzzyFragment() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Routine(name: "Probe Legs", order: 0))
        context.insert(Routine(name: "Probe Arms", order: 1))

        let typo = service(context, today: date(2026, 7, 15)).findItems(kind: .routine, nameContains: "lgegs")
        #expect(typo.contains("Probe Legs"))
        #expect(!typo.contains("Probe Arms"))

        let glued = service(context, today: date(2026, 7, 15)).findItems(kind: .routine, nameContains: "probelegs")
        #expect(glued.contains("Probe Legs"))
    }

    @Test("Library digest marks the active library and names the gear")
    func libraryDigest() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = EquipmentLibrary(name: "Probe Home", order: 0)
        context.insert(home)
        context.insert(EquipmentLibrary(name: "Probe Hotel", order: 1))
        for name in ["Probe Bench", "Probe Bands", "Probe Bar"] {
            let item = Equipment(name: name)
            context.insert(item)
            home.setMembership(item, true)
        }
        let digest = service(context, today: date(2026, 7, 15)).findItems(kind: .library)
        let lines = digest.split(separator: "\n").map(String.init)
        // Names ride in the line, alphabetized — a count-only digest
        // leaves the model unable to say WHICH gear (first field round).
        #expect(lines[1] == "Probe Home · 3 items: Probe Bands, Probe Bar, Probe Bench · active")
        #expect(lines[2] == "Probe Hotel · 0 items")
    }

    @Test("Library digest caps the gear list")
    func libraryDigestCap() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = EquipmentLibrary(name: "Probe Home", order: 0)
        context.insert(home)
        for index in 1...12 {
            let item = Equipment(name: String(format: "Probe Gear %02d", index))
            context.insert(item)
            home.setMembership(item, true)
        }
        let digest = service(context, today: date(2026, 7, 15)).findItems(kind: .library)
        let lines = digest.split(separator: "\n").map(String.init)
        #expect(lines[1].hasSuffix("Probe Gear 10, +2 more · active"))
        #expect(lines[1].contains("12 items: Probe Gear 01,"))
    }

    // MARK: - get_stats

    @Test("Workout count respects the day window and routine scope")
    func workoutCount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = date(2026, 7, 15)
        _ = finishedSession("Probe Legs", on: date(2026, 7, 10), in: context)
        _ = finishedSession("Probe Legs", on: date(2026, 5, 1), in: context)
        _ = finishedSession("Probe Arms", on: date(2026, 7, 12), in: context)
        // Unfinished sessions never count.
        context.insert(WorkoutSession(routineName: "Probe Legs", startedAt: date(2026, 7, 14)))

        let all = service(context, today: today).stats(kind: .workoutCount)
        #expect(all == "workouts in last 30 days: 2")
        // The reply speaks the CANONICAL history name, not the model's
        // casing of it.
        let scoped = service(context, today: today).stats(kind: .workoutCount, routineName: "probe legs", days: 90)
        #expect(scoped == "workouts of Probe Legs in last 90 days: 2")
        // A typo resolves to one canonical routine; the count stays
        // exact-scoped to it.
        let typo = service(context, today: today).stats(kind: .workoutCount, routineName: "probe lgegs", days: 90)
        #expect(typo == "workouts of Probe Legs in last 90 days: 2")
        // An unresolvable name echoes raw and counts zero — never a
        // silent blend of near-matches.
        let missing = service(context, today: today).stats(kind: .workoutCount, routineName: "pilates", days: 90)
        #expect(missing == "workouts of pilates in last 90 days: 0")
    }

    @Test("Last done reports the set summary with dates")
    func lastDone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = date(2026, 7, 15)
        let session = finishedSession("Probe Legs", on: date(2026, 7, 8), in: context)
        for setNumber in 1...3 {
            let log = SetLog(order: setNumber, groupIndex: 0, setNumber: setNumber, exerciseName: "Probe Deadlift", targetWeight: 225)
            log.actualWeight = 225
            log.actualReps = 5
            log.completedAt = session.startedAt
            log.session = session
            context.insert(log)
        }

        let digest = service(context, today: today).stats(kind: .lastDone, exerciseName: "deadlift")
        #expect(digest == "Probe Deadlift last done 2026-07-08 (7 days ago) · 3 sets · top 225")

        // Fuzzy lookup, canonical answer: a typo'd exercise name still
        // resolves, and the reply names the real thing.
        let typo = service(context, today: today).stats(kind: .lastDone, exerciseName: "dedlift")
        #expect(typo == "Probe Deadlift last done 2026-07-08 (7 days ago) · 3 sets · top 225")

        let routineDigest = service(context, today: today).stats(kind: .lastDone, routineName: "Probe Legs")
        #expect(routineDigest == "Probe Legs last done 2026-07-08 (7 days ago) · 3 sets logged")

        let missing = service(context, today: today).stats(kind: .lastDone, exerciseName: "bench")
        #expect(missing == "no logged sets of bench yet")
    }

    @Test("Set volume counts completed sets in the window")
    func setVolume() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = date(2026, 7, 15)
        let recent = finishedSession("Probe Legs", on: date(2026, 7, 10), in: context)
        let old = finishedSession("Probe Legs", on: date(2026, 3, 1), in: context)
        for (index, session) in [recent, recent, old].enumerated() {
            let log = SetLog(order: index, groupIndex: 0, setNumber: 1, exerciseName: "Probe Squat")
            log.completedAt = session.startedAt
            log.session = session
            context.insert(log)
        }
        let digest = service(context, today: today).stats(kind: .setVolume, exerciseName: "Probe Squat")
        #expect(digest == "completed sets of Probe Squat in last 30 days: 2")
    }

    @Test("Streak counts consecutive weeks; an empty current week holds")
    func streak() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // 2026-07-15 is a Wednesday. Workouts last week and the week
        // before, none yet this week: streak reads 2 and holds.
        _ = finishedSession("Probe Legs", on: date(2026, 7, 9), in: context)
        _ = finishedSession("Probe Legs", on: date(2026, 7, 1), in: context)
        let digest = service(context, today: date(2026, 7, 15)).stats(kind: .streak)
        #expect(digest == "current streak: 2 weeks with a workout")

        // A workout this week extends it to 3.
        _ = finishedSession("Probe Arms", on: date(2026, 7, 14), in: context)
        let extended = service(context, today: date(2026, 7, 15)).stats(kind: .streak)
        #expect(extended == "current streak: 3 weeks with a workout")
    }
}
