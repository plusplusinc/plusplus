import DesignSystem
import SwiftUI
import WorkoutStore

/// The screen the app launches into: a new, empty routine.
///
/// The name and the exercises live only in memory for now. The app deliberately creates no
/// `ModelContainer` yet: storage wiring lives in `WorkoutStoreContainer` and gets connected when
/// there is a data model worth connecting.
struct RoutineScreen: View {
    @State private var name = Self.defaultName
    @State private var exercises: [RoutineExercise] = []
    @State private var isPicking = false
    /// What was picked, held until the picker's sheet is down.
    @State private var picked: Exercise?
    /// Whether the title has scrolled up under the bar, where a small copy of it shows instead.
    @State private var isTitleUnderBar = false
    @ObserveHotReload private var hotReload

    private static let markWidth: CGFloat = 20
    /// A plus sits on the font's math axis, about a point below the middle of its line, so the
    /// mark is lifted to look centered in the round button.
    private static let markLift: CGFloat = 1

    private static let defaultName = String(localized: "New routine")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    EditableTitle(
                        text: $name,
                        defaultText: Self.defaultName,
                        accessibilityLabel: "Routine name",
                        accessibilityHint: "Renames the routine.",
                    )
                    .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                        withAnimation(.snappy) {
                            isTitleUnderBar = !isVisible
                        }
                    }
                    Rail(exercises) { item in
                        RowLabel(title: item.exercise.name, detail: item.exercise.equipmentLine)
                            .railRow()
                            .accessibilityIdentifier("routine.exercise")
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    withAnimation(.snappy) {
                                        exercises.removeAll { $0.id == item.id }
                                    }
                                }
                            }
                    } end: {
                        Button("Add exercise", systemImage: "plus") {
                            isPicking = true
                        }
                        .buttonStyle(.key)
                    }
                }
                .padding(.horizontal, Spacing.md)
                // Room under Add exercise, so at the end of a long list it clears Start.
                .padding(.bottom, Spacing.md)
                // When the keyboard rises, UIKit scrolls the focused field to sit at least 5pt
                // below the top of the visible area. Starting there keeps the title still.
                .padding(.top, Spacing.sm)
            }
            .primaryKeyBar(isPresented: !exercises.isEmpty) {
                // Starting a workout is a later slice.
                Button("Start", systemImage: "play.fill") { }
            }
            // One row open at a time, closed by a scroll or a tap anywhere else, Start included,
            // so the container holds Start's bar as well as the scroll view.
            .swipeActionsContainer()
            // A shape-style background stops at the keyboard's safe area, which left the
            // window's black behind the keyboard's rounded top corners.
            .background { Color.pp(.background).ignoresSafeArea() }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isPicking, onDismiss: addPicked) {
                ExercisePicker { exercise in
                    // A second tap while the sheet goes down keeps the first pick.
                    guard isPicking else { return }
                    picked = exercise
                    isPicking = false
                }
            }
            .toolbar {
                // As a large title does, the title shows small in the bar once it is under it.
                ToolbarItem(placement: .title) {
                    if isTitleUnderBar {
                        Text(name)
                            .font(.ppInlineTitle)
                            .foregroundStyle(.pp(.textPrimary))
                            .lineLimit(1)
                            // A heading, as the system's own bar title is.
                            .accessibilityAddTraits(.isHeader)
                            .transition(.opacity)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    // The drawer is a later slice.
                    Button { } label: {
                        Text(verbatim: "++")
                            .font(.ppMark)
                            .foregroundStyle(.pp(.accent))
                            // The glass sizes itself to its label. Reserving less width than
                            // the mark's advance draws the mark large in a compact button.
                            .fixedSize()
                            .frame(width: Self.markWidth)
                            .offset(y: -Self.markLift)
                    }
                    .accessibilityLabel("Menu")
                }
            }
        }
        .hotReloadable()
    }

    /// Adds what was picked once the sheet is down, where the row can be seen going in. Added
    /// behind the sheet, it was already in place when the sheet uncovered it.
    private func addPicked() {
        guard let picked else { return }
        // Quicker than .snappy's default, which read as mushy after the wait for the sheet.
        withAnimation(.snappy(duration: 0.25)) {
            exercises.append(RoutineExercise(exercise: picked))
        }
        self.picked = nil
    }
}

#Preview {
    RoutineScreen()
}
