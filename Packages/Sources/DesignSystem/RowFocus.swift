/// A row grown into the current exercise of a workout.
public struct RowFocus: Equatable {
    /// Which set it is on: "Set 1 of 3".
    public var progress: String
    /// The side the set works, "Left", for an exercise done one side at a time.
    public var side: String?
    /// The exercise's own equipment, as capsules; none for an exercise that needs none.
    public var equipment: [String]
    public var figures: [Figure]
    /// The figures in words, for VoiceOver.
    public var spokenFigures: String
    /// What follows the set, at the caption line's end: "then rest 1:00", "last set"; nil for
    /// nothing.
    public var after: String?
    /// Whether the side shows; unseen, it keeps its room, so the caption line keeps the height
    /// a side gives it, as through a rest after a set's two sides.
    public var showsSide = true
    /// Whether `after` shows; unseen, it keeps its room, as on a set's first side, where the
    /// other side follows, so the line holds the height the second side's rest gives it.
    public var showsAfter = true
    public init(
        progress: String,
        side: String? = nil,
        equipment: [String] = [],
        figures: [Figure],
        spokenFigures: String,
        after: String? = nil,
    ) {
        self.progress = progress
        self.after = after
        self.side = side
        self.equipment = equipment
        self.figures = figures
        self.spokenFigures = spokenFigures
    }

    /// A number shown large, with what it counts: "10" "reps".
    public struct Figure: Hashable {
        public var number: String
        public var unit: String

        public init(number: String, unit: String) {
            self.number = number
            self.unit = unit
        }
    }
}
