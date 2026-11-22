import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// Every saved workout, most recently opened or edited first, each by its name.
/// Tapping one pushes it on the workout screen; + pushes a new one. A line runs under each row,
/// the last included, as under each row in Add exercise.
///
/// A row swiped left shows the system's red Delete, and a row held opens the system's context
/// menu with Delete, red with a trash, the held row lifted on a rounded platter in the screen's
/// color, as a row in Add exercise is. Either asks first in a centered alert, "Delete <name>?",
/// the name as the row shows it; confirmed, the row leaves and the rows below close the gap,
/// and the screen stays on Workouts (`AppSession.delete(_:)`).
struct WorkoutsScreen: View {
    @Bindable var session: AppSession
    let namer: WorkoutNamer

    /// The order the rows are drawn in, taken only while the list is out of sight or as it
    /// shows, so a workout opened from it moves to the top unseen, not as it slides away.
    @State private var order: [Workout.ID] = []
    @State private var scrollPosition = ScrollPosition()
    /// Whether the title has scrolled out of sight under the bar, for its small copy to show.
    @State private var isTitleUnderBar = false
    /// The workout Delete last asked about, kept as the alert goes, so its title keeps the name.
    @State private var deleting: Workout?
    @State private var isAskingToDelete = false
    /// Workouts whose delete is confirmed, left out of the list from the confirming tap, in its
    /// animation, before the store has taken the delete.
    @State private var leaving: Set<Workout.ID> = []
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Workouts")
                        .ppFixedTitleFont()
                        .foregroundStyle(.pp(.textPrimary))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, Spacing.md)
                        .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                            withAnimation(.easeOut(duration: WorkoutScreen.barFade)) {
                                isTitleUnderBar = !isVisible
                            }
                        }
                    ForEach(shown, content: row)
                }
                // The scroll view takes its content's width, so with no row to stretch it the
                // title alone would set it.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)
            }
            .scrollPosition($scrollPosition)
            // One row open at a time, closed by a scroll or a tap anywhere else.
            .swipeActionsContainer()
            .accessibilityHidden(session.isDrawerOpen)
            .background { Color.pp(.background).ignoresSafeArea() }
            .onAppear(perform: takeOrder)
            .onDisappear(perform: takeOrder)
            .navigationDestination(isPresented: isWorkoutPushed) {
                // Each workout opened gives a fresh screen: scroll, sheets, and title.
                WorkoutScreen(session: session, namer: namer, isPushed: true)
                    .id(session.opened.id)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // As the workout screen's: always there, faded, and a tap scrolls to the top.
                ToolbarItem(placement: .title) {
                    Button {
                        withAnimation(.snappy) { scrollPosition.scrollTo(edge: .top) }
                    } label: {
                        Text("Workouts")
                            .font(.ppBarTitle)
                            .foregroundStyle(.pp(.textPrimary))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint("Scrolls to the top.")
                    .hiddenBehindDrawer()
                    .opacity(isTitleUnderBar ? 1 : 0)
                    .allowsHitTesting(isTitleUnderBar)
                    .accessibilityShown(isTitleUnderBar)
                }
                ToolbarItem(placement: .topBarLeading) {
                    MenuButton(session: session)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New workout", systemImage: "plus") {
                        Task { await session.startNew() }
                    }
                    .makesSomething()
                    .hiddenBehindDrawer()
                }
            }
        }
        // Outside the stack, as the picker's: centered, with the system's colors.
        .alert(
            "Delete \(deleting.map(namer.listedName(of:)) ?? "")?",
            isPresented: $isAskingToDelete,
            presenting: deleting,
        ) { workout in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { delete(workout.id) }
        }
        .task {
            await session.refreshRecent(weightUnit: weightUnit)
            takeOrder()
        }
    }

    private func row(_ workout: Workout) -> some View {
        Button {
            Task { await session.open(workout.id, weightUnit: weightUnit) }
        } label: {
            NameRow(namer.listedName(of: workout))
                .padding(.leading, Spacing.md)
                .padding(.trailing, Spacing.md - Self.swipeInset)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workouts.row")
        // The system draws a swiped action inset from its row's end, so the row it swipes
        // ends that far short of the screen's edge, and Delete ends in line with the line
        // under the row and with the bar's +.
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { askToDelete(workout) }
        }
        .padding(.trailing, Self.swipeInset)
        // The platter the held row lifts on, as a list row's in Add exercise: in the screen's
        // own color, so it shows only once the screen behind it dims. Like a picker row's cell,
        // it spans the screen with the name a margin inside, and the system shrinks the lifted
        // row into the screen's margins, which leaves the name the picker's room inside the
        // lifted platter. Behind the swiped row, so it never covers Delete.
        .background(Color.pp(.background), in: Self.platter)
        .contentShape(.contextMenuPreview, Self.platter)
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { askToDelete(workout) }
        }
        // Across the name's width, outside the platter, so a held row lifts without it.
        .overlay(alignment: .bottom) {
            RowLine().padding(.horizontal, Spacing.md)
        }
    }

    private static let platter = RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
    /// How far inside its row's end the system draws a swiped action. Log's History rows take it
    /// too, so their Delete lines up as these do.
    static let swipeInset = Spacing.sm

    private func askToDelete(_ workout: Workout) {
        deleting = workout
        isAskingToDelete = true
    }

    /// Takes the row out at once, the rows below closing the gap, then deletes the workout.
    private func delete(_ id: Workout.ID) {
        withAnimation(.snappy) {
            _ = leaving.insert(id)
        }
        Task {
            await session.delete(id)
            // Gone from the session's list once stored; back in the list if the delete failed,
            // or was refused as a switch was under way.
            withAnimation(.snappy) {
                _ = leaving.remove(id)
            }
        }
    }

    /// The stack's push: the session's pushed workout, which the back button and the back swipe
    /// pop.
    private var isWorkoutPushed: Binding<Bool> {
        Binding {
            session.screen == .pushedWorkout
        } set: { isPushed in
            if !isPushed {
                session.popWorkout()
            }
        }
    }

    private var shown: [Workout] {
        session.recent.held(in: order).filter { !leaving.contains($0.id) }
    }

    private func takeOrder() {
        order = session.recent.map(\.id)
    }

    private var weightUnit: WeightUnit {
        WeightUnit(region: locale)
    }
}

#Preview {
    WorkoutsScreen(
        session: AppSession(
            workout: Workout(name: "Upper body"),
            store: nil,
            namer: .muscleGroupsOnly,
        ),
        namer: .muscleGroupsOnly,
    )
}

extension WorkoutNamer {
    /// A workout's name where workouts are listed: the name it shows, else New workout.
    func listedName(of workout: Workout) -> String {
        shownName(of: workout) ?? WorkoutScreen.defaultName
    }
}
