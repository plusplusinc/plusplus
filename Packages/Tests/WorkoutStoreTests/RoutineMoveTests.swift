import Foundation
import Testing
@testable import WorkoutStore

@Suite("Moving a row")
struct RoutineMoveTests {
    private let rows: [RoutineExercise]
    private let routine: Routine

    init() throws {
        rows = try ["Push-up", "Plank", "Pull-up", "Goblet squat"].map { try .builtIn($0) }
        routine = Routine(exercises: rows)
    }

    private func names(_ routine: Routine?) -> [String]? {
        routine?.exercises.map(\.exercise.name)
    }

    @Test("A row moves down before the row it's dropped above")
    func movesDown() {
        let moved = routine.moving(rows[1].id, to: .before(rows[3].id))
        #expect(names(moved) == ["Push-up", "Pull-up", "Plank", "Goblet squat"])
    }

    @Test("A row moves up")
    func movesUp() {
        let moved = routine.moving(rows[3].id, to: .before(rows[1].id))
        #expect(names(moved) == ["Push-up", "Goblet squat", "Plank", "Pull-up"])
    }

    @Test("A row moves to the end")
    func movesToEnd() {
        let moved = routine.moving(rows[0].id, to: .end)
        #expect(names(moved) == ["Plank", "Pull-up", "Goblet squat", "Push-up"])
    }

    @Test("Dropping a row at its own place changes nothing")
    func ownPlace() {
        #expect(routine.moving(rows[1].id, to: .before(rows[1].id)) == nil)
        #expect(routine.moving(rows[1].id, to: .before(rows[2].id)) == nil)
        #expect(routine.moving(rows[3].id, to: .end) == nil)
    }

    @Test("A missing row or slot changes nothing")
    func missing() {
        #expect(routine.moving(UUID(), to: .end) == nil)
        #expect(routine.moving(rows[0].id, to: .before(UUID())) == nil)
    }

    @Test("Duplicates move by their own id")
    func duplicates() throws {
        let first = try RoutineExercise.builtIn("Pull-up")
        let second = try RoutineExercise.builtIn("Pull-up")
        let plank = try RoutineExercise.builtIn("Plank")
        let moved = Routine(exercises: [first, plank, second]).moving(
            second.id,
            to: .before(plank.id),
        )
        #expect(moved?.exercises.map(\.id) == [first.id, second.id, plank.id])
    }

    @Test("A row keeps its plan when it moves")
    func keepsPlan() throws {
        let edited = try RoutineExercise.builtIn("Pull-up") { $0.sets = 5 }
        let moved = Routine(exercises: rows + [edited]).moving(edited.id, to: .before(rows[0].id))
        #expect(moved?.exercises.first == edited)
    }

    @Test("Move up and down exist only where they'd move the row")
    func neighbors() {
        #expect(routine.slotMovingUp(rows[0].id) == nil)
        #expect(routine.slotMovingDown(rows[3].id) == nil)
        #expect(routine.slotMovingUp(rows[2].id) == .before(rows[1].id))
        #expect(routine.slotMovingDown(rows[1].id) == .before(rows[3].id))
        #expect(routine.slotMovingDown(rows[2].id) == .end)

        let one = Routine(exercises: [rows[0]])
        #expect(one.slotMovingUp(rows[0].id) == nil)
        #expect(one.slotMovingDown(rows[0].id) == nil)
    }

    @Test("Moving up then down returns the row to its place")
    func upThenDown() throws {
        let up = try #require(routine.slotMovingUp(rows[2].id))
        let moved = try #require(routine.moving(rows[2].id, to: up))
        #expect(names(moved) == ["Push-up", "Pull-up", "Plank", "Goblet squat"])
        let down = try #require(moved.slotMovingDown(rows[2].id))
        #expect(moved.moving(rows[2].id, to: down) == routine)
    }

    @Test("A move is announced by the row it passed")
    func announcement() throws {
        let upSlot = try #require(routine.slotMovingUp(rows[2].id))
        let up = try #require(routine.moving(rows[2].id, to: upSlot))
        #expect(up.moveAnnouncement(for: rows[2].id, wentUp: true) == "Moved above Plank")
        let downSlot = try #require(routine.slotMovingDown(rows[0].id))
        let down = try #require(routine.moving(rows[0].id, to: downSlot))
        #expect(down.moveAnnouncement(for: rows[0].id, wentUp: false) == "Moved below Plank")
        #expect(routine.moveAnnouncement(for: rows[0].id, wentUp: false) == nil)
        #expect(routine.moveAnnouncement(for: rows[3].id, wentUp: true) == nil)
    }
}

extension Routine {
    /// The routine with the row moved, or nil when `move` refused, having left it unchanged.
    fileprivate func moving(_ id: RoutineExercise.ID, to slot: RoutineSlot) -> Routine? {
        var moved = self
        guard moved.move(id, to: slot) else {
            #expect(moved == self, "A refused move changed the routine")
            return nil
        }
        return moved
    }
}
