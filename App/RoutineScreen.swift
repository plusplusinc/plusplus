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
    @State private var scrollPosition = ScrollPosition()
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
                                    withAnimation(.railChange) {
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
            .scrollPosition($scrollPosition)
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
            .sheet(isPresented: $isPicking) {
                ExercisePicker { exercise in
                    // A second tap while the sheet goes down keeps the first pick.
                    guard isPicking else { return }
                    isPicking = false
                    add(exercise)
                }
            }
            .toolbar {
                // As a large title does, the title shows small in the bar once it is under it.
                ToolbarItem(placement: .title) {
                    if isTitleUnderBar {
                        // As a tap on the status bar does, a tap brings the title back. At the
                        // accessibility text sizes the bar keeps touches on its title for the large
                        // content viewer, so there the button is reached through VoiceOver only.
                        Button {
                            withAnimation(.snappy) {
                                scrollPosition.scrollTo(edge: .top)
                            }
                        } label: {
                            Text(name)
                                .font(.ppInlineTitle)
                                .foregroundStyle(.pp(.textPrimary))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        // A heading, as the system's own bar title is.
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityHint("Scrolls to the top.")
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

    /// Adds a picked exercise as its sheet starts down, so the row goes in alongside it. Then,
    /// when the row has pushed Add exercise below the visible area, scrolls to the end so the new
    /// row and the key both show; when everything fits, the end is already in view and nothing
    /// moves. The scroll waits for the row: asked for while the row went in, it stopped at the
    /// end the list had before.
    private func add(_ exercise: Exercise) {
        // Started a beat into the sheet's slide, as it uncovers the screen from the top, so a row
        // low on the screen is not still covered for the whole motion.
        withAnimation(
            .railChange.delay(0.1),
            completionCriteria: .logicallyComplete,
        ) {
            exercises.append(RoutineExercise(exercise: exercise))
        } completion: {
            withAnimation(.railChange) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
    }
}

#Preview {
    RoutineScreen()
}
