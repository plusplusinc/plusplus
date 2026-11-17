import DesignSystem
import SwiftUI
import WorkoutStore

/// A list pushed from one of New exercise's rows, Muscle groups or Equipment: every case, any
/// number checked, a tap toggling one. Rows with checkmarks rather than `List(selection:)`,
/// which needs edit mode on iPhone. Each checkmark keeps its room and fades, so a row's text
/// never moves.
struct Checklist<Item: NamedCase>: View {
    let title: String
    let footer: String
    @Binding var checked: Set<Item>

    var body: some View {
        Form {
            Section {
                ForEach(Item.allCases, id: \.self) { item in
                    let isChecked = checked.contains(item)
                    Button {
                        withAnimation(.snappy) {
                            if isChecked {
                                checked.remove(item)
                            } else {
                                checked.insert(item)
                            }
                        }
                    } label: {
                        HStack {
                            Text(item.name)
                                .foregroundStyle(Color.pp(.textPrimary))
                            Spacer()
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.pp(.textPrimary))
                                .opacity(isChecked ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityAddTraits(isChecked ? .isSelected : [])
                }
            } footer: {
                Text(footer)
            }
            .listRowBackground(Color.pp(.surface))
        }
        .scrollContentBackground(.hidden)
        .background(Color.pp(.background))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    @Previewable @State var checked: Set<MuscleGroup> = [.back, .shoulders]
    NavigationStack {
        Checklist(title: "Muscle groups", footer: "Check all it works.", checked: $checked)
    }
}
