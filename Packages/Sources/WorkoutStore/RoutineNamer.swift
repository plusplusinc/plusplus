import Foundation
import FoundationModels
import OSLog

/// Names a routine from its exercises: with Apple's on-device model when it is there, and from
/// the exercises' muscle groups when it isn't or gives nothing usable.
public struct RoutineNamer: Sendable {
    private let isAvailable: @Sendable () -> Bool
    private let respond: @Sendable (_ prompt: String) async throws -> String

    private static let logger = Logger(subsystem: "com.plusplusinc.plusplus", category: "naming")
    /// Longer than this, an answer is more sentence than name.
    static let longestName = 40

    /// The model's availability and a request, injected so tests never touch the model.
    init(
        isAvailable: @escaping @Sendable () -> Bool,
        respond: @escaping @Sendable (_ prompt: String) async throws -> String,
    ) {
        self.isAvailable = isAvailable
        self.respond = respond
    }

    /// The on-device model. An ineligible device, Apple Intelligence turned off, and a model
    /// still downloading all get the muscle-group name.
    public static let onDevice = Self(
        isAvailable: { SystemLanguageModel.default.availability == .available },
        respond: { prompt in
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedName.self,
                // The same exercises get the same name, rather than a new one at each ask.
                options: GenerationOptions(samplingMode: .greedy),
            )
            return response.content.name
        },
    )

    /// Muscle-group names only, never the model: the same name on every device.
    public static let muscleGroupsOnly = Self(isAvailable: { false }, respond: { _ in "" })

    /// A name for these exercises: the model's when it is available and answers with something
    /// usable, else the muscle-group name. Nil for no exercises, and when the ask was cancelled,
    /// so a superseded ask writes nothing.
    public func name(for exercises: [Exercise]) async -> String? {
        let fallback = MuscleGroup.routineName(for: exercises.map(\.muscleGroup))
        guard fallback != nil, isAvailable() else { return fallback }
        do {
            return try await Self.cleaned(respond(Self.prompt(for: exercises))) ?? fallback
        } catch is CancellationError {
            return nil
        } catch {
            Self.logger.info("Named from muscle groups; the model said: \(error)")
            return fallback
        }
    }

    /// Tried against the model: without "don't just repeat" and examples of names a person
    /// would give, it answered "Goblet squat legs".
    static let instructions = """
    You name workout routines. Given the exercises in a routine, each with the muscle group it \
    works, reply with a short, natural name a lifter would give it, the way a person titles a \
    workout in a notes app. Two to four words, sentence case, no punctuation, no emoji. Don't \
    just repeat an exercise name with its muscle group. Good names: Leg day, Squats and \
    pull-ups, Push day, Upper body, Legs and core, Pull and hinge.
    """

    /// Each exercise once, in order, with its group: "- Goblet squat (legs)".
    static func prompt(for exercises: [Exercise]) -> String {
        var seen = Set<Exercise.ID>()
        let lines = exercises
            .filter { seen.insert($0.id).inserted }
            .map { "- \($0.name) (\($0.muscleGroup.name.lowercased()))" }
        return (["Exercises:"] + lines).joined(separator: "\n")
    }

    /// The answer as a title: trimmed of space, quotes, and trailing punctuation, and starting
    /// with a capital, which the model sometimes leaves off. Nil when nothing is left or it runs
    /// long.
    static func cleaned(_ answer: String) -> String? {
        let trimmed = answer
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}"),
            )
        let name = String(trimmed.reversed().drop { $0.isPunctuation || $0.isWhitespace }
            .reversed())
        guard let first = name.first, name.count <= longestName else { return nil }
        return first.uppercased() + name.dropFirst()
    }
}

@Generable
private struct GeneratedName {
    @Guide(description: "The routine's name, two to four words")
    var name: String
}
