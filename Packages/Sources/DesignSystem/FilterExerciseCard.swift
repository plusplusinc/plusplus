#if os(iOS)
import SwiftUI

/// A card of exercises to tap, on a new workout made from a list's filters: on its top line the
/// chosen filters' words in the light capsules an on filter button wears, with no chevron and no
/// tap, and at its trailing end a round × in Clear's look (`ClearFiltersLabel`) that closes the
/// card; under them each exercise as a raised capsule, a green + and its name, wrapping, a tap
/// adding it; last, "More ›" at the trailing end, which opens the full list.
///
/// The exercise capsules are a filter sheet's chips (`ChipButtonStyle`), laid out touching so
/// each one's touch reaches a thumb's height with no dead strip between them.
public struct FilterExerciseCard: View {
    public struct Item: Identifiable, Equatable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    let filterWords: [String]
    let items: [Item]
    let onAdd: (Item.ID) -> Void
    let onClose: () -> Void
    let onMore: () -> Void

    public init(
        filterWords: [String],
        items: [Item],
        onAdd: @escaping (Item.ID) -> Void,
        onClose: @escaping () -> Void,
        onMore: @escaping () -> Void,
    ) {
        self.filterWords = filterWords
        self.items = items
        self.onAdd = onAdd
        self.onClose = onClose
        self.onMore = onMore
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.sm) {
                FlowLayout(spacing: Spacing.sm) {
                    ForEach(filterWords, id: \.self) { words in
                        Text(words)
                            .fontWeight(.semibold)
                            .modifier(FilterCapsule(isOn: true))
                    }
                }
                .accessibilityElement(children: .combine)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) { ClearFiltersLabel() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
            }
            FlowLayout(spacing: 0) {
                ForEach(items) { item in
                    Button { onAdd(item.id) } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "plus")
                                .imageScale(.small)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.pp(.accent))
                                .accessibilityHidden(true)
                            Text(item.name)
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(ChipButtonStyle(isOn: false))
                    .accessibilityLabel("Add \(item.name)")
                }
            }
            .padding(.horizontal, -Spacing.xs)
            Button(action: onMore) {
                HStack(spacing: Spacing.xxs) {
                    Text("More")
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .font(.ppRowDetail.weight(.semibold))
                .foregroundStyle(Color.pp(.textSecondary))
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
            // Its touch reaches up into the last capsules' half gap, so the words sit close
            // under them, as in the drawing.
            .padding(.top, -Spacing.xs)
        }
        .padding(.leading, Spacing.md)
        .padding(.trailing, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.pp(.surface), in: .rect(cornerRadius: Radius.card))
    }
}

#Preview {
    FilterExerciseCard(
        filterWords: ["Legs", "Dumbbells"],
        items: [
            .init(id: "1", name: "Calf raise"),
            .init(id: "2", name: "Reverse lunge"),
            .init(id: "3", name: "Romanian deadlift"),
            .init(id: "4", name: "Walking lunge"),
        ],
        onAdd: { _ in },
        onClose: { },
        onMore: { },
    )
    .padding()
    .background(Color.pp(.background))
}
#endif
