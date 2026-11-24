import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// The workout being edited, or a new one; the app launches here, except after a finish.
///
/// Every change saves on its own, with no drafts. A new workout is saved once something is put
/// in it, and deleted once it is cleared back to nothing.
struct WorkoutScreen: View {
    // What the `WorkoutScreen+` extensions read is internal, not private, so they can be apart.

    /// The workout as drawn. Written only through `workout`, which saves each change.
    @State private var shownWorkout: Workout
    /// Saves every change, and opens the drawer.
    let session: AppSession
    let namer: WorkoutNamer
    /// Pushed onto the Workouts screen, with a back button where ++ otherwise is.
    let isPushed: Bool
    /// How high the picker is: half as it opens (`openPicker()`), full once pulled up or once
    /// its search opens.
    @State var pickerDetent: PresentationDetent = .medium
    @State var listEnd = ListEnd()
    @State var scrollPosition = ScrollPosition()
    /// The row just added, holding its place until it can be seen going in.
    @State var arriving: WorkoutExercise.ID?
    /// The row just added, from the add until its entry has played. A view takes taps where it
    /// will end up, not where it's drawn, so while its place opens a tap there, on what is still
    /// drawn there, lands on it; it ignores taps until it has landed.
    @State var entering: WorkoutExercise.ID?
    /// A created row landed, its sheet waiting out `createdHold` (`showCreated()`).
    @State var createdWait: CreatedWait?
    /// Whether the list's end, the room it leaves for the floating +, is fully in view.
    @State var isEndInView = true
    /// While an added row's place opens, the list's end stays put on screen: as the content grows
    /// past the visible area, it scrolls in step (`keepEndInView`), at the stage `EndFollow`
    /// names; nil while no place opens, and from Start's press or a move to the next exercise
    /// until an add with no room under the list (`isMakingRoom`).
    @State var endFollow: EndFollow?
    /// Whether the list is being scrolled by hand, which the in-step scroll leaves alone.
    @State var isScrollingByHand = false
    /// Whether the title's field has focus. Any touch outside the title ends the edit.
    @State var isEditingTitle = false
    /// Where the touch down last came, which tells a tap on the list what to do, and the
    /// keyboard a picker waits on (`tappedList(at:)`).
    @State var titleTap = TapPastTitle()
    /// Whether the screen's foot shows the workout as empty: no Start, and the + low. It follows
    /// the exercises, but the first add and the last Remove change it only once their sheet has
    /// gone, so Start and the + are seen rising or going down (`settleFoot(after:)`).
    @State var footShowsEmpty: Bool
    /// Whether the title has scrolled up under the bar, where a small copy of it shows instead.
    @State var isTitleUnderBar = false
    /// How far Start rides down with the rows below the current exercise as it grows at Start.
    @State var startDrop: CGFloat = 0
    /// While the current exercise is scrolled away, which way the key points back to it,
    /// held while a finger is on the list and following the row as the list coasts once it lifts
    /// (`settleWayBack()`); none while it logs.
    @State var keyWayBack: WorkoutKey.WayBack?
    /// The key's logs of a set, each with a medium impact, and of a side, each with a light one;
    /// each log pops a +1 off the key.
    @State var setLogs = 0
    @State var sideLogs = 0
    /// Whether the dialog asking how to end the workout shows.
    @State var isConfirmingEnd = false
    /// Whether the alert asking to delete the workout shows.
    @State var isAskingToDeleteWorkout = false
    /// The scroll in Start's sequence, and how far the list is scrolled.
    @State var scrollBeat = ScrollBeat()
    /// With Reduce Motion, how many times the list has crossfaded into or out of a workout, or
    /// to a deleted exercise's rows gone: each a new view, so the old one fades out as the new
    /// one fades in.
    @State var listChanges = 0
    /// A created exercise being deleted, which Add exercise stops listing on its beat, before
    /// the store takes the delete (`deleteExercise(_:closing:)`).
    @State var leavingExercise: Exercise.ID?
    /// While the list crossfades, when nothing in it animates but its fade.
    @State var isCrossfading = false
    /// Crossfading up to the list's top, how much of the list going out was under the bar, which
    /// is cut away as it fades.
    @State var underBarCut: CGFloat = 0
    /// At Start, how far the list's content is drawn below where it is scrolled to, run down to 0.
    @State var growthLift: CGFloat = 0
    /// The lift as last drawn, mid-animation included, which End takes up from.
    @State var shownLift = ShownLift()
    /// From Start's press until the first exercise has grown, through a move to the next exercise,
    /// and while End shrinks the current one back: room under the list's end, out of sight, so
    /// the list can scroll the row to the top and holds still as rows change height; at Start,
    /// `landingRoomTop` holds the landing. While it is on, the list's end is that room, so an
    /// added row's scroll to the end must not run.
    @State var isMakingRoom = false
    /// Where the first exercise, the current one in a workout, is against the part showing.
    @State var currentPlace: CurrentPlace?
    /// The list's height between the bars, 0 until the list first has one. Read only in actions,
    /// never in `body`, so its writes as the screen lays out don't run the screen again.
    @State var listHeight: CGFloat = 0
    /// Back in a workout after a relaunch, the list opens on the current exercise, once grown.
    @State var opensOnCurrent = false
    /// Counts Start's grows of the first exercise and End's shrinks of the current one, each
    /// changing it on the motion's own animation, so the list knows its rows are mid-motion until
    /// that animation has really ended (`listResizes(_:)`).
    @State var resizes = 0
    /// After the last set, the room to land the current exercise, closing as its row does, the
    /// list's end held where it shows (`keepEndPinned(from:to:)`). Its own value, not derived from
    /// the phase: it has to change in the close's animated transaction, and a number set to
    /// the landing and back to 0 in one turn, as a derived one would be, did not change at all,
    /// so the room went at once and the list jumped to its top.
    @State var closingRoomTop: CGFloat?
    /// The pulse that carries the workout from one exercise's node to the next one's.
    @State var railPulse: RailPulse<WorkoutExercise.ID>?
    /// Counts the moves landed on another exercise's node, each with a tick lighter than a log's.
    @State var landings = 0
    /// Counts the rests run to their end, each with a heavy tap, felt with the phone set down;
    /// and the taps on Skip rest, with the rest the last one cut (`RestSkips`).
    @State var restEnds = 0
    @State var restSkips = RestSkips()
    /// A set's beats: "Start in" ending, and the set running out (`WorkoutScreen+Timing`).
    @State var countBeats = CountBeats()
    /// Where the workout is in its sequence: out of one, starting, at rest, showing a set just
    /// logged (`play(_:leadingTo:)`), or ending. Every change to it lands in a transaction the
    /// screen names.
    @State var phase: WorkoutPhase
    /// The timed beats of the sequence playing, Start's, a logged set's, or End's, which End and
    /// the screen going away stop.
    @State var sequence = SequenceTask()
    @State var rowFrames = RowFrames()
    @Environment(\.locale) var locale
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    static let defaultName = String(localized: "New workout")

