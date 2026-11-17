import Foundation

/// Every exercise there is to pick: the built-ins and the ones someone created, A to Z together.
/// The one place a stored row's exercise id becomes an `Exercise`.
public struct ExerciseList: Equatable, Sendable {
    /// A to Z by name; a tie by id, so the order is stable if sync ever leaves two with one name.
    public let all: [Exercise]
    private let byID: [String: Exercise]

    public init(created: [CreatedExercise]) {
        self.init(unsorted: Exercise.builtIn + created.map(Exercise.init(created:)))
    }

    private init(unsorted: [Exercise]) {
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

    /// Whether an exercise is named `name`, by the search's folding.
    public func hasExercise(named name: String) -> Bool {
        all.hasExercise(named: name)
    }

    /// Whether a search for `query` offers to create an exercise of that name: something is
    /// typed, and no exercise has exactly that name.
    public func offersCreate(for query: String) -> Bool {
        !hasExercise(named: query) && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The list with `created` in it at its place, or in place of the one with its id.
    public func adding(_ created: CreatedExercise) -> Self {
        Self(unsorted: all.filter { $0.id != created.id } + [Exercise(created: created)])
    }
}
