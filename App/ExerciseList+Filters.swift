import DesignSystem
import SwiftUI
import WorkoutStore

/// The three filters' buttons over Add exercise's list (`ExerciseListView`), alike whatever
/// they open, on one line that scrolls sideways when their words don't fit (decided
/// 2026-11-22: the row never wraps); under them, while one is on, the count and Clear
/// (`FilterCount`). Muscle and Equipment open a sheet of chips through `onOpen`; Kind, which
/// takes one at a time, is the system's menu.
///
/// VoiceOver reads each button by its filter's name, "Muscle", with what is chosen as its
/// value, "Chest, Back", and as selected while on: the words drawn change to the choice, and
/// read alone they would lose which filter it is.
struct FilterBar: View {
    @Binding var filter: ExerciseFilter
    /// How many exercises show, for the count line.
    let count: Int
    let onOpen: (FilterSheet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.sm) {
                    Button {
                        onOpen(.muscle)
                    } label: {
                        FilterLabel(
                            filter.muscleLabel ?? "Muscle",
                            isOn: !filter.muscleGroups.isEmpty,
                        )
                    }
                    .buttonStyle(.plain)
                    .filterReading("Muscle", value: filter.muscleLabel)
                    kindMenu
                    Button {
                        onOpen(.equipment)
                    } label: {
                        FilterLabel(
                            filter.equipmentLabel ?? "Equipment",
                            isOn: !filter.equipment.isEmpty,
                        )
                    }
                    .buttonStyle(.plain)
                    .filterReading("Equipment", value: filter.equipmentLabel)
                }
                // Inside the scroll's content, so the first button lines up with the rows and
                // the last scrolls clear of the edge.
                .padding(.horizontal, Spacing.md)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            if filter.isOn {
                FilterCount(Self.countText(count)) {
                    filter = ExerciseFilter()
                }
                .padding(.horizontal, Spacing.md)
                // Clear is a button of its own, so the line stands off the filters' buttons by
                // more than the gap between two of them.
                .padding(.top, Spacing.sm + Spacing.xs)
                .padding(.bottom, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Kind takes one at a time, so it is the system's menu: a toggle per kind, the chosen one
    /// checked; picking it again clears it. It leaves Add exercise at the height it has.
    private var kindMenu: some View {
        Menu {
            ForEach(ExerciseKind.allCases, id: \.self) { kind in
                Toggle(kind.name, isOn: Binding {
                    filter.kind == kind
                } set: { _ in
                    filter.toggle(kind)
                })
            }
        } label: {
            FilterLabel(filter.kindLabel ?? "Kind", isOn: filter.kind != nil)
                .filterReading("Kind", value: filter.kindLabel)
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
    }

    /// The count line's words: "12 exercises", "1 exercise", "0 exercises".
    static func countText(_ count: Int) -> String {
        count == 1 ? "1 exercise" : "\(count) exercises"
    }
}

/// A filter that takes several choices, and so opens a sheet of chips.
enum FilterSheet: Identifiable {
    case muscle
    case equipment

    var id: Self {
        self
    }
}

extension View {
    /// A filter's button as VoiceOver reads it: its name, what is chosen, and selected while on.
    fileprivate func filterReading(_ name: String, value: String?) -> some View {
        accessibilityLabel(name)
            .accessibilityValue(value ?? "")
            .accessibilityAddTraits(value != nil ? .isSelected : [])
    }
}
