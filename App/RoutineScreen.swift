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
    /// The row just added, holding its place until it can be seen going in.
    @State private var arriving: RoutineExercise.ID?
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
                    Rail(exercises, arriving: arriving) { item in
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
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }, action: placed)
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

    /// Adds a picked exercise. Its row takes its place as the sheet starts down, moving Add
    /// exercise, but enters only where it can be seen: a moment into the sheet's slide when
    /// everything still fits, and otherwise once a scroll to the end has brought the row and Add
    /// exercise into view. The scroll waits for the row's place: asked for while the row went in,
    /// it stopped at the end the list had before.
    private func add(_ exercise: Exercise) {
        let row = RoutineExercise(exercise: exercise)
        arriving = row.id
        withAnimation(.railChange, completionCriteria: .logicallyComplete) {
            exercises.append(row)
        } completion: {
            guard arriving == row.id else { return }
            withAnimation(.railChange, completionCriteria: .logicallyComplete) {
                scrollPosition.scrollTo(edge: .bottom)
            } completion: {
                if arriving == row.id {
                    letArrivingEnter(after: 0)
                }
            }
        }
    }

    /// Once the arriving row has its place, it enters where everything is still in view, a
    /// moment into the sheet's slide, which uncovers the screen from the top.
    private func placed(from old: ScrollGeometry, to new: ScrollGeometry) {
        guard arriving != nil, new.contentSize.height > old.contentSize.height else { return }
        let visibleEnd = new.contentOffset.y + new.contentInsets.top + new.containerSize.height
        if new.contentSize.height <= visibleEnd.rounded(.up) {
            letArrivingEnter(after: 0.15)
        }
    }

    private func letArrivingEnter(after delay: TimeInterval) {
        var transaction = Transaction()
        transaction.railEntryDelay = delay
        withTransaction(transaction) {
            arriving = nil
        }
    }
}

#Preview {
    RoutineScreen()
}