    /// Shows the workout the session opened. A switch to another gives a new screen.
    init(session: AppSession, namer: WorkoutNamer, isPushed: Bool = false) {
        _shownWorkout = State(initialValue: session.opened)
        _opensOnCurrent = State(initialValue: session.loggedWorkout != nil)
        _phase = State(initialValue: WorkoutPhase(
            resuming: session.loggedWorkout
                .map { LiveWorkout(workout: session.opened, loggedWorkout: $0) },
            restOverride: Self.restOverride,
            at: .now,
        ))
        _footShowsEmpty = State(initialValue: session.opened.exercises.isEmpty)
        self.session = session
        self.namer = namer
        self.isPushed = isPushed
    }

    /// The workout on screen. Every change to it is saved as it is made, and a write that changes
    /// nothing saves nothing, so a workout opened and left alone is never saved. Saved here, not
    /// from an `onChange` of the workout, which SwiftUI skips when the workout changes again in a
    /// frame its action already ran in, losing the last key of a name typed fast.
    var workout: Workout {
        get { shownWorkout }
        nonmutating set {
            guard newValue != shownWorkout else { return }
            shownWorkout = newValue
            session.save(newValue)
        }
    }

    /// The name made for the workout from its exercises, which a chosen name hides and which
    /// clearing it brings back. Not stored: made again from the same exercises, it is the same
    /// name, so it is the same after a relaunch.
    private var generatedName: String? {
        namer.name(for: workout.exercises.map(\.exercise), of: workout.id)
    }

