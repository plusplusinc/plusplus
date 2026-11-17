import Foundation

/// The exercises under one letter heading of an A to Z list, and that letter's place in the
/// list's index.
public struct ExerciseSection: Identifiable, Equatable, Sendable {
    /// The heading: a capital letter, or "#" for names that start with no letter.
    public let letter: String
    public let exercises: [Exercise]

    public var id: String {
        letter
    }

    /// The heading for names that start with no letter, such as a digit or an emoji.
    public static let otherLetter = "#"
}

extension [Exercise] {
    /// These exercises, in order, under the letter each name starts with, ignoring case and
    /// diacritics, so Élan sits under E. Only letters some name starts with get a section, so
    /// an index of them never jumps to nothing. Names that start with no letter go under "#",
    /// last, where the index ends.
    public func lettered() -> [ExerciseSection] {
        var letters: [String] = []
        var byLetter: [String: [Exercise]] = [:]
        for exercise in self {
            let letter = Self.letter(of: exercise.name)
            if byLetter[letter] == nil {
                letters.append(letter)
            }
            byLetter[letter, default: []].append(exercise)
        }
        let ordered = letters.filter { $0 != ExerciseSection.otherLetter }
            + letters.filter { $0 == ExerciseSection.otherLetter }
        return ordered.map { ExerciseSection(letter: $0, exercises: byLetter[$0] ?? []) }
    }

    private static func letter(of name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first,
              first.isLetter
        else { return ExerciseSection.otherLetter }
        // One character: ß capitalizes to SS.
        return String(String(first)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .uppercased()
            .prefix(1))
    }
}
