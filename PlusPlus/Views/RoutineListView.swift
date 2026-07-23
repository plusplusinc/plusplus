import SwiftUI
import SwiftData
import PlusPlusKit

/// A routine added from ANOTHER tab (Today's setup step, a share import)
/// lands on the Routines list with the same entrance flash a same-tab add
/// gets — one landing for every add (Dave, 2026-07-23; the Today setup
/// flow used to land inside the new routine's detail instead). The uuid
/// is a HANDOFF SLOT, not a notification payload: the Routines tab may
/// not be mounted yet when the add happens (a first-run setup flow), so
/// the list consumes it on appear as well as on receive — whichever
/// fires first wins, and consuming clears the slot.
@MainActor
enum RoutineArrival {
    static var pending: UUID?

    /// Stamp the arrival and announce it: RootTabView switches to the
    /// Routines tab; a mounted list consumes immediately, an unmounted
    /// one on its first appear.
    static func land(_ uuid: UUID) {
        pending = uuid
        NotificationCenter.default.post(name: .plusplusRoutineArrived, object: nil)
    }
}

/// The Routines tab, v3 (#109): routine cards with equipment pills and
/// a contextual header + (new routine). Library/History/Settings left
/// this header with the nav restructure — Exercises and Equipment are
/// tabs, history lives on Today, settings opens from Today's header.
struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var routines: [Routine]

    @State private var path = NavigationPath()
    /// Filters your routines by name (2026-07-18); the add row threads it
    /// into the catalog's search so "Add <query>" lands ready.
    @State private var searchText = ""
    @State private var openSwipeRow: SwipeRevealOpen<PersistentIdentifier>?
    /// The routine just added from a template — scrolled into view and
    /// given an entrance flash when we land back on the library, then
    /// released (Dave, 2026-07-15). Permanent id (set post-save), so it is
    /// safe as list/scroll identity.
    @State private var newlyAdded: PersistentIdentifier?
    /// Held false for one beat after an add so the new card is ABSENT from
    /// the list, then flipped true inside `withAnimation` so it fades in and
    /// the cards below slide down to make room (Dave, 2026-07-16). Reset to
    /// false where the add lands, before the list re-renders.
    @State private var revealNewCard = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                CatalogTabHeader(
                    title: "Routines",
                    // Creation moved into the list (a top row that opens the
                    // catalog); the header's top-right is the expanding search.
                    search: HeaderSearchConfig(
                        text: $searchText,
                        prompt: "Search routines",
                        identifier: "routinesSearchField"
                    )
                )

                ScrollViewReader { proxy in
                    List {
                    addRoutineRow
                    ForEach(displayedRoutines) { routine in
                        SwipeRevealRow(
                            id: routine.persistentModelID,
                            openRow: $openSwipeRow,
                            actionsWidth: 58,
                            onTap: { routine.uuid.map { path.append(RoutineRef(uuid: $0)) } },
                            accessibilityActions: [
                                SwipeRowAction(name: "Delete") {
                                    openSwipeRow = nil
                                    deleteRoutine(routine)
                                }
                            ]
                        ) {
                            RoutineCard(routine: routine, justAdded: routine.persistentModelID == newlyAdded)
                        } actions: {
                            SwipeActionButton(label: "DELETE", color: Theme.destructive) {
                                openSwipeRow = nil
                                deleteRoutine(routine)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .transition(.opacity)
                    }
                        .onMove(perform: moveRoutines)
                    if displayedRoutines.isEmpty {
                        routinesEmptyHint
                    }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    // A template add pops back here and sets newlyAdded;
                    // let the pop settle, then scroll the new card into
                    // view (it lands at order 0 = top, but the list may
                    // have been scrolled) and release so the entrance
                    // flash can retrigger on the next add. Lifecycle-bound
                    // via .task(id:): leaving the tab or a rapid second add
                    // cancels this in flight, and the throwing sleeps bail
                    // in the catch WITHOUT clearing newlyAdded — so a
                    // superseding add keeps its own highlight (the repo's
                    // cancel-deferred-UI-on-disappear law, ui-interaction.md).
                    .task(id: newlyAdded) {
                        guard let id = newlyAdded else { return }
                        do {
                            // Beat of absence: the card is held out of the
                            // list (revealNewCard == false) so the eye sees
                            // the row OPEN, not one that was already sitting
                            // there.
                            try await Task.sleep(for: .milliseconds(300))
                            withAnimation(Theme.Anim.flourish(.easeOut(duration: 0.3))) {
                                revealNewCard = true      // fade in + push the rest down
                            }
                            // Let the fade begin, then bring the card into view.
                            try await Task.sleep(for: .milliseconds(60))
                            withAnimation(Theme.Anim.standard) {
                                proxy.scrollTo(id, anchor: .top)
                            }
                            try await Task.sleep(for: .milliseconds(1600))
                        } catch {
                            // Cancelled (tab left, or a superseding add whose
                            // callback already reset the flags): leave state
                            // alone so the newer add keeps its own entrance.
                            return
                        }
                        newlyAdded = nil
                    }
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            // A plain push, no hero zoom (Dave, build 37): the #216 zoom
            // made list -> detail read as a custom cover rather than a
            // navigation push. Today's zooms (committed card -> record,
            // pending card -> workout cover) are unchanged.
            .navigationDestination(for: RoutineRef.self) { ref in
                // Resolve the routine from its stable uuid (not by pushing
                // the @Model, whose persistentModelID can swap under the
                // push). A just-created routine resolves via a direct fetch.
                if let routine = modelContext.routine(uuid: ref.uuid) {
                    RoutineDetailView(routine: routine)
                }
            }
            // Registered at the stack root, NOT inside RoutineCatalogScreen:
            // a value destination declared on a screen that is itself pushed
            // (the catalog rides navigationDestination(isPresented:)) failed
            // to resolve in production — template taps hit SwiftUI's
            // missing-destination placeholder (build 33).
            .navigationDestination(for: RoutineTemplate.self) { template in
                RoutineTemplateDetailScreen(template: template, path: $path) { routine in
                    // A template is complete on arrival, so return to the
                    // library with the new card highlighted rather than
                    // pushing into an empty-feeling detail (Dave,
                    // 2026-07-15). Popping the whole path also clears the
                    // catalog beneath, so Back is never stranded.
                    revealNewCard = false     // hold the card out for the entrance beat
                    newlyAdded = routine.persistentModelID
                    path = NavigationPath()
                }
            }
            // No dead-end empty overlay: the add row is always the first
            // list row, and an empty list shows an inline hint beneath it.
            // The + pushes the routine catalog (#223) — the same
            // grammar as the library tabs: adding starts from a
            // browsable catalog, with blank creation as its first row.
            // A PATH entry, not isPresented (Dave, build 44): the
            // catalog appends templates/routines to this same path,
            // and a value appended beneath a boolean-presented screen
            // replaces it transition-less and double-pops on back.
            .navigationDestination(for: RoutineCatalogDestination.self) { dest in
                RoutineCatalogScreen(path: $path, initialQuery: dest.query)
            }
        }
        .revealRoot(tab: "routines", atRoot: path.isEmpty)
        // Operator's outcome navigation: a touched routine pushes by its
        // stable uuid (RoutineRef is registered at this stack root, per
        // the #262/#291 laws). The path resets first so the result is
        // one Back from the list, never stacked under stale screens.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusOperatorShow)) { note in
            guard let destination = note.object as? OperatorDestination,
                  case .routine(let uuid) = destination
            else { return }
            path = NavigationPath()
            path.append(RoutineRef(uuid: uuid))
        }
        // A cross-tab add (Today's setup, a share import) lands HERE with
        // the entrance flash — consumed on receive when mounted, on appear
        // when this tab mounts for the first time because of the add.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusRoutineArrived)) { _ in
            consumeArrival()
        }
        .onAppear(perform: consumeArrival)
        // Routine creates / deletes / reorders reach GitHub when you leave the
        // tab. Debounced + dirty-gated (see requestSync).
        .syncsProgramOnClose()
    }

    /// The Add row (Add family): it NAVIGATES to the catalog (browse
    /// templates + blank create), so "Add routine" / Add "<query>", never
    /// "New" (which would imply an inline create). Keeps the
    /// `newRoutineButton` id so the smoke flows still open the catalog here.
    private var addRoutineLabel: String {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? "Add routine" : "Add \u{201C}\(q.sentenceCasedFirst)\u{201D}"
    }

    private var addRoutineRow: some View {
        CreateRow(label: addRoutineLabel, identifier: "newRoutineButton") {
            // Root-only affordance, so emptiness doubles as the double-tap
            // guard: a second tap during the push must not stack a second
            // catalog.
            guard path.isEmpty else { return }
            path.append(RoutineCatalogDestination(query: searchText.trimmingCharacters(in: .whitespaces)))
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
    }

    /// Land a cross-tab add: pop to the list and play the same held-out
    /// entrance a same-tab template add gets. The slot clears BEFORE
    /// resolution — every landing path saves before posting, so a miss
    /// means a stale/deleted routine, and holding the slot would fire a
    /// phantom path-reset on some much later visit (swift-reviewer).
    private func consumeArrival() {
        guard let uuid = RoutineArrival.pending else { return }
        RoutineArrival.pending = nil
        guard let routine = modelContext.routine(uuid: uuid) else { return }
        path = NavigationPath()
        revealNewCard = false     // hold the card out for the entrance beat
        newlyAdded = routine.persistentModelID
    }

    private var routinesEmptyHint: some View {
        VStack(spacing: 10) {
            Text(searchText.trimmingCharacters(in: .whitespaces).isEmpty
                 ? "No routines yet. Add one to get started."
                 : "Nothing matches.")
                .font(.system(.footnote))
                .foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// The list, minus the just-added card while it's still held out for its
    /// entrance (revealNewCard == false), narrowed by the header search.
    /// Once `newlyAdded` clears and the query is empty, both filters are a
    /// no-op, so the steady state shows everything.
    private var displayedRoutines: [Routine] {
        let base = routines.filter { $0.persistentModelID != newlyAdded || revealNewCard }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        return FuzzySearch.ranked(base, query: q) { $0.name }
    }

    private func deleteRoutine(_ routine: Routine) {
        modelContext.delete(routine)
        reindexRoutines()
    }

    private func moveRoutines(from source: IndexSet, to destination: Int) {
        // Reordering a fuzzy-ranked search result would scramble `order`;
        // manual arrangement only makes sense on the full, unsearched list.
        guard searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // Reorder over the SAME collection the ForEach displays: `.onMove`
        // hands indices into `displayedRoutines`, so basing the move on the
        // full `routines` would mis-map during the brief entrance window
        // where the two diverge. In the steady state they're identical.
        var reordered = displayedRoutines
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, routine) in reordered.enumerated() {
            routine.order = index
        }
    }

    private func reindexRoutines() {
        for (index, routine) in routines.enumerated() {
            routine.order = index
        }
    }
}

/// 44 pt rounded-square raised icon key used in tab/pushed/sheet headers
/// (Quiet Arcade: header icon buttons are neutral secondary keys —
/// supersedes #202's green header +; green's scope tightened to true data
/// and in-list creation rows). Rounded squares (radius 11) are the app's
/// one key shape everywhere — Dave reverted the brief all-circles round
/// (2026-07-19) and the sheet-corner concentric experiment (2026-07-19,
/// the uneven corners read wrong).
struct HeaderIconButton: View {
    let systemImage: String
    /// Spoken VoiceOver name for the action (required — the glyph alone reads
    /// as its raw SF Symbol name, e.g. "slider horizontal 3").
    let accessibilityLabel: String
    var identifier: String?
    /// Glyph tint; defaults to the neutral header ink. The favorite star
    /// passes `Theme.accent` when lit (green = the user's own data).
    var tint: Color = Theme.textSecondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(.raisedKey())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier ?? systemImage)
    }
}

