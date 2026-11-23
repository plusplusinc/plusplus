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
    /// What the typed words offer (`FilterOffer`), on a line under the count line, or under
    /// the buttons while no filter is on.
    var offers: [FilterOffer] = []
    var onTake: (FilterOffer) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.sm) {
                    Button { onOpen(.muscle) } label: {
                        label("Muscle", choice: filter.muscleLabel)
                    }
                    .buttonStyle(.plain)
                    kindMenu
                    Button { onOpen(.equipment) } label: {
                        label("Equipment", choice: filter.equipmentLabel)
                    }
                    .buttonStyle(.plain)
                }
                // Inside the scroll's content, so the first button lines up with the rows and
                // the last scrolls clear of the edge.
                .padding(.horizontal, Spacing.md)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            if filter.isOn || !offers.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if filter.isOn {
                        FilterCount(Self.countText(count)) {
                            filter = ExerciseFilter()
                        }
                    }
                    if !offers.isEmpty {
                        offerLine
                    }
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

    /// The offer line: "Filter by muscle" for one offer, "Filter by" for several, a button
    /// each.
    private var offerLine: some View {
        let text = offers.count == 1
            ? "Filter by \(offers[0].choice.filterName.lowercased())"
            : "Filter by"
        return FilterOfferLine(text, offers: offers.map { offer in
            FilterOfferLine.Offer(
                title: offer.choice.name,
                filterName: offer.choice.filterName,
            ) { onTake(offer) }
        })
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
            label("Kind", choice: filter.kindLabel)
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
    }

    /// A filter's button: its choice, or its name while none is chosen, lit while on. VoiceOver
    /// reads its name, then the choice, and selected while on.
    private func label(_ name: String, choice: String?) -> some View {
        FilterLabel(choice ?? name, isOn: choice != nil)
            .accessibilityLabel(name)
            .accessibilityValue(choice ?? "")
            .accessibilityAddTraits(choice != nil ? .isSelected : [])
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
