/// What changes a row's value as a step does, a ruler's tick, or a switch: its number, or, for
/// a row without one, its text. A row's text alone also changes as the row opens and shuts
/// ("30s", "0m 30s"), which is no step: with Reduce Motion a value laid out at once on that
/// change jumped ahead of its moving row, and the step's tick played on a plain open.
enum ValueChange: Hashable {
    case number(Double)
    case text(String)

    init(number: Double?, value: String) {
        self = number.map(Self.number) ?? .text(value)
    }
}
