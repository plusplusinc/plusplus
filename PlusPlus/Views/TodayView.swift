import Foundation
import SwiftUI
import SwiftData
import PlusPlusKit

/// Today — the unified timeline (#110, Claude Design v3 §3): pending
/// (staged) routines on top, committed sessions below, one scroll on a
/// continuous rail. A pending entry is a routine the schedule says is
/// due (one entry per routine, max — a missed day carries over until
/// the next occurrence supersedes it). Committed entries are the
/// append-only record; no delete affordances, ever.
///
/// A fresh install's timeline IS the onboarding (setup-as-timeline
/// handoff): three setup steps render as gated entries stacked
/// bottom-up like commits — equipment at the bottom, then first
/// routine, then schedule — each becoming a committed-style card when
/// done. The scaffold lives until the first real session commits.
struct TodayView: View {
    /// Switches the root to the Routines tab (the done routine-step
    /// card's edit affordance).
    var onGoToRoutines: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    /// Pending (today's) card sits on a translucent surface; under Reduce
    /// Transparency it goes opaque so its caption text keeps contrast.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var routines: [Routine]
    @Query(sort: \Equipment.name) private var equipment: [Equipment]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""
    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]
    )
    private var sessions: [WorkoutSession]

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    @State private var showingSwapIn = false
    @State private var swapInPick: Routine?
    /// Programmatic pushes (#208: land in a routine created from the
    /// swap-in tray).
    @State private var todayPath = NavigationPath()
    @State private var showingNewRoutine = false
    @State private var pendingCreateFromSwapIn = false
    @State private var pendingStartEmpty = false
    @State private var newRoutineName = ""
    /// Hero zooms (#216): starting a workout grows the pending card
    /// into the session screen; a committed card grows into its
    /// record. Off-card starts (swap-in, Siri) have no source and fall
    /// back to the system transition on their own.
    @Namespace private var zoomNamespace
    @State private var showingEquipmentSetup = false
    /// Nonzero presents the populate-offer alert (#204); computed at
    /// present time from the store, never carried stale.
    @State private var populateOfferCount = 0
    @State private var scheduleEditTarget: IdentifiedUUID?
    @State private var activeSession: WorkoutSession?
    /// Bumped on day change so every Date()-based computed re-evaluates
    /// — without it, an app resident overnight keeps rendering
    /// yesterday's due list (bug hunt).
    @State private var dayToken = 0
    @State private var sync = GitHubSyncCoordinator.shared
    /// Transient pull-to-refresh confirmation (a sync result, or a quip when
    /// there's nothing to sync). Cleared automatically by the toast.
    @State private var refreshMessage: String?
    /// One-shot: the timeline anchors to today's content on FIRST
    /// appearance only (#267) — re-appearances mid-session (returning
    /// from a workout cover, tab hops) must not yank the scroll
    /// position. Day changes re-anchor separately via dayToken.
    @State private var hasAnchoredToday = false
    /// The workout just finished (its recap closed), awaiting the
    /// pending→done conversion flourish on its committed card. Nil
    /// outside the beat.
    @State private var justCompletedID: PersistentIdentifier?
    /// Flips true a beat after landing on Today: the just-finished
    /// card's node completes its green→purple turn and the checkmark
    /// seals it. False both before the turn and after it settles.
    @State private var completionConverted = false

    /// The zero-height marker the opening scroll anchors to — today's
    /// content top-aligns here, with the week ahead above it (#267).
    private static let todayAnchorID = "todayAnchor"

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }
    private var calendar: Calendar { Calendar.current }

    /// Startable routines for the start tray (#208): empty routines
    /// can't stage (the 0-set-session bug class), so they don't appear.
    /// The rest-day card still gates on candidates existing; the header
    /// start button (#266) opens the tray unconditionally — its create
    /// and empty-workout rows carry the no-candidates case.
    private var swapInCandidates: [Routine] {
        routines.filter { !$0.groups.isEmpty }
    }

    /// Mirrors RoutineListView's create flow, then lands in the new
    /// routine so exercises can be added immediately (#208).
    private func createRoutine() {
        let name = newRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
        newRoutineName = ""
        guard !name.isEmpty else { return }
        let routine = Routine(name: Routine.uniqueName(name, among: routines), order: 0)
        modelContext.insert(routine)
        for existing in routines where existing !== routine {
            existing.order += 1
        }
        // Push by stable uuid, resolved in the destination (ModelRefs) — the
        // nav path no longer depends on the swappable persistentModelID. The
        // save keeps the routine durable before it's navigated to.
        try? modelContext.save()
        routine.uuid.map { todayPath.append(RoutineRef(uuid: $0)) }
    }

    var body: some View {
        NavigationStack(path: $todayPath) {
            VStack(spacing: 0) {
                header

                // The viewport height feeds the below-anchor min height
                // (#267 follow-up): bound synchronously through the
                // GeometryReader so today's region is already a screen
                // tall on the FIRST layout — the opening scrollTo then
                // always has room to seat today at the very top, even on
                // a short fresh-install timeline that couldn't otherwise
                // scroll the week ahead off-screen.
                GeometryReader { viewport in
                    ScrollViewReader { proxy in
                        ScrollView {
                            // The week ahead rides ABOVE today (#267) in a
                            // plain VStack: laziness above the anchor would
                            // give the opening scrollTo estimated heights to
                            // aim at (a LazyVStack sizes unrealized content
                            // approximately, so an anchor below lazy rows
                            // can land off by their estimation error). The
                            // future section is small by construction — at
                            // most a summary block plus 7 days of occurrence
                            // cards — so eager layout is cheap; the
                            // committed history below the anchor stays lazy.
                            VStack(spacing: 0) {
                                if showsFutureSection {
                                    futureSection
                                }
                                // The opening anchor: today's content
                                // top-aligns here; the week above is
                                // reachable by scrolling up.
                                Color.clear
                                    .frame(height: 0)
                                    .id(Self.todayAnchorID)
                                // Lazy: the committed section is the whole
                                // history — eager building made every render
                                // O(sessions) (bug hunt perf finding).
                                LazyVStack(spacing: 0) {
                                    // The date lives here now (Dave's ask),
                                    // on the item it names — and it's the
                                    // line the opening scroll lands on.
                                    todayMarker
                                    // The rest-day item yields to the setup scaffold
                                    // until a startable routine exists — "nothing
                                    // scheduled" and "schedule it (3 of 3)" saying
                                    // the same thing twice reads broken. Once a
                                    // routine CAN start, the item returns (#246):
                                    // scheduling is optional and must not read as
                                    // the only path to working out. It also yields
                                    // when carried-over work exists (2026-07-14):
                                    // the CARRIED OVER lane is the actionable
                                    // surface then, so a "rest day · start whenever"
                                    // line above it would read as a blind claim.
                                    if dueRoutines.isEmpty && missedEntries.isEmpty
                                        && (!setupActive || allSetupDone || !swapInCandidates.isEmpty) {
                                        restDayItem
                                    }
                                    ForEach(dueButEmptyRoutines) { routine in
                                        // Inert grey by intent: the ROUTINE isn't
                                        // startable — the card's CTA repairs, it
                                        // doesn't perform (rail grammar call).
                                        TimelineItem(node: .inert) {
                                            emptyRoutineCard(routine)
                                        }
                                    }
                                    ForEach(dueRoutines) { routine in
                                        TimelineItem(node: .pending) {
                                            pendingCard(routine)
                                                .matchedTransitionSource(id: routine.persistentModelID, in: zoomNamespace)
                                        }
                                    }
                                    if setupActive {
                                        setupSection
                                    }
                                    // Carried-over occurrences (Kit .missed):
                                    // a past scheduled day that lapsed, shown
                                    // calmly between today's work and the
                                    // history below — never as a green due, and
                                    // never dressed up as today's date.
                                    if !missedEntries.isEmpty {
                                        carriedOverSection
                                    }
                                    ForEach(sessions) { session in
                                        // The just-finished session converts
                                        // on landing (recap-close animation):
                                        // its node turns from actionable green
                                        // to done purple and a checkmark seals
                                        // it. Every other committed card is a
                                        // plain purple ring.
                                        let converting = justCompletedID == session.persistentModelID
                                        TimelineItem(
                                            node: .committed,
                                            strokeOverride: converting
                                                ? (completionConverted ? Theme.committedFill : Theme.accent)
                                                : nil,
                                            showCheckmark: converting && completionConverted
                                        ) {
                                            committedCard(session)
                                                .scaleEffect(converting && !completionConverted ? 0.97 : 1.0)
                                        }
                                    }
                                }
                                // Pad the below-anchor region to at least a
                                // screen so today can always scroll to the
                                // top (see the GeometryReader note); taller
                                // timelines make this a no-op.
                                .frame(minHeight: viewport.size.height, alignment: .top)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                        .refreshable {
                            // Honest refresh (#267): due-ness is pure local
                            // computation keyed on the clock, so bumping the
                            // token re-derives everything instantly.
                            dayToken += 1
                            // #23: pull-to-refresh now also syncs GitHub. The
                            // spinner should stay up only while there's real
                            // work — so we await the sync ONLY when connected.
                            // Disconnected, there's nothing to fetch, so we skip
                            // the network (the spinner snaps back) and reward the
                            // gesture with a little delight instead of nothing.
                            if !sync.isConnected {
                                // Nothing to fetch — skip the network (the
                                // spinner snaps back) and reward the pull with a
                                // little delight instead of a dead gesture.
                                refreshMessage = RefreshQuip.random()
                            } else if sync.isSyncing {
                                // A pass is already running (foreground or Sync
                                // now). sync() is single-flight, so this call
                                // would no-op — don't report a result it didn't
                                // produce (that would show a stale summary).
                                refreshMessage = "Syncing…"
                            } else {
                                let units = WeightUnit(rawValue: weightUnitRaw) ?? .lb
                                await sync.sync(context: modelContext, units: units)
                                if case .error = sync.activity {
                                    refreshMessage = "Couldn't sync. Try again."
                                } else {
                                    refreshMessage = sync.lastSyncSummary ?? "Synced"
                                }
                            }
                        }
                        .onAppear {
                            // Only seat once the GeometryReader has a real
                            // height — the below-anchor min height must have
                            // grown the region before there's room to push
                            // the week ahead off-screen. If height is still
                            // pending, the onChange below fires the anchor.
                            guard !hasAnchoredToday, viewport.size.height > 0 else { return }
                            hasAnchoredToday = true
                            // Unanimated: Today OPENS at today; the week
                            // above is something you go looking for.
                            proxy.scrollTo(Self.todayAnchorID, anchor: .top)
                        }
                        .onChange(of: viewport.size.height) { _, height in
                            // GeometryReader can publish the real height a
                            // beat after onAppear; seat today the instant we
                            // have room. One-shot via hasAnchoredToday, so a
                            // later height change (rotation, keyboard) never
                            // yanks a scroll the user has since moved.
                            guard !hasAnchoredToday, height > 0 else { return }
                            hasAnchoredToday = true
                            proxy.scrollTo(Self.todayAnchorID, anchor: .top)
                        }
                        .onChange(of: dayToken) {
                            // A new day moves "today" — re-anchor. (This
                            // also runs after pull-to-refresh: the gesture
                            // asks for a fresh Today, and Today opens at
                            // today.) Next runloop, not mid-update: the new
                            // day's content must lay out before the anchor
                            // frame it scrolls to is real.
                            Task { @MainActor in
                                proxy.scrollTo(Self.todayAnchorID, anchor: .top)
                            }
                        }
                        .onChange(of: showsFutureSection) { _, shows in
                            // The week ahead can pop in mid-lifetime (the
                            // last setup step completing, the first
                            // schedule being created) — content inserted
                            // above the viewport shoves today's cards
                            // down-screen. Re-anchor so today stays on top.
                            guard shows else { return }
                            Task { @MainActor in
                                proxy.scrollTo(Self.todayAnchorID, anchor: .top)
                            }
                        }
                    }
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: RoutineRef.self) { ref in
                // Resolve by stable uuid, not by pushing the @Model (whose
                // persistentModelID can swap under the push) — see ModelRefs.
                if let routine = modelContext.routine(uuid: ref.uuid) {
                    RoutineDetailView(routine: routine)
                }
            }
            .navigationDestination(for: SessionRecordDestination.self) { destination in
                // "Do it again" starts from INSIDE the record, state
                // local to that screen — routing it through this
                // view's start() parked the deferred fire's state on
                // a surviving screen, where a mid-pop drop would have
                // wedged the cover for good (swift-reviewer catch).
                //
                // Plain push, NOT a zoom (Dave, build-48): the record
                // now opens with the same standard slide as tapping a
                // pending/upcoming card into routine detail — the two
                // navigations felt different and the plain push won.
                SessionDetailView(session: destination.session)
            }
            // Registered at the stack root, NOT inside RoutineCatalogScreen
            // (pushed below for setup step 2): a value destination declared
            // on a screen that is itself pushed failed to resolve in
            // production — template taps hit SwiftUI's missing-destination
            // placeholder (build 33).
            .navigationDestination(for: RoutineTemplate.self) { template in
                RoutineTemplateDetailScreen(template: template, path: $todayPath) { routine in
                    // Today has no routines list to return to, so keep the
                    // land-in-the-new-routine feedback — but COLLAPSE the
                    // catalog + template out from beneath it (like
                    // createBlankRoutine), so the detail sits directly on
                    // Today's root and Back — or a delete from its settings —
                    // returns to the timeline instead of stranding the user
                    // on the template/catalog level (Dave, 2026-07-15).
                    guard let uuid = routine.uuid else { return }
                    var collapsed = NavigationPath()
                    collapsed.append(RoutineRef(uuid: uuid))
                    todayPath = collapsed
                }
            }
            .sheet(isPresented: $showingSwapIn, onDismiss: {
                // Start only once the sheet is fully gone: dismissing a
                // sheet and presenting a cover in one transaction can
                // drop the presentation — with the session already
                // inserted, that left an invisible orphan (bug hunt).
                if let routine = swapInPick {
                    swapInPick = nil
                    start(routine)
                } else if pendingCreateFromSwapIn {
                    pendingCreateFromSwapIn = false
                    showingNewRoutine = true
                } else if pendingStartEmpty {
                    pendingStartEmpty = false
                    startEmptySession()
                }
            }) {
                SwapInSheet(routines: swapInCandidates, dueIDs: Set(dueRoutines.map(\.persistentModelID)), onPick: { routine in
                    swapInPick = routine
                    showingSwapIn = false
                }, onCreate: {
                    // Same drop class as swapInPick above: the alert
                    // waits for the sheet to finish dismissing.
                    pendingCreateFromSwapIn = true
                    showingSwapIn = false
                }, onStartEmpty: {
                    pendingStartEmpty = true
                    showingSwapIn = false
                })
            }
            .fullScreenCover(item: $activeSession, onDismiss: resolveOrphanedSessions) { session in
                // The card→session zoom is deliberate large-scale motion, so
                // Reduce Motion gets the plain cross-fade cover instead
                // (WCAG 2.3.3).
                if Theme.Anim.reduceMotion {
                    ActiveSessionView(session: session)
                } else {
                    ActiveSessionView(session: session)
                        .navigationTransition(.zoom(
                            sourceID: session.routine?.persistentModelID ?? session.persistentModelID,
                            in: zoomNamespace
                        ))
                }
            }
            .navigationDestination(isPresented: $showingEquipmentSetup) {
                CatalogBrowseScreen(kind: .equipment, setupMode: true, offersPopulateOnDone: true)
            }
            // The populate offer, asked from home ground (#204): the
            // catalog's Done raises a one-shot flag and dismisses; the
            // question waits here, anchored, with a live count.
            .onChange(of: showingEquipmentSetup) { _, showing in
                guard !showing, SetupState.consumePopulateOffer() else { return }
                // Next runloop, not mid-pop-transition: presenting in
                // the same transaction as a navigation change is the
                // documented drop class (see the swap-in sheet note).
                Task { @MainActor in
                    populateOfferCount = SeedData.populateCandidateCount(context: modelContext)
                }
            }
            .alert(
                // "your equipment supports" right after "Done ·
                // bodyweight only" reads as a mistake (FTUE audit).
                !(activeLibrary?.members.isEmpty ?? true)
                    ? "Add \(populateOfferCount) exercise\(populateOfferCount == 1 ? "" : "s") your equipment supports?"
                    : "Add \(populateOfferCount) exercise\(populateOfferCount == 1 ? " that needs" : "s that need") no equipment?",
                isPresented: Binding(
                    get: { populateOfferCount > 0 },
                    set: { if !$0 { populateOfferCount = 0 } }
                )
            ) {
                Button("Add them") {
                    SeedData.populateLibraryFromEquipment(context: modelContext)
                    populateOfferCount = 0
                }
                Button("Start empty", role: .cancel) {
                    populateOfferCount = 0
                }
            } message: {
                Text("Skipping is fine — the catalog stays a tap away, and anything you use joins your library on its own.")
            }
            // Step 2 IS the routine catalog (#246): search, facets,
            // honest gear checks, blank creation as its first row, and
            // Add lands in the new routine — the two-option seeder
            // sheet (whose starter split degraded to one exercise per
            // routine at zero gear) died in its favor. A PATH entry,
            // not isPresented (Dave, build 44): the catalog appends
            // templates/routines to this same path, and a value
            // appended beneath a boolean-presented screen replaces it
            // transition-less and double-pops on back.
            .navigationDestination(for: RoutineCatalogDestination.self) { _ in
                RoutineCatalogScreen(path: $todayPath)
            }
            .alert("New Routine", isPresented: $showingNewRoutine) {
                TextField("Name", text: $newRoutineName)
                Button("Cancel", role: .cancel) { newRoutineName = "" }
                Button("Create") { createRoutine() }
            }
            .navigationDestination(item: $scheduleEditTarget) { ref in
                if let routine = modelContext.routine(uuid: ref.id) {
                    RoutineSettingsScreen(routine: routine) {
                        scheduleEditTarget = nil
                        Task { @MainActor in
                            modelContext.delete(routine)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                dayToken += 1
            }
            // Crash-orphans from a previous launch get salvaged here;
            // in-flight dismissal paths are covered by the cover's
            // onDismiss.
            .onAppear(perform: resolveOrphanedSessions)
            .onReceive(NotificationCenter.default.publisher(for: .plusplusStartRoutine)) { note in
                guard activeSession == nil,
                      let name = note.object as? String,
                      let routine = routines.first(where: { $0.name.lowercased() == name.lowercased() })
                else { return }
                start(routine)
            }
            // A finished workout's recap just closed: pop to the Today
            // root (the session may have started from a pushed screen)
            // and convert its committed card to done.
            .onReceive(NotificationCenter.default.publisher(for: .plusplusWorkoutFinished)) { note in
                guard let id = note.object as? PersistentIdentifier else { return }
                if !todayPath.isEmpty { todayPath = NavigationPath() }
                playCompletionConversion(for: id)
            }
        }
        // Equipment setup pushes via isPresented (not the path), so factor it
        // into root-ness or swipe-to-open would fight its swipe-back.
        .revealRoot(tab: "today", atRoot: todayPath.isEmpty && !showingEquipmentSetup)
        // Pull-to-refresh confirmation (sync result, or a quip when there's
        // nothing to sync). Self-clears.
        .toast($refreshMessage)
    }

    /// The pending→done conversion, staged so it reads as a sequence:
    /// the card lands looking still-active (green node, a hair small),
    /// then a beat later the node turns purple and a checkmark seals it,
    /// then it settles into the resting committed look. A completion
    /// flourish, so it runs slower than the app's 0.15 s selection/nav
    /// motion on purpose (the grammar's "completion" beat — the recap's
    /// own checkmark bounces too); DECISIONS.md 2026-07-11 logs the
    /// exception. The 0.35 s lead matches the finish cover's dismiss so
    /// the turn plays in full view, not behind the pull-away.
    private func playCompletionConversion(for id: PersistentIdentifier) {
        // Pre-state set WITHOUT animation, and safe only because the only
        // caller (the recap close) fires while the full-screen cover
        // still covers Today — the purple→green reset is invisible. A
        // future caller firing over a visible Today would blink; wrap
        // this in a transaction if that ever becomes a path.
        justCompletedID = id
        completionConverted = false
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.35))
            guard justCompletedID == id else { return }
            withAnimation(Theme.Anim.flourish(.spring(response: 0.4, dampingFraction: 0.7))) {
                completionConverted = true
            }
            try? await Task.sleep(for: .seconds(0.8))
            // A newer finish supersedes this one — don't clear its beat.
            guard justCompletedID == id else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                justCompletedID = nil
                completionConverted = false
            }
        }
    }

    /// Reading this in the timeline ties the render to day rollovers.
    private var today: Date {
        _ = dayToken
        return Date()
    }

    /// A session that never reached Finish/Discard (a dismissal path
    /// that skipped the exit dialog — e.g. an interactive zoom
    /// dismiss — or a mid-workout crash on a previous launch) has
    /// endedAt == nil, which every timeline/history query filters
    /// out: an invisible orphan with no resume path. Salvage instead
    /// of losing it — keep what was logged, drop what wasn't.
    private func resolveOrphanedSessions() {
        guard activeSession == nil else { return }
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt == nil }
        )
        for session in (try? modelContext.fetch(descriptor)) ?? [] where !session.isDeleted {
            if session.completedSetLogs.isEmpty {
                modelContext.delete(session)
            } else {
                session.finish()
            }
        }
    }

    // MARK: - Data assembly

    private var dueRoutines: [Routine] {
        // Only routines with something in them stage: starting an empty
        // routine would instantly commit a bogus 0-set session AND mark
        // the schedule satisfied (bug hunt, highest severity).
        routines.filter { routine in
            guard !routine.groups.isEmpty else { return false }
            return dueState(of: routine) == .due
        }
    }

    /// One carried-over occurrence: the routine plus the day it lapsed
    /// (its `.missed(since:)`). Bundling the day here means the card
    /// renders straight from it instead of re-deriving the due-state (and
    /// re-scanning sessions) per card per render.
    private struct MissedEntry: Identifiable {
        let routine: Routine
        let since: Date
        var id: PersistentIdentifier { routine.persistentModelID }
    }

    /// Routines whose most recent scheduled day lapsed within the carry
    /// window (Kit `.missed`, 2026-07-14): today isn't their day, but a
    /// past occurrence went unmet. Surfaced as a calm amber card, never
    /// the green due. Empty routines can't start, so they don't appear —
    /// nothing to make up.
    private var missedEntries: [MissedEntry] {
        routines.compactMap { routine in
            guard !routine.groups.isEmpty else { return nil }
            if case .missed(let since) = dueState(of: routine) {
                return MissedEntry(routine: routine, since: since)
            }
            return nil
        }
    }

    /// The routine's due state, anchored to when it joined the library
    /// (`createdAt`) so a freshly added routine never carries a scheduled
    /// day it wasn't around for (2026-07-14).
    private func dueState(of routine: Routine) -> RoutineSchedule.DueState {
        let completions = recentCompletions(of: routine)
        return routine.schedule.dueState(
            lastCompleted: completions.last,
            previousCompleted: completions.previous,
            today: today,
            addedOn: routine.createdAt,
            calendar: calendar
        )
    }

    /// Scheduled-but-empty routines whose day this is (#246): they
    /// can't stage (the 0-set bug class), but silently rendering "Rest
    /// day" while the user's scheduled routine exists gaslights — the
    /// timeline names the state and points at the fix instead.
    private var dueButEmptyRoutines: [Routine] {
        routines.filter { routine in
            guard routine.groups.isEmpty else { return false }
            return dueState(of: routine) == .due
        }
    }

    // MARK: - The week ahead (#267)

    /// One future occurrence of one routine — a routine can appear on
    /// two days of the same week, so identity is the (routine, day)
    /// pair.
    private struct UpcomingEntry: Identifiable {
        struct ID: Hashable {
            let routine: PersistentIdentifier
            let day: Date
        }

        let routine: Routine
        let day: Date
        var id: ID { ID(routine: routine.persistentModelID, day: day) }
    }

    /// The week ahead renders only once Today is its own surface — a
    /// fresh install's setup scaffold keeps the focus — and only when a
    /// schedule exists to preview; with nothing scheduled the whole
    /// section (summary + cards) collapses away.
    private var showsFutureSection: Bool {
        (!setupActive || allSetupDone) && scheduledRoutinesExist
    }

    private var scheduledRoutines: [Routine] {
        routines.filter { $0.schedule.normalized != .unscheduled }
    }

    /// Occurrence days over the next 7 (tomorrow through today + 7),
    /// one entry per routine per day, sorted furthest-future FIRST —
    /// the timeline reads top-down: beyond → this week → today →
    /// history. Same-day ties keep the user's routine order. Empty
    /// routines never appear: they can't start (the 0-set bug class),
    /// and today's due-but-empty card owns the repair path.
    private var upcomingEntries: [UpcomingEntry] {
        var entries: [(entry: UpcomingEntry, order: Int)] = []
        for (index, routine) in routines.enumerated() where !routine.groups.isEmpty {
            let completions = recentCompletions(of: routine)
            let days = routine.schedule.upcomingScheduledDays(
                lastCompleted: completions.last,
                previousCompleted: completions.previous,
                today: today,
                addedOn: routine.createdAt,
                calendar: calendar
            )
            entries.append(contentsOf: days.map { (entry: UpcomingEntry(routine: routine, day: $0), order: index) })
        }
        return entries.sorted { a, b in
            if a.entry.day != b.entry.day { return a.entry.day > b.entry.day }
            return a.order < b.order
        }.map { $0.entry }
    }

    @ViewBuilder
    private var futureSection: some View {
        beyondThisWeekBlock
        ForEach(upcomingEntries) { entry in
            // Inert grey: green rings stay exclusive to today's
            // actionable cards (rail grammar) — a future day is a
            // calendar fact, not a call to action.
            TimelineItem(node: .inert) {
                futureCard(entry)
            }
        }
    }

    /// The cadence summary: the timeline's far end, one faint line of
    /// the recurring rhythm per scheduled routine ("every mon/thu ·
    /// Push Day", "3×/wk · Full Body"). Phrased as the ongoing pattern,
    /// not a dated occurrence, so it doesn't read as a duplicate of the
    /// concrete upcoming card beside it. No obligation words (#172);
    /// presence and position communicate. Empty scheduled routines still
    /// appear here: the schedule is a fact even while the routine can't
    /// start (its due-day card names that state). Spine only, no node:
    /// nothing here is an entry.
    private var beyondThisWeekBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                SheetSectionLabel("BEYOND THIS WEEK")
                ForEach(scheduledRoutines) { routine in
                    Text("\(routine.schedule.recurrenceLabel) · \(routine.name)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 10)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The rail's "now" line, sitting directly on today's first item:
    /// the date left the header (Dave's ask) for the item it describes,
    /// and this marker is what the opening scroll (#267) seats at the
    /// top. A spine-only divider like the beyond-this-week block — no
    /// node, because it names a moment, it isn't an entry.
    private var todayMarker: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                SheetSectionLabel("TODAY")
                Text(todayDateText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.vertical, 10)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "sat · jul 11" — the timeline's own weekday·date grammar (matches
    /// the upcoming cards' caption), lowercased like every rail caption.
    private var todayDateText: String {
        let weekday = today.formatted(.dateTime.weekday(.abbreviated)).lowercased()
        let date = today.formatted(.dateTime.month(.abbreviated).day()).lowercased()
        return "\(weekday) · \(date)"
    }

    /// A condensed pending card, deliberately SECONDARY to today's
    /// (Dave's #267 call): name + date + estimate, no promoted diff, no
    /// muscles/gear rows. The whole card navigates to the routine — the
    /// committed-card grammar (tap the card, chevron trailing) — so an
    /// upcoming workout can be configured (or started) from its detail.
    /// One-click Start is reserved for TODAY's card now (Dave,
    /// 2026-07-14): a future day is a calendar fact, not a call to act, so
    /// the inline Start button is gone. No matchedTransitionSource: the
    /// same routine's pending card may be on screen with that id — off-card
    /// starts fall back to the standard transition (#216).
    private func futureCard(_ entry: UpcomingEntry) -> some View {
        NavigationLink(value: entry.routine.uuid.map { RoutineRef(uuid: $0) }) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.routine.name)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(futureCaption(for: entry))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            // Dashed grey: a future occurrence is "not yet" (Dave,
            // build-48) — the dash carries provisionality, and grey keeps
            // it inert while today's card wears the solid green it earns.
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("configureUpcoming-\(dayStamp(entry.day))")
    }

    /// Stable "2026-07-11" stamp for identifiers — calendar components,
    /// not a formatter, so locale/timezone settings can't vary it.
    private func dayStamp(_ day: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// "fri · jul 11 · ~40 min" — plain calendar facts, lowercase like
    /// every caption on the rail.
    private func futureCaption(for entry: UpcomingEntry) -> String {
        let weekday = entry.day.formatted(.dateTime.weekday(.abbreviated)).lowercased()
        let date = entry.day.formatted(.dateTime.month(.abbreviated).day()).lowercased()
        return "\(weekday) · \(date) · \(entry.routine.estimateText)"
    }

    // MARK: - Carried over (missed occurrences)

    /// A quiet cluster between today's work and the history below: routines
    /// whose most recent scheduled day lapsed within the carry window
    /// (Kit `.missed`, 2026-07-14). Its own faint marker keeps them OFF
    /// today's date, and amber (never green) keeps them a gentle nudge, not
    /// a call to act — the anti-shame grammar holds ("no obligation words").
    @ViewBuilder
    private var carriedOverSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                SheetSectionLabel("CARRIED OVER")
                Text("still open from earlier — do them whenever")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
            .padding(.vertical, 10)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        ForEach(missedEntries) { entry in
            // Amber node, amber card: a lapsed occurrence is neither the
            // green "today" nor the grey "not yet" — it's the warm
            // in-between (the notes/advisory amber already in the grammar).
            TimelineItem(node: .inert, strokeOverride: Theme.notes) {
                missedCard(entry)
            }
        }
    }

    /// The gentle carried-over card: name, the day it was scheduled, and
    /// the estimate — no diff, no green border, and no one-click Start
    /// (reserved for today). Tapping opens the routine, where Start lives.
    private func missedCard(_ entry: MissedEntry) -> some View {
        NavigationLink(value: entry.routine.uuid.map { RoutineRef(uuid: $0) }) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.routine.name)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(missedCaption(entry))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.notes)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(reduceTransparency ? 1 : 0.55), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            // A soft, solid amber edge: distinct from today's solid green
            // and the future cards' dashed grey.
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.notes.opacity(0.55), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("missedRoutine-\(entry.routine.name)")
    }

    /// "was tue · jul 7 · ~30 min" — the lapsed day named plainly (the
    /// "was" reads it as past without any obligation word), then the
    /// estimate.
    private func missedCaption(_ entry: MissedEntry) -> String {
        let weekday = entry.since.formatted(.dateTime.weekday(.abbreviated)).lowercased()
        let date = entry.since.formatted(.dateTime.month(.abbreviated).day()).lowercased()
        return "was \(weekday) · \(date) · \(entry.routine.estimateText)"
    }

    /// The two most recent completions of a routine: `.last` drives
    /// due-ness, `.previous` tells the Kit's banking rule whether that
    /// last session was an extra or a make-up (#267 — one workout, one
    /// occurrence). Identity match wins; the name fallback only applies
    /// when no session references this routine — two routines sharing a
    /// name must not satisfy each other's schedules (bug hunt).
    /// "Latest" is by endedAt, matching the comparison the schedule
    /// engine makes.
    private func recentCompletions(of routine: Routine) -> (last: Date?, previous: Date?) {
        let identityMatches = sessions.filter { $0.routine === routine }
        let pool = identityMatches.isEmpty
            ? sessions.filter { $0.routineName == routine.name }
            : identityMatches
        let dates = pool.compactMap(\.endedAt).sorted(by: >)
        return (dates.first, dates.count > 1 ? dates[1] : nil)
    }

    /// The last time each staged exercise was actually performed —
    /// newest finished session containing it, represented by its TOP
    /// set (heaviest completed weight) with THAT set's reps: weight and
    /// reps must come from the same set or the delta describes a set
    /// that never happened (bug hunt). Duration takes the last set.
    private func prior(for routineExercise: RoutineExercise) -> RoutineDiff.Prior? {
        let exercise = routineExercise.exercise
        let name = exercise?.name ?? ""
        for session in sessions {
            let matches = session.completedSetLogs.filter { log in
                if let a = log.exercise, let b = exercise { return a === b }
                return log.exerciseName == name
            }
            guard let last = matches.last else { continue }
            let top = matches.max { ($0.actualWeight ?? 0) < ($1.actualWeight ?? 0) } ?? last
            return RoutineDiff.Prior(
                weight: top.actualWeight,
                reps: top.actualReps ?? last.actualReps,
                durationSeconds: last.actualDuration,
                extras: last.extraActuals
            )
        }
        return nil
    }

    private struct DiffLine: Identifiable {
        let id: PersistentIdentifier
        let name: String
        let target: String
        let delta: RoutineDiff.Delta
    }

    private func diffLines(for routine: Routine) -> [DiffLine] {
        var lines: [DiffLine] = []
        for group in routine.sortedGroups {
            for entry in group.sortedExercises {
                guard let exercise = entry.exercise else { continue }
                let profile = exercise.metricProfile
                let target = RoutineDiff.Target(
                    name: exercise.name,
                    isDuration: profile.legacyType == .duration,
                    weight: entry.weight,
                    reps: entry.reps,
                    durationSeconds: entry.durationSeconds,
                    extras: entry.extraTargets.filter { profile.contains($0.key) },
                    distanceUnit: profile.distanceUnit
                )
                lines.append(DiffLine(
                    id: entry.persistentModelID,
                    name: exercise.name,
                    target: targetText(entry, exercise: exercise, sets: group.sets),
                    delta: RoutineDiff.delta(target: target, prior: prior(for: entry))
                ))
            }
        }
        // Changed first, unchanged (with =) after, both in routine order.
        return lines.filter { $0.delta.isChange } + lines.filter { !$0.delta.isChange }
    }

    private func targetText(_ entry: RoutineExercise, exercise: Exercise, sets: Int) -> String {
        let profile = exercise.metricProfile
        if profile.tracksReps {
            var text = "\(sets)×\(RepTarget(lower: entry.reps, upper: entry.repsUpper).display)"
            if let weight = entry.weight, weight > 0 {
                text += " @ " + WorkoutMetric.weight.displayText(weight, weightUnit: weightUnit)
            }
            return text
        }
        // Cardio blocks: rounds × the work target ("4× 500 m", "3× 20:00").
        let driver = profile.driver { entry.target($0) }
        return "\(sets)× " + driver.displayText(
            entry.target(driver),
            weightUnit: weightUnit,
            distanceUnit: profile.distanceUnit
        )
    }

    /// Top completed weight per exercise — the input to the net chip.
    private func topWeights(_ session: WorkoutSession) -> [String: Double] {
        var result: [String: Double] = [:]
        for log in session.completedSetLogs {
            if let weight = log.actualWeight, weight > 0 {
                result[log.exerciseName] = max(result[log.exerciseName] ?? 0, weight)
            }
        }
        return result
    }

    private func netGain(for session: WorkoutSession) -> Double? {
        // Identity when both sessions still reference a routine; name
        // otherwise. "Previous" is the max endedAt below this one — the
        // query's startedAt order isn't the comparison order (bug hunt).
        let candidates = sessions.filter { other in
            let sameRoutine: Bool
            if let a = other.routine, let b = session.routine {
                sameRoutine = a === b
            } else {
                sameRoutine = other.routineName == session.routineName
            }
            return sameRoutine && (other.endedAt ?? .distantPast) < (session.endedAt ?? .distantPast)
        }
        guard let previous = candidates.max(by: { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }) else { return nil }
        let gain = RoutineDiff.netWeightGain(current: topWeights(session), previous: topWeights(previous))
        return gain > 0 ? gain : nil
    }

    private func start(_ routine: Routine) {
        // Belt and braces with the dueRoutines/swap-in filters: an empty
        // routine must never become a committed 0-set session.
        guard !routine.groups.isEmpty else { return }
        // Re-checked at FIRE time, not just tap time: StartFlashButton
        // defers ~0.85 s, long enough for a second Start to flash
        // (double-start orphan) or the start tray to present — setting
        // activeSession under a live sheet is the documented
        // presentation-drop class, and a dropped cover with a non-nil
        // activeSession would wedge every future start and salvage
        // (swift-reviewer). A tap that raced the tray simply loses.
        guard activeSession == nil, !showingSwapIn else { return }
        // ActiveSessionView requests notification permission on appear.
        activeSession = WorkoutSession.start(from: routine, context: modelContext)
    }

    /// The no-plan session (#239): starts empty, gets filled on the
    /// gym floor. An empty scratch session is safe to abandon — the
    /// orphan salvage deletes 0-set sessions, and the empty stage never
    /// auto-finishes, so nothing 0-set can commit.
    private func startEmptySession() {
        guard activeSession == nil else { return }
        activeSession = WorkoutSession.startEmpty(context: modelContext)
    }

    // MARK: - Header

    private var header: some View {
        let plan = weekPlan
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                // The ++ is a button (#266): the app-level page —
                // Settings, About, What's new, links, feedback. Since
                // build 44 every root header wears it (AppMenuKey).
                AppMenuKey()
                Spacer()
                // Settings' old seat starts workouts instead (#266):
                // the one action that should never be more than a tap
                // away, via the existing start tray. Neutral like every
                // header key (Quiet Arcade tightened green's scope to
                // true data; the flourish moved into Start's flash).
                HeaderIconButton(systemImage: "play.fill", accessibilityLabel: "Start a workout", identifier: "startTrayButton") {
                    showingSwapIn = true
                }
            }
            Text("Today")
                .font(.system(.title, weight: .bold))
                .padding(.top, 10)
            if let caption = caption(plan: plan) {
                Text(caption)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.top, 3)
            }
            // The week block bar: one block per scheduled session this
            // week, filled purple as sessions land. Purple, not green —
            // it counts what's committed, and it hides entirely when
            // nothing is scheduled (no plan, no empty scorecard).
            if !(setupActive && !allSetupDone), plan.planned > 0 {
                BlockBar(total: plan.planned, filled: plan.completed)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var weekPlan: (completed: Int, planned: Int) {
        WeekPlan.counts(routines: routines, sessions: sessions, today: today, calendar: calendar)
    }

    /// The header's status line — setup progress, or the week tally.
    /// The DATE left the header (Dave's ask): it belongs on today's
    /// item, and now rides the timeline's TODAY marker. Nil when there's
    /// nothing to say (no plan, past setup) so the line drops entirely.
    private func caption(plan: (completed: Int, planned: Int)) -> String? {
        if setupActive && !allSetupDone {
            return "setup \(setupDoneCount) of 3"
        }
        // The week tally is calendar fact, not obligation (#172-safe:
        // it never says what's LEFT, only what the plan holds and what
        // has landed). No "N due" tally — the staged cards ARE that.
        guard plan.planned > 0 else { return nil }
        return "\(plan.completed) of \(plan.planned) session\(plan.planned == 1 ? "" : "s") this week"
    }

    // MARK: - Pending card

    private func pendingCard(_ routine: Routine) -> some View {
        let lines = diffLines(for: routine)
        let summary = RoutineDiff.summary(deltas: lines.map(\.delta), weightUnit: weightUnit)
        // The identity moment must read on day one and on plan-held
        // days (#246): never-performed gets words with stakes instead
        // of a bare inventory count, and an all-unchanged day keeps
        // the Kit's single faint "=" — hiding the line entirely made
        // the diff grammar unlearnable exactly when it was legible.
        let segments: [RoutineDiff.Segment]
        if !lines.isEmpty && lines.allSatisfy({ $0.delta == .new }) {
            segments = [RoutineDiff.Segment(kind: .new, text: "first time — sets the baseline")]
        } else if summary.contains(where: { $0.kind != .unchanged }) {
            segments = summary.filter { $0.kind != .unchanged }
        } else {
            // Zero comparable lines (every entry dangling) must not
            // claim "=" — there is nothing to be equal to.
            segments = lines.isEmpty ? [] : summary
        }

        return VStack(alignment: .leading, spacing: 0) {
            // The whole meta region above Start navigates to the routine
            // (Dave's ask): the Configure capsule is gone, replaced by a
            // trailing chevron in the committed-card grammar (tap the
            // card, chevron trailing) that the upcoming cards already
            // speak. Start keeps its own frame below, so exactly one
            // affordance fires per tap.
            NavigationLink(value: routine.uuid.map { RoutineRef(uuid: $0) }) {
                VStack(alignment: .leading, spacing: 0) {
                    // The name owns the top row (the estimate moved down
                    // to the go/no-go meta row — Dave's ask); the chevron
                    // trails it like every navigating card.
                    HStack(alignment: .center, spacing: 8) {
                        Text(routine.name)
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(.caption2, weight: .bold))
                            .foregroundStyle(Theme.textFaint)
                    }

                    // Two meta rows: what it hits, then what to have
                    // nearby and how long it runs. The schedule label is
                    // gone — the card's presence on Today IS the schedule
                    // statement.
                    if let muscles = cappedList(musclesFor(routine)) {
                        Text(muscles)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(1)
                            .padding(.top, 9)
                    }
                    // Gear + estimate pair on the go/no-go row — what to
                    // have nearby and how long it takes, the two "can I do
                    // this now?" facts. The estimate keeps priority so a
                    // long gear list truncates before the time does.
                    HStack(spacing: 8) {
                        Text(cappedList(gearFor(routine)) ?? "bodyweight")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(routine.estimateText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                            .layoutPriority(1)
                    }
                    .padding(.top, 3)

                    // The diff is the identity moment — it outranks the
                    // meta above it (footnote semibold; unchanged tallies
                    // aren't news).
                    if !segments.isEmpty {
                        diffSummaryText(segments)
                            .lineLimit(1)
                            .padding(.top, 8)
                            .accessibilityIdentifier("diffSummary")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("configureRoutineButton")

            StartFlashButton(label: "Start", identifier: "startStagedButton") {
                start(routine)
            }
            .padding(.top, 12)
        }
        .padding(12)
        .background(Theme.surface.opacity(reduceTransparency ? 1 : 0.55), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        // Today's card is the one to DO now: a solid green border marks
        // it (Dave, build-48), the same actionable-green the node ring
        // already speaks. Dashes moved to the FUTURE cards (see
        // futureCard) — a dash now reads "not yet", not "pending here".
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.accent, lineWidth: 1.5)
        )
    }

    /// Muscles and gear beat a bare exercise count (Dave, #173): what
    /// the workout hits and what to have nearby is decision-relevant;
    /// "6 exercises" isn't. Both lists cap at 3 + overflow (SSE).
    private func musclesFor(_ routine: Routine) -> [String] {
        let exercises = routine.sortedGroups.flatMap(\.sortedExercises).compactMap(\.exercise)
        return Array(Set(exercises.map { $0.muscleGroup.displayName.lowercased() })).sorted()
    }

    private func gearFor(_ routine: Routine) -> [String] {
        let exercises = routine.sortedGroups.flatMap(\.sortedExercises).compactMap(\.exercise)
        return Array(Set(exercises.flatMap { $0.equipment.map { $0.name.lowercased() } })).sorted()
    }

    private func cappedList(_ list: [String]) -> String? {
        guard !list.isEmpty else { return nil }
        let shown = list.prefix(3).joined(separator: ", ")
        return list.count > 3 ? "\(shown) +\(list.count - 3)" : shown
    }

    /// The colored summary line, composed as one Text so it truncates
    /// gracefully. Up = data green; down = neutral gray (deloads are
    /// intentional — celebrate-up only); new = info; "n =" faint.
    private func diffSummaryText(_ segments: [RoutineDiff.Segment]) -> Text {
        var result = Text("")
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                result = result + Text(" · ").font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textFaint)
            }
            result = result + Text(segment.text)
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .foregroundStyle(color(for: segment.kind))
        }
        return result
    }

    private func color(for kind: RoutineDiff.Segment.Kind) -> Color {
        switch kind {
        case .up: Theme.accent
        case .down: Theme.textSecondary
        case .new: Theme.accent
        case .unchanged: Theme.textFaint
        }
    }

    // MARK: - Committed card

    private func committedCard(_ session: WorkoutSession) -> some View {
        NavigationLink(value: SessionRecordDestination(session: session)) {
            HStack(spacing: 8) {
                // A purple check seal on the card itself (Dave, 2026-07-14):
                // the rail node already reads done, but a committed card
                // should say so at a glance without leaning on its ring —
                // the finish-checkmark grammar, purple = landed (#201).
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(.subheadline))
                    .foregroundStyle(Theme.done)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.routineName)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(committedSubtitle(session))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                if let gain = netGain(for: session) {
                    Text(RoutineDiff.summary(deltas: [.weight(gain)], weightUnit: weightUnit)[0].text)
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.5)))
                }
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
    }

    private func committedSubtitle(_ session: WorkoutSession) -> String {
        var parts = [session.startedAt.formatted(.dateTime.month(.abbreviated).day()).lowercased()]
        let sets = session.completedSetLogs.count
        parts.append("\(sets) \(sets == 1 ? "set" : "sets")")
        if let duration = session.duration {
            let minutes = Int(duration / 60)
            parts.append(minutes < 1 ? "<1 min" : "\(minutes) min")
        }
        // The session's average heart rate, when Health had one.
        if let average = session.averageHeartRate {
            parts.append("\(average) bpm")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Setup timeline

    /// The scaffold shows until the first real session commits — done
    /// steps sit on the rail like history until actual history takes
    /// their place.
    private var setupActive: Bool { sessions.isEmpty }

    private var equipmentStepDone: Bool { SetupState.equipmentDone }
    private var routineStepDone: Bool { !routines.isEmpty }
    private var scheduleStepDone: Bool {
        routines.contains { $0.schedule.normalized != .unscheduled }
    }

    private var allSetupDone: Bool { equipmentStepDone && routineStepDone && scheduleStepDone }

    private var setupDoneCount: Int {
        [equipmentStepDone, routineStepDone, scheduleStepDone].filter { $0 }.count
    }

    /// Bottom-up like commits: equipment is the first entry (bottom),
    /// schedule the last (top). Each step gates on the one below it.
    private var setupSection: some View {
        Group {
            SetupRow(
                state: scheduleStepDone ? .done : (routineStepDone ? .ready : .gated),
                badge: "3 of 3",
                title: "Schedule it",
                doneTitle: "Schedule set",
                sub: scheduleStepDone ? scheduleDoneSub : "Days or a pace — routines appear here on their day",
                gatedSub: "Needs a routine first",
                cta: "Choose days or pace",
                identifier: "setupScheduleStep",
                action: { scheduleEditTarget = scheduleEditRoutine?.uuid.map(IdentifiedUUID.init)},
                edit: { scheduleEditTarget = scheduleEditRoutine?.uuid.map(IdentifiedUUID.init)}
            )
            SetupRow(
                state: routineStepDone ? .done : (equipmentStepDone ? .ready : .gated),
                badge: "2 of 3",
                title: "Create your first routine",
                doneTitle: routines.count == 1 ? "Routine created" : "Routines created",
                sub: routineStepDone ? routineDoneSub : "Browse the catalog, or start from a blank slate",
                gatedSub: "Needs your equipment first",
                cta: "Pick a routine",
                identifier: "setupRoutineStep",
                // Root-only affordance: emptiness doubles as the
                // double-tap guard (see RoutineListView's +).
                action: { if todayPath.isEmpty { todayPath.append(RoutineCatalogDestination()) } },
                edit: { onGoToRoutines() }
            )
            SetupRow(
                state: equipmentStepDone ? .done : .ready,
                badge: "1 of 3",
                title: "What do you have access to?",
                doneTitle: "Equipment set",
                sub: equipmentStepDone ? equipmentDoneSub : "Your equipment filters the catalog everywhere",
                gatedSub: "",
                cta: "Pick equipment",
                identifier: "setupEquipmentStep",
                action: { showingEquipmentSetup = true },
                edit: { showingEquipmentSetup = true }
            )
        }
    }

    private func doneDatePrefix(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day()).lowercased() + " · "
    }

    private var equipmentDoneSub: String {
        let count = activeLibrary?.members.count ?? 0
        let summary = count == 0 ? "bodyweight only" : "\(count) item\(count == 1 ? "" : "s")"
        return doneDatePrefix(SetupState.equipmentDoneDate) + summary
    }

    private var routineDoneSub: String {
        let date = doneDatePrefix(routines.map(\.createdAt).min())
        let names = routines.map(\.name)
        if names.count <= 2 { return date + names.joined(separator: " + ") }
        return date + "\(names.count) routines"
    }

    private var scheduleDoneSub: String {
        let scheduled = routines.filter { $0.schedule.normalized != .unscheduled }
        let labels = scheduled.prefix(2).map(\.schedule.shortLabel).joined(separator: " · ")
        return scheduled.count > 2 ? labels + " · …" : labels
    }

    /// The routine the schedule step edits: the first already-scheduled
    /// one, else the first routine.
    private var scheduleEditRoutine: Routine? {
        routines.first { $0.schedule.normalized != .unscheduled } ?? routines.first
    }

    // MARK: - Empty states

    /// A timeline ITEM, not a floating empty state: rest days are part
    /// of the record too.
    private var restDayItem: some View {
        TimelineItem(node: .inert) {
            VStack(alignment: .leading, spacing: 8) {
                Text(restDayTitle)
                    .font(.system(.body, weight: .semibold))
                Text(restDayItemCaption)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                // A true rest day carries NO start key (Dave, 2026-07-12):
                // rest is the point, swapping in a workout is possible but
                // not primary — the header's play key (always a tap away)
                // owns starting. The card only offers an action when it's
                // NOT resting: creation when no routine can start, or the
                // "Work out now" prompt when one is due-but-empty / mid-setup.
                if swapInCandidates.isEmpty {
                    // No candidates → no dead tray (#208): offer
                    // creation directly instead, with the no-plan
                    // escape (#239) beside it — the tray's picker
                    // would be empty, so the card keeps both paths.
                    Button {
                        showingNewRoutine = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(.caption, weight: .semibold))
                            Text("New routine")
                                .font(.system(.footnote, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderStrong))
                    }
                    .buttonStyle(.raisedKey(cornerRadius: 10))
                    .accessibilityIdentifier("restDayNewRoutineButton")
                    QuietKey(label: "build as you go", systemImage: "plus.square.dashed", identifier: "startEmptyWorkoutButton") {
                        startEmptySession()
                    }
                } else if promptsWorkout {
                    // Not a rest day: the card is telling you to work out
                    // (a scheduled routine is due-but-empty, or setup's
                    // first-workout step). Keep the start key here — the
                    // rest-day silence would misread as "nothing to do".
                    Button {
                        showingSwapIn = true
                    } label: {
                        HStack(spacing: 6) {
                            // play.fill, not the old swap arrows: the
                            // button STARTS something (same glyph as
                            // the header's start key); "swap" was a
                            // pre-#266 framing this card outgrew.
                            Image(systemName: "play.fill")
                                .font(.system(.caption, weight: .semibold))
                            // Shares the tray's vocabulary ("Start a
                            // workout") since #266 retitled it.
                            Text("Start a workout")
                                .font(.system(.footnote, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderStrong))
                    }
                    .buttonStyle(.raisedKey(cornerRadius: 10))
                    .accessibilityIdentifier("swapInButton")
                }
                // The schedule offer (#246): routines exist, none
                // scheduled, and nothing on Today ever said scheduling
                // exists — one offer-shaped line, gone the moment any
                // schedule does. Below the action: it's a footnote-
                // weight suggestion, not this card's job. During setup
                // the scaffold's own step is the offer.
                if !setupActive, !scheduledRoutinesExist,
                   let target = swapInCandidates.first {
                    QuietKey(
                        label: "schedule a routine — it appears here on its day",
                        identifier: "scheduleOfferButton"
                    ) {
                        scheduleEditTarget = target.uuid.map(IdentifiedUUID.init)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        }
    }

    /// A scheduled routine with nothing in it, on its day (#246): name
    /// the state and point at the fix — the only prior rendering was a
    /// "Rest day" card denying the routine existed.
    private func emptyRoutineCard(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(routine.name)
                .font(.system(.body, weight: .semibold))
            Text("no exercises yet — it can start once it has some")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            Button {
                // Root-only affordance: emptiness doubles as the
                // double-tap guard (see the setup step's catalog push).
                if todayPath.isEmpty { routine.uuid.map { todayPath.append(RoutineRef(uuid: $0)) } }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(.caption, weight: .semibold))
                    Text("Add exercises")
                        .font(.system(.footnote, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderStrong))
            }
            .buttonStyle(.raisedKey(cornerRadius: 10))
            .accessibilityIdentifier("emptyRoutineAddButton")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }

    private var scheduledRoutinesExist: Bool {
        !scheduledRoutines.isEmpty
    }

    /// The card is prompting a workout, not resting: mid-setup (the first-
    /// workout step is the point) or an empty scheduled routine is due (the
    /// card above names that state). Gates both the title AND the on-card
    /// start key — a true rest day carries neither.
    private var promptsWorkout: Bool {
        (setupActive && !allSetupDone) || !dueButEmptyRoutines.isEmpty
    }

    /// "Rest day" is a claim — don't make it while an empty scheduled
    /// routine is due (the card above names that state) or mid-setup.
    private var restDayTitle: String {
        if promptsWorkout {
            return "Work out now"
        }
        return scheduledRoutinesExist ? "Rest day" : "Nothing scheduled"
    }

    /// The "optional" reassurance belongs only before ANY schedule
    /// exists (swift-reviewer: it contradicted a visible "Schedule
    /// set" step); everyone else gets the calendar facts.
    private var restDayItemCaption: String {
        if setupActive && !allSetupDone && !scheduledRoutinesExist {
            return "Scheduling is optional — start whenever you like"
        }
        return restDayCaption
    }

    private var restDayCaption: String {
        var best: (date: Date, name: String)?
        for routine in routines {
            if case .notDue(let next) = dueState(of: routine) {
                if best == nil || next < best!.date {
                    best = (next, routine.name)
                }
            }
        }
        // Not "Nothing scheduled" — the title already says that, and
        // saying it twice reads broken (the header comment's own rule).
        // With a schedule that exists but can't stage (the empty card
        // above), calendar-denial would be false too.
        guard let best else {
            return scheduledRoutinesExist
                ? "start whenever you like"
                : "No routine on the calendar — start one whenever"
        }
        let day = best.date.formatted(.dateTime.weekday(.abbreviated)).lowercased()
        // Within the week "next thu" is unambiguous; further out the
        // bare weekday would lie by omission — add the plain date
        // (#267: a banked occurrence can push "next" past the week).
        if let weekBoundary = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: today)),
           best.date > weekBoundary {
            let monthDay = best.date.formatted(.dateTime.month(.abbreviated).day()).lowercased()
            return "on pace · next \(day) · \(monthDay) — \(best.name)"
        }
        return "on pace · next \(day) — \(best.name)"
    }
}

