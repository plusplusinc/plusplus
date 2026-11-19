import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// Every saved routine, most recently opened or edited first, each by its name.
/// Tapping one pushes it on the routine screen; + pushes a new one. A line runs under each row,
/// the last included, as under each row in Add exercise.
///
/// A row swiped left shows the system's red Delete, and a row held opens the system's context
/// menu with Delete, red with a trash, the held row lifted on a rounded platter in the screen's
/// color, as a row in Add exercise is. Either asks first in a centered alert, "Delete <name>?",
/// the name as the row shows it; confirmed, the row leaves and the rows below close the gap,
/// and the screen stays on Routines (`RoutineSession.delete(_:)`).
struct RoutinesScreen: View {
    @Bindable var session: RoutineSession
    let namer: RoutineNamer

    /// The order the rows are drawn in, taken only while the list is out of sight or as it
    /// shows, so a routine opened from it moves to the top unseen, not as it slides away.
    @State private var order: [Routine.ID] = []
    @State private var scrollPosition = ScrollPosition()
    /// Whether the title has scrolled out of sight under the bar, for its small copy to show.
    @State private var isTitleUnderBar = false
    /// The routine Delete is asking about.
    @State private var deleting: Routine?
    /// Routines whose delete is confirmed, left out of the list from the confirming tap, in its
    /// animation, before the store has taken the delete.
    @State private var leaving: Set<Routine.ID> = []
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Routines")
                        .ppFixedTitleFont()
                        .foregroundStyle(.pp(.textPrimary))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, Spacing.md)
                        .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                            withAnimation(.easeOut(duration: RoutineScreen.barFade)) {
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
            .navigationDestination(isPresented: isRoutinePushed) {
                // Each routine opened gives a fresh screen: scroll, sheets, and title.
                RoutineScreen(session: session, namer: namer, isPushed: true)
                    .id(session.opened.id)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // As the routine screen's: always there, faded, and a tap scrolls to the top.
                ToolbarItem(placement: .title) {
                    Button {
                        withAnimation(.snappy) { scrollPosition.scrollTo(edge: .top) }
                    } label: {
                        Text("Routines")
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
                    Button("New routine", systemImage: "plus") {
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
            isPresented: Binding { deleting != nil } set: {
                if !$0 {
                    deleting = nil
                }
            },
            presenting: deleting,
        ) { routine in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { delete(routine.id) }
        }
        .task {
            await session.refreshRecent(weightUnit: weightUnit)
            takeOrder()
        }
    }

    private func row(_ routine: Routine) -> some View {
        Button {
            Task { await session.open(routine.id, weightUnit: weightUnit) }
        } label: {
            NameRow(namer.listedName(of: routine))
                .padding(.horizontal, Spacing.md)
                // The platter the held row lifts on, as a list row's in Add exercise: in the
                // screen's own color, so it shows only once the screen behind it dims. Like a
                // picker row's cell, it spans the screen with the name a margin inside, and the
                // system shrinks the lifted row into the screen's margins, which leaves the
                // name the picker's room inside the lifted platter.
                .background(Color.pp(.background), in: Self.platter)
                .contentShape(.contextMenuPreview, Self.platter)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("routines.row")
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { deleting = routine }
        }
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = routine }
        }
        // Drawn as Add exercise's list draws its own: the system's separator, a point thick,
        // across the name's width at the row's foot. Over the row, so no row moves, and
        // outside the platter, so a held row lifts without it.
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
                .padding(.horizontal, Spacing.md)
                .accessibilityHidden(true)
        }
    }

    private static let platter = RoundedRectangle(cornerRadius: Radius.key, style: .continuous)

    /// Takes the row out at once, the rows below closing the gap, then deletes the routine.
    private func delete(_ id: Routine.ID) {
        withAnimation(.snappy) {
            _ = leaving.insert(id)
        }
        Task {
            await session.delete(id)
            // Gone from the session's list once stored; back in the list if the delete failed.
            leaving.remove(id)
        }
    }

    /// The stack's push: the session's pushed routine, which the back button and the back swipe
    /// pop.
    private var isRoutinePushed: Binding<Bool> {
        Binding {
            session.screen == .pushedRoutine
        } set: { isPushed in
            if !isPushed {
                session.popRoutine()
            }
        }
    }

    private var shown: [Routine] {
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
    RoutinesScreen(
        session: RoutineSession(
            routine: Routine(name: "Upper body"),
            store: nil,
            namer: .muscleGroupsOnly,
        ),
        namer: .muscleGroupsOnly,
    )
}

extension RoutineNamer {
    /// A routine's name where routines are listed: the name it shows, else New routine.
    func listedName(of routine: Routine) -> String {
        shownName(of: routine) ?? RoutineScreen.defaultName
    }
}
