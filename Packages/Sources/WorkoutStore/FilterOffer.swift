import Foundation

/// A choice one of Add exercise's three filters has: a muscle group, a kind, or an equipment
/// choice.
public enum FilterChoice: Hashable, Sendable {
    case muscle(MuscleGroup)
    case kind(ExerciseKind)
    case equipment(EquipmentChoice)

    /// Every choice, Muscle's, then Kind's, then Equipment's, each in its filter's order.
    static let allCases: [Self] = MuscleGroup.allCases.map(Self.muscle)
        + ExerciseKind.allCases.map(Self.kind)
        + EquipmentChoice.allCases.map(Self.equipment)

    /// The choice's name as its filter shows it: "Back", "Stretch", "Dumbbells".
    public var name: String {
        switch self {
        case let .muscle(group): group.name
        case let .kind(kind): kind.name
        case let .equipment(choice): choice.name
        }
    }

    /// The filter's name, as the offer line and VoiceOver read it: "Muscle", "Kind",
    /// "Equipment".
    public var filterName: String {
        switch self {
        case .muscle: "Muscle"
        case .kind: "Kind"
        case .equipment: "Equipment"
        }
    }

    /// The words that name the choice, folded: its name, and "bodyweight" for No equipment.
    fileprivate var foldedNames: [String] {
        let own = FilterOffer.folded(name)
        return self == .equipment(.none) ? [own, "bodyweight"] : [own]
    }
}

/// What Add exercise offers when a typed word names a filter's choice: the choice, and the
/// search text left once the offer is taken, without the word or words that named it.
///
/// A run of typed words names a choice when, folded as search folds a name (case, diacritics,
/// and everything but letters and digits ignored), it is the choice's whole name, singular or
/// plural: "back", "leg" or "legs", "dumbbell", "pull up bar", "medicine balls"; "bodyweight"
/// names No equipment. Part of a word names nothing ("bac"), and a choice already on is not
/// offered. Search itself stays names only: an offer is a nudge to the filter, never a match.
public struct FilterOffer: Hashable, Sendable {
    public let choice: FilterChoice
    /// The search text with the offer's words taken out, and the space beside them.
    public let remainingText: String

    /// The most words a choice's name runs to, typed apart: "pull up bar".
    private static let longestRun = 3

    /// The offers `text` makes against `filter`, in the order their words were typed, one per
    /// choice. Longer names win over the shorter ones inside them, and a word belongs to one
    /// offer at most.
    public static func offers(in text: String, given filter: ExerciseFilter) -> [Self] {
        let words = words(in: text)
        var offers: [Self] = []
        var index = 0
        while index < words.count {
            var taken = false
            for length in stride(from: min(longestRun, words.count - index), through: 1, by: -1) {
                let run = words[index ..< index + length]
                let folded = run.map(\.folded).joined()
                guard let choice = choice(named: folded) else { continue }
                taken = true
                if !filter.has(choice), !offers.contains(where: { $0.choice == choice }) {
                    let range = words[index].range.lowerBound
                        ..< words[index + length - 1].range.upperBound
                    offers.append(Self(choice: choice, remainingText: removing(range, from: text)))
                }
                index += length
                break
            }
            if !taken {
                index += 1
            }
        }
        return offers
    }

    private static func choice(named folded: String) -> FilterChoice? {
        FilterChoice.allCases.first { choice in
            choice.foldedNames.contains { name in
                folded == name || folded == name + "s" || folded == name + "es"
                    || (name.hasSuffix("s") && folded == String(name.dropLast()))
            }
        }
    }

    /// The text's words, split at spaces, each with its folded form; a word that folds to
    /// nothing, such as "-", is left out.
    private static func words(in text: String) -> [Word] {
        var words: [Word] = []
        var start: String.Index?
        for index in text.indices {
            if text[index].isWhitespace {
                if let begun = start {
                    words.append(Word(text, begun ..< index))
                    start = nil
                }
            } else if start == nil {
                start = index
            }
        }
        if let begun = start {
            words.append(Word(text, begun ..< text.endIndex))
        }
        return words.filter { !$0.folded.isEmpty }
    }

    /// `text` without `range` and one space beside it, trimmed.
    private static func removing(_ range: Range<String.Index>, from text: String) -> String {
        var upper = range.upperBound
        if upper < text.endIndex, text[upper].isWhitespace {
            upper = text.index(after: upper)
        }
        let left = text[..<range.lowerBound] + text[upper...]
        return left.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lowercased letters and digits alone, diacritics folded, as search compares names.
    static func folded(_ text: some StringProtocol) -> String {
        let plain = String(text).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil,
        ).lowercased()
        let kept = plain.unicodeScalars.filter(CharacterSet.alphanumerics.contains)
        return String(String.UnicodeScalarView(kept))
    }

    private struct Word {
        let range: Range<String.Index>
        let folded: String

        init(_ text: String, _ range: Range<String.Index>) {
            self.range = range
            folded = FilterOffer.folded(text[range])
        }
    }
}

extension ExerciseFilter {
    /// Whether `choice` is on.
    public func has(_ choice: FilterChoice) -> Bool {
        switch choice {
        case let .muscle(group): muscleGroups.contains(group)
        case let .kind(kind): self.kind == kind
        case let .equipment(piece): equipment.contains(piece)
        }
    }

    /// Turns `choice` on: Muscle and Equipment add it to what is chosen, Kind sets it.
    public mutating func turnOn(_ choice: FilterChoice) {
        switch choice {
        case let .muscle(group): muscleGroups.insert(group)
        case let .kind(kind): self.kind = kind
        case let .equipment(piece): equipment.insert(piece)
        }
    }
}
