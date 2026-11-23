import DesignSystem
import SwiftUI
import WorkoutStore

/// The filters' buttons over the Workouts list, in the row Add exercise's bar shares
/// (`FilterButtonRow`): one line that scrolls sideways when their words don't fit, led by Clear
/// while a filter is on. No count shows; VoiceOver hears it with each change
/// (`WorkoutsScreen.announcedFilter`). Each button opens its sheet through `onOpen`: Muscle and
/// Equipment of chips, Length of presets and wheels.
struct WorkoutsFilterBar: View {
    @Binding var filter: WorkoutFilter
    let onOpen: (WorkoutsSheet) -> Void

    var body: some View {
        FilterButtonRow(isOn: filter.isOn, shows: filter) {
            filter = WorkoutFilter()
        } buttons: {
            button("Muscle", choice: filter.muscleLabel, opens: .muscle)
            button("Equipment", choice: filter.equipmentLabel, opens: .equipment)
            button(
                "Length",
                choice: filter.lengthLabel,
                spoken: filter.lengthSpoken,
                opens: .length,
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Spacing.sm)
    }

    /// A filter's button: its choice, or its name while none is chosen, lit while on. VoiceOver
    /// reads its name, then the choice (in `spoken` words where given), and selected while on.
    private func button(
        _ name: String,
        choice: String?,
        spoken: String? = nil,
        opens sheet: WorkoutsSheet,
    ) -> some View {
        Button { onOpen(sheet) } label: {
            FilterLabel(choice ?? name, isOn: choice != nil)
                .accessibilityLabel(name)
                .accessibilityValue(spoken ?? choice ?? "")
                .accessibilityAddTraits(choice != nil ? .isSelected : [])
        }
        .buttonStyle(.plain)
    }
}

/// The sheet a Workouts filter button opens.
enum WorkoutsSheet: Identifiable {
    case muscle
    case equipment
    case length

    var id: Self {
        self
    }
}

/// One entry of the Workouts list under its bar: a workout's row, or an "Also needs" heading.
enum WorkoutsItem: Identifiable {
    case workout(Workout)
    case needs(Equipment)

    enum Key: Hashable {
        case workout(Workout.ID)
        case needs(Equipment)
    }

    var id: Key {
        switch self {
        case let .workout(workout): .workout(workout.id)
        case let .needs(piece): .needs(piece)
        }
    }

    var workout: Workout? {
        if case let .workout(workout) = self {
            workout
        } else {
            nil
        }
    }

    /// The matches, then each section under its heading.
    static func items(_ filtered: FilteredWorkouts) -> [Self] {
        filtered.matches.map(workout) + filtered.alsoNeeds.flatMap { section in
            [.needs(section.piece)] + section.items.map(Self.workout)
        }
    }
}

extension WorkoutRow.Shape {
    /// A workout's row shape from its summary, its bar `fill` of the column.
    init(_ summary: WorkoutSummary, fill: Double) {
        let (named, rest) = summary.segments(limit: 3)
        self.init(
            length: "\(summary.minutes) min",
            kind: summary.kind.workoutWord,
            equipment: summary.equipment.map(\.name),
            segments: named.map { ($0.group.name, $0.share) },
            more: rest.map(\.share),
            fill: fill,
        )
    }
}

extension WorkoutSummary {
    /// What VoiceOver reads after a row's name: "35 min, Strength, Legs, Core, Dumbbells".
    var spoken: String {
        let kit = equipment.isEmpty ? ["No equipment"] : equipment.map(\.name)
        return (["\(minutes) min", kind.workoutWord] + muscles.map(\.group.name) + kit)
            .joined(separator: ", ")
    }
}
