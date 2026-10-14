import Foundation
import FoundationModels
import OSLog

/// Names a routine from its exercises: with Apple's on-device model when it is there, and from
/// the exercises' muscle groups when it isn't or gives nothing usable.
public struct RoutineNamer: Sendable {
    private let isAvailable: @Sendable () -> Bool
    private let respond: @Sendable (_ prompt: String) async throws -> String

    private static let logger = Logger(subsystem: "com.plusplusinc.plusplus", category: "naming")
    /// Longer than this, a name doesn't fit one line of the title.
    static let longestName = 20

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
            // The default guardrails refuse a routine with Dead bug or Dead hang in it as
            // sensitive. Permissive ones apply only to text answers, so the answer is text, and
            // `cleaned(_:)` and the length cap catch anything that isn't a name.
            let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                // The same exercises get the same name, rather than a new one at each ask.
                options: GenerationOptions(samplingMode: .greedy),
            )
            return response.content
        },
    )

    /// Muscle-group names only, never the model: the same name on every device.
    public static let muscleGroupsOnly = Self(isAvailable: { false }, respond: { _ in "" })

    /// A name for these exercises: the model's when it is available and answers with something
    /// usable, else the muscle-group name. Nil for no exercises, and when the ask was cancelled,
    /// so a superseded ask writes nothing.
    public func name(for exercises: [Exercise]) async -> String? {
        let fallback = MuscleGroup.routineName(for: exercises.map(\.muscleGroup))
        guard let fallback else { return nil }
        guard isAvailable() else {
            Self.logger.notice("Named \(fallback, privacy: .public) from muscle groups: no model")
            return fallback
        }
        let unique = Self.unique(exercises)
        let prompt = Self.prompt(for: exercises)
        let asked = prompt.replacingOccurrences(of: "\n", with: " ")
        do {
            let answer = try await respond(prompt)
            guard let cleaned = Self.cleaned(answer) else {
                Self.logger.notice(
                    "Named \(fallback, privacy: .public), not \(answer, privacy: .public)",
                )
                return fallback
            }
            let name = RoutineFocus(of: unique).checked(cleaned, against: unique)
            Self.logger.notice("Named \(name, privacy: .public) (\(cleaned, privacy: .public))")
            Self.logger.notice("For \(asked, privacy: .public)")
            return name
        } catch is CancellationError {
            Self.logger.notice("Naming cancelled by a newer ask")
            return nil
        } catch {
            let reason = String(describing: error)
            Self.logger.notice("Named \(fallback, privacy: .public): \(reason, privacy: .public)")
            return fallback
        }
    }

    /// Tried against the model with the naming eval in the slice's working files. The focus is
    /// worked out here, so the name is honest about what the routine works, and the model only
    /// words it. No example names: with them it copied the last one ("Pull and hinge") for
    /// whatever it was given.
    static let instructions = """
    You name workout routines for people who lift casually. You get the routine's exercises, \
    each with the muscle group it works, and the routine's focus. Reply with a short name for \
    the routine, the way a person titles a workout in a notes app.
    Rules:
    - One to four words, at most 20 characters, sentence case, no punctuation, no emoji.
    - Name the focus. Mention only muscle groups that are in the routine.
    - Use plain gym words. No technical terms.
    - Never use an exercise's name, and never answer with only a muscle group.
    - Sometimes, not always, start with one light positive word such as strong, steady, or \
    solid. Never hype.
    Names that fit each focus:
    - legs: Leg day, Strong legs
    - back: Pull day, Back strength
    - chest: Push day, Chest strength
    - shoulders: Shoulder day, Strong shoulders
    - arms: Arm day, Strong arms
    - core: Core work, Steady core
    - upper body: Upper body, Upper body strength
    - upper body and core: Upper body and core
    - legs and core: Legs and core
    - full body: Full body, Full body strength
    - mobility and stretching: Stretch and reset, Mobility
    - two groups, like chest and back: name both, Chest and back
    """

    /// Each exercise once, in order, with its group, then the focus: "- Goblet squat (legs)",
    /// and "Focus: legs".
    static func prompt(for exercises: [Exercise]) -> String {
        let unique = unique(exercises)
        let lines = unique.map { exercise in
            let kind = exercise.isStretch ? ", stretch" : ""
            return "- \(exercise.name) (\(exercise.muscleGroup.name.lowercased())\(kind))"
        }
        let focus = RoutineFocus(of: unique).phrase
        return (["Exercises:"] + lines + ["Focus: \(focus)"]).joined(separator: "\n")
    }

    private static func unique(_ exercises: [Exercise]) -> [Exercise] {
        var seen = Set<Exercise.ID>()
        return exercises.filter { seen.insert($0.id).inserted }
    }

    /// The answer as a title: its first line, trimmed of space, quotes, and trailing
    /// punctuation, and starting with a capital, which the model sometimes leaves off. Nil when
    /// nothing is left or it runs long.
    static func cleaned(_ answer: String) -> String? {
        let firstLine = answer.split(whereSeparator: \.isNewline)
            .first { !$0.allSatisfy(\.isWhitespace) } ?? ""
        let trimmed = firstLine
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
