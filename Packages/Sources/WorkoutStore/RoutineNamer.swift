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
    /// `routine` seeds the name's style, so each routine keeps its own as its exercises change,
    /// and different routines differ.
    public func name(for exercises: [Exercise], of routine: Routine.ID) async -> String? {
        let fallback = MuscleGroup.routineName(for: exercises.map(\.muscleGroup))
        guard let fallback else { return nil }
        guard isAvailable() else {
            Self.logger.notice("Named \(fallback, privacy: .public) from muscle groups: no model")
            return fallback
        }
        let unique = Self.unique(exercises)
        let style = NameStyle(of: routine)
        let prompt = Self.prompt(for: exercises, style: style)
        let asked = prompt.replacingOccurrences(of: "\n", with: " ")
        do {
            let answer = try await respond(prompt)
            guard let cleaned = Self.cleaned(answer) else {
                Self.logger.notice(
                    "Named \(fallback, privacy: .public), not \(answer, privacy: .public)",
                )
                return fallback
            }
            // A reply off the list, or one that isn't honest, takes the routine's own first name.
            let names = Self.candidates(for: unique, style: style)
            let picked = names.first { $0.lowercased() == cleaned.lowercased() } ?? names[0]
            let name = RoutineFocus(of: unique).checked(picked, against: unique)
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
    /// words it. Examples are tied to a focus or a tone: loose ones got copied whatever the
    /// routine was ("Pull and hinge").
    static let instructions = """
    You name workout routines for people who lift casually. You get the routine's exercises, \
    each with the muscle group it works, and a short list of names. Reply with exactly one name \
    from the list, the one that fits the exercises best, and nothing else.
    """

    /// Each exercise once, in order, with its group, then the names to pick from.
    static func prompt(for exercises: [Exercise], style: NameStyle) -> String {
        let unique = unique(exercises)
        let lines = unique.map { exercise in
            let kind = exercise.isStretch ? ", stretch" : ""
            return "- \(exercise.name) (\(exercise.muscleGroup.name.lowercased())\(kind))"
        }
        let names = candidates(for: unique, style: style)
        let pick = "Names: \(names.joined(separator: ", "))."
        return (["Exercises:"] + lines + [pick]).joined(separator: "\n")
    }

    static func candidates(for unique: [Exercise], style: NameStyle) -> [String] {
        let focus = RoutineFocus(of: unique)
        let stretches = unique.filter(\.isStretch).count
        let endsWithStretching = focus != .mobility && stretches * 3 >= unique.count
        return focus.candidates(style: style, endsWithStretching: endsWithStretching)
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
