import Foundation
import Testing
@testable import WorkoutStore

@Suite("Supersets")
struct RoutineSupersetTests {
    /// Rows A to E, each with its own set count: A has 1, B 2, and so on.
    private let rows: [RoutineExercise]

    init() throws {
        rows = try ["Push-up", "Plank", "Pull-up", "Goblet squat", "Dumbbell row"].enumerated()
            .map { index, name in try .builtIn(name) { $0.sets = index + 1 } }
    }

    // MARK: Drawing a superset by its node

    @Test("A node dragged onto the next row makes the two a superset, with the held row's rounds")
    func pair() {
        let result = regrouped("A B C", holding: "A", reaching: "B")
        #expect(shape(result?.routine) == "A-B C")
        #expect(sets(result?.routine) == [1, 1, 3])
        #expect(result?.superset == [id("A"), id("B")])
    }

    @Test("The span runs from the held row to the row reached, and shrinks as the drag comes back")
    func spanAndShrink() {
        #expect(shape(regrouped("A B C D E", holding: "A", reaching: "D")?.routine) == "A-B-C-D E")
        #expect(shape(regrouped("A B C D E", holding: "A", reaching: "C")?.routine) == "A-B-C D E")
        #expect(shape(regrouped("A B C D E", holding: "A", reaching: "B")?.routine) == "A-B C D E")
        #expect(regrouped("A B C D E", holding: "A", reaching: "A") == nil)
        #expect(regrouped("A-B C", holding: "A", reaching: "A") == nil)
        #expect(shape(regrouped("A B C D", holding: "B", reaching: "D")?.routine) == "A B-C-D")
    }

    @Test("A span drawn upward takes the held row's rounds too")
    func upward() {
        let result = regrouped("A B C D", holding: "D", reaching: "B")
        #expect(shape(result?.routine) == "A B-C-D")
        #expect(sets(result?.routine) == [1, 4, 4, 4])
        #expect(result?.superset == [id("B"), id("C"), id("D")])
    }

    @Test("A middle member draws a new superset, cutting the old one; a lone row left goes plain")
    func middleCuts() {
        #expect(shape(regrouped("A-B-C-D", holding: "C", reaching: "B")?.routine) == "A B-C D")
        #expect(shape(regrouped("A-B-C-D-E", holding: "C", reaching: "D")?.routine) == "A-B C-D E")
        #expect(shape(regrouped("A-B-C D-E", holding: "B", reaching: "D")?.routine) == "A B-C-D E")
    }

    @Test("An end member moves its end: the superset runs from its other end to the row reached")
    func endMoves() {
        #expect(shape(regrouped("A-B-C-D", holding: "A", reaching: "B")?.routine) == "A B-C-D")
        #expect(shape(regrouped("A-B C-D", holding: "B", reaching: "D")?.routine) == "A-B-C-D")
        #expect(shape(regrouped("A-B C-D", holding: "B", reaching: "C")?.routine) == "A-B-C D")
        #expect(shape(regrouped("A-B C", holding: "B", reaching: "C")?.routine) == "A-B-C")
        #expect(shape(regrouped("A-B-C D", holding: "C", reaching: "B")?.routine) == "A-B C D")
        #expect(shape(regrouped("A B-C", holding: "B", reaching: "A")?.routine) == "A-B-C")
        #expect(shape(regrouped("A-B C-D", holding: "A", reaching: "D")?.routine) == "A B-C-D")
    }

    @Test("An end moved onto the other end leaves a span of one: every row plain, none a superset")
    func endOntoEnd() {
        let pair = regrouped("A-B C", holding: "A", reaching: "B")
        #expect(shape(pair?.routine) == "A B C")
        #expect(pair?.superset == [])
        #expect(shape(regrouped("A-B-C", holding: "C", reaching: "A")?.routine) == "A B C")
    }

    @Test("An end's superset keeps its round count; rows it takes in take it too")
    func endKeepsRounds() {
        let result = regrouped("A B-C D", holding: "C", reaching: "D")
        #expect(shape(result?.routine) == "A B-C-D")
        #expect(sets(result?.routine) == [1, 2, 2, 2])
        let grown = regrouped("A B-C D", holding: "B", reaching: "A")
        #expect(sets(grown?.routine) == [2, 2, 2, 4])
    }