/// Push destination for a committed session record. A tiny wrapper so
/// the destination is Hashable without making the @Model itself the
/// path element in two different roles.
struct SessionRecordDestination: Hashable {
    let session: WorkoutSession
}

/// One row of the Today rail: node in a fixed-width gutter with a
/// continuous 2 px spine, card alongside. Every node is a RING —
/// stroke only, never filled (Dave's build-33 call, superseding
/// #201's filled-purple done dot). State lives entirely in the
/// stroke's color: green = actionable now, grey = inert, faint =
/// gated, purple = done.
private enum TimelineNode {
    /// Ready to do — a green ring. Green marks the next increment.
    case pending
    /// Nothing actionable here (rest day) — neutral grey ring.
    case inert
    /// Done — a purple ring (GitHub's merged hue carries the meaning;
    /// the fill no longer does).
    case committed
    /// A setup step whose prerequisite isn't met yet — border-faint,
    /// so the rail reads "not yet yours".
    case gated

    var strokeColor: Color {
        switch self {
        case .pending: Theme.accent
        case .inert: Theme.textFaint
        case .gated: Theme.borderStrong
        case .committed: Theme.committedFill
        }
    }
}

private struct TimelineItem<Content: View>: View {
    let node: TimelineNode
    /// Drives the node color directly (the completion conversion animates
    /// green → purple here). Nil falls back to the node's own color.
    var strokeOverride: Color? = nil
    /// A one-shot purple checkmark that seals the node at the end of the
    /// conversion — bigger than the ring, so it reads as a stamp, then
    /// fades back to the resting ring (nodes are rings at rest, #build-33).
    var showCheckmark: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Circle()
                    .strokeBorder(strokeOverride ?? node.strokeColor, lineWidth: 2)
                    .frame(width: 10, height: 10)
                    .background(Circle().fill(Theme.background))
                    .overlay {
                        if showCheckmark {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.done)
                                .symbolEffect(.bounce, options: .nonRepeating, value: showCheckmark)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.top, 18)
            }
            .frame(width: 20)

            content()
                .padding(.vertical, 5)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One setup step on the Today rail (setup-as-timeline handoff).
