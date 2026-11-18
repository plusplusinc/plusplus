import Foundation

/// Every exercise there is to pick: the built-ins and the ones someone created, A to Z together.
/// The one place a stored row's exercise id becomes an `Exercise`.
public struct ExerciseList: Equatable, Sendable {
    /// A to Z by name; a tie by id, so the order is stable if sync ever leaves two with one name.
    public let all: [Exercise]
    private let byID: [String: Exercise]
    /// The created ones as someone set them, by id, for their form to open with.
    private let createdByID: [String: CreatedExercise]
    /// The built-ins someone customized, by slug, none of them empty.
    private let customizationsByID: [String: Customization]

    /// With a customization for a slug no built-in has, or an empty one, read as none.
    public init(created: [CreatedExercise], customizations: [Customization] = []) {
        // Ids are unique in the app's own writes; keyed leniently against a store that isn't.
        self.init(
            createdByID: Dictionary(
                created.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first },
            ),
            customizationsByID: Dictionary(
                customizations.filter { !$0.isEmpty && Self.catalog[$0.exerciseID] != nil }
                    .map { ($0.exerciseID, $0) },
                uniquingKeysWith: { first, _ in first },
            ),
        )
    }

    private init(
        createdByID: [String: CreatedExercise],
        customizationsByID: [String: Customization],
    ) {
        self.createdByID = createdByID
        self.customizationsByID = customizationsByID
        let builtIns = Exercise.builtIn.map { shipped in
            customizationsByID[shipped.id]
                .map { Exercise(builtIn: shipped, customized: $0) } ?? shipped
        }
        let unsorted = builtIns + createdByID.values.map(Exercise.init(created:))
        all = unsorted.sorted { one, other in
            switch one.name.localizedStandardCompare(other.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: one.id < other.id
            }
        }
        // Ids are unique in the app's own writes; keyed leniently against a store that isn't.
        byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The built-ins alone, as before anything is created or read.
    public static let builtIn = Self(created: [])

    public func exercise(id: String) -> Exercise? {
        byID[id]
    }

    /// The exercises whose names contain the query, A to Z, by the search's folding.
    public func matching(_ query: String) -> [Exercise] {
        all.matching(query)
    }

    /// Whether an exercise, other than `id` if given, is named `name`, by the search's folding:
    /// a rename may keep its own name, or change only its case. A renamed built-in's shipped name
    /// stays taken, so clearing its customizations can never leave two exercises with one name.
    public func hasExercise(named name: String, besides id: String? = nil) -> Bool {
        let renamed = customizationsByID.values.filter { $0.changed.contains(.name) }
            .compactMap { Self.catalog[$0.exerciseID] }
        let taken = all + renamed
        let others = id.map { id in taken.filter { $0.id != id } } ?? taken
        return others.hasExercise(named: name)
    }

    /// Whether a search for `query` offers to create an exercise of that name: something is
    /// typed, and no exercise has exactly that name.
    public func offersCreate(for query: String) -> Bool {
        !hasExercise(named: query) && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The name Create starts from for a search of `query`: as typed, trimmed, its first letter
    /// a capital, as the built-ins' names are ("curl" → "Curl"). The search itself doesn't
    /// capitalize, as the system's doesn't.
    public static func createdName(from query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }

    /// The settings of the created exercise `id`, or nil for a built-in.
    public func created(id: String) -> CreatedExercise? {
        createdByID[id]
    }

    /// The built-in `id` as it shipped, whatever its customization; nil for a created one.
    public func original(id: String) -> Exercise? {
        Self.catalog[id]
    }

    /// The changes someone made to the built-in `id`, or nil while it is as shipped.
    public func customization(id: String) -> Customization? {
        customizationsByID[id]
    }

    /// The list with `created` in it at its place, or in place of the one with its id.
    public func adding(_ created: CreatedExercise) -> Self {
        var createdByID = createdByID
        createdByID[created.id] = created
        return Self(createdByID: createdByID, customizationsByID: customizationsByID)
    }

    /// The list without the created exercise `id`.
    public func removing(_ id: String) -> Self {
        var createdByID = createdByID
        createdByID[id] = nil
        return Self(createdByID: createdByID, customizationsByID: customizationsByID)
    }

    /// The list with the exercise `id` set to `settings`: a created one's own, a built-in's as
    /// its customization, none at all once they are as it shipped. Unchanged for an unknown id.
    public func customizing(_ id: String, to settings: ExerciseSettings) -> Self {
        if var created = created(id: id) {
            created.settings = settings
            return adding(created)
        }
        guard let shipped = original(id: id) else { return self }
        var customizationsByID = customizationsByID
        let customization = Customization(of: shipped, to: settings)
        customizationsByID[id] = customization.isEmpty ? nil : customization
        return Self(createdByID: createdByID, customizationsByID: customizationsByID)
    }

    /// The list with the built-in `id` exactly as it shipped.
    public func clearingCustomizations(_ id: String) -> Self {
        var customizationsByID = customizationsByID
        customizationsByID[id] = nil
        return Self(createdByID: createdByID, customizationsByID: customizationsByID)
    }

    /// The catalog by slug, never customized.
    private static let catalog = Dictionary(
        Exercise.builtIn.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first },
    )
}
