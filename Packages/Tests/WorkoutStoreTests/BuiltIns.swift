import Testing
@testable import WorkoutStore

extension Exercise {
    /// The built-in exercise named `name`; a failed requirement when there is none.
    static func builtIn(named name: String) throws -> Exercise {
        try #require(builtIn.first { $0.name == name }, "No built-in named \(name)")
    }

    /// The built-in exercises named, in order.
    static func builtIn(named names: [String]) throws -> [Exercise] {
        try names.map(builtIn(named:))
    }
}
