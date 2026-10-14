import Foundation
import Synchronization
import Testing
@testable import WorkoutStore

@Suite("Routine namer")
struct RoutineNamerTests {
    private static func exercises(_ names: String...) throws -> [Exercise] {
        try names.map { name in try #require(Exercise.builtIn.first { $0.name == name }) }
    }

    private static func namer(answering answer: Result<String, any Error>) -> RoutineNamer {
        RoutineNamer(isAvailable: { true }, respond: { _ in try answer.get() })
    }

    private struct ModelError: Error { }

    /// A routine whose seed is 1: plain, its first variant.
    private static let routine = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0))
    /// A routine whose seed is 0: warm, its first variant.
    private static let warmRoutine = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    @Test("An unavailable model gives the muscle-group name without asking")
    func unavailable() async throws {
        let asks = Atomic(0)
        let namer = RoutineNamer(isAvailable: { false }, respond: { _ in
            asks.add(1, ordering: .relaxed)
            return "Leg day"
        })
        #expect(try await namer
            .name(for: Self.exercises("Goblet squat"), of: Self.routine) == "Legs")
        #expect(asks.load(ordering: .relaxed) == 0)
    }

    @Test("A model error gives the muscle-group name")
    func modelError() async throws {
        let namer = Self.namer(answering: .failure(ModelError()))
        let exercises = try Self.exercises("Pull-up", "Barbell bench press")
        #expect(await namer.name(for: exercises, of: Self.routine) == "Chest and back")
    }

    @Test("The model's answer is used, cleaned")
    func answerUsed() async throws {
        let namer = Self.namer(answering: .success(" \"leg day.\" \n"))
        #expect(try await namer
            .name(for: Self.exercises("Goblet squat"), of: Self.routine) == "Leg day")
    }

    @Test("An empty or overlong answer gives the muscle-group name", arguments: [
        "", " . ", String(repeating: "Squat ", count: 10),
    ])
    func unusableAnswer(answer: String) async throws {
        let namer = Self.namer(answering: .success(answer))
        #expect(try await namer
            .name(for: Self.exercises("Goblet squat"), of: Self.routine) == "Legs")
    }

    @Test("A cancelled ask gives nothing")
    func cancelled() async throws {
        let namer = Self.namer(answering: .failure(CancellationError()))
        #expect(try await namer.name(for: Self.exercises("Goblet squat"), of: Self.routine) == nil)
    }

    @Test("No exercises get no name, without asking")
    func noExercises() async {
        #expect(await Self.namer(answering: .success("Leg day"))
            .name(for: [], of: Self.routine) == nil)
    }

    @Test("The model's first line is the name")
    func firstLine() {
        #expect(RoutineNamer.cleaned("\nleg day\nA routine for legs.") == "Leg day")
    }

    @Test("A name that runs past one title line gives the muscle-group name")
    func overlongAnswer() async throws {
        let namer = Self.namer(answering: .success("Lower body strength builder"))
        #expect(try await namer
            .name(for: Self.exercises("Goblet squat"), of: Self.routine) == "Legs")
    }

    @Test("An answer off the list takes the routine's first name")
    func offListAnswer() async throws {
        let namer = Self.namer(answering: .success("Leg grind"))
        let squat = try Self.exercises("Goblet squat")
        #expect(await namer.name(for: squat, of: Self.routine) == "Leg day")
        #expect(await namer.name(for: squat, of: Self.warmRoutine) == "Strong legs")
    }

    @Test("The model picks from the list, in the routine's tone")
    func pickFromList() async throws {
        let squat = try Self.exercises("Goblet squat")
        let namer = Self.namer(answering: .success("lower body"))
        #expect(await namer.name(for: squat, of: Self.routine) == "Lower body")
    }

    @Test("The prompt lists each exercise once, with its group, then the names to pick from")
    func prompt() throws {
        let exercises = try Self.exercises("Pull-up", "Goblet squat", "Pull-up", "Pigeon stretch")
        #expect(RoutineNamer.prompt(for: exercises, style: NameStyle(of: Self.routine)) == """
        Exercises:
        - Pull-up (back)
        - Goblet squat (legs)
        - Pigeon stretch (legs, stretch)
        Names: Back and legs, Legs and back.
        """)
    }

    @Test("A routine keeps its style, and about a third of routines are warm")
    func styleBySeed() {
        let routine = UUID()
        let first = NameStyle(of: routine)
        let again = NameStyle(of: routine)
        #expect(first == again)
        let warm = (0 ..< 300).count { _ in NameStyle(of: UUID()).isWarm }
        #expect((60 ... 140).contains(warm))
        #expect(!NameStyle(of: Self.routine).isWarm)
        #expect(NameStyle(of: Self.warmRoutine).isWarm)
    }
}
