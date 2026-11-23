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

    /// Every folded form that names a choice, singular and plural, to its choice; where two
    /// choices share a form, the first in `FilterChoice.allCases` keeps it.
    private static let choicesByName: [String: FilterChoice] = {
        var named: [String: FilterChoice] = [:]
        for choice in FilterChoice.allCases {
            for name in choice.foldedNames {
                let forms = [name, name + "s", name + "es"]
                    + (name.hasSuffix("s") ? [String(name.dropLast())] : [])
                for form in forms where named[form] == nil {
                    named[form] = choice
                }
            }
        }
        return named
    }()

    /// The most words a choice's name runs to, typed apart: "pull up bar".
    private static let longestRun = FilterChoice.allCases.map { choice in
        choice.name.split { !$0.isLetter && !$0.isNumber }.count
    }.max() ?? 1

    /// The offers `text` makes against `filter`, in the order their words were typed, one per
    /// choice. Longer names win over the shorter ones inside them, and a word belongs to one
    /// offer at most.
    /// Taking one takes out every run of words that names its choice: "back back" leaves nothing.
    public static func offers(in text: String, given filter: ExerciseFilter) -> [Self] {
        let words = text.split(whereSeparator: \.isWhitespace).map(Word.init)
            .filter { !$0.folded.isEmpty }
        var runs: [(choice: FilterChoice, range: Range<String.Index>)] = []
        var index = 0
        while index < words.count {
            guard let (choice, length) = longestChoice(at: index, in: words) else {
                index += 1
                continue
            }
            if !filter.has(choice) {
                let range = words[index].range.lowerBound
                    ..< words[index + length - 1].range.upperBound
                runs.append((choice, range))
            }
            index += length
        }
        var offers: [Self] = []
        for run in runs where !offers.contains(where: { $0.choice == run.choice }) {
            let ranges = runs.filter { $0.choice == run.choice }.map(\.range)
            offers.append(Self(choice: run.choice, remainingText: removing(ranges, from: text)))
        }
        return offers
    }

    /// The choice the longest run of words from `index` names, and how many words it took.
    private static func longestChoice(at index: Int, in words: [Word]) -> (FilterChoice, Int)? {
        for length in stride(from: min(longestRun, words.count - index), through: 1, by: -1) {
            let folded = words[index ..< index + length].map(\.folded).joined()
            if let choice = choicesByName[folded] {
                return (choice, length)
            }
        }
        return nil
    }

    /// `text` without `ranges`, each with one space beside it, the one after where there is
    /// one, so the rest of the text, its spaces at either end included, stays as typed.
    private static func removing(_ ranges: [Range<String.Index>], from text: String) -> String {
        // Taken out last to first, character offsets before each cut still hold.
        let cuts = ranges.map {
            (
                text.distance(from: text.startIndex, to: $0.lowerBound),
                text.distance(from: text.startIndex, to: $0.upperBound),
            )
        }
        var left = text
        for (start, end) in cuts.sorted(by: { $0.0 > $1.0 }) {
            var lower = left.index(left.startIndex, offsetBy: start)
            var upper = left.index(left.startIndex, offsetBy: end)
            if upper < left.endIndex, left[upper].isWhitespace {
                upper = left.index(after: upper)
            } else if lower > left.startIndex, left[left.index(before: lower)].isWhitespace {
                lower = left.index(before: lower)
            }
            left.removeSubrange(lower ..< upper)
        }
        return left.allSatisfy(\.isWhitespace) ? "" : left
    }

    /// Letters and digits alone, as search compares names (`[Exercise].lettersAndDigits`), with
    /// case and diacritics folded away, as search's comparison ignores them.
    static func folded(_ text: some StringProtocol) -> String {
        [Exercise].lettersAndDigits(String(text))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private struct Word {
        let range: Range<String.Index>
        let folded: String

        init(_ word: Substring) {
            range = word.startIndex ..< word.endIndex
            folded = FilterOffer.folded(word)
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
