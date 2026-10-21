import DesignSystem
import SwiftUI
import WorkoutStore

/// The screen the app launches into: the routine being edited, or a new one.
///
/// Every change saves on its own, with no drafts. A new routine is saved once something is put
/// in it, and deleted once it is cleared back to nothing.
struct RoutineScreen: View {
    // What the `RoutineScreen+` extensions read is internal, not private, so they can be apart.

    @State var routine: Routine
    /// Saves every change, and opens the drawer.
    let session: RoutineSession
    private let namer: RoutineNamer
    /// Pushed onto the Routines screen, with a back button where ++ otherwise is.
    private let isPushed: Bool
    @State private var isPicking = false
    /// The row whose values are open in a sheet, as it was when opened: only its id is read.
    @State private var editing: RoutineExercise?
    @State var scrollPosition = ScrollPosition()
    /// The row just added, holding its place until it can be seen going in.
    @State private var arriving: RoutineExercise.ID?
    /// The row just added, from the add until its entry has played. A view takes taps where it
    /// will end up, not where it's drawn, so while its place opens a tap on Add exercise, still
    /// drawn there, lands on it; it ignores taps until it has landed.
    @State private var entering: RoutineExercise.ID?
    /// Whether Add exercise, at the list's end, is fully in view.
    @State private var isEndInView = true
    /// While an added row's place opens, the list's end stays put on screen: as the content grows
    /// past the visible area, it scrolls in step (`keepEndInView`).
    @State private var isOpeningPlace = false
    /// Whether the list is being scrolled by hand, which the in-step scroll leaves alone.
    @State private var isScrollingByHand = false
    /// Whether the title's field has focus. Any touch outside the title ends the edit.
    @State private var isEditingTitle = false
    /// Whether the title has scrolled up under the bar, where a small copy of it shows instead.
    @State private var isTitleUnderBar = false
    /// Start held down on its ledge from its press until the workout starts, its hold running.
    @State var isStarting = false
    /// Start kept out of its bar from its press until the workout starts, and as one ends.
    @State var isStartAway = false
    /// The scroll in Start's sequence and the end's, and whether the list is at its top.
    @State var scrollBeat = ScrollBeat()
    /// With Reduce Motion, the list faded out while it changes into a workout.
    @State var isFadedOut = false
    /// At Start, how far the list's content is drawn below where it is scrolled to, run down to 0.
    @State var growthLift: CGFloat = 0
    /// While the first exercise grows at Start, room under the list's end to scroll it to the top.
    @State var isMakingRoom = false
    /// Where the first exercise, the current one in a workout, is against the part showing.
    @State var currentPlace: CurrentPlace?
    /// The height of the area between the bars, less the room under the list's end in a workout.
    @State var visibleHeight: CGFloat = 0
    /// The list's height between the bars and the safe area, and the screen's height below it:
    /// in a workout, the current exercise and the next fill both.
    @State var listHeight: CGFloat = 0
    @State var listFoot: CGFloat = 0
    /// Back in a workout after a relaunch, the list opens on the current exercise, once it has
    /// grown to its size.
    @State var opensOnCurrent = false
    /// Room under the list's end in a workout, so Add exercise scrolls clear of the way back to
    /// the current exercise.
    @ScaledMetric(relativeTo: .body) var wayToCurrentRoom: CGFloat = 64
    /// The height of the row after the current exercise, which the current one leaves room for.
    @State var nextRowHeight: CGFloat?
    /// What the current exercise leaves of that area when nothing follows it: Add exercise.
    @ScaledMetric(relativeTo: .body) var endRoom: CGFloat = 96
    @Environment(\.locale) var locale
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ObserveHotReload private var hotReload

    static let defaultName = String(localized: "New routine")

    /// Shows the routine the session opened. A switch to another gives a new screen.
    init(session: RoutineSession, namer: RoutineNamer, isPushed: Bool = false) {
        _routine = State(initialValue: session.opened)
        _opensOnCurrent = State(initialValue: session.workout != nil)
        self.session = session
        self.namer = namer
        self.isPushed = isPushed
    }

    /// The name made for the routine from its exercises, which a chosen name hides and which
    /// clearing it brings back. Not stored: made again from the same exercises, it is the same
    /// name, so it is the same after a relaunch.
    private var generatedName: String? {
        namer.name(for: routine.exercises.map(\.exercise), of: routine.id)
    }

    var body: some View {
        Group {
            if isPushed {
                screen
            } else {
                NavigationStack { screen }
            }
        }
        // A touch anywhere outside the title, bars included, ends its edit and still acts. The
        // keyboard slides down as on Return, where `.scrollDismissesKeyboard` drops it at once.
        .onTouchDownOutsideTitle { isEditingTitle = false }
        // `onChange` skips the first value, so a routine opened and left alone is never saved.
        .onChange(of: routine) { _, changed in
            session.save(changed)
        }
        .hotReloadable()
    }