    @Test("A plain row's span takes the rows it covers, whole supersets or not")
    func plainAcross() {
        #expect(shape(regrouped("A B-C D-E", holding: "A", reaching: "D")?.routine) == "A-B-C-D E")
        #expect(shape(regrouped("A B-C-D", holding: "A", reaching: "B")?.routine) == "A-B C-D")
    }

    @Test("Rows cut off keep the round count they shared")
    func cutKeepsRounds() throws {
        var start = routine("A-B-C-D")
        start.exercises = start.exercises.map { var row = $0
            row.plan.sets = 3
            return row
        }
        let result = try #require(start.regrouped(holding: id("C"), reaching: id("B")))
        #expect(sets(result.routine) == [3, 3, 3, 3])
        let split = try #require(start.regrouped(holding: id("B"), reaching: id("A")))
        #expect(shape(split.routine) == "A-B C-D")
        #expect(split.routine.exercises[0].supersetID != split.routine.exercises[2].supersetID)
    }

    @Test("Regroup applies the rule, and refuses a drag onto the held row")
    func regroup() {
        var start = routine("A B")
        let changed = start.regroup(holding: id("A"), reaching: id("A"))
        #expect(!changed)
        let changedAgain = start.regroup(holding: id("A"), reaching: id("B"))
        #expect(changedAgain)
        #expect(shape(start) == "A-B")
    }

    // MARK: Moving by the row's body

    @Test("A plain row moved between two members joins, and takes the superset's rounds")
    func moveInside() {
        var start = routine("A-B C")
        let changed = start.move(id("C"), to: .before(id("B")))
        #expect(changed)
        #expect(shape(start) == "A-C-B")
        #expect(sets(start) == [1, 1, 1])
    }

    @Test("A row moved to a superset's edge joins it on the side named, and else stays plain")
    func moveToEdge() {
        var below = routine("A B-C")
        let changed = below.move(id("A"), to: .before(id("B"), joining: .below))
        #expect(changed)
        #expect(shape(below) == "A-B-C")
        #expect(sets(below) == [2, 2, 2])

        var above = routine("A-B C")
        let changedAgain = above.move(id("C"), to: .end)
        #expect(!changedAgain)
        let changedThird = above.move(id("C"), to: RoutineSlot(.end, joining: .above))
        #expect(changedThird)
        #expect(shape(above) == "A-B-C")
        #expect(sets(above) == [1, 1, 1])

        var plain = routine("C A-B")
        let changedFourth = plain.move(id("C"), to: .end)
        #expect(changedFourth)
        #expect(shape(plain) == "A-B C")
    }

    @Test("A member moved away leaves a pair plain, and a triple a pair")
    func moveOut() {
        var pair = routine("A-B C")
        let changed = pair.move(id("A"), to: .end)
        #expect(changed)
        #expect(shape(pair) == "B C A")
        var triple = routine("A-B-C D")
        let changedAgain = triple.move(id("B"), to: .end)
        #expect(changedAgain)
        #expect(shape(triple) == "A-C D B")
    }

    @Test("A member dropped back at its own place, in its own superset, changes nothing")
    func moveInPlace() {
        var start = routine("A-B C")
        let before = start
        let changed = start.move(id("B"), to: .before(id("C"), joining: .above))
        #expect(!changed)
        let changedAgain = start.move(id("A"), to: .before(id("B"), joining: .below))
        #expect(!changedAgain)
        #expect(start == before)
        let changedThird = start.move(id("B"), to: .before(id("C")))
        #expect(changedThird)
        #expect(shape(start) == "A B C")
    }

    // MARK: Delete and rounds

    @Test("Deleting one of a pair leaves the other plain, and one of three a pair")
    func delete() {
        var pair = routine("A-B C")
        pair.remove(id("A"))
        #expect(shape(pair) == "B C")
        #expect(pair.exercises.allSatisfy { $0.supersetID == nil })
        var triple = routine("A-B-C")
        triple.remove(id("B"))
        #expect(shape(triple) == "A-C")
    }

    @Test("Stepping a member's rounds steps every member's; nothing else is shared")
    func sharedRounds() throws {
        var start = try #require(routine("A B C").regrouped(holding: id("A"), reaching: id("B")))
            .routine
        var edited = start.exercises[1]
        edited.plan.sets = 4
        edited.plan.target = .reps(15)
        start.update(edited)
        #expect(sets(start) == [4, 4, 3])
        #expect(start.exercises[0].plan.target == row("A").plan.target)
        #expect(start.exercises[1].plan.target == .reps(15))

        var plain = start.exercises[2]
        plain.plan.sets = 6
        start.update(plain)
        #expect(sets(start) == [4, 4, 6])
        #expect(start.partners(of: id("A")).map(\.id) == [id("B")])
        #expect(start.partners(of: id("C")).isEmpty)
    }