/// Three states: done reads like a committed entry (green node, solid
/// card, an edit affordance); ready is a dashed pending card with its
/// "N of 3" badge and a full-width CTA; gated is the same card dimmed,
/// non-interactive, its sub explaining the prerequisite.
private struct SetupRow: View {
    enum StepState {
        case done, ready, gated
    }

    let state: StepState
    let badge: String
    let title: String
    let doneTitle: String
    let sub: String
    let gatedSub: String
    let cta: String
    let identifier: String
    let action: () -> Void
    let edit: () -> Void

    /// Pending/gated setup cards render on a translucent surface so they read
    /// as not-yet-real. Under Reduce Transparency they go fully opaque so the
    /// (already faint) caption text keeps its contrast.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var cardFill: Color { Theme.surface.opacity(reduceTransparency ? 1 : 0.55) }
    private var gatedDim: Double { reduceTransparency ? 1 : 0.55 }

    var body: some View {
        TimelineItem(node: node) {
            card
        }
    }

    private var node: TimelineNode {
        switch state {
        case .done: .committed
        case .ready: .pending
        case .gated: .gated
        }
    }

    @ViewBuilder
    private var card: some View {
        switch state {
        case .done:
            Button(action: edit) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doneTitle)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(sub)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 3) {
                        Text("edit")
                            .font(.system(.footnote, design: .monospaced))
                        Image(systemName: "chevron.right")
                            .font(.system(.caption2, weight: .bold))
                    }
                    .foregroundStyle(Theme.textFaint)
                }
                .padding(.vertical, 13)
                .padding(.horizontal, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)

        case .ready:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    Text(badge)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                }
                Text(sub)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 5)
                Button(action: action) {
                    Text(cta)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.onPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.raisedPrimaryKey())
                .accessibilityIdentifier(identifier)
                .padding(.top, 10)
            }
            .padding(12)
            .background(cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )

        case .gated:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    Text(badge)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                }
                Text(gatedSub)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.top, 5)
            }
            .padding(12)
            .background(cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .opacity(gatedDim)
        }
    }
}

