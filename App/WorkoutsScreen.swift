import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// Every saved workout, most recently opened or edited first, each a `WorkoutRow`: its name,
/// estimated length, kind, equipment, and a bar of the muscles it works, as long as the workout
/// against the longest row shown, never less than 30 minutes (`WorkoutSummary.fullBarMinutes`).
/// The app launches here when a finish was the last thing done (`Store.Launch.workouts`).
/// Tapping one pushes it on the workout screen; the round green + at the bottom right, where an
/// empty workout's + sits, pushes a new one. A line runs under each row, the last included, as
/// under each row in Add exercise.
///
/// Under the title, pinned once it scrolls away, the filters' bar (`WorkoutsFilterBar`): Muscle
/// and Equipment open sheets of chips, Length a sheet of presets and two wheels (`LengthSheet`),
/// and the three narrow the list together (`WorkoutFilter`). A change animates in one `.tapChange`
/// move, as Add exercise's, the bars that stay taking their new scale, and VoiceOver hears the
/// new count. Under the
/// matches, a workout one piece of equipment short is listed under "Also needs" and a button
/// that adds the piece (`NeedsHeader`). The filters hold through opening a workout and coming
/// back, and clear as the screen leaves for another place.
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
    /// Whether the title has been reported in sight. The first report, as the screen first lays
    /// out, says the title is out of sight, and the next, 15 to 55 ms on, that it is in sight;
    /// taken, the first showed the small title at launch, fading as the next came.
    @State private var hasSeenTitle = false
    /// The workout Delete last asked about, kept as the alert goes, so its title keeps the name.
    @State private var deleting: Workout?
    @State private var isAskingToDelete = false
    /// Workouts whose delete is confirmed, left out of the list from the confirming tap, in its
    /// animation, before the store has taken the delete.
    @State private var leaving: Set<Workout.ID> = []
    /// What the list is narrowed by; it clears as the screen leaves for another place.
    @State private var filter = WorkoutFilter()
    /// The filter's sheet showing, if any.
    @State private var choosing: WorkoutsSheet?
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Each workout summarized once per pass, for its row and the filter alike.
        let summaries = Dictionary(
            session.recent.compactMap { workout in workout.summary.map { (workout.id, $0) } },
            uniquingKeysWith: { first, _ in first },
        )
        let filtered = filter.filtered(shown) { summaries[$0.id] }
        let items = WorkoutsItem.items(filtered)
        // Every row shown sets the scale, a section's included.
        let fullBar = WorkoutSummary.fullBarMinutes(among: items.compactMap {
            $0.workout.flatMap { summaries[$0.id] }
        })
        return NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    Text("Workouts")
                        .ppFixedTitleFont()
                        .foregroundStyle(.pp(.textPrimary))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, Spacing.md)
                        .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                            if isVisible {
                                hasSeenTitle = true
                            }
                            guard hasSeenTitle else { return }
                            withAnimation(.easeOut(duration: WorkoutScreen.barFade)) {
                                isTitleUnderBar = !isVisible
                            }
                        }
                    Section {
                        // One ForEach for matches and sections alike, so a workout whose
                        // piece is added keeps its identity and moves up into the matches.
                        ForEach(items) { item in
                            switch item {
                            case let .workout(workout):
                                row(workout, summary: summaries[workout.id], fullBar: fullBar)
                            case let .needs(piece):
                                needsHeader(piece)
                            }
                        }
                        FloatingButtonRoom()
                    } header: {
                        // Pinned under the bar once the title scrolls away, as Add exercise's.
                        // The only pinned view: "Also needs" headings are rows that scroll
                        // under it, as a second pinned header would push the bar away.
                        WorkoutsFilterBar(filter: announcedFilter) {
                            choosing = $0
                        }
                        .background(Color.pp(.background))
                    }
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
            }
            // Where the workout screen's + sits on an empty workout.
            .floatingButton(
                Button("New workout", systemImage: "plus") {
                    Task { await session.startNew() }
                },
            )
            .sheet(item: $choosing) { sheet in
                switch sheet {
                case .muscle:
                    ChipSheet(
                        title: "Muscle",
                        items: MuscleGroup.allCases,
                        chosen: announcedFilter.muscleGroups,
                        name: \.name,
                        onDone: { choosing = nil },
                    )
                case .equipment:
                    ChipSheet(
                        title: "Equipment",
                        items: EquipmentChoice.allCases,
                        chosen: announcedFilter.equipment,
                        name: \.name,
                        onDone: { choosing = nil },
                    )
                case .length:
                    lengthSheet
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

    /// The filter, written through one place: animated, so rows leave, the rest close up, and
    /// the bars move to their new scale in one move, and telling VoiceOver how many workouts
    /// show, as it cannot glance at the list behind a sheet of chips. At the write, not from a
    /// change of the filter, which can be skipped.
    private var announcedFilter: Binding<WorkoutFilter> {
        Binding { filter } set: { changed in
            // `.tapChange`, as Add exercise's filter, so the two bars move alike.
            withAnimation(reduceMotion ? nil : .tapChange) { filter = changed }
            // Over the rows the bar counts, so a delete still leaving reads as gone.
            let count = shown.count { changed.passes($0.summary) }
            AccessibilityNotification.Announcement(WorkoutFilter.countText(count)).post()
        }
    }

    /// The Length sheet over the filter's range: a preset sets both ends, the lit one turns the
    /// filter off, and each wheel moves its end, carrying the other past a crossing.
    private var lengthSheet: some View {
        let length = announcedFilter.length
        let presets = LengthRange.Preset.allCases
        return LengthSheet(
            presets: presets.map(\.range.label),
            spokenPresets: presets.map(\.range.spoken),
            lit: filter.length.preset.flatMap { presets.firstIndex(of: $0) },
            lower: filter.length.lower,
            upper: filter.length.upper,
            lowerValues: LengthRange.lowerValues,
            upperValues: LengthRange.upperValues,
            onPreset: { index in
                let range = presets[index].range
                length.wrappedValue = filter.length == range ? .full : range
            },
            onLower: { length.wrappedValue.setLower($0) },
            onUpper: { length.wrappedValue.setUpper($0) },
            onDone: { choosing = nil },
        )
    }

    /// "Also needs" and a button, "+ Bench", that adds the piece to the Equipment filter, through
    /// the one animated, announced write the sheet's chips use.
    private func needsHeader(_ piece: Equipment) -> some View {
        NeedsHeader(needed: piece.needed, addTitle: piece.name) {
            announcedFilter.wrappedValue.equipment.insert(.piece(piece))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xs)
    }

    private func row(_ workout: Workout, summary: WorkoutSummary?, fullBar: Int) -> some View {
        Button {
            Task { await session.open(workout.id, weightUnit: weightUnit) }
        } label: {
            WorkoutRow(
                namer.listedName(of: workout),
                shape: summary.map { WorkoutRow.Shape($0, fill: $0.fill(of: fullBar)) },
            )
            .padding(.leading, Spacing.md)
            .padding(.trailing, Spacing.md - Self.swipeInset)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(namer.listedName(of: workout))
        .accessibilityValue(summary?.spoken ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("workouts.row")
        // The system draws a swiped action inset from its row's end, so the row it swipes
        // ends that far short of the screen's edge, and Delete ends in line with the line
        // under the row and with the bar's +.
        .rowSwipe("Delete", value: workout, action: askToDelete)
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
