import DesignSystem
import SwiftUI
import WorkoutStore

/// The filters' buttons over the Workouts list, on one line that scrolls sideways when their
/// words don't fit, as Add exercise's (`FilterBar`); under them, while one is on, the count and
/// Clear. Muscle opens a sheet of chips through `onOpen`. Equipment and Length are still to
/// come.
///
/// Its own copy of `FilterBar`'s scrolling shell while that bar changes in another PR; the two
/// will share one shell once it lands.
struct WorkoutsFilterBar: View {
    @Binding var filter: WorkoutFilter
    /// How many workouts show, for the count line.
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.sm) {
                    Button(action: onOpen) {
                        FilterLabel(filter.muscleLabel ?? "Muscle", isOn: filter.muscleLabel != nil)
                            .accessibilityLabel("Muscle")
                            .accessibilityValue(filter.muscleLabel ?? "")
                            .accessibilityAddTraits(filter.muscleLabel != nil ? .isSelected : [])
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.md)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            if filter.isOn {
                FilterCount(WorkoutFilter.countText(count)) {
                    filter = WorkoutFilter()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm + Spacing.xs)
                .padding(.bottom, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Spacing.sm)
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