/// The start tray, restructured as a two-stage menu (Dave, build-45:
/// a routine listed directly under the title read as part of the
/// title, not an option). Stage one offers the two WAYS to start —
/// "Choose a routine" and the no-plan escape — and stage two is the
/// routine picker itself (rows + creation), sliding in like a push
/// while the sheet grows a detent. Choosing a routine starts it — it
/// commits to the timeline like any other session.
private struct SwapInSheet: View {
    @Environment(\.dismiss) private var dismiss
    let routines: [Routine]
    /// Routines due today — they wear the pill, everyone else shows
    /// their cadence.
    let dueIDs: Set<PersistentIdentifier>
    let onPick: (Routine) -> Void
    let onCreate: () -> Void
    let onStartEmpty: () -> Void

    private enum Stage {
        case menu, picker
    }

    /// The menu is two keys tall — a compact detent; the picker grows
    /// to .medium (user-expandable to .large). The detent rides the
    /// stage so the sheet resizes with the slide. The compact height
    /// scales with Dynamic Type so the two keys don't clip at large
    /// accessibility sizes (a11y audit 2026-07-13).
    @ScaledMetric(relativeTo: .body) private var menuDetentHeight: CGFloat = 280
    private var menuDetent: PresentationDetent { .height(menuDetentHeight) }