    private var screen: some View {
        let generatedName = generatedName
        let shownName = routine.name.isEmpty ? generatedName : routine.name
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                EditableTitle(
                    text: $routine.name,
                    isEditing: $isEditingTitle,
                    placeholder: Self.defaultName,
                    suggestion: generatedName,
                    accessibilityLabel: "Routine name",
                    accessibilityHint: "Renames the routine.",
                )
                .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                    withAnimation(.snappy) {
                        isTitleUnderBar = !isVisible
                    }
                }
                let equipment = routine.exercises.map(\.exercise).equipment
                if !equipment.isEmpty {
                    Capsules(equipment.map(\.name))
                        .accessibilityIdentifier("routine.equipment")
                        .transition(.opacity)
                }
                Rail(
                    routine.exercises,
                    links: routine.joinedToNext,
                    arriving: arriving,
                    current: currentID,
                    onMove: move,
                    regroup: regroup,
                ) { item in
                    RowLabel(
                        title: item.exercise.name,
                        detail: item.detailParts(locale: locale),
                        spokenDetail: item.spokenDetail(locale: locale),
                        focus: item.id == currentID ? item.focus(
                            inSuperset: routine.isInSuperset(item.id),
                            minHeight: currentLabelHeight,
                            locale: locale,
                        ) : nil,
                    )
                    .id(item.id)
                    .reportingPlace(item.id == routine.exercises.first?.id, to: placeCurrent)
                    // Until an added row has entered it takes no taps, and its frame is
                    // where it will be rather than where it is drawn, so VoiceOver and the UI
                    // tests find it once it has. On the label, the row's one element: on the
                    // row, `false` would un-hide the rail's node.
                    .accessibilityHidden(item.id == entering)
                    .railRow()
                    .reportingHeight(item.id == nextID) { nextRowHeight = $0 }
                    // Under the tap, which stays on where the swipe is off.
                    .swipeToDelete(isOn: item.id != currentID) { delete(item.id) }
                    .contentShape(.rect)
                    .onTapGesture {
                        guard item.id != entering else { return }
                        editing = item
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityValue(supersetValue(item.id))
                    // None where it would do nothing: at an end, or with one row.
                    .accessibilityActions {
                        if let up = routine.slotMovingUp(item.id) {
                            Button("Move up") { step(item.id, to: up, wentUp: true) }
                        }
                        if let down = routine.slotMovingDown(item.id) {
                            Button("Move down") { step(item.id, to: down, wentUp: false) }
                        }
                        supersetActions(item.id)
                    }
                    .accessibilityIdentifier("routine.exercise")
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
            // In the content, not a margin, so the visible height the row is sized from stays.
            .padding(.bottom, isMakingRoom ? visibleHeight : 0)
            // When the keyboard rises, UIKit scrolls the focused field to sit at least 5pt
            // below the top of the visible area. Starting there keeps the title still.
            .padding(.top, Spacing.sm)
            .opacity(isFadedOut ? 0 : 1)
            .offset(y: growthLift)
            .coordinateSpace(.list)
        }
        .contentMargins(.bottom, session.workout == nil ? 0 : wayToCurrentRoom, for: .scrollContent)
        // The room under the end is empty: under Start it would raise the edge effect's band.
        .scrollEdgeEffectHidden(isMakingRoom, for: .bottom)
        .scrollPosition($scrollPosition)
        .railAutoscroll($scrollPosition)
        .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }, action: keepEndInView)
        .onScrollPhaseChange { _, phase in
            isScrollingByHand = phase == .interacting || phase == .decelerating
            scrollBeat.phaseChanged(to: phase)
        }
        .onScrollGeometryChange(for: Bool.self, of: Self.endIsInView(of:)) { isEndInView = $1 }
        .onScrollGeometryChange(for: CGFloat.self, of: \.scrolledY) { scrollBeat.listMoved(to: $1) }
        .onScrollGeometryChange(for: CGFloat.self, of: \.containerSize.height) {
            containerResized($1)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { listHeight = $0 }
        .reportingFoot { listFoot = $0 }
        .overlay(alignment: .bottom) { wayToCurrent }
        .primaryKeyBar(
            isPresented: !routine.exercises.isEmpty && session.workout == nil && !isStartAway,
            isPressedIn: isStarting,
        ) {
            Button("Start", systemImage: "play.fill", action: pressStart)
        }
        .task(id: isStarting) { await holdStart(named: shownName ?? "") }
        // One row open at a time, closed by a scroll or a tap anywhere else, Start included,
        // so the container holds Start's bar as well as the scroll view.
        .swipeActionsContainer()
        // The drawer's `accessibilityHidden` stops at the navigation stack, whose content is
        // hosted apart, so the screen hides its own content behind the open drawer.
        .accessibilityHidden(session.isDrawerOpen)
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
        // By item, so the sheet keeps its content as it slides away.
        .sheet(item: $editing) { opened in
            if let item = row(opened.id) {
                ExerciseSheet(
                    item: item,
                    partners: routine.partnerNames(of: opened.id),
                ) { delete(opened.id) }
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
                        // Gray only for New routine, as in the title.
                        Text(shownName ?? Self.defaultName)
                            .font(.ppInlineTitle)
                            .foregroundStyle(.pp(shownName == nil ? .textSecondary :
                                    .textPrimary))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    // A heading, as the system's own bar title is.
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint("Scrolls to the top.")
                    .hiddenBehindDrawer()
                    .transition(.opacity)
                }
            }
            if let workout = session.workout {
                ToolbarItem(placement: .topBarLeading) {
                    FinishButton(session: session, routineName: shownName ?? "", end: end)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    WorkoutTimeKey(session: session, workout: workout)
                }
            } else if !isPushed {
                ToolbarItem(placement: .topBarLeading) {
                    MenuButton(session: session)
                }
            }
        }
    }
}

