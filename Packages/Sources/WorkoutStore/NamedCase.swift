/// A kind an exercise has any number of, as a created exercise checks them off a list: its
/// muscle groups and its equipment. Cases are declared in display order.
public protocol NamedCase: CaseIterable, Hashable, Sendable, RawRepresentable<String>
    where AllCases == [Self]
{
    var name: String { get }
}

extension Set where Element: NamedCase {
    /// The checked ones as a line of text in display order, "Dumbbells, bench" or "Back,
    /// shoulders", or nil for none.
    public var line: String? {
        let names = Element.allCases.filter(contains).map(\.name)
        guard let first = names.first else { return nil }
        return ([first] + names.dropFirst().map { $0.lowercased() }).joined(separator: ", ")
    }

    /// Raw values joined by commas in display order: a string, not an array, which SwiftData
    /// would store, and CloudKit sync, as opaque bytes.
    var stored: String {
        Element.allCases.filter(contains).map(\.rawValue).joined(separator: ",")
    }

    /// The ones `stored` names, leaving out a value this build doesn't know.
    init(stored: String) {
        self.init(stored.split(separator: ",").compactMap { Element(rawValue: String($0)) })
    }
}
