import DesignSystem
import SwiftUI
import WorkoutStore

/// A list pushed from one of New exercise's rows, Muscle groups or Equipment: every case, any
/// number checked, a tap toggling one. Rows with their own marks rather than
/// `List(selection:)`, which needs edit mode on iPhone. Every row ends in a circle: empty and
/// gray while unchecked, so an untouched list already says any number can be checked, and
/// filled green with a cut-out check once checked, as the Exercises icon's front circle is.
/// The two crossfade in the same spot on the tap's quick curve, so a row's text never moves. Each
/// tap plays the system's selection tick. No note under the list: the
/// screen's title says what it is.
struct Checklist<Item: NamedCase>: View {
    let title: String
    @Binding var checked: Set<Item>

    var body: some View {
        Form {
            Section {
                ForEach(Item.allCases, id: \.self) { item in
                    let isChecked = checked.contains(item)
                    Button {
                        withAnimation(.tapChange) {
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
                            ZStack {
                                Image(systemName: "circle")
                                    .foregroundStyle(Color.pp(.textSecondary))
                                    .opacity(isChecked ? 0 : 1)
                                // The check is cut out of the fill, so the row shows through.
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.pp(.accent))
                                    .opacity(isChecked ? 1 : 0)
                            }
                            .font(.title3)
                            .accessibilityHidden(true)
                        }
                    }
                    .accessibilityAddTraits(isChecked ? .isSelected : [])
                }
            }
            .listRowBackground(Color.pp(.surface))
        }
        .sensoryFeedback(.selection, trigger: checked)
        .scrollContentBackground(.hidden)
        .background(Color.pp(.background))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    @Previewable @State var checked: Set<MuscleGroup> = [.back, .shoulders]
    NavigationStack {
        Checklist(title: "Muscle groups", checked: $checked)
    }
}