/// Plain content, deliberately NOT a Button: activation belongs to
/// SwipeRevealRow's onTap (see the component contract — a Button here
/// fired on reveal-drag release and closed the row it opened).
private struct RoutineCard: View {
    let routine: Routine
    /// True for the routine just added from a template — plays a one-shot
    /// entrance flash so the eye lands on it (Dave, 2026-07-15).
    var justAdded: Bool = false
    /// 1 at the peak of the entrance flash, animating to 0 at rest.
    @State private var entrance: Double = 0
    /// The deferred flash beat (it fires just after the card fades in);
    /// cancelled on disappear so it can't light onto a recycled row.
    @State private var flashTask: Task<Void, Never>?
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    private var availableEquipmentNames: Set<String> {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)?.memberNames ?? []
    }

    var body: some View {
        // The shared metadata body (title · one meta line · equipment tags) —
        // the same vocabulary the catalog card and detail header render
        // (2026-07-22), so a routine reads the same everywhere. The tags are
        // inert here: the whole card is the tap target.
        RoutineCardContent(
            title: routine.name,
            meta: RoutineMeta(routine: routine, activeNames: availableEquipmentNames)
        )
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        // Entrance: the green (creation) ring lights just AFTER the card has
        // faded into the list (the list handles the fade + push-down), then
        // fades out. No scaling — a card scaled past its row width clipped
        // its own edges until it settled (Dave, 2026-07-16).
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.accent, lineWidth: 2)
                .opacity(entrance)
        )
        .onChange(of: justAdded, initial: true) { _, isNew in
            guard isNew else { return }
            flashTask?.cancel()
            flashTask = Task { @MainActor in
                // Let the fade-in land before the ring lights.
                try? await Task.sleep(for: .milliseconds(340))
                guard !Task.isCancelled else { return }
                entrance = 1
                // Deliberately NOT gated on Reduce Motion: this is a pure
                // opacity fade (fades are fine under RM, per the Anim token
                // docs), and it carries information — which card just landed.
                // An instant disappear would erase the signal, not the motion.
                withAnimation(.easeOut(duration: 0.9)) { entrance = 0 }
            }
        }
        .onDisappear { flashTask?.cancel() }
    }
}