    @State private var stage: Stage = .menu
    @State private var detent: PresentationDetent = .height(280)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // The stage slide reads as a push: picker in from the
            // trailing edge, menu out the leading one, reversing on
            // back. Clipped so the moving stage can't draw over the
            // sheet's padding mid-flight.
            ZStack(alignment: .top) {
                switch stage {
                case .menu:
                    menu
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                case .picker:
                    picker
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .clipped()
        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.background)
        .presentationDetents([menuDetent, .medium, .large], selection: $detent)
        .onAppear { if stage == .menu { detent = menuDetent } }
    }

    private func go(to newStage: Stage) {
        withAnimation(Theme.Anim.standard) {
            stage = newStage
            detent = newStage == .menu ? menuDetent : .medium
        }
    }

    /// SheetHeader's closeOnly layout, hand-rolled so the picker stage
    /// can seat a back key before the title.
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if stage == .picker {
                Button {
                    go(to: .menu)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.border))
                        // 32 pt visual, 44 pt hit — the ✕'s own
                        // treatment (#130 target floor).
                        .padding(6)
                        .contentShape(Circle())
                }
                .accessibilityIdentifier("trayBackButton")
                .transition(.opacity)
            }
            // "Start a workout", not "Swap in": the header's start
            // button opens this same tray (#266), and starting is what
            // every path in it does.
            Text(stage == .menu ? "Start a workout" : "Choose a routine")
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 12)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border))
                    .padding(6)
                    .contentShape(Circle())
            }
        }
        .padding(.top, 14)
        .animation(Theme.Anim.standard, value: stage == .picker)
    }

    // MARK: - Stage one: the two ways to start

    private var menu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                go(to: .picker)
            } label: {
                HStack(spacing: 10) {
                    // The Routines tab's own glyph: this key drills
                    // into that library.
                    Image(systemName: "square.stack")
                        .font(.system(.subheadline, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Choose a routine")
                            .font(.system(.footnote, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(routineCountCaption)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(.caption2, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 56)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.borderStrong))
            }
            .buttonStyle(.raisedKey())
            .accessibilityIdentifier("chooseRoutineButton")

            // The no-plan path (#239): walk in, start logging, keep the
            // result as a routine at the finish if it earned it. A full
            // primary key equal to "Choose a routine" (Dave, build-78) —
            // the two ways to start now read as siblings of equal weight.
            Button {
                onStartEmpty()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.square.dashed")
                        .font(.system(.subheadline, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Work out now")
                            .font(.system(.footnote, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("build the routine as you go")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 8)
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 56)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.borderStrong))
            }
            .buttonStyle(.raisedKey())
            .accessibilityIdentifier("swapInStartEmpty")
        }
        .padding(.top, 14)
    }

    private var routineCountCaption: String {
        routines.isEmpty
            ? "none startable yet"
            : "\(routines.count) routine\(routines.count == 1 ? "" : "s")"
    }

    // MARK: - Stage two: the routine picker

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if routines.isEmpty {
                    // Only empty routines (or none) exist — name the
                    // state; the creation key below is the fix.
                    Text("nothing startable yet — a routine needs at least one exercise")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.vertical, 10)
                }
                ForEach(routines) { routine in
                    Button {
                        onPick(routine)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(routine.name)
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text(rowCaption(for: routine))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Theme.textFaint)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            if dueIDs.contains(routine.persistentModelID) {
                                // Green pill: today's occurrence is
                                // data (the next increment), not
                                // selection.
                                Text("today")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2.5)
                                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4)))
                            } else {
                                Text(routine.schedule.shortLabel)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Theme.textFaint)
                            }
                        }
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
                }

                // Creation lives in the picker (Dave, build-45) —
                // green content on a raised key, like every in-list
                // creation row.
                Button {
                    onCreate()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(.caption, weight: .semibold))
                        Text("New routine")
                            .font(.system(.footnote, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .strokeBorder(Theme.borderStrong)
                    )
                }
                .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
                .accessibilityIdentifier("swapInCreateRoutine")
                .padding(.top, 14)

                // Only when something IS scheduled today — on a rest
                // day there's no swap to explain.
                if !dueIDs.isEmpty {
                    Text("picking a different routine here IS the swap — it runs today without rescheduling")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 10)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    /// "6 exercises · ~40 min" — the go/no-go facts for picking.
    private func rowCaption(for routine: Routine) -> String {
        let count = routine.sortedGroups.reduce(0) { $0 + $1.sortedExercises.count }
        return "\(count) exercise\(count == 1 ? "" : "s") · \(routine.estimateText)"
    }
}
