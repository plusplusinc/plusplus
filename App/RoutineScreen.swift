import DesignSystem
import OSLog
import SwiftUI
import WorkoutStore

/// The screen the app launches into: the routine being edited, or a new one.
///
/// Every change saves on its own, with no drafts. A new routine is saved once something is put
/// in it, and deleted once it is cleared back to nothing.
struct RoutineScreen: View {
    @State private var routine: Routine
    /// Nil when the store didn't open: the screen works, and nothing saves.
    private let store: RoutineStore?
    private let namer: RoutineNamer
    /// Where every change to the routine goes, to be saved one at a time in the order they
    /// happened, so an older version can never land last. The save task sets it, since a stream
    /// is spent once its task ends, and a task run again needs a new one.
    @State private var saves: AsyncStream<Routine>.Continuation?
    @State private var isPicking = false
    /// The row whose sheet is open.
    @State private var editing: Edited?
    /// The row the sheet's Delete removes once the sheet is down, so its fade is seen.
    @State private var deleting: RoutineExercise.ID?
    @State private var scrollPosition = ScrollPosition()
    /// The row just added, holding its place until it can be seen going in.
    @State private var arriving: RoutineExercise.ID?
    /// Whether Add exercise, at the list's end, is fully in view.
    @State private var isEndInView = true
    /// While an added row's place opens, the list's end stays put on screen: as the content grows
    /// past the visible area, it scrolls in step (`keepEndInView`).
    @State private var isOpeningPlace = false
    /// Whether the list is being scrolled by hand, which the in-step scroll leaves alone.
    @State private var isScrollingByHand = false
    /// Whether the title has scrolled up under the bar, where a small copy of it shows instead.
    @State private var isTitleUnderBar = false
    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    private static let markWidth: CGFloat = 20
    /// A plus sits on the font's math axis, about a point below the middle of its line, so the
    /// mark is lifted to look centered in the round button.
    private static let markLift: CGFloat = 1

    private static let defaultName = String(localized: "New routine")

    init(routine: Routine, store: RoutineStore?, namer: RoutineNamer) {
        _routine = State(initialValue: routine)
        self.store = store
        self.namer = namer
    }

    /// The name made for the routine from its exercises, which a chosen name hides and which
    /// clearing it brings back. Not stored: made again from the same exercises, it is the same
    /// name, so it is the same after a relaunch.
    private var generatedName: String? {
        namer.name(for: routine.exercises.map(\.exercise), of: routine.id)
    }

    var body: some View {
        let generatedName = generatedName
        // The name the title shows: chosen, else generated, else none.
        let shownName = routine.name.isEmpty ? generatedName : routine.name
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    EditableTitle(
                        text: $routine.name,
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
                    Rail(routine.exercises, arriving: arriving) { item in
                        Button {
                            editing = Edited(id: item.id)
                        } label: {
                            RowLabel(
                                title: item.exercise.name,
                                detail: item.detailParts(locale: locale),
                                spokenDetail: item.spokenDetail(locale: locale),
                                showsSides: item.exercise.isPerSide,
                            )
                            .railRow()
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("routine.exercise")
                        .accessibilityHint("Opens its plan.")
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    withAnimation(.railChange) {
                                        routine.exercises.removeAll { $0.id == item.id }
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
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }, action: keepEndInView)
            .onScrollPhaseChange { _, phase in
                isScrollingByHand = phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(
                for: Bool.self,
                of: Self.endIsInView(of:),
                action: { _, isInView in isEndInView = isInView },
            )
            .primaryKeyBar(isPresented: !routine.exercises.isEmpty) {
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
            .sheet(item: $editing, onDismiss: removeDeleted) { edited in
                if let row = row(edited.id) {
                    ExerciseSheet(item: row) { deleting = edited.id }
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
        // `onChange` skips the first value, so a routine opened and left alone is never saved.
        .onChange(of: routine) { _, changed in
            saves?.yield(changed)
        }
        .task {
            // Only the newest unsaved version waits.
            let (stream, continuation) = AsyncStream.makeStream(
                of: Routine.self,
                bufferingPolicy: .bufferingNewest(1),
            )
            saves = continuation
            for await version in stream {
                do {
                    try await store?.save(version)
                } catch {
                    Logger.app.error("The routine didn't save: \(error)")
                }
            }
        }
        .hotReloadable()
    }

    /// The row with `id`, bound into the routine, so the sheet's changes save as they happen;
    /// nil once it is gone.
    private func row(_ id: RoutineExercise.ID) -> Binding<RoutineExercise>? {
        guard let current = routine.exercises.first(where: { $0.id == id }) else { return nil }
        return Binding {
            routine.exercises.first { $0.id == id } ?? current
        } set: { changed in
            guard let index = routine.exercises.firstIndex(where: { $0.id == id }) else { return }
            routine.exercises[index] = changed
        }
    }

    private func removeDeleted() {
        guard let id = deleting else { return }
        deleting = nil
        withAnimation(.railChange) {
            routine.exercises.removeAll { $0.id == id }
        }
    }

    /// Adds a picked exercise. Its row takes its place as the sheet starts down, moving Add
    /// exercise, but enters only where it can be seen: a moment into the sheet's slide when
    /// everything still fits, and otherwise once a scroll to the end has brought the row and Add
    /// exercise into view. The scroll waits for the row's place: asked for while the row went in,
    /// it stopped at the end the list had before.
    private func add(_ exercise: Exercise) {
        let row = RoutineExercise(exercise: exercise)
        arriving = row.id
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
        // `scrollTo(y:)` counts from the top of the content, not from above the top inset.
        let end = new.contentSize.height - new.containerSize.height
        guard end > new.contentOffset.y + new.contentInsets.top else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollPosition.scrollTo(y: end)
        }
    }

    /// Whether the list's end, Add exercise, is in view. The container is the area between the
    /// bars, and the offset counts from above the top one.
    private static func endIsInView(of geometry: ScrollGeometry) -> Bool {
        let visibleEnd = geometry.contentOffset.y + geometry.contentInsets.top
            + geometry.containerSize.height
        return geometry.contentSize.height <= visibleEnd.rounded(.up)
    }

    /// Lets `row` enter, unless a later add has taken its place as the arriving row.
    private func letArrivingEnter(_ row: RoutineExercise) {
        guard arriving == row.id else { return }
        var transaction = Transaction()
        transaction.isRailEntry = true
        // A later add, its row arriving, keeps the scroll in step for its own place.
        transaction.addAnimationCompletion { isOpeningPlace = arriving != nil }
        withTransaction(transaction) {
            arriving = nil
        }
    }
}

/// The row whose sheet is open, by id, since a sheet presents an identifiable item.
private struct Edited: Identifiable {
    let id: RoutineExercise.ID
}

#Preview {
    RoutineScreen(routine: Routine(), store: nil, namer: .muscleGroupsOnly)
}
