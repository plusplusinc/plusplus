import Foundation
import SwiftUI
import SwiftData
import PlusPlusKit
import UIKit        // UIFont metrics: the pinned band's height, derived not measured

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
    /// The header title rides the icon row except at accessibility text
    /// sizes, where it reflows to its own line below (#164 / axiom).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var routines: [Routine]
    @Query(sort: \Equipment.name) private var equipment: [Equipment]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    /// The catalog, for resolving quick-start picks by name and offering
    /// the cardio rows when the row is edited.
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""
    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]
    )
    private var sessions: [WorkoutSession]

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    /// Programmatic pushes (#208: land in a freshly created routine).
    @State private var todayPath = NavigationPath()
    @State private var showingNewRoutine = false
    /// The config sheet's committed Start, carried across its dismissal:
    /// presenting the session cover in the sheet's own dismissing
    /// transaction is the documented presentation-drop class, so the
    /// sheet sets this and `onDismiss` acts.
    @State private var pendingStartQuickConfig: SessionExerciseConfig?
    @State private var newRoutineName = ""
    /// Hero zooms (#216): starting a workout grows the pending card
    /// into the session screen; a committed card grows into its
    /// record. Off-card starts (swap-in, Siri) have no source and fall
    /// back to the system transition on their own.
    @Namespace private var zoomNamespace
    @State private var showingEquipmentSetup = false
    @State private var scheduleEditTarget: IdentifiedUUID?
    /// The two-step "Schedule a routine" tray (pick a routine → schedule it),
    /// opened from the rest-day card's schedule offer (2026-07-24).
    @State private var showingScheduleRoutine = false
    /// Quick start (2026-07-30): the picked sports on the pinned band.
    @AppStorage(QuickStartPicks.key) private var quickStartRaw = QuickStartPicks.raw(from: QuickStartPicks.fallback)
    /// The schedule step's no-schedule completion (#505, Q26-A) —
    /// @AppStorage so choosing it re-renders the scaffold.
    @AppStorage(SetupState.trainingFreestyleKey) private var trainingFreestyle = false
    @State private var quickStartConfig: SessionExerciseConfig?
    @State private var editingQuickStarts = false
    @State private var activeSession: WorkoutSession?
    /// The first-workout Health primer, raised by the start gate.
    @State private var healthStartRequest: HealthStartRequest?
    /// Bumped on day change so every Date()-based computed re-evaluates
    /// — without it, an app resident overnight keeps rendering
    /// yesterday's due list (bug hunt). Pull-to-refresh bumps it too: the
    /// gesture asks for a freshly derived Today.
    @State private var dayToken = 0
    /// Bumped ONLY when the calendar day actually moves. Re-anchoring the
    /// scroll to today belongs to this, never to `dayToken` (2026-07-27): a
    /// pull-to-refresh re-derives Today without moving what "today" IS, and
    /// scrolling the surface mid-gesture yanks the view out from under the
    /// pull — it also carried the pull's own answer off-screen, which is why
    /// the refresh line was never seen.
    @State private var dayChangeToken = 0
    @State private var sync = GitHubSyncCoordinator.shared
    /// Transient pull-to-refresh answer: a sync result, or a quip when the
    /// pass had no news (disconnected, or nothing moved). It renders in the
    /// SPACE THE PULL OPENS, above the scroll's first row (the app has no
    /// toasts, Dave 2026-07-23), so it is visible for exactly as long as the
    /// gesture holds that gap — see the overlay at the mount site and
    /// `clearRefreshMessageAfterSnapBack`.
    @State private var refreshMessage: String?
    @State private var refreshClearTask: Task<Void, Never>?
    /// Why a routine-start deep link (calendar / Siri / plusplus.fit)
    /// could not start — surfaced as an alert, never swallowed.
    @State private var startLinkFailure: StartLinkFailure?
    /// One-shot: the timeline anchors to today's content on FIRST
    /// appearance only (#267) — re-appearances mid-session (returning
    /// from a workout cover, tab hops) must not yank the scroll
    /// position. Day changes re-anchor separately via dayChangeToken.
    @State private var hasAnchoredToday = false
    /// Measured height of the first setup step (equipment), fed back into
    /// the reveal-upward headroom so step 1 seats at the top of the scroll
    /// container AND can't be scrolled off the top (Dave, 2026-07-17):
    /// the headroom below it is capped to exactly one viewport minus the
    /// step, so "step 1 at top" is the maximum downward scroll.
    /// The workout just finished (its recap closed), awaiting the
    /// pending→done conversion flourish on its committed card. Nil
    /// outside the beat.
    @State private var justCompletedID: PersistentIdentifier?
    /// Flips true a beat after landing on Today: the just-finished
    /// card's node completes its green→purple turn and the checkmark
    /// seals it. False both before the turn and after it settles.
    @State private var completionConverted = false
    /// Pending cards whose ledger is showing every mover rather than the
    /// first four. Keyed by `Routine.uuid` like every other routine-keyed
    /// state here, never `persistentModelID`.
    @State private var expandedLedgers: Set<UUID> = []

    /// The zero-height marker the opening scroll anchors to — today's
    /// content top-aligns here, with the week ahead above it (#267).
    private static let todayAnchorID = "todayAnchor"

    /// Per-step scroll anchors for the setup scaffold. The timeline reveals
    /// the steps upward (Dave, 2026-07-16): a fresh install lands on step 1
    /// (equipment, the bottom-most / first-to-do) with steps 2 and 3 above
    /// it off-screen, and completing a step scrolls the next one — which
    /// sits above — up to the top of the scroll area on return to Today.
    private static let setupEquipmentAnchor = "setupAnchor.equipment"
    private static let setupRoutineAnchor = "setupAnchor.routine"
    private static let setupScheduleAnchor = "setupAnchor.schedule"

    /// The step the setup scroll should seat at the top: the lowest
    /// incomplete step (equipment → routine → schedule). Nil once setup is
    /// past or every step is done — nothing left to reveal.
    private var activeSetupAnchor: String? {
        guard setupActive else { return nil }
        if !equipmentStepDone { return Self.setupEquipmentAnchor }
        if !routineStepDone { return Self.setupRoutineAnchor }
        if !scheduleStepDone { return Self.setupScheduleAnchor }
        return nil
    }

    /// The opening scroll target: the active setup step during onboarding,
    /// else today's content. Keeps the returning-user path (#267) unchanged.
    private var openingScrollTarget: String {
        activeSetupAnchor ?? Self.todayAnchorID
    }

    /// True only when Today's own timeline is the visible surface — no
    /// pushed routine/catalog, no equipment setup, no schedule editor, no
    /// live session covering it. A setup step completes behind one of these
    /// (the equipment screen, the routine catalog, the schedule editor), so
    /// this going true again is the "sent back to Today" moment that reveals
    /// the next step.
    private var isTodayRootVisible: Bool {
        todayPath.isEmpty && !showingEquipmentSetup && scheduleEditTarget == nil && activeSession == nil
    }

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }
    private var calendar: Calendar { Calendar.current }

    /// Fact captions (dates, estimates, cadences) reflow to two lines at
    /// accessibility text sizes instead of truncating the facts they
    /// exist to carry — the #164 "reflow, don't cap" law extended from
    /// the heading to the rail (2026-07-23).
    ///
    /// ⚠️ The companion half of that law is RETIRED (Dave, 2026-07-29).
    /// Names used to stay single-line here, on the reasoning that a
    /// truncated name is recoverable one tap away while a truncated date
    /// isn't. Routine names now wrap to two lines wherever they appear, so
    /// Today matches `RoutineCardContent`, which already wrapped to two on
    /// every catalog row. A name is the thing you pick the row BY, and one
    /// line was ellipsizing routines that differ only in their tail.
    private var factLineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 2 : 1
    }

    /// Startable routines (#208): empty routines can't stage (the
    /// 0-set-session bug class), so they don't count. Gates the rest-day
    /// card's creation-vs-prompt branch and the schedule offer.
    private var startableRoutines: [Routine] {
        routines.filter { !$0.groups.isEmpty }
    }

    /// BLANK creation lands in detail, because creating starts editing
    /// (#208; the design-review landing law). ⚠️ It does NOT mirror the
    /// catalog's create row, and the comment that said so was stale twice
    /// over (#508, b28): `RoutineListView` was replaced by
    /// `CatalogScopeView`, and that row lands on the Routines LIST with the
    /// entrance flash rather than pushing anywhere. Named-from-a-query
    /// creation lands; blank creation pushes. Both are deliberate.
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
                        // The week ahead rides ABOVE today (#267), and since
                        // build 163 it rides INSIDE the band's section so the
                        // band can sit above it (see the Section below). It
                        // stays EAGER either way — a LazyVStack sizes
                        // unrealized content approximately, and the opening
                        // scrollTo aims at an anchor below it, so lazy rows
                        // above that anchor land the landing off by their
                        // estimation error. The future block is small by
                        // construction (a summary plus at most 7 days of
                        // occurrence cards), so eager layout is cheap;
                        // committed history below the anchor stays lazy.
                        VStack(spacing: 0) {
                            // The pull's answer hangs ABOVE the content, in
                            // the space the pull opens — where the system
                            // spinner used to sit (Dave, build 154). A
                            // zero-height line at the very top of the content
                            // with the answer overlaid BOTTOM-aligned puts the
                            // line's bottom edge exactly on the content's top,
                            // so it is entirely above the first row, reserves
                            // nothing, and the scroll view clips it at rest.
                            // ⚠️ Plain alignment, deliberately: the first cut
                            // used `alignmentGuide(.top) { $0[.bottom] }` on an
                            // overlay of the content stack, which SwiftUI did
                            // not honour — the line rendered at the content's
                            // top edge and collided with the week tally
                            // (Dave's screenshot). `fixedSize` because the
                            // zero-height base proposes zero height to it.
                            Color.clear
                                .frame(height: 0)
                                .overlay(alignment: .bottom) {
                                    if let refreshMessage {
                                        Text(refreshMessage)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(Theme.textSecondary)
                                            .fixedSize()
                                            .padding(.bottom, 14)
                                            .transition(.opacity)
                                    }
                                }
                            // Lazy: the committed section is the whole
                            // history — eager building made every render
                            // O(sessions) (bug hunt perf finding).
                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                // ONE section holds the whole timeline, and
                                // the week band is its HEADER — which is what
                                // pins the band (build 162: as a top
                                // `safeAreaInset` it desynced the system
                                // large-title bar; a section header lives
                                // inside the scroll's own layout, where the
                                // bar never sees it).
                                //
                                // ⚠️ The band owns the pin OUTRIGHT (Dave:
                                // "the band must pin at the top and not be
                                // usurped by anything else"). A scroll gets
                                // exactly ONE sticky header at a time, so
                                // nothing else on this surface may be a
                                // `Section` — the month landmarks are plain
                                // rows (see `committedHistory`). Everything
                                // below the landing lives in this section so
                                // the band stays pinned the whole way down.
                                Section {
                                    // The week ahead is INSIDE the band's
                                    // section (build 163, Dave: the bar
                                    // "should always sit fully above the
                                    // timeline, including future items").
                                    // A section header renders where its
                                    // section BEGINS, so while the future
                                    // block sat above the section the band
                                    // drew between the week ahead and
                                    // today — chrome wedged into the middle
                                    // of the rail. (Its eagerness and its
                                    // anchor are load-bearing — see
                                    // `weekAheadBlock`.)
                                    weekAheadBlock
                                    // ⚠️ The min-height binds the BELOW-ANCHOR
                                    // region ONLY, which is why it moved off
                                    // the outer stack (review): with the band
                                    // header and the week ahead now inside
                                    // that stack, a min-height there is eaten
                                    // by content ABOVE the anchor and stops
                                    // guaranteeing today can reach the top.
                                    // Nested and LAZY — an eager stack here
                                    // would reinstate the O(sessions) render
                                    // the bug hunt killed; as the section's
                                    // last child its size only feeds the
                                    // outer stack's estimate.
                                    LazyVStack(spacing: 0) {
                                        presentEntries(viewportHeight: viewport.size.height)
                                        committedHistory
                                    // Once real history exists the interactive
                                    // scaffold is gone, but the finished setup
                                    // steps stay as permanent "origin"
                                    // milestones at the very bottom (Dave,
                                    // 2026-07-24): the done steps read as
                                    // committed cards, and any step left
                                    // unfinished stays actionable so setup is
                                    // still reachable. The onboarding anchors
                                    // it carries are inert here (the
                                    // reveal-scroll only runs while setup is
                                    // active).
                                        if !setupActive {
                                            setupSection(viewportHeight: viewport.size.height)
                                        }
                                    }
                                    .frame(minHeight: viewport.size.height, alignment: .top)
                                } header: {
                                    weekStripBand
                                }
                                // Reveal-upward headroom (2026-07-16): the
                                // setup scaffold reveals its steps by
                                // scrolling the active one to the top, with
                                // the others above it off-screen. The bottom
                                // step (equipment) can only reach the top if
                                // scrollable space sits below it, so during
                                // onboarding we add some. Capped (2026-07-17)
                                // to exactly one viewport minus the step's own
                                // height + bottom pad, so step 1 seats at the
                                // top AND that IS the maximum downward scroll —
                                // it can't be pushed off the top. It sits below
                                // the fold and vanishes with the scaffold at
                                // the first logged session.
                            }
                            .padding(.horizontal, 16)
                        }
                        // ⚠️ The 16 pt content column stays per-child, NOT on
                        // this stack: the pinned band above is full-width
                        // chrome, and rows scrolling under its edge must
                        // reach the screen edge too, or the gutters show
                        // content sliding past the band's flanks.
                        .padding(.bottom, 24)
                        // The app's ambient tint, restored INSIDE the scroll:
                        // the ScrollView itself wears a clear tint to kill the
                        // system refresh spinner (below), and without this the
                        // content would inherit that clear.
                        .tint(Theme.textPrimary)
                    }
                    // ⚠️ NO top `safeAreaInset` here. The week band used to
                    // pin from one (build 159) and it cost the large title:
                    // insetting the scroll's safe area shifts its resting
                    // offset by the band's own height, which the system bar
                    // reads as "already collapsed" — so "Today" never drew
                    // at rest, leaving a title-sized dead band above the
                    // tally (Dave's build-162 screenshots; the catalogs
                    // measured the same thing in #521). The band pins as
                    // the timeline's first SECTION HEADER instead, inside
                    // the scroll's own layout where the bar never sees it.
                    // SOFT at the bottom — same call as the catalogs. The
                    // `.hard` slab is what Dave killed; hiding the effect
                    // outright let content read through the bar. Soft is
                    // the system's gradient: visible only where something
                    // is actually passing under the chrome.
                    .scrollEdgeEffectStyle(.soft, for: .bottom)
                    // ⚠️ Kills the system refresh SPINNER (Dave, build 153):
                    // the space it occupies is the space the pull's answer
                    // lives in now, and two things in that gap is one too
                    // many. There is no API to hide the indicator, so it is
                    // drawn in a clear tint instead — hence the
                    // `.tint(Theme.textPrimary)` restoring the content's tint
                    // one level in. Today's is the app's only `.refreshable`,
                    // so nothing else inherits this.
                    .tint(.clear)
                    .refreshable {
                        // Honest refresh (#267): due-ness is pure local
                        // computation keyed on the clock, so bumping the
                        // token re-derives everything instantly. It does
                        // NOT re-anchor the scroll (dayChangeToken's job):
                        // a refresh must leave the surface where the pull
                        // left it, answer included.
                        dayToken += 1
                        // #23: pull-to-refresh now also syncs GitHub. The
                        // spinner should stay up only while there's real
                        // work — so we await the sync ONLY when connected.
                        // Disconnected, there's nothing to fetch, so we skip
                        // the network (the spinner snaps back) and reward the
                        // gesture with a little delight instead of nothing.
                        if !sync.isConnected {
                            // Nothing to fetch — skip the network and reward
                            // the pull with a little delight instead of a
                            // dead gesture.
                            refreshMessage = RefreshQuip.random()
                        } else if sync.isSyncing {
                            // A pass is already running (foreground or Sync
                            // now). sync() is single-flight, so this call
                            // would no-op — don't report a result it didn't
                            // produce (that would show a stale summary).
                            refreshMessage = "Syncing…"
                        } else {
                            // Said BEFORE the network, not after: with the
                            // spinner gone this line is the only thing in the
                            // gap, and a multi-second sync behind an empty
                            // gap reads as a dead pull.
                            refreshMessage = "Syncing…"
                            let units = WeightUnit(rawValue: weightUnitRaw) ?? .lb
                            await sync.sync(context: modelContext, units: units)
                            if case .error = sync.activity {
                                refreshMessage = "Couldn't sync. Try again."
                            } else {
                                // A pass that moved nothing is as dead a
                                // pull as a disconnected one, so it earns
                                // the same reward: lastSyncSummary is nil
                                // unless something actually moved.
                                refreshMessage = sync.lastSyncSummary ?? RefreshQuip.random()
                            }
                        }
                        // The system holds the gap open until this closure
                        // returns, and the answer is only visible while it is
                        // open — so hold it a beat. Long enough to read six
                        // words, short enough that the surface doesn't feel
                        // stuck.
                        try? await Task.sleep(for: .seconds(1.1))
                        clearRefreshMessageAfterSnapBack()
                    }
                    .onAppear {
                        // Only seat once the GeometryReader has a real
                        // height — the below-anchor min height must have
                        // grown the region before there's room to push
                        // the week ahead off-screen. If height is still
                        // pending, the onChange below fires the anchor.
                        guard !hasAnchoredToday, viewport.size.height > 0 else { return }
                        hasAnchoredToday = true
                        // Unanimated: Today OPENS at its target. During
                        // onboarding that's the active setup step (step 1
                        // at first, its siblings above it off-screen);
                        // otherwise today's content, with the week above
                        // it something you go looking for.
                        // ⚠️ Deferred a runloop, like the three re-anchors
                        // below: the anchor lives inside the LazyVStack now,
                        // and `scrollTo` against an id the lazy container
                        // has not created yet is a SILENT no-op — which,
                        // with the one-shot flag already burned, would skip
                        // the landing permanently for that appearance.
                        Task { @MainActor in
                            proxy.scrollTo(openingScrollTarget, anchor: .top)
                        }
                    }
                    .onChange(of: viewport.size.height) { _, height in
                        // GeometryReader can publish the real height a
                        // beat after onAppear; seat the opening target the
                        // instant we have room. One-shot via
                        // hasAnchoredToday, so a later height change
                        // (rotation, keyboard) never yanks a scroll the
                        // user has since moved.
                        guard !hasAnchoredToday, height > 0 else { return }
                        hasAnchoredToday = true
                        // Deferred for the same reason as onAppear's.
                        Task { @MainActor in
                            proxy.scrollTo(openingScrollTarget, anchor: .top)
                        }
                    }
                    .onChange(of: isTodayRootVisible) { _, visible in
                        // Sent back to Today after finishing a setup step
                        // (the equipment screen, routine catalog, or
                        // schedule editor each complete a step behind a
                        // push): reveal the NEXT step, which sits above,
                        // by smoothly scrolling it up to the top. Deferred
                        // a runloop so the pop settles and the newly-active
                        // step has laid out before we aim at its anchor.
                        guard visible, setupActive, let anchor = activeSetupAnchor else { return }
                        Task { @MainActor in
                            withAnimation(Theme.Anim.flourish(.easeInOut(duration: 0.5))) {
                                proxy.scrollTo(anchor, anchor: .top)
                            }
                        }
                    }
                    .onChange(of: dayChangeToken) {
                        // A new day moves "today" — re-anchor. Only a real
                        // day change does this; a pull-to-refresh derives
                        // the same day and must not move the scroll (see
                        // dayChangeToken). Next runloop, not mid-update:
                        // the new day's content must lay out before the
                        // anchor frame it scrolls to is real.
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
            .background(Theme.background)
            // The SYSTEM navigation bar, like every other tab root as of
            // 2026-07-26 — Today's hand-rolled header is gone with the
            // catalogs'. Nothing forced it here (Today hosts no search), but
            // one tab keeping a drawn title row while four wear the real bar
            // is an inconsistency with nothing behind it.
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // Both keys bring their own chrome, so they opt OUT of the
                // toolbar's shared glass rather than nesting inside a system
                // capsule — same as the catalog tabs.
                ToolbarItem(placement: .topBarLeading) { AppMenuKey() }
                    .sharedBackgroundVisibility(.hidden)
                // ⚠️ NO trailing play key (Dave, build 159, retiring #266's
                // tray with it): every start it offered has a first-class
                // home — today's routine on its own card, the routine
                // library on its tab, and the scratch start as the band's
                // Train key. A second door to each is chrome, not access.
            }
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
            // (The RoutineTemplate destination retired with the routine
            // catalog, 2026-07-24: templates are found/added on the Find or
            // create stack now, which registers its own; nothing pushes a
            // template onto Today's path anymore.)
            // (The start tray died with the play key, build 159: today's
            // routine starts from its card, routines start from their
            // tab, and the scratch start is the band's Train key.)
            .sheet(isPresented: $showingScheduleRoutine) {
                ScheduleRoutineTray(routines: routines)
            }
            // One optional-target sheet, then go (Dave). It is the same
            // "configure before you do it" card the picker uses, so the
            // prescription reads identically whichever way you started.
            // ⚠️ The start rides onDismiss, not the commit closure:
            // presenting the session cover in the same transaction as
            // this sheet's dismissal is the drop class every other
            // handoff here already avoids — it shipped leaning on the
            // orphan salvage as a backstop (swift-reviewer).
            .sheet(item: $quickStartConfig, onDismiss: {
                if let config = pendingStartQuickConfig {
                    pendingStartQuickConfig = nil
                    startQuick(config)
                }
            }) { config in
                ExerciseConfigSheet(config: config, actionLabel: "Start") {
                    pendingStartQuickConfig = config
                    quickStartConfig = nil
                }
            }
            .sheet(isPresented: $editingQuickStarts) {
                NavigationStack {
                    SheetPickList(
                        title: "Quick start",
                        sections: [SheetPickList.Section(
                            title: nil,
                            options: quickStartCandidates.map { SheetPickList.Option($0.name) }
                        )],
                        selected: Set(QuickStartPicks.names(from: quickStartRaw)),
                        searchPrompt: "Search cardio",
                        note: "These get a one-tap key when you start a workout."
                    ) { name in
                        var names = QuickStartPicks.names(from: quickStartRaw)
                        if let index = names.firstIndex(of: name) {
                            names.remove(at: index)
                        } else {
                            names.append(name)
                        }
                        // Never empty: an empty row would hide the "+" that
                        // is the only way back to this screen.
                        quickStartRaw = QuickStartPicks.raw(from: names.isEmpty ? QuickStartPicks.fallback : names)
                    }
                    .navigationTitle("Quick start")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationBackground(Theme.background)
                .presentationDetents([.medium, .large])
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
            // The one-time Health ask, in front of the first workout start.
            .healthStartPrimer($healthStartRequest)
            .navigationDestination(isPresented: $showingEquipmentSetup) {
                CatalogScopeView(scope: .kit, setupMode: true)
            }
            .alert("New routine", isPresented: $showingNewRoutine) {
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
                dayChangeToken += 1
            }
            // Crash-orphans from a previous launch get salvaged here;
            // in-flight dismissal paths are covered by the cover's
            // onDismiss.
            .onAppear(perform: resolveOrphanedSessions)
            // Calendar events, plusplus.fit/start links, and Siri all start a
            // routine BY NAME through this one notification. The guards used
            // to fail silently — a renamed/deleted routine or an in-progress
            // workout made the tap look broken to exactly the users who set
            // those integrations up (design review 2026-07-23, the UX
            // audit's one HIGH). Each miss now says why. Follow-up filed:
            // resolve these entry points by stable id instead of name.
            .onReceive(NotificationCenter.default.publisher(for: .plusplusStartRoutine)) { note in
                guard let name = note.object as? String else { return }
                guard let routine = routines.first(where: { $0.name.lowercased() == name.lowercased() }) else {
                    startLinkFailure = StartLinkFailure(
                        title: "Couldn't find that routine",
                        message: "It may have been renamed or removed."
                    )
                    return
                }
                // Already mid-workout: NO alert — the live cover is up, so a
                // sibling alert can't present (it drops, or worse, defers and
                // pops as a stale non-sequitur after the finish;
                // swift-reviewer). Landing INSIDE the running workout is the
                // honest answer the screen already gives.
                guard activeSession == nil else { return }
                start(routine)
            }
            .alert(
                startLinkFailure?.title ?? "",
                isPresented: Binding(
                    get: { startLinkFailure != nil },
                    set: { if !$0 { startLinkFailure = nil } }
                )
            ) {
                Button("OK") { startLinkFailure = nil }
            } message: {
                if let text = startLinkFailure?.message {
                    Text(text)
                }
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
        .animation(Theme.Anim.standard, value: refreshMessage)
    }

    /// Clears the pull's answer once the gap it lives in has closed.
    ///
    /// ⚠️ Driven from the END of the refresh, not from a timer started when
    /// the message is set: a sync can take longer than any fixed window, and a
    /// line that expired mid-pass would leave the open gap empty. The delay is
    /// just the snap-back, so the line goes while it can't be watched going.
    private func clearRefreshMessageAfterSnapBack() {
        refreshClearTask?.cancel()
        refreshClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.35))
            guard !Task.isCancelled else { return }
            refreshMessage = nil
        }
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
            // Live on the wrist right now is not an orphan: its ops have
            // been arriving. Leave it to its own lifecycle — glancing at
            // the phone used to destroy a running wrist workout (#510).
            if LiveMirror.isLiveElsewhere(session.sessionId) { continue }
            if session.completedSetLogs.isEmpty {
                // Emit before delete — the op needs the sessionId, and
                // the wrist needs the discard to clear its journal.
                LiveMirror.shared.closeRemotely(session, discarded: true)
                modelContext.delete(session)
            } else {
                // Anchor to the last real activity: the crash-to-reopen
                // gap is not training time (#503).
                session.finish(at: session.lastActivityAt)
                LiveMirror.shared.closeRemotely(session, discarded: false)
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

    /// A workout — scheduled OR ad-hoc — was completed today (Dave,
    /// 2026-07-24). The day is a "win" when this holds AND nothing
    /// scheduled is still outstanding; the rest-day placeholder yields to
    /// the completed card + week-ahead in that case (the timeline already
    /// shows what's done and what's coming up).
    private var completedAnyToday: Bool {
        sessions.contains { session in
            session.endedAt.map { calendar.isDate($0, inSameDayAs: today) } ?? false
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

    /// The routine's due state, anchored to the later of joining the
    /// library and the last schedule change (`scheduleAnchor`) so a
    /// freshly added routine never carries a day it wasn't around for
    /// (2026-07-14), and a freshly SET schedule never banks tomorrow
    /// against a completion that predates it (2026-07-23).
    private func dueState(of routine: Routine) -> RoutineSchedule.DueState {
        let completions = recentCompletions(of: routine)
        return routine.schedule.dueState(
            lastCompleted: completions.last,
            previousCompleted: completions.previous,
            today: today,
            addedOn: routine.scheduleAnchor,
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
                addedOn: routine.scheduleAnchor,
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
            // calendar fact, not a call to action. Its date rides the
            // entry's own row (build 161); two routines on one future
            // day each print it, the per-entry rule everywhere.
            TimelineItem(node: .inert, dateline: railDay(entry.day)) {
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
    /// nothing here is an entry. Unlabeled (Dave, 2026-07-23: the rail's
    /// all-caps headings died — its old "BEYOND THIS WEEK" header read
    /// as a section header for the DATED cards below, which are the next
    /// 7 days; position and the undated phrasing carry the meaning).
    private var beyondThisWeekBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(scheduledRoutines) { routine in
                    Text("\(routine.schedule.recurrenceLabel) · \(routine.name)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(factLineLimit)
                }
            }
            .padding(.vertical, 10)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The anytime card, wired to Today's start machinery. Quick starts
    /// commit through `startQuick` (the pending-flag config-sheet route
    /// stays the CUSTOM escape); Train's two paths are the scratch start
    /// and a handoff to the Routines tab — a pointer, never a second
    /// copy of the library.
    private var anytimeCard: some View {
        AnytimeCard(
            exercises: quickStartExercises,
            lastOuting: { lastOutingLine(for: $0) },
            onStart: { startQuick($0) },
            onCustom: { quickStartConfig = SessionExerciseConfig(exercise: $0) },
            onStartEmpty: { startEmptySession() },
            onChooseRoutine: { onGoToRoutines() },
            onEdit: { editingQuickStarts = true }
        )
    }

    /// "last · 5.1 km · 28 min" — the sport panel's memory, from the most
    /// recent finished session that logged this exercise. One exercise,
    /// first match, panel-only: never the per-row relationship walk the
    /// history list can't afford. nil when there's no history (a first
    /// outing needs no caption).
    private func lastOutingLine(for exercise: Exercise) -> String? {
        guard let session = sessions.first(where: { session in
            session.completedSetLogs.contains { $0.exerciseName == exercise.name }
        }) else { return nil }
        let logs = session.completedSetLogs.filter { $0.exerciseName == exercise.name }
        var parts: [String] = []
        let distance = logs.compactMap { $0.actual(.distance) }.reduce(0, +)
        if distance > 0 {
            // ⚠️ The LOG's snapshot unit, never the live profile's: the
            // stored distance is in the unit it was logged under, and a
            // later unit edit must not relabel history (rule-5 class;
            // the overview reads the same way — swift-reviewer).
            let unit = logs.first?.metricProfile.distanceUnit ?? exercise.metricProfile.distanceUnit
            parts.append(WorkoutMetric.distance.displayText(distance, distanceUnit: unit))
        }
        let seconds = logs.compactMap(\.actualDuration).reduce(0, +)
        if seconds > 0 {
            parts.append(seconds < 60 ? "<1 min" : "\(seconds / 60) min")
        }
        guard !parts.isEmpty else { return nil }
        return "last · " + parts.joined(separator: " · ")
    }

    /// "sat · aug 2" — one grammar for every entry's date row.
    private func railDay(_ date: Date) -> String {
        let weekday = date.formatted(.dateTime.weekday(.abbreviated)).lowercased()
        let day = date.formatted(.dateTime.month(.abbreviated).day()).lowercased()
        return "\(weekday) · \(day)"
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
                        .lineLimit(2)
                    Text(futureCaption(for: entry))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(factLineLimit)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 12)
            // 10, matching the missed card — the two rows share an
            // anatomy (name + caption + chevron), so they share a
            // rhythm (design review 2026-07-23, finding 8).
            .padding(.vertical, 10)
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

    /// "~40 min" — the date left the card for the entry's own date row
    /// (build 161), so the caption is down to the estimate.
    private func futureCaption(for entry: UpcomingEntry) -> String {
        entry.routine.estimateText
    }

    // MARK: - Carried over (missed occurrences)

    /// A quiet cluster between today's work and the history below: routines
    /// whose most recent scheduled day lapsed within the carry window
    /// (Kit `.missed`, 2026-07-14). No marker, no caption (Dave,
    /// 2026-07-23: the rail's all-caps headings died, and the old
    /// explainer line truncated mid-sentence on device) — the cards
    /// carry it alone: amber ink, an amber node, and a past-dated row
    /// say lapsed-but-open without an obligation word.
    @ViewBuilder
    private var carriedOverSection: some View {
        ForEach(missedEntries) { entry in
            // Amber node, amber card: a lapsed occurrence is neither the
            // green "today" nor the grey "not yet" — it's the warm
            // in-between (the notes/advisory amber already in the grammar).
            // The lapsed day IS its date row (build 161), printed plain
            // since 2026-08-01: amber ink, an amber node and the rail
            // position carry the tense, and VoiceOver hears "carried
            // over" from the row's own label. Never today's date.
            TimelineItem(
                node: .inert,
                strokeOverride: Theme.notes,
                dateline: missedDateline(entry),
                datelineColor: Theme.notes,
                datelineAccessibilityLabel: "\(missedDateline(entry)), carried over"
            ) {
                missedCard(entry)
            }
        }
    }

    /// "tue · jul 7" — the carried entry's date row, in the rail's one
    /// date grammar. ⚠️ The "was" prefix is GONE (Dave, build 161 device
    /// pass): every other entry prints a bare date, and a date in the
    /// past under an amber node beside an amber card is already past
    /// tense. The word was carrying tense the position had covered since
    /// the dates left the cards.
    private func missedDateline(_ entry: MissedEntry) -> String {
        railDay(entry.since)
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
                        .lineLimit(2)
                    Text(missedCaption(entry))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.notes)
                        .lineLimit(factLineLimit)
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
                    .strokeBorder(Theme.notesRing, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("missedRoutine-\(entry.routine.name)")
    }

    /// "~30 min" — the lapsed day moved to the entry's date row (build
    /// 160), leaving the card the estimate.
    private func missedCaption(_ entry: MissedEntry) -> String {
        entry.routine.estimateText
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
        // ONE pool definition, four consumers (#505 review) — the
        // rail, the tab icon, the widget and the recap must never
        // disagree about what completed a routine.
        WorkoutSession.recentCompletionDates(of: routine, in: sessions)
    }

    /// Committed history in month runs, newest first (#506, Q11-A) —
    /// the record's only landmarks. Keyed by year AND month so a
    /// December→January crossing never folds two years into one run;
    /// the label carries the year only when it isn't this one, which
    /// keeps the common case short ("august", not "august 2026").
    private var sessionMonths: [(key: String, label: String, sessions: [WorkoutSession])] {
        // The day token, so a run resident across midnight (or New
        // Year) re-derives its labels with the rest of the surface.
        _ = dayToken
        let calendar = Calendar.current
        let now = Date()
        // ⚠️ ADJACENT walk, not a dictionary of `dateComponents` (the
        // #506 review): the query is newest-first, so months are
        // already contiguous — one `isDate(equalTo:toGranularity:)`
        // per session, no components allocation, no keyed lookups.
        // This body re-runs on every pull frame and every landing beat,
        // and eager per-session work here is the exact O(sessions)
        // class the LazyVStack comment above memorializes.
        var runs: [(key: String, label: String, sessions: [WorkoutSession])] = []
        for session in sessions {
            let date = session.startedAt
            if var last = runs.last,
               let head = last.sessions.first,
               calendar.isDate(head.startedAt, equalTo: date, toGranularity: .month),
               calendar.isDate(head.startedAt, equalTo: date, toGranularity: .year) {
                last.sessions.append(session)
                runs[runs.count - 1] = last
                continue
            }
            let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
            let label = date
                .formatted(sameYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
                .lowercased()
            let parts = calendar.dateComponents([.year, .month], from: date)
            runs.append((key: "\(parts.year ?? 0)-\(parts.month ?? 0)", label: label, sessions: [session]))
        }
        return runs
    }

    /// The committed run, in month sections (#506, Q11-A).
    ///
    /// ⚠️ EXTRACTED, not inlined in the timeline stack: nesting a
    /// `Section` + inner `ForEach` inside that already-enormous
    /// ViewBuilder pushed it past the type-checker's budget outright
    /// ("unable to type-check this expression in reasonable time",
    /// CI on the first push). A `some View` boundary is what keeps the
    /// stack checkable — anything added to this timeline from here on
    /// belongs in its own property for the same reason.
    /// Everything on the rail that is NOT history: the anytime offer,
    /// today's dated group, the setup scaffold while it runs, and the
    /// carried-over lane. Its own property for the reason the comment on
    /// `committedHistory` gives — this timeline stack is at the
    /// type-checker's budget, and a `Section` wrapping four more entries
    /// inline is exactly what tips it.
    @ViewBuilder
    private func presentEntries(viewportHeight: CGFloat) -> some View {
        // The ANYTIME entry (Dave, build 161): quick start as a card ON
        // the rail — below the future, above whatever today holds, every
        // day. Its node is solid like every other; the card's dashed
        // shell is what says "offer, not occurrence".
        // It reveals once the KIT is settled (#505, Q25-A): step 1 keeps
        // the landing's focus, and from step 2 on a spontaneous run is a
        // valid second door — a committed session dissolves the scaffold
        // naturally.
        if !setupActive || equipmentStepDone {
            TimelineItem(node: .offer, dateline: "anytime") {
                anytimeCard
            }
        }
        // A broken sync, said once, where you already are (#509, Q19-A).
        // ⚠️ Moved UP from the bottom of this stack (review): under the
        // carried-over lane it was an advisory a long timeline hides, and
        // an advisory nobody scrolls to is the drawer's red dot again.
        //
        // ⚠️ But NOT first, which is where the review put it. First is the
        // landing slot — the opening `scrollTo` seats whatever follows the
        // week-ahead directly under the band, and navigation.md spends that
        // slot on the ANYTIME row deliberately. Taking over the landing on
        // every open until someone fixes their token is what an ALARM does,
        // and design-grammar's amber law is explicit that this isn't one:
        // nothing is lost, the edits are on the device, they push the
        // moment the connection is repaired. Second is enough — it is on
        // screen at landing either way, directly under the card it sits
        // below, and it costs the rail's normal content nothing.
        //
        // ⚠️ Which is why it carries the ANYTIME row's own gate rather than
        // trusting position (second review round): the anytime entry is
        // conditional, so "second" was incidental, and in the one state that
        // hides it — a fresh install still on setup step 1 — the advisory
        // WAS first, in the landing slot, on a phone whose owner hasn't done
        // anything yet. Reachable: restore onto a new phone, connect, pull a
        // template-only repo, then break the connection. Sharing the gate
        // makes the invariant structural: whenever this can render, the row
        // above it rendered too. It costs a fresh install one setup step of
        // silence, which is the right trade on the surface that is teaching
        // them the app.
        if sync.isBackupBroken, !setupActive || equipmentStepDone {
            brokenSyncEntry
        }
        // TODAY is ONE dated group (the build-161 restructure: dates pop
        // out of the cards, the node centers on the date row, cards hang
        // below). Every card of the day shares this one date row.
        // ⚠️ The whole ENTRY is gated, not just its cards: a date row with
        // nothing under it is a rail entry that isn't one (Dave, build 161
        // device pass — carried-over work suppresses the rest-day card,
        // which left "today · sat · aug 1" standing alone over the amber
        // lane). Today earns a row when it has something to show; the
        // carried entries right below carry their own dates.
        if todayGroupHasCards {
            TimelineItem(
                node: dueRoutines.isEmpty ? .inert : .pending,
                dateline: "today · \(todayDateText)"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if showsRestDayCard {
                        restDayCard
                    }
                    ForEach(dueButEmptyRoutines) { routine in
                        // Inert grey by intent lives on the CARD now (the
                        // group node reads the day): the routine isn't
                        // startable — its CTA repairs, it doesn't perform.
                        emptyRoutineCard(routine)
                    }
                    ForEach(dueRoutines) { routine in
                        pendingCard(routine)
                            .matchedTransitionSource(id: routine.persistentModelID, in: zoomNamespace)
                    }
                }
            }
        }
        if setupActive {
            setupSection(viewportHeight: viewportHeight)
        }
        // Carried-over occurrences (Kit .missed): a past scheduled day
        // that lapsed, shown calmly between today's work and the history
        // below — never as a green due, never dressed as today's date.
        if !missedEntries.isEmpty {
            carriedOverSection
        }
    }

    /// An expired or revoked GitHub connection. It used to live ONLY as a
    /// red dot in the drawer — a surface you might not open for weeks while
    /// local edits piled up un-backed-up, which is the one thing a backup
    /// failing quietly must not do.
    ///
    /// ⚠️ It is gated on `sync.isBackupBroken`, NOT on the drawer row's
    /// `isFaulted` (review): `faulted` is set by any failed CONNECT attempt
    /// — a dropped wifi mid-device-flow, an expired code, a Cancel on
    /// github.com — so someone who tried sync once, failed, and never came
    /// back would otherwise get a permanent card promising their workouts
    /// were safe in a backup that never existed. `lastSyncedAt` is written
    /// only by a pass that SUCCEEDED, so it is the honest gate. The drawer
    /// row keeps the broader predicate on purpose: a red dot on a row you
    /// went looking for is a status, not a claim.
    ///
    /// ⚠️ The dateline is a TIME, not a label (copy review): every rail
    /// entry puts a temporal value in that slot — a date, "today",
    /// "anytime" — so a categorical noun there reads as a rendering fault
    /// rather than a class. "waiting" is also the literal truth: the
    /// workouts are on the device waiting to go up. ("pending" was
    /// proposed and is wrong in the other direction — a stopped
    /// connection is not about to resume by itself.)
    ///
    /// ⚠️ The app's word is SYNC, not "backup" (copy review): the drawer
    /// section, the tray's own copy and the coordinator all say sync.
    /// "Backup" appears once, descriptively, inside the tray.
    ///
    /// ⚠️ AMBER, not red, and that is the whole judgment (design-grammar:
    /// amber is advisory, never alarm). Nothing is lost — the edits are on
    /// the device and will push the moment the connection is fixed — so an
    /// alarm would be a lie about the stakes. It wears the carried-over
    /// lane's exact idiom for the same reason: this is work waiting on
    /// something, not work gone wrong.
    ///
    /// The anti-shame law governs PERFORMANCE, not plumbing; a backup that
    /// stopped working is a fact about the app, not about the user, so
    /// stating it plainly breaks nothing.
    private var brokenSyncEntry: some View {
        TimelineItem(
            node: .inert,
            strokeOverride: Theme.notes,
            dateline: "waiting",
            datelineColor: Theme.notes,
            datelineAccessibilityLabel: "Waiting"
        ) {
            Button {
                NotificationCenter.default.post(name: .plusplusOpenSyncTray, object: nil)
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("GitHub sync stopped")
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        // ⚠️ Metadata shape, like every other caption on the
                        // rail (review): lowercase mono facts joined by "·",
                        // not a sentence. "tap to reconnect" left with the
                        // chevron that already says it — a card whose whole
                        // body is one button doesn't need the instruction
                        // spelled out, and VoiceOver gets it as a hint.
                        //
                        // ⚠️ NOT "paused" (copy review): nobody paused this,
                        // it broke, and the title one line up already says
                        // stopped. And not "safe on this phone" either —
                        // amber plus "nothing lost" carries the reassurance
                        // without narrating where the bytes are. What the
                        // second half buys is the part the title can't say:
                        // this resumes, and reconnecting is what resumes it.
                        Text("nothing lost · syncs when you reconnect")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.notes)
                            .lineLimit(factLineLimit)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(.caption2, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface.opacity(reduceTransparency ? 1 : 0.55), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(Theme.notesRing, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("brokenSyncAdvisory")
            .accessibilityHint("Opens GitHub sync")
        }
    }

    /// History's MONTH landmarks (#506, Q11-A): one flat newest-first run
    /// had nothing to orient by at depth.
    ///
    /// ⚠️ They are plain ROWS, not pinned `Section` headers (build 162,
    /// Dave: "the band must pin at the top and not be usurped by anything
    /// else"). A scroll gets exactly ONE sticky header, the week band owns
    /// it, and a second `Section` here would take the pin away the moment
    /// history came into view. The landmark still does its job — it names
    /// the month you are reading — it just travels with the rail instead
    /// of holding the top.
    @ViewBuilder
    private var committedHistory: some View {
        ForEach(sessionMonths, id: \.key) { month in
            monthHeader(month.label)
            ForEach(month.sessions) { session in
                // The just-finished session converts on landing
                // (recap-close animation): its node turns from
                // actionable green to the done purple checkmark,
                // which seals it. Every other committed card rests
                // at that filled checkmark node. The date rides the
                // entry's own row (build 161) — two workouts one day
                // print the day twice, which is what a log does.
                committedEntry(session)
            }
        }
    }

    /// One committed entry. Its own function so neither the conversion
    /// ternaries nor `TimelineItem`'s five arguments land inside a
    /// `ForEach` inside a `Section` inside the timeline stack.
    private func committedEntry(_ session: WorkoutSession) -> some View {
        let converting = justCompletedID == session.persistentModelID
        return TimelineItem(
            node: .committed,
            dateline: railDay(session.startedAt),
            converting: converting,
            converted: converting && completionConverted
        ) {
            committedCard(session)
                .scaleEffect(converting && !completionConverted ? 0.97 : 1.0)
        }
    }

    /// A month landmark on the rail. Lowercase mono like every other
    /// date line (the rail's all-caps headings died 2026-07-23 round 2b
    /// — this is a DATE, and it speaks the datelines' own grammar).
    /// ⚠️ Two things the pin needs: the spine draws THROUGH it so the
    /// rail reads unbroken while it holds the top, and its background
    /// bleeds past the stack's 16 pt column — rows slide under a pinned
    /// header, and the gutters would otherwise show them through (the
    /// sticky-band law's own trap).
    private func monthHeader(_ label: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .frame(width: 20)
            Text(label)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
        .background {
            Theme.background
                .padding(.horizontal, -16)
        }
        .accessibilityAddTraits(.isHeader)
    }

    /// The last time each staged exercise was performed, summarized
    /// plan-stably. The rules live in `RoutineLedger` (2026-07-29; upheld
    /// 2026-07-30) so routine detail's rail reads the same "last time" this
    /// card does.
    private func prior(for routineExercise: RoutineExercise) -> RoutineDiff.Prior? {
        RoutineLedger.prior(for: routineExercise, in: sessions)
    }

    /// One staged exercise: its prescription, and how it last actually went.
    private struct LedgerEntry {
        let entry: RoutineExercise
        let exercise: Exercise
        let profile: MetricProfile
        let target: RoutineDiff.Target
        let prior: RoutineDiff.Prior?
    }

    /// What the pending card draws where the one-line diff summary used to
    /// be: the moved rows, plus enough to name the state when there are none.
    private struct LedgerContent {
        let rows: [DiffLedgerRow]
        /// Nothing here has ever been performed — the routine is unrun.
        let isFirstTime: Bool
        let hasExercises: Bool
    }

    private func ledgerEntries(for routine: Routine) -> [LedgerEntry] {
        var entries: [LedgerEntry] = []
        for group in routine.sortedGroups {
            for entry in group.sortedExercises {
                guard let exercise = entry.exercise else { continue }
                let profile = exercise.metricProfile
                entries.append(LedgerEntry(
                    entry: entry,
                    exercise: exercise,
                    profile: profile,
                    target: RoutineDiff.Target(
                        name: exercise.name,
                        isDuration: profile.legacyType == .duration,
                        // The block's rounds. Superset members each run once
                        // per round, so every entry in the group carries the
                        // group's count — which is what `prior` counts back.
                        sets: group.sets,
                        weight: entry.weight,
                        reps: entry.reps,
                        repsUpper: entry.repsUpper,
                        durationSeconds: entry.durationSeconds,
                        extras: entry.extraTargets.filter { profile.contains($0.key) },
                        distanceUnit: profile.distanceUnit
                    ),
                    prior: prior(for: entry)
                ))
            }
        }
        return entries
    }

    /// The ledger in the shape the routine calls for. A ONE-exercise routine
    /// varies by metric, so its rows are metrics and the card title already
    /// names the exercise; anything larger varies by exercise. Movers only
    /// either way — an unchanged row states nothing, the standing law.
    private func ledger(for routine: Routine) -> LedgerContent {
        let entries = ledgerEntries(for: routine)
        guard !entries.isEmpty else {
            return LedgerContent(rows: [], isFirstTime: false, hasExercises: false)
        }
        // Nothing here has run yet: the card says so in words rather than
        // listing every exercise against an empty column.
        guard !entries.allSatisfy({ $0.prior == nil }) else {
            return LedgerContent(rows: [], isFirstTime: true, hasExercises: true)
        }

        if entries.count == 1, let only = entries.first, let prior = only.prior {
            return LedgerContent(rows: metricRows(only, prior: prior), isFirstTime: false, hasExercises: true)
        }

        var rows: [DiffLedgerRow] = []
        for (index, item) in entries.enumerated() {
            // The uuid is effectively always present, but a store migrated
            // before the backfill runs can hold nil — and two blocks of the
            // same exercise is an anticipated shape, so the fallback carries
            // the position to keep ForEach identity unique.
            let id = item.entry.uuid?.uuidString ?? "\(index)·\(item.exercise.name)"
            guard let prior = item.prior else {
                // Added since the last run. It states its target against an
                // empty column rather than vanishing — dropping it would let
                // the card claim "same as last time" over an exercise that
                // has never been done, which is the one thing on the card
                // worth knowing.
                rows.append(DiffLedgerRow(
                    id: id,
                    label: item.exercise.name,
                    target: Prescription.blockRuns(target: item.target, profile: item.profile, weightUnit: weightUnit),
                    prev: [],
                    changed: [],
                    isNew: true
                ))
                continue
            }
            let moved = RoutineDiff.movedFields(target: item.target, prior: prior, profile: item.profile)
            guard !moved.isEmpty else { continue }
            rows.append(DiffLedgerRow(
                id: id,
                label: item.exercise.name,
                target: Prescription.blockRuns(target: item.target, profile: item.profile, weightUnit: weightUnit),
                prev: Prescription.blockRuns(prior: prior, profile: item.profile, weightUnit: weightUnit),
                changed: moved,
                directions: RoutineDiff.movedDirections(target: item.target, prior: prior, profile: item.profile),
                isNew: false
            ))
        }
        return LedgerContent(rows: rows, isFirstTime: false, hasExercises: true)
    }

    /// One row per moved field, in the profile's canonical order.
    /// `movedFields` guarantees both sides carry a value, so no row here can
    /// render a half-empty comparison.
    private func metricRows(_ item: LedgerEntry, prior: RoutineDiff.Prior) -> [DiffLedgerRow] {
        let moved = RoutineDiff.movedFields(target: item.target, prior: prior, profile: item.profile)
        let directions = RoutineDiff.movedDirections(target: item.target, prior: prior, profile: item.profile)
        let fields: [RoutineDiff.Field] = [.sets] + item.profile.metrics.map { .metric($0) }
        return fields.filter(moved.contains).compactMap { field -> DiffLedgerRow? in
            guard let staged = item.target.value(for: field),
                  let last = prior.value(for: field) else { return nil }
            func runs(_ value: Double, repsUpper: Int?) -> [PrescriptionRun] {
                [PrescriptionRun(
                    Prescription.text(
                        for: field,
                        value: value,
                        repsUpper: repsUpper,
                        distanceUnit: item.profile.distanceUnit,
                        weightUnit: weightUnit
                    ),
                    field
                )]
            }
            return DiffLedgerRow(
                id: fieldKey(field),
                label: fieldLabel(field),
                // A range belongs to the plan; a performance is one count.
                target: runs(staged, repsUpper: item.target.repsUpper),
                prev: runs(last, repsUpper: nil),
                changed: moved,
                directions: directions,
                isNew: false
            )
        }
    }

    private func fieldKey(_ field: RoutineDiff.Field) -> String {
        switch field {
        case .sets: "sets"
        case .metric(let metric): metric.rawValue
        }
    }

    /// Lowercase, like every other metadata caption on the rail.
    private func fieldLabel(_ field: RoutineDiff.Field) -> String {
        switch field {
        case .sets: "sets"
        case .metric(let metric): metric.label.lowercased()
        }
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
        let names = Set(session.completedSetLogs.map(\.exerciseName))
        let candidates = sessions.filter { other in
            let sameRoutine: Bool
            if let a = other.routine, let b = session.routine {
                sameRoutine = a === b
            } else {
                // The same shared-exercise gate the record's Δ header
                // wears (#505, b7): the card's net chip and the record
                // must resolve the SAME previous session, and a name
                // pair with nothing in common is a number about nothing.
                sameRoutine = other.routineName == session.routineName
                    && !names.isDisjoint(with: other.completedSetLogs.map(\.exerciseName))
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
        // defers ~0.85 s — long enough for a second Start to flash (a
        // double start orphans a session, which would wedge every future
        // start and salvage) or for an anytime-card key to raise a sheet
        // (the config sheet, the picker, the Health primer) — and setting
        // activeSession under a live sheet is the documented
        // presentation-drop class: the cover never presents, the saved
        // session has no screen (swift-reviewer, twice). A tap that
        // raced a presentation simply loses.
        guard activeSession == nil, quickStartConfig == nil,
              !editingQuickStarts, healthStartRequest == nil else { return }
        // First workout gets the Health primer; after that (or under UI
        // test) this begins immediately. The start runs from the primer's
        // onDismiss, so re-check activeSession at fire time — the sheet can
        // sit open for seconds.
        HealthStartGate.begin({
            guard activeSession == nil else { return }
            // ActiveSessionView requests notification permission on appear.
            activeSession = WorkoutSession.start(from: routine, context: modelContext)
        }, orPresent: { healthStartRequest = $0 })
    }

    /// The quick-start picks, resolved from names to live catalog rows.
    /// A name that no longer resolves (a deleted custom) simply drops out
    /// rather than rendering a dead key.
    private var quickStartExercises: [Exercise] {
        let names = QuickStartPicks.names(from: quickStartRaw)
        let byName = Dictionary(
            allExercises.filter { !$0.isDeleted }.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return names.compactMap { byName[$0] }
    }

    /// Everything a quick-start key could reasonably be: the cardio the
    /// catalog knows. A one-tap row for a bench press is not the problem
    /// this solves, and an unfiltered catalog would bury the four rows
    /// that are.
    private var quickStartCandidates: [Exercise] {
        allExercises
            .filter { !$0.isDeleted && $0.modality.isCardio }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// One tap from the tray to moving: start a scratch session and plant
    /// the configured block in it.
    ///
    /// ⚠️ It IS a scratch session (#239), not a parallel mechanism — so it
    /// lands in history, salvages on crash, never auto-finishes, and can
    /// graduate to a routine afterwards, all for free. And it routes
    /// through `HealthStartGate` like every other start, or the first
    /// workout would skip the Health primer.
    private func startQuick(_ config: SessionExerciseConfig) {
        // The same fire-time guard row as start(_:), and for the same
        // reason since the anytime panels wired StartFlashButton straight
        // in: the deferred fire can land after a same-panel Custom… tap
        // has already presented the config sheet (the panel's removal
        // transition outlives nothing — the 0.85 s flash outlives IT),
        // and setting activeSession under a live sheet is the
        // presentation-drop class (swift-reviewer, anytime round).
        guard activeSession == nil, quickStartConfig == nil,
              !editingQuickStarts, healthStartRequest == nil else { return }
        HealthStartGate.begin({
            guard activeSession == nil else { return }
            let session = WorkoutSession.startEmpty(context: modelContext)
            // The sport is the name (#505, Q9-A): a week of runs read
            // as identical "Scratch workout" cards forever, and the
            // Δ-vs-previous matcher paired every scratch session by
            // that one shared name. The marker is what keeps the
            // sport name OUT of a same-named routine's completion
            // pool (`WorkoutSession.completions`).
            session.routineName = config.exercise.name
            session.isQuickStart = true
            _ = session.appendExercise(config: config, context: modelContext)
            activeSession = session
        }, orPresent: { healthStartRequest = $0 })
    }

    /// The no-plan session (#239): starts empty, gets filled on the
    /// gym floor. An empty scratch session is safe to abandon — the
    /// orphan salvage deletes 0-set sessions, and the empty stage never
    /// auto-finishes, so nothing 0-set can commit.
    private func startEmptySession() {
        // Same fire-time guard row as start(_:)/startQuick — Train's
        // "Start empty" rides the same deferred flash (swift-reviewer).
        guard activeSession == nil, quickStartConfig == nil,
              !editingQuickStarts, healthStartRequest == nil else { return }
        HealthStartGate.begin({
            guard activeSession == nil else { return }
            activeSession = WorkoutSession.startEmpty(context: modelContext)
        }, orPresent: { healthStartRequest = $0 })
    }

    // MARK: - Week strip

    /// The Today header band: the week strip alone, as PINNED CHROME on
    /// the scroll's shell (`safeAreaInset`, the catalogs' #494 mount).
    /// Not scroll content, not a sticky trick, no reservation, no
    /// visualEffect — Dave, build 159, after three rounds of in-scroll
    /// placements each still reading as "part of the timeline". Facts
    /// only since build 161: the quick-start rack moved to the rail's
    /// anytime card, and the band is back to the week's two quiet lines.
    private var weekStripBand: some View {
        VStack(alignment: .leading, spacing: 0) {
            // FACTS ONLY (Dave, build 161): the quick-start rack left the
            // band for the rail's anytime card, so the band is back to
            // two quiet lines — the tally and its bar. Still pinned
            // chrome; the starts are timeline content now.
            weekStrip
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque, because the timeline slides UNDER it — and BLED back
        // out past the timeline's 16 pt column, the month landmarks'
        // own idiom: the band is full-width chrome sitting inside a
        // padded stack, so without this the rows would show at the
        // margins as they pass beneath it. It draws nothing when the
        // strip is empty: a zero-height view with a background is
        // invisible.
        .background {
            Theme.background
                .padding(.horizontal, -16)
        }
        // The shelf: the hairline routine detail's pinned band already
        // draws (2026-07-30) — rows sliding under the band need its edge
        // to be a drawn fact, not an inference.
        // ⚠️ Gated, because a zero-HEIGHT band still has WIDTH and an
        // overlaid hairline would draw across it: during the setup
        // scaffold the strip collapses, and a stray line under the title
        // is the exact invisible-edge class the shelf exists to fix. The
        // gate mirrors the strip's own — change it there, change it here.
        .overlay(alignment: .bottom) {
            if !(setupActive && !allSetupDone) && weekPlan.planned > 0 {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                    .padding(.horizontal, -16)
            }
        }
    }

    /// The week's status: the tally line + the block bar, holding the top of
    /// the scroll, directly under the navigation bar.
    ///
    /// ⚠️ **PINNED CHROME, by Dave's build-159 reversal of the 2026-07-27
    /// sticky law** — pinned as the timeline's first SECTION HEADER since
    /// build 162, never a top `safeAreaInset` (which desynced the system
    /// large title; see the mount).
    /// The history matters: pinned is where this STARTED, and build 152
    /// killed it because the pull walks the large title down over pinned
    /// chrome. That cost is now accepted knowingly — the pull is the #1
    /// device check, and the sticky mechanism at 8b9e16b is the recorded
    /// fallback if it reads broken on glass.
    ///
    /// ⚠️ It does NOT ride the rail (Dave, reversing the first cut of this
    /// round): it keeps the screen's 16 pt content column and its full-width
    /// bar, so it reads as a BAND across the surface — the week header it is —
    /// rather than a timeline entry indented into the caption column.
    ///
    /// The title and the two keys that used to sit above this are the
    /// navigation bar's now.
    @ViewBuilder
    private var weekStrip: some View {
        let plan = weekPlan
        let showsBar = !(setupActive && !allSetupDone) && plan.planned > 0
        let line = caption(plan: plan)
        // Nothing to say (no plan, past setup) means no strip at all — not an
        // empty box holding padding open under the title.
        if line != nil || showsBar {
            VStack(alignment: .leading, spacing: 0) {
                if let line {
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                }
                // The week block bar: one block per scheduled session this
                // week, filled purple as sessions land. Purple, not green —
                // it counts what's committed, and it hides entirely when
                // nothing is scheduled (no plan, no empty scorecard).
                if showsBar {
                    BlockBar(total: plan.planned, filled: plan.completed)
                        .padding(.top, 8)
                        // The caption above already states the fact for
                        // VoiceOver; without this the bar announces a bare
                        // "2 of 4" with no subject (a11y, 2026-07-23).
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Both pads sit INSIDE the band's opaque background, so they are
            // also the clearance that keeps a row from touching the tally as
            // it slides under.
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
    }

    /// The week ahead, plus the opening anchor — ONE eager child of the
    /// band's section (build 163).
    ///
    /// ⚠️ Eager, and that is load-bearing: it makes the whole block one
    /// realized `LazyVStack` child, laid out in full with an exact height.
    /// A `LazyVStack` sizes UNREALIZED children approximately, and the
    /// opening `scrollTo` aims at an anchor below this block, so lazy rows
    /// above that anchor land the landing off by their estimation error
    /// (#267). Hoisted out of the `Section` builder to keep this file's
    /// largest ViewBuilder under the type-checker's budget.
    ///
    /// ⚠️ **The anchor is a zero-LAYOUT overlay held one band-height above
    /// this block's bottom, not a zero-height row at the bottom** (review).
    /// `ScrollViewProxy.scrollTo(anchor: .top)` aligns to the visible
    /// content top and knows nothing about a pinned header, so a bottom-
    /// seated anchor puts today's first row BEHIND the band by exactly the
    /// band's height. The old placement escaped this only because the
    /// section used to BEGIN at the anchor, which made the band the first
    /// thing on screen by construction rather than by intent. An overlay
    /// reserves no space, so nothing moves at rest.
    @ViewBuilder
    private var weekAheadBlock: some View {
        VStack(spacing: 0) {
            if showsFutureSection {
                futureSection
            }
        }
        // ⚠️ No horizontal padding here: the enclosing stack already carries
        // the 16 pt column. It needed its own while it was a SIBLING of that
        // stack; inside it, a second pad insets the week ahead by 32 and jogs
        // the rail's spine 16 pt at the anytime boundary (review).
        .overlay(alignment: .bottom) {
            Color.clear
                .frame(height: bandHeight)
                .allowsHitTesting(false)
                .id(Self.todayAnchorID)
        }
    }

    /// The pinned band's height, DERIVED from UIFont metrics rather than
    /// measured — the landing has to seat today's content below the pin, and
    /// a geometry probe that writes state is the one thing navigation.md
    /// bans anywhere in the TabView subtree (it breaks the search-role
    /// morph). Zero while the band draws nothing, so the landing degrades to
    /// its old exact behaviour during setup.
    ///
    /// ⚠️ This mirrors `weekStrip`'s own gating and constants. Change one,
    /// change the other — the same rule the shelf overlay already carries.
    private var bandHeight: CGFloat {
        let plan = weekPlan
        let showsBar = !(setupActive && !allSetupDone) && plan.planned > 0
        let hasLine = caption(plan: plan) != nil
        guard hasLine || showsBar else { return 0 }
        // The band's own vertical pads (6 top, 12 bottom). The hairline shelf
        // is an overlay, so it costs no layout height.
        var height: CGFloat = 6 + 12
        if hasLine {
            height += UIFont.preferredFont(forTextStyle: .caption1).lineHeight
        }
        if showsBar {
            // BlockBar's top pad, then the bar itself (9 pt; the 13 pt
            // variant is the live-block Differentiate Without Color case,
            // which a plain progress bar never enters).
            height += 8 + 9
        }
        return height
    }

    private var weekPlan: (completed: Int, planned: Int) {
        WeekPlan.counts(routines: routines, sessions: sessions, today: today, calendar: calendar)
    }

    /// The header's status line — setup progress, or the week tally.
    /// The DATE left the header (Dave's ask): it belongs on today's
    /// item, and now rides the timeline's TODAY marker. Nil when there's
    /// nothing to say (no plan, past setup) so the line drops entirely.
    private func caption(plan: (completed: Int, planned: Int)) -> String? {
        // No "setup N of 3" line under the title (Dave, 2026-07-17): the
        // timeline's own steps already carry their "N of 3" badges, so a
        // header echo was redundant — during setup the caption simply drops.
        guard !(setupActive && !allSetupDone) else { return nil }
        // The week tally is calendar fact, not obligation (#172-safe:
        // it never says what's LEFT, only what the plan holds and what
        // has landed). No "N due" tally — the staged cards ARE that.
        // "Workouts", never "sessions" (#144: performed things are
        // workouts; "session" is the type name, not the vocabulary).
        guard plan.planned > 0 else { return nil }
        return "\(plan.completed) of \(plan.planned) workout\(plan.planned == 1 ? "" : "s") this week"
    }

    // MARK: - Pending card

    private func pendingCard(_ routine: Routine) -> some View {
        let content = ledger(for: routine)
        let expandedLedger = Binding(
            get: { routine.uuid.map(expandedLedgers.contains) ?? false },
            set: { isOpen in
                guard let uuid = routine.uuid else { return }
                if isOpen { expandedLedgers.insert(uuid) } else { expandedLedgers.remove(uuid) }
            }
        )

        // The shared routine metadata, judged against the active kit (Today
        // now amber-flags a missing piece like the rest of the app), without
        // a schedule tier.
        let todayMeta = RoutineMeta(
            routine: routine,
            activeNames: activeLibrary?.memberNames ?? [],
            includeSchedule: false
        )

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
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(.caption2, weight: .bold))
                            .foregroundStyle(Theme.textFaint)
                    }

                    // The shared metadata (2026-07-22): a terse focus ·
                    // estimate line, then the equipment tier — amber-first, so
                    // a piece the active kit lacks flags here too (Today used
                    // to drop availability). No schedule — the card's presence
                    // on Today IS the schedule statement. Inert: the enclosing
                    // NavigationLink owns the tap.
                    if !todayMeta.todayLine.isEmpty {
                        Text(todayMeta.todayLine)
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(factLineLimit)
                            .padding(.top, 9)
                    }
                    if !todayMeta.gear.isEmpty {
                        RoutineEquipmentTags(gear: todayMeta.gear)
                            .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("configureRoutineButton")

            // The ledger sits OUTSIDE the navigating region, beside Start
            // rather than inside the link, because its expander is a tap
            // target: nested in the link it would race the push, which is
            // this card's documented silent-dead-tap class.
            if !content.rows.isEmpty {
                DiffLedger(rows: content.rows, expanded: expandedLedger)
                    .padding(.top, 10)
            } else if content.hasExercises {
                // Never render nothing (Dave, 2026-07-27). An absent region
                // reads as "no information" where the fact is "you are
                // repeating a session on purpose", which is a legitimate
                // thing to be doing and states itself in quiet ink.
                Text(content.isFirstTime ? "first time · sets the baseline" : "same as last time")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(content.isFirstTime ? Theme.accent : Theme.textFaint)
                    .lineLimit(factLineLimit)
                    .padding(.top, 8)
                    .accessibilityIdentifier("diffSummary")
            }

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

    // MARK: - Committed card

    private func committedCard(_ session: WorkoutSession) -> some View {
        NavigationLink(value: SessionRecordDestination(session: session)) {
            HStack(spacing: 8) {
                // Done reads on the rail node now — a filled purple checkmark
                // dot (Dave, 2026-07-24) — so the card itself carries no seal.
                // (Superseded the 2026-07-14 on-card check.)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.routineName)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(committedSubtitle(session))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                if let gain = netGain(for: session),
                   let text = RoutineDiff.summary(deltas: [.weight(gain)], weightUnit: weightUnit).first?.text {
                    // The soft r6 data-tag treatment, accent-tinted: a
                    // net gain is data, not a button — the stroked
                    // capsule predated the 2026-07-20 shape sweep and
                    // read as a control (design review 2026-07-23).
                    CardTagCapsule(text: text, tint: Theme.accent)
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
        // The smoke suite's only handle on the way into a record. Today prints
        // a routine's name in more than one row (the card, and the "Routine
        // created" entry under it), so a text match reached one that goes
        // nowhere and the flow sat here waiting for a screen it never opened.
        // An identifier only — no traits, no `.combine` — since either would
        // flatten the row and take its child texts out of the tree.
        .accessibilityIdentifier("committedSessionCard")
    }

    private func committedSubtitle(_ session: WorkoutSession) -> String {
        // No date here (build 161): it rides the entry's own date row,
        // and a fact printed twice an inch apart reads as a glitch.
        var parts: [String] = []
        if let count = WorkUnit.summaryCount(
            session.summaryWorkUnit,
            session.completedSetLogs.count
        ) {
            parts.append(count)
        }
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

    /// The INTERACTIVE scaffold (reveal-upward scroll, headroom) shows
    /// until the first real session commits. After that the same steps
    /// still render — as permanent origin milestones pinned to the bottom
    /// of the timeline (Dave, 2026-07-24) — but without the onboarding
    /// chrome; `setupActive` gates only the interactive treatment.
    private var setupActive: Bool { sessions.isEmpty }

    private var equipmentStepDone: Bool { SetupState.equipmentDone }
    private var routineStepDone: Bool { !routines.isEmpty }
    private var scheduleStepDone: Bool {
        // No-schedule is a fully valid completion (#505, Q26-A — the
        // anti-obligation stance): the stored freestyle choice counts,
        // exactly as equipment's own done flag does (#232).
        routines.contains { $0.schedule.normalized != .unscheduled } || trainingFreestyle
    }

    private var allSetupDone: Bool { equipmentStepDone && routineStepDone && scheduleStepDone }

    /// Bottom-up like commits: equipment is the first entry (bottom),
    /// schedule the last (top). Each step gates on the one below it.
    private func setupSection(viewportHeight: CGFloat) -> some View {
        Group {
            SetupRow(
                state: scheduleStepDone ? .done : (routineStepDone ? .ready : .gated),
                badge: "3 of 3",
                title: "Schedule it",
                // Freestyle-done names the CHOICE, not a schedule that
                // doesn't exist; a later real schedule takes the title
                // back (#505, Q26-A).
                doneTitle: scheduledRoutines.isEmpty ? "Training freestyle" : "Schedule set",
                sub: scheduleStepDone ? scheduleDoneSub : "Days or a pace. It shows up here on its day.",
                gatedSub: "Needs a routine first",
                cta: "Choose days or a pace",
                identifier: "setupScheduleStep",
                action: { scheduleEditTarget = scheduleEditRoutine?.uuid.map(IdentifiedUUID.init)},
                edit: { scheduleEditTarget = scheduleEditRoutine?.uuid.map(IdentifiedUUID.init)},
                quietCTA: (
                    label: "Train freestyle",
                    identifier: "setupTrainFreestyle",
                    run: { trainingFreestyle = true }
                )
            )
            // Stable per-step scroll anchor (constant across the step's
            // gated/ready/done states, so identity never churns): the
            // reveal-upward scroll seats the active step here.
            .id(Self.setupScheduleAnchor)
            SetupRow(
                state: routineStepDone ? .done : (equipmentStepDone ? .ready : .gated),
                badge: "2 of 3",
                title: "Create your first routine",
                doneTitle: routines.count == 1 ? "Routine created" : "Routines created",
                sub: routineStepDone ? routineDoneSub : "From the catalog, or from scratch.",
                gatedSub: "Needs your equipment first",
                cta: "Pick a routine",
                identifier: "setupRoutineStep",
                // Lands on the Routines tab, which IS the routine catalog now
                // (2026-07-25): yours, then everything you could add. The
                // standalone catalog screen and the pre-scoped search deep link
                // both retired into it.
                action: { onGoToRoutines() },
                edit: { onGoToRoutines() }
            )
            .id(Self.setupRoutineAnchor)
            SetupRow(
                state: equipmentStepDone ? .done : .ready,
                badge: "1 of 3",
                // The first card is title + key only — no sub (Dave,
                // 2026-07-17: the question carries it; explaining the
                // mechanism here was noise).
                title: "What do you train with?",
                doneTitle: "Equipment set",
                sub: equipmentStepDone ? equipmentDoneSub : "",
                gatedSub: "",
                cta: "Pick your equipment",
                identifier: "setupEquipmentStep",
                action: { showingEquipmentSetup = true },
                edit: { showingEquipmentSetup = true }
            )
            .id(Self.setupEquipmentAnchor)
            // Reveal-upward headroom (2026-07-16, rebuilt 2026-07-25): the
            // scaffold reveals steps by scrolling the active one to the top,
            // which the BOTTOM step can only reach if scrollable space sits
            // below it. A viewport-tall, top-aligned box IS that space — and
            // since the box is exactly one screen, seating this step at the top
            // is also the furthest the list can scroll, so it can never be
            // pushed off.
            //
            // This replaces a `Color.clear` spacer sized `viewport - stepHeight`
            // from an `.onGeometryChange` probe on this row. That probe was the
            // documented iOS 26 morph trigger (nav-diag 4e): a layout observer
            // anywhere in the TabView subtree broke `Tab(role: .search)`'s morph
            // on FIRST activation, and the catalog surface hid its nav bar, so
            // the fallback placement had nowhere to render — no visible field at
            // all. Build 126 shipped straight into it. ⚠️ The search tab is gone
            // (2026-08-02) and with it that trigger, but the measurement stays
            // deleted on its own merits: `UIFont` metrics answer this without a
            // probe, and a probe here re-runs the whole timeline on every size
            // change.
            .frame(minHeight: setupActive ? viewportHeight : 0, alignment: .top)
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
        // Freestyle-done (#505, Q26-A): a valid state in its own words,
        // never an apology for a schedule that isn't there.
        if scheduled.isEmpty { return "No set days. Workouts land here as you do them." }
        let labels = scheduled.prefix(2).map(\.schedule.shortLabel).joined(separator: " · ")
        return scheduled.count > 2 ? labels + " · …" : labels
    }

    /// The routine the schedule step edits: the first already-scheduled
    /// one, else the first routine.
    private var scheduleEditRoutine: Routine? {
        routines.first { $0.schedule.normalized != .unscheduled } ?? routines.first
    }

    // MARK: - Empty states

    /// A card in TODAY's dated group, not a floating empty state: rest
    /// days are part of the record too. (Its TimelineItem wrapper died
    /// in the build-160 restructure — the group's date row carries the
    /// node now.)
    private var restDayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
                Text(restDayTitle)
                    .font(.system(.body, weight: .semibold))
                Text(restDayItemCaption)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                // A true rest day carries NO start key (Dave, 2026-07-12):
                // rest is the point, and the anytime card sits directly
                // above for a workout anyway. The card only offers an
                // action when it's NOT resting: creation when no routine
                // can start, or the "Start a workout" prompt when one is
                // due-but-empty / mid-setup.
                if startableRoutines.isEmpty {
                    // No startable routine → offer creation directly,
                    // with the no-plan escape (#239) beside it.
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
                        startEmptySession()
                    } label: {
                        HStack(spacing: 6) {
                            // play.fill: the button STARTS something. It
                            // begins a build-as-you-go session directly —
                            // the start tray died with the play key
                            // (build 159); routines start from their own
                            // cards and the Routines tab.
                            Image(systemName: "play.fill")
                                .font(.system(.caption, weight: .semibold))
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
                    // Not "startWorkoutButton": routine detail already
                    // uses that for its own Start, and one identifier
                    // naming two different acts is a test trap.
                    .accessibilityIdentifier("startScratchWorkoutButton")
                }
                // The schedule offer (#246): routines exist, none
                // scheduled, and nothing on Today ever said scheduling
                // exists — one offer-shaped line, gone the moment any
                // schedule does. Below the action: it's a footnote-
                // weight suggestion, not this card's job. During setup
                // the scaffold's own step is the offer.
                if !setupActive, !scheduledRoutinesExist, !startableRoutines.isEmpty {
                    QuietKey(
                        label: "Schedule a routine",
                        identifier: "scheduleOfferButton"
                    ) {
                        showingScheduleRoutine = true
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }

    /// A scheduled routine with nothing in it, on its day (#246): name
    /// the state and point at the fix — the only prior rendering was a
    /// "Rest day" card denying the routine existed.
    private func emptyRoutineCard(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(routine.name)
                .font(.system(.body, weight: .semibold))
            Text("no exercises yet · it can start once it has some")
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

    /// The rest-day card yields to the setup scaffold until a startable
    /// routine exists — "nothing scheduled" and "schedule it (3 of 3)"
    /// saying the same thing twice reads broken. Once a routine CAN start,
    /// it returns (#246): scheduling is optional and must not read as the
    /// only path to working out. It also yields when carried-over work
    /// exists (2026-07-14): the CARRIED OVER lane is the actionable surface
    /// then. A won day (a workout completed, nothing scheduled outstanding)
    /// shows no placeholder (Dave, 2026-07-24). A due-but-empty repair
    /// prompt (promptsWorkout) still shows.
    private var showsRestDayCard: Bool {
        dueRoutines.isEmpty && missedEntries.isEmpty
            && !(completedAnyToday && !promptsWorkout)
            && (!setupActive || allSetupDone || !startableRoutines.isEmpty)
    }

    /// Whether TODAY's dated group holds any card at all — a card-less day
    /// renders its date row alone, with no phantom content gap.
    private var todayGroupHasCards: Bool {
        showsRestDayCard || !dueButEmptyRoutines.isEmpty || !dueRoutines.isEmpty
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
            return "Scheduling is optional. Start whenever you like."
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
                : "No routine on the calendar. Start one whenever."
        }
        let day = best.date.formatted(.dateTime.weekday(.abbreviated)).lowercased()
        // Within the week "next thu" is unambiguous; further out the
        // bare weekday would lie by omission — add the plain date
        // (#267: a banked occurrence can push "next" past the week).
        if let weekBoundary = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: today)),
           best.date > weekBoundary {
            let monthDay = best.date.formatted(.dateTime.month(.abbreviated).day()).lowercased()
            return "on pace · next \(day) · \(monthDay) · \(best.name)"
        }
        return "on pace · next \(day) · \(best.name)"
    }
}

/// Push destination for a committed session record. A tiny wrapper so
/// the destination is Hashable without making the @Model itself the
/// path element in two different roles.
struct SessionRecordDestination: Hashable {
    let session: WorkoutSession
}

/// Why a routine-start deep link couldn't start (renamed/removed
/// routine, or a workout already running) — alert-presented, because a
/// tapped calendar event or Siri phrase that silently does nothing
/// reads as the app being broken.
private struct StartLinkFailure {
    let title: String
    let message: String?
}

/// One row of the Today rail: node in a fixed-width gutter with a
/// continuous 2 px spine, card alongside. Nodes are uniform-diameter
/// (Dave, 2026-07-24): the actionable/inert/gated states are stroke-only
/// RINGS whose color carries meaning (green = actionable now, grey =
/// inert, faint = gated), and DONE is a FILLED purple checkmark circle —
/// the seal moved off the committed card onto its rail node (superseding
/// the build-33 rings-only rule and the 2026-07-14 on-card check). All
/// nodes share one diameter so the row reads even, checkmark and all.
private enum TimelineNode: Equatable {
    /// Ready to do — a green ring. Green marks the next increment.
    case pending
    /// Nothing actionable here (rest day) — neutral grey ring.
    case inert
    /// Done — a filled purple checkmark circle (GitHub's merged hue).
    case committed
    /// A setup step whose prerequisite isn't met yet — border-faint,
    /// so the rail reads "not yet yours".
    case gated
    /// An OFFER on the rail (the anytime entry) — a neutral ring, same
    /// as `.inert`. ⚠️ It shipped build 161 DASHED, to echo the card's
    /// shell; on glass an 18 pt circle of 2.6 pt dashes reads as a
    /// rendering fault rather than a grammar (Dave). The card's own
    /// dashed border carries "offer"; the dot just marks the row.
    case offer

    var strokeColor: Color {
        switch self {
        case .pending: Theme.accent
        case .inert, .offer: Theme.textFaint
        case .gated: Theme.borderStrong
        case .committed: Theme.done
        }
    }
}

private struct TimelineItem<Content: View>: View {
    let node: TimelineNode
    /// Overrides a RING node's color (the carried-over lane's amber node).
    /// Ignored by the committed done-fill, which is always purple.
    var strokeOverride: Color? = nil
    /// The entry's own date row (Dave, the build-160 restructure: dates
    /// POP OUT of the cards). When set, it renders as the entry's first
    /// line, the node centers on IT, and the cards hang below. nil keeps
    /// the node beside the content's first line — the setup rows' look,
    /// the one undated entry class left.
    var dateline: String? = nil
    /// The dateline's ink — faint by default; the carried lane's date
    /// stays advisory amber.
    var datelineColor: Color = Theme.textFaint
    /// What the date row SAYS when the ink is the only thing saying it.
    /// ⚠️ The carried lane needs this (2026-08-01): with the "was" prefix
    /// gone, a lapsed entry prints the same bare date a future one does
    /// and differs only in amber ink and rail position — colour alone
    /// (WCAG 1.4.1), and nothing at all through VoiceOver. The visible
    /// row stays bare; the state rides the spoken label.
    var datelineAccessibilityLabel: String? = nil
    /// The just-finished card animates green → purple done on landing.
    /// While `converting` is true and `converted` is false the node shows
    /// the pre-flip green ring; once `converted`, it seals into the done
    /// fill with a bounce. Both false everywhere else (a resting committed
    /// node just shows the done fill; every other node its ring).
    var converting: Bool = false
    var converted: Bool = false
    @ViewBuilder let content: () -> Content

    /// One diameter for every node so the row reads even — big enough that
    /// the done checkmark stays legible (Dave, 2026-07-24).
    private static var diameter: CGFloat { 18 }

    /// The done fill shows for a resting committed node, and for the
    /// converting one once it has flipped; the pre-flip converting node
    /// still wears the green ring.
    private var showsDoneFill: Bool {
        node == .committed && (!converting || converted)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                marker(diameter: Self.diameter)
                    // Dot and date share a centerline: the date row stands
                    // exactly one node-diameter tall inside the content's
                    // 5 pt pad, so a 5 pt top inset centers the dot on it.
                    // Undated entries keep the old card-first-line seat.
                    .padding(.top, dateline == nil ? 14 : 5)
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 8) {
                if let dateline {
                    Text(dateline)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(datelineColor)
                        .accessibilityLabel(datelineAccessibilityLabel ?? dateline)
                        // minHeight, not height: AX type sizes outgrow
                        // 18 pt and a fixed frame doesn't clip — the row
                        // grows and the node reads top-aligned there,
                        // which beats overlap (swift-reviewer).
                        .frame(minHeight: Self.diameter, alignment: .leading)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func marker(diameter dot: CGFloat) -> some View {
        if showsDoneFill {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: dot, weight: .bold))
                .foregroundStyle(Theme.done)
                .frame(width: dot, height: dot)
                .background(Circle().fill(Theme.background))
                // Bounce on the SEAL only (showsDoneFill false→true at the
                // beat), not on cleanup: `converted` flips back to false when
                // justCompletedID clears while the node stays filled, and a
                // `value: converted` bounce would re-fire then. `showsDoneFill`
                // stays true through cleanup and never changes for a resting
                // committed node, so it fires exactly once (swift-reviewer).
                .symbolEffect(.bounce, options: .nonRepeating, value: showsDoneFill)
                .transition(.scale.combined(with: .opacity))
        } else {
            Circle()
                .strokeBorder(strokeOverride ?? (converting ? Theme.accent : node.strokeColor), lineWidth: 2)
                .frame(width: dot, height: dot)
                .background(Circle().fill(Theme.background))
                .transition(.opacity)
        }
    }
}

/// One setup step on the Today rail (setup-as-timeline handoff).
/// Three states: done reads like a committed entry (purple .committed
/// node — Dave keeps finished tasks purple, design review 2026-07-23 —
/// solid card, an edit affordance); ready is a dashed pending card with
/// its "N of 3" badge and a full-width CTA; gated is the same card
/// dimmed, non-interactive, its sub explaining the prerequisite.
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
    /// A quiet second door under the CTA (#505, Q26-A): the schedule
    /// step's "no schedule" completion — a fully valid choice, so it
    /// renders as the escape-hatch key grammar, never as a skip.
    var quietCTA: (label: String, identifier: String, run: () -> Void)? = nil

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
                // A step may carry no sub at all (the equipment card is
                // title + key only) — skip the row entirely so no orphan
                // padding survives.
                if !sub.isEmpty {
                    Text(sub)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 5)
                }
                Button(action: action) {
                    Text(cta)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.onPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                }
                .buttonStyle(.raisedPrimaryKey())
                .accessibilityIdentifier(identifier)
                .padding(.top, 10)
                if let quietCTA {
                    QuietKey(label: quietCTA.label, identifier: quietCTA.identifier, action: quietCTA.run)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
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


/// The "Schedule a routine" tray (Dave, 2026-07-24): PICK a routine, then
/// push its SCHEDULER. Reached from the rest-day card's schedule offer, and
/// the pushed screen is `ScheduleEditor` (extracted from `ScheduleTray`), so
/// scheduling reads identically wherever it opens. The push is a real
/// `NavigationStack` as of 2026-07-28 — it spent four days as a hand-rolled
/// horizontal slide, which is the thing that read janky.
private struct ScheduleRoutineTray: View {
    @Environment(\.dismiss) private var dismiss
    /// The whole library — an empty routine is still schedulable, so this is
    /// the full list, not the startable subset.
    let routines: [Routine]

    var body: some View {
        // A real NavigationStack, not the hand-rolled stage slide it shipped
        // with (2026-07-28) — see the law in .claude/rules/ui-interaction.md.
        // The back swipe, the titled back button and the settling sheet
        // height all come from the system now.
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader(title: "Schedule a routine", closeOnly: true) { dismiss() }
                    .padding(.horizontal, 18)
                picker
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.medium, .large])
    }

    // MARK: - Pick a routine

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if routines.isEmpty {
                    Text("no routines yet · create one first")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.vertical, 10)
                }
                ForEach(routines) { routine in
                    // A closure destination, so each push builds a FRESH
                    // `ScheduleEditor` and its @State re-seeds from that
                    // routine. The stage version reused one view and needed
                    // an `.id(persistentModelID)` to force the same thing.
                    NavigationLink {
                        ScheduleEditor(routine: routine)
                            .navigationTitle(routine.name)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(routine.name)
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                Text(rowCaption(for: routine))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Theme.textFaint)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            // The routine's CURRENT schedule, so an
                            // already-scheduled routine shows its cadence.
                            Text(routine.schedule.shortLabel)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Theme.textFaint)
                        }
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("scheduleRoutineRow")
                    .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
            .padding(.horizontal, 18)
        }
    }

    /// "6 exercises · ~40 min" — the go/no-go facts for picking.
    private func rowCaption(for routine: Routine) -> String {
        let count = routine.sortedGroups.reduce(0) { $0 + $1.sortedExercises.count }
        return "\(count) exercise\(count == 1 ? "" : "s") · \(routine.estimateText)"
    }
}
