import DesignSystem
import SwiftUI
import WorkoutStore

/// Equipment, pushed from New exercise's Equipment row: every piece, any number checked, a tap
/// toggling one. Rows with checkmarks rather than `List(selection:)`, which needs edit mode on
/// iPhone. Each checkmark keeps its room and fades, so a row's text never moves.
struct EquipmentChecklist: View {
    @Binding var checked: Set<Equipment>

    var body: some View {
        Form {
            Section {
                ForEach(Equipment.allCases, id: \.self) { piece in
                    let isChecked = checked.contains(piece)
                    Button {
                        withAnimation(.snappy) {
                            if isChecked {
                                checked.remove(piece)
                            } else {
                                checked.insert(piece)
                            }
                        }
                    } label: {
                        HStack {
                            Text(piece.name)
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
                Text("Check all it needs. None means bodyweight.")
            }
            .listRowBackground(Color.pp(.surface))
        }
        .scrollContentBackground(.hidden)
        .background(Color.pp(.background))
        .navigationTitle("Equipment")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    @Previewable @State var checked: Set<Equipment> = [.rings]
    NavigationStack {
        EquipmentChecklist(checked: $checked)
    }
}