/// Editing the rows: the sheet's binding, moves, deletes, and adds.
extension RoutineScreen {
    /// The row with this id, bound by id rather than by index, so a sheet still showing it
    /// never reads past the end of the rows once it is deleted.
    private func row(_ id: RoutineExercise.ID) -> Binding<RoutineExercise>? {
        guard let current = routine.exercises.first(where: { $0.id == id }) else { return nil }
        return Binding {
            routine.exercises.first { $0.id == id } ?? current
        } set: { item in
            routine.update(item)
        }
    }

    /// Moves a row dropped on the rail, in the rail's transaction, so the order changes as the
    /// card settles into its gap; it saves once, as any change does.
    private func move(_ id: RoutineExercise.ID, to slot: RailSlot<RoutineExercise.ID>) {
        routine.move(id, to: RoutineSlot(slot))
    }

    /// Moves a row one place with VoiceOver's Move up or Move down, and says which row it
    /// passed.
    private func step(_ id: RoutineExercise.ID, to slot: RoutineSlot, wentUp: Bool) {
        withAnimation(.railChange) {
            routine.move(id, to: slot)
        }
        if let announcement = routine.moveAnnouncement(for: id, wentUp: wentUp) {
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    private func delete(_ id: RoutineExercise.ID) {
        withAnimation(.railChange) {
            routine.remove(id)
        }
    }

    /// Adds a picked exercise. Its row takes its place as the sheet starts down, moving Add
    /// exercise, but enters only where it can be seen: a moment into the sheet's slide when
    /// everything still fits, and otherwise once a scroll to the end has brought the row and Add
    /// exercise into view. The scroll waits for the row's place: asked for while the row went in,
    /// it stopped at the end the list had before.
    private func add(_ exercise: Exercise) {
        let row = RoutineExercise(exercise: exercise, weightUnit: WeightUnit(region: locale))
        arriving = row.id
        entering = row.id
        isOpeningPlace = true
        // The row goes in with no space yet, so nothing moves; its fade, of a row that draws
        // nothing yet, times the entry a moment into the sheet's slide: the line barely moves
        // at first, and the sheet has cleared all but the screen's foot by the time it shows.
        withAnimation(.linear(duration: 0.1)) {
            routine.exercises.append(row)
        } completion: {
            guard arriving == row.id else { return }
            guard !isEndInView else { return letArrivingEnter(row) }
            withAnimation(.railChange, completionCriteria: .logicallyComplete) {
                scrollPosition.scrollTo(edge: .bottom)
            } completion: {
                letArrivingEnter(row)
            }
        }
    }

    /// While an added row's place opens past the visible area, scrolls with it, a frame at a
    /// time, so Add exercise stays put on screen as the line grows above it. The place opens
    /// with the list's end in view, so the end is where the scroll stays.
    private func keepEndInView(from old: ScrollGeometry, to new: ScrollGeometry) {
        guard isOpeningPlace, !isScrollingByHand,
              new.contentSize.height > old.contentSize.height
        else { return }
        guard new.endY > new.scrolledY else { return }
        withTransaction(\.disablesAnimations, true) {
            scrollPosition.scrollTo(y: new.endY)
        }
    }

    /// Whether the list's end, Add exercise, is in view, below the area between the bars.
    private static func endIsInView(of geometry: ScrollGeometry) -> Bool {
        geometry.contentSize.height
            <= (geometry.scrolledY + geometry.containerSize.height).rounded(.up)
    }

    /// Lets `row` enter, unless a later add has taken its place as the arriving row.
    private func letArrivingEnter(_ row: RoutineExercise) {
        guard arriving == row.id else { return }
        var transaction = Transaction()
        transaction.isRailEntry = true
        // A later add, its row arriving, keeps the scroll in step for its own place.
        transaction.addAnimationCompletion {
            isOpeningPlace = arriving != nil
            if entering == row.id {
                entering = nil
            }
        }
        withTransaction(transaction) {
            arriving = nil
        }
    }
}

#Preview {
    RoutineScreen(
        session: RoutineSession(routine: Routine(), store: nil),
        namer: .muscleGroupsOnly,
    )
}
