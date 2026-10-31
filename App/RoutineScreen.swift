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
    let isPushed: Bool
    @State private var isPicking = false
    /// The row whose values are open in a sheet, as it was when opened: only its id is read.
    @State var editing: RoutineExercise?
    @State var scrollPosition = ScrollPosition()
    /// The row just added, holding its place until it can be seen going in.
    @State var arriving: RoutineExercise.ID?
    /// The row just added, from the add until its entry has played. A view takes taps where it
    /// will end up, not where it's drawn, so while its place opens a tap on Add exercise, still
    /// drawn there, lands on it; it ignores taps until it has landed.
    @State var entering: RoutineExercise.ID?
    /// Whether Add exercise, at the list's end, is fully in view.
    @State var isEndInView = true
    /// While an added row's place opens, the list's end stays put on screen: as the content grows
    /// past the visible area, it scrolls in step (`keepEndInView`).
    @State var isOpeningPlace = false
    /// Whether the list is being scrolled by hand, which the in-step scroll leaves alone.
    @State var isScrollingByHand = false
    /// Whether the title's field has focus. Any touch outside the title ends the edit.
    @State private var isEditingTitle = false
    /// Whether the title has scrolled up under the bar, where a small copy of it shows instead.
    @State var isTitleUnderBar = false
    /// From Start's press until its key has gone: its beat, and the grow.
    @State var isStarting = false
    /// How far Start rides down with the rows below the current exercise as it grows at Start.
    @State var startDrop: CGFloat = 0
    /// Under Start, the scroll edge effect's band hidden while the list makes room.
    @State var isBottomEdgeHidden = false
    /// The key kept out of its bar from the end of Start's grow until the workout's key comes
    /// up, and as a workout ends until the list has landed and Start comes up.
    @State var isKeyAway = false
    /// While the current exercise is mostly out of view, which way the key points back to it,
    /// settled only once a scroll has ended (`settleKeyRole()`); none while it logs.
    @State var keyWayBack: VerticalEdge?
    /// While the key swaps (`swapKey(_:)`), the role of the key going, until it has gone.
    @State var heldKeyRole: KeyRole?
    /// From a key swap's start until the next key is coming in: the key down out of sight, its
    /// room in the bar kept, and taps do nothing.
    @State var isKeySwapping = false
    /// The key's logs, each popping a +1 off it.
    @State var plusOnes = 0
    /// The key's logs of a set, each with a medium impact, and of a side, each with a light one.
    @State var setLogs = 0
    @State var sideLogs = 0
    /// As a workout ends, it as it was, for a beat: the time key's glass stays in the bar while
    /// the time fades out of it.
    @State var endingWorkout: Workout?
    /// Whether the dialog asking how to end the workout shows.
    @State var isConfirmingEnd = false
    /// The scroll in Start's sequence, and how far the list is scrolled.
    @State var scrollBeat = ScrollBeat()
    /// With Reduce Motion, how many times the list has crossfaded into or out of a workout: each
    /// a new view, so the old one fades out as the new one fades in.
    @State var listChanges = 0
    /// While the list crossfades, when nothing in it animates but its fade.
    @State var isCrossfading = false
    /// Crossfading up to the list's top, how much of the list going out was under the bar, which
    /// is cut away as it fades.
    @State var underBarCut: CGFloat = 0
    /// At Start, how far the list's content is drawn below where it is scrolled to, run down to 0.
    @State var growthLift: CGFloat = 0
    /// While the first exercise grows at Start, room under the list's end to scroll it to the top.
    @State var isMakingRoom = false
    /// Where the first exercise, the current one in a workout, is against the part showing.
    @State var currentPlace: CurrentPlace?
    /// The list's height between the bars.
    @State var listHeight: CGFloat = 0
    /// Back in a workout after a relaunch, the list opens on the current exercise, once grown.
    @State var opensOnCurrent = false
    /// While the current exercise moves to the next row, when rows' heights are mid-motion.
    @State var isMovingOn = false
    /// After the last set, the room to land the current exercise, closing as its row does, the
    /// list's end held where it shows (`keepEndPinned(from:to:)`).
    @State var closingRoomTop: CGFloat?
    /// While a log moves the workout to another exercise, until the next one has grown.
    @State var exerciseMove: ExerciseMove?
    /// The pulse that carries the workout from one exercise's node to the next one's.
    @State var railPulse: RailPulse<RoutineExercise.ID>?
    /// Counts the moves to another exercise that have landed on its node, each with a light tick,
    /// lighter than a log's.
    @State var landings = 0
    /// The last set logged, while it stays on the current exercise, for a beat after the key's
    /// tap (`heldSet`).
    @State var unshownSet: PlannedSet?
    @State var rowFrames = RowFrames()
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

    /// The name the routine shows: its chosen one, or else the one made for it.
    var shownName: String? {
        namer.shownName(of: routine)
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
        .endWorkoutDialog(
            isPresented: $isConfirmingEnd,
            session: session,
            routineName: shownName ?? "",
            end: end,
        )
        // `onChange` skips the first value, so a routine opened and left alone is never saved.
        .onChange(of: routine) { _, changed in
            session.save(changed)
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: landings)
        .sensoryFeedback(.impact(weight: .medium), trigger: setLogs)
        .sensoryFeedback(.impact(weight: .light), trigger: sideLogs)
        .sensoryFeedback(.impact(weight: .medium), trigger: isStarting) { !$0 && $1 }
        .hotReloadable()
    }

    private var screen: some View {
        let generatedName = generatedName
        let shownName = shownName
        // Read once here, so the rows' closure holds them as values: a list crossfading out keeps
        // drawing its rows with what it had, rather than the workout it is fading into.
        let currentID = currentID
        let currentSet = currentSet
        let rowBars = rowBars
        let tracksRows = session.workout != nil || isStarting
        let underBar = underBarCut
        return ScrollView {
            // One over the other, as a crossfade has them: in the scroll view's own stack, the
            // list coming in and the one going stood one after the other.
            ZStack(alignment: .topLeading) {
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
                        // A short fade, so the small title has gone by the time the large one
                        // is out from under the bar.
                        withAnimation(.easeOut(duration: Self.barFade)) {
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
                        current: litID,
                        done: finishedRows,
                        isSetHeld: heldSet != nil,
                        pulse: railPulse,
                        onMove: move,
                        regroup: regroup,
                    ) { item in
                        rowLabel(item, current: currentID, on: currentSet, bars: rowBars[item.id])
                            .environment(\.exerciseMoveWay, exerciseMove?.way)
                            .id(item.id)
                            .padding(.top, item.id == currentID ? Self.currentTopSpace : 0)
                            // Only while it is read: as the list scrolls, every change redraws the
                            // screen.
                            .reportingPlace(
                                item.id == growingID && tracksRows,
                                to: placeCurrent,
                            )
                            // Until an added row has entered it takes no taps, and its frame is
                            // where it will be rather than where it is drawn, so VoiceOver and the
                            // UI tests find it once it has. On the label, the row's one element:
                            // on the row, `false` would un-hide the rail's node.
                            .accessibilityHidden(item.id == entering)
                            .railRow()
                            // The whole row, its insets included, as the rail stacks it.
                            .reportingFrame(tracksRows) { rowFrames.tops[item.id] = $0.minY }
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
                            // Outermost, as the system's swipe actions are, or their Delete is
                            // folded into the row's accessibility element, where VoiceOver and
                            // the UI tests never find it. The row's tap stays on where the swipe
                            // is off.
                            .swipeToDelete(isOn: item.id != currentID) { delete(item.id) }
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
                // In the content, not a margin, so the visible height the row is sized from
                // stays.
                .roomToLand(
                    top: closingRoomTop
                        ?? (currentID != nil || isMovingOn ? currentPlace?.landingY : nil),
                )
                .roomBelow(isMakingRoom)
                // When the keyboard rises, UIKit scrolls the focused field to sit at least 5pt
                // below the top of the visible area. Starting there keeps the title still.
                .padding(.top, Spacing.sm)
                .clipShape(TopClip(height: underBar))
                .modifier(GrowthLift(lift: growthLift))
                // Crossfading, the changed list comes in already changed: only its fade
                // animates.
                .transaction { transaction in
                    if isCrossfading {
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                }
                .id(listChanges)
                .transition(.opacity)
            }
            .coordinateSpace(.list)
        }
        .scrollEdgeEffectHidden(isBottomEdgeHidden, for: .bottom)
        .scrollPosition($scrollPosition)
        .railAutoscroll($scrollPosition)
        .onScrollGeometryChange(for: ScrollGeometry.self, of: \.self) { old, new in
            keepEndInView(from: old, to: new)
            keepEndPinned(from: old, to: new)
        }
        .onScrollPhaseChange { _, phase in
            isScrollingByHand = phase == .interacting || phase == .decelerating
            scrollBeat.phaseChanged(to: phase)
            if phase == .idle {
                settleKeyRole()
            }
        }
        .onScrollGeometryChange(for: Bool.self, of: Self.endIsInView(of:)) { isEndInView = $1 }
        .onScrollGeometryChange(for: CGFloat.self, of: \.scrolledY) {
            scrollBeat.listMoved(to: $1)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { listHeight = $0 }
        .primaryKeyBar(
            isPresented: showsKey,
            keyID: keyRole.kind,
            isSwappedOut: isKeySwapping,
            plusOnes: plusOnes,
            drop: startDrop,
        ) {
            key(keyRole, named: shownName ?? "")
        }
        .task(id: isStarting) { await holdStart(named: shownName ?? "") }
        .task(id: unshownSet) { await rollHeldSet() }
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
        .toolbar { barItems }
    }
}

#Preview {
    RoutineScreen(
        session: RoutineSession(routine: Routine(), store: nil),
        namer: .muscleGroupsOnly,
    )
}