    /// The name the workout shows: its chosen one, or else the one made for it.
    var shownName: String? {
        namer.shownName(of: workout)
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
        .onTouchDownOutsideTitle(
            onTitle: { titleTap.touchDown(.onTitle) },
            perform: { touchedDownOutsideTitle() },
        )
        .onKeyboardDown(for: $titleTap) { openPicker() }
        .endWorkoutDialog(
            isPresented: $isConfirmingEnd,
            session: session,
            end: end,
        )
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: landings)
        .sensoryFeedback(.impact(weight: .medium), trigger: setLogs)
        .sensoryFeedback(.impact(weight: .heavy), trigger: restEnds)
        .sensoryFeedback(.impact(weight: .light), trigger: sideLogs)
        .sensoryFeedback(.impact(weight: .medium), trigger: isStarting) { !$0 && $1 }
    }

    private var screen: some View {
        let generatedName = generatedName
        // Read once here, so the rows' closure holds them as values: a list crossfading out keeps
        // drawing its rows with what it had, rather than the workout it is fading into.
        let currentID = currentID
        let shown = shown
        let currentSet = shown?.currentSet
        let rows = rowParts(in: shown, current: currentID)
        let tracksRows = shown != nil || isStarting
        let underBar = underBarCut
        return ScrollView {
            // One over the other, as a crossfade has them: in the scroll view's own stack, the
            // list coming in and the one going stood one after the other.
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    EditableTitle(
                        text: Binding { workout.name } set: { workout.name = $0 },
                        isEditing: $isEditingTitle,
                        placeholder: Self.defaultName,
                        suggestion: generatedName,
                        accessibilityLabel: "Workout name",
                        accessibilityHint: "Renames the workout.",
                    )
                    .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                        // Not while the list is 0 high, as for a pass of its first layout: the
                        // title is out of sight there, and taking it ran the screen again in that
                        // frame, which SwiftUI logged as a fault per row (`rowSwipe`).
                        guard listHeight > 0 else { return }
                        // A short fade, so the small title has gone by the time the large one
                        // is out from under the bar.
                        withAnimation(.easeOut(duration: Self.barFade)) {
                            isTitleUnderBar = !isVisible
                        }
                    }
                    let equipment = workout.exercises.map(\.exercise).equipment
                    if !equipment.isEmpty {
                        Capsules(equipment.map(\.name))
                            .accessibilityIdentifier("workout.equipment")
                            .transition(.opacity)
                    }
                    Rail(
                        workout.exercises,
                        links: workout.joinedToNext,
                        arriving: arriving,
                        current: litID,
                        done: shown?.finishedRows ?? [],
                        isSetHeld: heldSet != nil,
                        pulse: railPulse,
                        restDot: restDotRow,
                        isMoving: isMovingOn,
                        onMove: move,
                        regroup: regroup,
                    ) { item in
                        rowContent(item, current: currentID, on: currentSet, parts: rows[item.id])
                            .environment(\.exerciseMoveWay, moveWay)
                            .environment(\.restSkips, restSkips.count)
                            .id(item.id)
                            .topSpace(item.id == currentID ? Self.currentTopSpace : 0)
                            // Only while it is read: as the list scrolls, every change redraws the
                            // screen.
                            .reportingPlace(item.id == growingID && tracksRows, to: placeCurrent)
                            // Until an added row has entered it takes no taps, and its frame is
                            // where it will be rather than where it is drawn, so VoiceOver and the
                            // UI tests find it once it has. On the label, the row's one element:
                            // on the row, `false` would un-hide the rail's node.
                            .accessibilityHidden(item.id == entering)
                            .railRow()
                            .reportingRailPitch(
                                isOn: notesRestingPitch(of: item.id, current: currentID),
                            ) { restingContent(item, in: shown) } to: {
                                rowFrames.restingPitch[item.id] = $0
                            }
                            // The whole row, its insets included, as the rail stacks it.
                            .reportingFrame(tracksRows) { rowFrames.tops[item.id] = $0.minY }
                            .contentShape(.rect)
                            .onTapGesture {
                                guard item.id != entering else { return }
                                session.openRowSheet(RowSheet(id: item.id))
                            }
                            // Outermost, as the system's swipe actions are, or their Remove is
                            // folded into the row's accessibility element, where VoiceOver and
                            // the UI tests never find it. The row's tap stays on where the swipe
                            // is off.
                            .swipeToDelete(item.id, isOn: item.id != currentID) { delete($0) }
                    } end: {
                        FloatingButtonRoom()
                            .onGeometryChange(for: CGFloat.self) {
                                $0.frame(in: .global).minY
                            } action: { listEnd.top = $0 }
                    }
                }
                .padding(.horizontal, Spacing.md)
                // With the floating +'s room above it, so at the end of a long list the last row
                // scrolls clear of the +.
                .padding(.bottom, Spacing.md)
                // In the content, not a margin, so the visible height the row is sized from
                // stays.
                .roomToLand(top: landingRoomTop)
                .roomBelow(isMakingRoom)
                // Outside the rail and the room under the list, which both read it.
                .listResizes(resizes)
                // When the keyboard rises, UIKit scrolls the focused field to sit at least 5pt
                // below the top of the visible area. Starting there keeps the title still.
                .padding(.top, Spacing.sm)
                // Inside the lift, so a row's place is where it lies in the content, as a scroll
                // position counts, and not where it is drawn as Start's grow runs the lift down.
                .coordinateSpace(.list)
                .clipShape(TopClip(height: underBar))
                .modifier(GrowthLift(lift: growthLift, shown: shownLift))
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
        }
        .scrollPosition($scrollPosition)
        .railAutoscroll($scrollPosition)
        // Not the whole geometry: its insets settle in several passes of a push's first frame.
        .onScrollGeometryChange(for: ScrollExtent.self, of: ScrollExtent.init) { old, new in
            keepEndInView(from: old, to: new)
            keepEndPinned(from: old, to: new)
        }
        .onScrollPhaseChange { _, phase in
            isScrollingByHand = phase == .interacting || phase == .decelerating
            scrollBeat.phaseChanged(to: phase)
            settleWayBack()
        }
        .onScrollGeometryChange(for: Bool.self, of: Self.endIsInView(of:)) { isEndInView = $1 }
        .onScrollGeometryChange(for: CGFloat.self, of: \.scrolledY) { old, new in
            scrollBeat.listMoved(to: new, asked: scrollPosition)
            // Back from past the top, where the key's role was held.
            if old < 0, new >= 0 {
                settleWayBack()
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { listHeight = $0 }
        .emptyNote("No exercises", isEmpty: workout.exercises.isEmpty)
        // Alongside the taps of what is in the list, which never reach below its end.
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tap in
            tappedList(at: tap.location)
        })
        .primaryKeyBar(
            isPresented: showsKey,
            face: liveKey.role,
            keepsRoom: phase.keyGone == .keepingRoom,
            plusOnes: setLogs + sideLogs + countBeats.ends,
            drop: startDrop,
            floatsLow: footShowsEmpty,
        ) { role, isOut in
            key(role, isOut: isOut)
        } floating: {
            addButton
        }
        .onDisappear { stopSequence() }
        .modifier(AddExerciseOnArrival(session: session))
        // Cancelled as the screen goes, so the wait never outlives it.
        .task(id: createdWait) { await showCreated() }
        .task(id: restWatch) { await watchRest() }
        .timedSets(self)
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
        .sheet(item: addExerciseOpening, content: picker)
        // By item, so the sheet keeps its content as it slides away; by opening, so each opening
        // starts from fresh state (`RowSheet.opening`).
        .sheet(item: Binding { editing } set: {
            if $0 == nil {
                session.closeRowSheet()
            }
        }) { opened in
            exerciseSheet(opened)
                .id(opened.opening)
        }
        .toolbar { barItems }
    }
}

extension WorkoutScreen {
    /// Shows the workout as the store has it, not saving it again (`showStoredWorkout`).
    func show(stored: Workout) {
        shownWorkout = stored
    }
}

#Preview {
    WorkoutScreen(
        session: AppSession(workout: Workout(), store: nil, namer: .muscleGroupsOnly),
        namer: .muscleGroupsOnly,
    )
}
