import Foundation

/// What an exercise is: its name and the equipment it uses. A routine holds instances of it,
/// as `RoutineExercise`.
public struct Exercise: Identifiable, Equatable, Sendable {
    /// A stable slug, so a routine can refer to a built-in exercise by something its display
    /// name can change without breaking.
    public let id: String
    public let name: String
    /// Empty for bodyweight.
    public let equipment: Set<Equipment>

    public init(id: String, name: String, equipment: Set<Equipment> = []) {
        self.id = id
        self.name = name
        self.equipment = equipment
    }

    /// The equipment as a line of text in display order, "Dumbbells, bench", or nil for
    /// bodyweight, which shows no line at all.
    public var equipmentLine: String? {
        let names = Equipment.allCases.filter(equipment.contains).map(\.name)
        guard let first = names.first else { return nil }
        return ([first] + names.dropFirst().map { $0.lowercased() }).joined(separator: ", ")
    }
}

extension [Exercise] {
    /// The exercises whose names contain the query, in order, ignoring case, diacritics, and
    /// everything but letters and digits: "pullup", "pull up", and "PULL-UP" all find Pull-up,
    /// and an apostrophe of either kind, or none, finds Farmer’s carry. A query with nothing
    /// left to match matches everything.
    public func matching(_ query: String) -> [Exercise] {
        let query = Self.lettersAndDigits(query)
        guard !query.isEmpty else { return self }
        return filter { Self.lettersAndDigits($0.name).localizedStandardContains(query) }
    }

    private static func lettersAndDigits(_ text: String) -> String {
        let kept = text.unicodeScalars.filter(CharacterSet.alphanumerics.contains)
        return String(String.UnicodeScalarView(kept))
    }
}