    @Test("A member's partners read as a list of names; a plain row has none")
    func partnerNames() {
        let start = routine("A-B-C D")
        let (bName, cName) = (row("B").exercise.name, row("C").exercise.name)
        #expect(start.partnerNames(of: id("A")) == "\(bName) and \(cName)")
        #expect(start.partnerNames(of: id("D")) == nil)
    }

    @Test("Normalizing splits a broken run, drops a run of one, and evens rounds")
    func normalize() {
        let superset = UUID()
        var exercises = rows
        for index in [0, 1, 3, 4] {
            exercises[index].supersetID = superset
        }
        exercises[2].supersetID = UUID()
        exercises.normalizeSupersets()
        let routine = Routine(exercises: exercises)
        #expect(shape(routine) == "A-B C D-E")
        #expect(exercises[0].supersetID == superset)
        #expect(exercises[3].supersetID != superset)
        #expect(exercises[2].supersetID == nil)
        #expect(sets(routine) == [1, 1, 3, 4, 4])
    }

    @Test("The rows joined to the next")
    func joinedToNext() {
        #expect(routine("A-B C D-E").joinedToNext == [id("A"), id("D")])
        #expect(routine("A B").joinedToNext.isEmpty)
    }

    // MARK: VoiceOver

    @Test("Joining a neighbor is offered only where there's one, not joined yet")
    func canJoin() {
        let start = routine("A B-C D")
        #expect(!start.canJoin(id("A"), .above))
        #expect(start.canJoin(id("A"), .below))
        #expect(!start.canJoin(id("B"), .below))
        #expect(start.canJoin(id("C"), .below))
        #expect(!start.canJoin(id("D"), .below))
        #expect(start.neighbor(of: id("A"), .below)?.id == id("B"))
        #expect(start.neighbor(of: id("A"), .above) == nil)
        var joined = start
        joined.join(id("D"), .above)
        #expect(shape(joined) == "A B-C-D")
        #expect(sets(joined) == [1, 4, 4, 4])
    }

    @Test("Leaving a superset: in place from an end, to just below it from the middle")
    func leave() {
        var end = routine("A-B-C D")
        end.leaveSuperset(id("C"))
        #expect(shape(end) == "A-B C D")
        var first = routine("A-B D")
        first.leaveSuperset(id("A"))
        #expect(shape(first) == "A B D")
        var middle = routine("A-B-C D")
        middle.leaveSuperset(id("B"))
        #expect(shape(middle) == "A-C B D")
        #expect(!middle.isInSuperset(id("B")))
    }

