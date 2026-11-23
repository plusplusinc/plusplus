import DesignSystem
import SwiftUI
import WorkoutStore

/// The three filters' buttons over Add exercise's list (`ExerciseListView`), alike whatever
/// they open, on one line that scrolls sideways when their words don't fit (decided
/// 2026-11-22: the row never wraps). While a filter is on, Clear (`ClearFiltersLabel`) leads
/// the row, before Muscle, and scrolls with it. Each change of the filter is one `.tapChange`
/// transaction (`ExerciseListView.announcedFilter`): Clear fades as the buttons slide over,
/// each button's fill and words crossfade and its width eases. No count shows: VoiceOver hears
/// it with each change (`ExerciseListView.announcedFilter`). Under the buttons, while typed
/// words name a filter's choice, the offer line (`FilterOfferLine`), whose button turns that
/// choice on and takes its words out of the search; with no offer, no line. Muscle and
/// Equipment open a sheet of chips through `onOpen`; Kind, which takes one at a time, is the
/// system's menu.
///
/// VoiceOver reads each button by its filter's name, "Muscle", with what is chosen as its
/// value, "Chest, Back", and as selected while on: the words drawn change to the choice, and
/// read alone they would lose which filter it is.
struct FilterBar: View {
    @Binding var filter: ExerciseFilter
    let onOpen: (FilterSheet) -> Void
    /// What the typed words offer (`FilterOffer`), on a line right under the buttons.
    let offers: [FilterOffer]
    let onTake: (FilterOffer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.sm) {
                    if filter.isOn {
                        Button { filter = ExerciseFilter() } label: { ClearFiltersLabel() }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                    }
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
            if !offers.isEmpty {
                offerLine
                    .padding(.horizontal, Spacing.md)
                    // Its buttons are small buttons of their own, so the line stands off the
                    // filters' buttons by more than the gap between two of them.
                    .padding(.top, Spacing.sm + Spacing.xs)
                    .padding(.bottom, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The offer line: "Filter by" and a button per offer.
    private var offerLine: FilterOfferLine {
        FilterOfferLine(offers: offers.map { offer in
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

    /// The count VoiceOver hears with each change: "12 exercises", "1 exercise", "0 exercises".
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