    @Test("Move up and down keep a member in its superset, and take a plain row past one")
    func moveUpDown() throws {
        let start = routine("A B-C D")
        #expect(start.slotMovingUp(id("B")) == nil)
        #expect(start.slotMovingDown(id("C")) == nil)

        var down = start
        try down.move(id("B"), to: #require(start.slotMovingDown(id("B"))))
        #expect(shape(down) == "A C-B D")

        var upward = start
        try upward.move(id("C"), to: #require(start.slotMovingUp(id("C"))))
        #expect(shape(upward) == "A C-B D")

        var plainDown = start
        try plainDown.move(id("A"), to: #require(start.slotMovingDown(id("A"))))
        #expect(shape(plainDown) == "B-C A D")

        var plainUp = start
        try plainUp.move(id("D"), to: #require(start.slotMovingUp(id("D"))))
        #expect(shape(plainUp) == "A D B-C")
    }
}

extension RoutineSupersetTests {
    /// A routine of rows A to E grouped as `shape` writes them: "A-B C D-E", each superset at
    /// its first row's round count.
    private func routine(_ shape: String) -> Routine {
        var exercises: [RoutineExercise] = []
        for group in shape.split(separator: " ") {
            let superset = group.count > 1 ? UUID() : nil
            for letter in group.split(separator: "-") {
                var row = row(String(letter))
                row.supersetID = superset
                exercises.append(row)
            }
        }
        // As every rule leaves it: a superset's rounds are its first row's.
        exercises.normalizeSupersets()
        return Routine(exercises: exercises)
    }

    private func row(_ letter: String) -> RoutineExercise {
        rows[Int(letter.unicodeScalars.first?.value ?? 65) - 65]
    }

    private func id(_ letter: String) -> RoutineExercise.ID {
        row(letter).id
    }

    private func letter(_ id: RoutineExercise.ID) -> String {
        rows.firstIndex { $0.id == id }
            .map { String(UnicodeScalar(65 + $0).map(Character.init) ?? "?") } ?? "?"
    }

    /// The routine's rows and supersets as `routine(_:)` takes them.
    private func shape(_ routine: Routine?) -> String? {
        guard let routine else { return nil }
        var groups: [String] = []
        var previous: UUID?
        for row in routine.exercises {
            if let superset = row.supersetID, superset == previous {
                groups[groups.count - 1] += "-" + letter(row.id)
            } else {
                groups.append(letter(row.id))
            }
            previous = row.supersetID
        }
        return groups.joined(separator: " ")
    }

    private func sets(_ routine: Routine?) -> [Int]? {
        routine?.exercises.map(\.plan.sets)
    }

    private func regrouped(
        _ shape: String,
        holding held: String,
        reaching reach: String,
    ) -> Regrouping? {
        routine(shape).regrouped(holding: id(held), reaching: id(reach))
    }
}

// MARK: An end, a middle, and a press

extension RoutineSupersetTests {
    @Test("The card's examples, each as Dave settled it")
    func cardExamples() {
        #expect(shape(regrouped("A-B", holding: "A", reaching: "B")?.routine) == "A B")
        #expect(shape(regrouped("A-B-C-D", holding: "A", reaching: "B")?.routine) == "A B-C-D")
        #expect(shape(regrouped("A-B C-D", holding: "B", reaching: "D")?.routine) == "A-B-C-D")
        #expect(shape(regrouped("A-B C-D", holding: "B", reaching: "C")?.routine) == "A-B-C D")
        #expect(shape(regrouped("A-B-C-D", holding: "C", reaching: "B")?.routine) == "A B-C D")
        #expect(shape(regrouped("A B-C-D", holding: "A", reaching: "B")?.routine) == "A-B C-D")
    }

    @Test("The span runs from the anchor to the row reached, a lone row when it collapses")
    func span() {
        #expect(regrouped("A-B C", holding: "A", reaching: "B")?.span == [id("B")])
        let across = regrouped("A-B C-D", holding: "B", reaching: "C")
        #expect(across?.span == [id("A"), id("B"), id("C")])
        #expect(regrouped("A-B-C-D", holding: "C", reaching: "B")?.span == [id("B"), id("C")])
    }

    @Test("A press picks up an end's whole superset, and a middle or plain row alone")
    func pickedUp() {
        let start = routine("A-B-C D-E")
        #expect(start.pickedUp(holding: id("A")) == [id("A"), id("B"), id("C")])
        #expect(start.pickedUp(holding: id("C")) == [id("A"), id("B"), id("C")])
        #expect(start.pickedUp(holding: id("B")) == [id("B")])
        #expect(start.pickedUp(holding: id("D")) == [id("D"), id("E")])
        #expect(start.pickedUp(holding: id("E")) == [id("D"), id("E")])
        #expect(routine("A B").pickedUp(holding: id("A")) == [id("A")])
    }
}

extension RoutineSupersetTests {
    @Test("A row moved to a plain row's edge, joining it, pairs the two at the larger set count")
    func moveToPair() {
        var below = routine("A B C")
        let changed = below.move(id("A"), to: .before(id("C"), joining: .below))
        #expect(changed)
        #expect(shape(below) == "B A-C")
        #expect(sets(below) == [2, 3, 3])

        var above = routine("A B C")
        let changedAgain = above.move(id("C"), to: .before(id("B"), joining: .above))
        #expect(changedAgain)
        #expect(shape(above) == "A-C B")
        #expect(sets(above) == [3, 3, 2])
        // Its own neighbor, without moving.
        var inPlace = routine("A B C")
        let changedThird = inPlace.move(id("B"), to: .before(id("C"), joining: .below))
        #expect(changedThird)
        #expect(shape(inPlace) == "A B-C")
        #expect(sets(inPlace) == [1, 3, 3])
    }

    @Test("A row moved into an existing superset still takes its rounds, fewer or more")
    func moveIntoSupersetTakesItsRounds() {
        var routine = routine("A-B C")
        let changed = routine.move(id("C"), to: .before(id("B"), joining: .above))
        #expect(changed)
        #expect(shape(routine) == "A-C-B")
        #expect(sets(routine) == [1, 1, 1])
    }
}
