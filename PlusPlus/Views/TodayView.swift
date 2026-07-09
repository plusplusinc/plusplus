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
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var routines: [Routine]
    @Query(sort: \Equipment.name) private var equipment: [Equipment]
    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]
    )
    private var sessions: [WorkoutSession]

    @State private var showingAppMenu = false
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
    @State private var showingSetupCatalog = false
    @State private var scheduleEditTarget: Routine?
    @State private var activeSession: WorkoutSession?
    /// Bumped on day change so every Date()-based computed re-evaluates
    /// — without it, an app resident overnight keeps rendering
    /// yesterday's due list (bug hunt).
    @State private var dayToken = 0

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
        todayPath.append(routine)
    }

    var body: some View {
        NavigationStack(path: $todayPath) {
            VStack(spacing: 0) {
                header

                ScrollView {
                    // Lazy: the committed section is the whole history —
                    // eager building made every render O(sessions) (bug
                    // hunt perf finding).
                    LazyVStack(spacing: 0) {
                        // The rest-day item yields to the setup scaffold
                        // until a startable routine exists — "nothing
                        // scheduled" and "schedule it (3 of 3)" saying
                        // the same thing twice reads broken. Once a
                        // routine CAN start, the item returns (#246):
                        // scheduling is optional and must not read as
                        // the only path to working out.
                        if dueRoutines.isEmpty
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
                        ForEach(sessions) { session in
                            TimelineItem(node: .committed) {
                                committedCard(session)
                                    .matchedTransitionSource(id: session.persistentModelID, in: zoomNamespace)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Routine.self) { routine in
                RoutineDetailView(routine: routine)
            }
            .navigationDestination(for: SessionRecordDestination.self) { destination in
                SessionDetailView(session: destination.session)
                    .navigationTransition(.zoom(sourceID: destination.session.persistentModelID, in: zoomNamespace))
            }
            // Registered at the stack root, NOT inside RoutineCatalogScreen
            // (pushed below for setup step 2): a value destination declared
            // on a screen that is itself pushed failed to resolve in
            // production — template taps hit SwiftUI's missing-destination
            // placeholder (build 33).
            .navigationDestination(for: RoutineTemplate.self) { template in
                RoutineTemplateDetailScreen(template: template, path: $todayPath)
            }
            .navigationDestination(isPresented: $showingAppMenu) {
                AppMenuScreen()
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
                SwapInSheet(routines: swapInCandidates, onPick: { routine in
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
                ActiveSessionView(session: session)
                    .navigationTransition(.zoom(
                        sourceID: session.routine?.persistentModelID ?? session.persistentModelID,
                        in: zoomNamespace
                    ))
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
                // "your equipment supports" right after "Done —
                // bodyweight only" reads as a mistake (FTUE audit).
                equipment.contains(where: { $0.inLibrary && !$0.isDeleted })
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
            // routine at zero gear) died in its favor.
            .navigationDestination(isPresented: $showingSetupCatalog) {
                RoutineCatalogScreen(path: $todayPath)
            }
            .alert("New Routine", isPresented: $showingNewRoutine) {
                TextField("Name", text: $newRoutineName)
                Button("Cancel", role: .cancel) { newRoutineName = "" }
                Button("Create") { createRoutine() }
            }
            .navigationDestination(item: $scheduleEditTarget) { routine in
                RoutineSettingsScreen(routine: routine) {
                    scheduleEditTarget = nil
                    Task { @MainActor in
                        modelContext.delete(routine)
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
            !routine.groups.isEmpty && routine.schedule.dueState(
                lastCompleted: lastCompleted(of: routine),
                today: today,
                calendar: calendar
            ) == .due
        }
    }

    /// Scheduled-but-empty routines whose day this is (#246): they
    /// can't stage (the 0-set bug class), but silently rendering "Rest
    /// day" while the user's scheduled routine exists gaslights — the
    /// timeline names the state and points at the fix instead.
    private var dueButEmptyRoutines: [Routine] {
        routines.filter { routine in
            routine.groups.isEmpty && routine.schedule.dueState(
                lastCompleted: lastCompleted(of: routine),
                today: today,
                calendar: calendar
            ) == .due
        }
    }

    /// Identity match wins; the name fallback only applies when no
    /// session references this routine — two routines sharing a name
    /// must not satisfy each other's schedules (bug hunt). "Latest" is
    /// by endedAt, matching the comparison the schedule engine makes.
    private func lastCompleted(of routine: Routine) -> Date? {
        let identityMatches = sessions.filter { $0.routine === routine }
        let pool = identityMatches.isEmpty
            ? sessions.filter { $0.routineName == routine.name }
            : identityMatches
        return pool.compactMap(\.endedAt).max()
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
                durationSeconds: last.actualDuration
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
                let target = RoutineDiff.Target(
                    name: exercise.name,
                    isDuration: exercise.exerciseType == .duration,
                    weight: entry.weight,
                    reps: entry.reps,
                    durationSeconds: entry.durationSeconds
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
        if exercise.exerciseType == .duration {
            return "\(sets)× " + WorkoutMetric.duration.displayText(entry.durationSeconds.map(Double.init))
        }
        var text = "\(sets)×\(RepTarget(lower: entry.reps, upper: entry.repsUpper).display)"
        if let weight = entry.weight, weight > 0 {
            text += " @ " + WorkoutMetric.weight.displayText(weight, weightUnit: weightUnit)
        }
        return text
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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // The ++ is a button now (#266): the app-level page —
                // Settings, About, What's new, links, feedback.
                Button {
                    showingAppMenu = true
                } label: {
                    HeaderGlyph()
                        .frame(width: 44, height: 44)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.border))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("appMenuButton")
                Spacer()
                // Settings' old seat starts workouts instead (#266,
                // Dave's call): the one action that should never be
                // more than a tap away, via the existing start tray.
                // Green deliberately: starting MINTS a session — a
                // pending history entry being created (the v3 framing) —
                // so it rides the creation grammar like the other
                // header-circle buttons, not selection blue.
                HeaderIconButton(systemImage: "play", identifier: "startTrayButton", tint: Theme.accent) {
                    showingSwapIn = true
                }
            }
            Text("Today")
                .font(.system(.title, weight: .bold))
                .padding(.top, 10)
            Text(caption)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 3)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var caption: String {
        let date = today.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).lowercased()
        if setupActive && !allSetupDone {
            return "\(date) · setup \(setupDoneCount) of 3"
        }
        // No "N due" tally (#172): the staged cards below ARE the tally.
        return date
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
            // SSE tiers: name (+ the one go/no-go fact, the estimate)
            // with Configure as a real-but-subordinate bordered capsule —
            // Start stays the card's only filled element.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(routine.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(estimateText(for: routine))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                Spacer(minLength: 8)
                NavigationLink(value: routine) {
                    HStack(spacing: 4) {
                        Text("Configure")
                            .font(.system(.caption, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(.caption2, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .overlay(Capsule().strokeBorder(Theme.borderStrong, lineWidth: 1))
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("configureRoutineButton")
            }

            // Two meta rows: what it hits, what to have nearby. The
            // schedule label is gone — the card's presence on Today IS
            // the schedule statement.
            if let muscles = cappedList(musclesFor(routine)) {
                Text(muscles)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .padding(.top, 9)
            }
            Text(cappedList(gearFor(routine)) ?? "bodyweight")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .lineLimit(1)
                .padding(.top, 3)

            // The diff is the identity moment — it outranks the meta
            // above it (footnote semibold; unchanged tallies aren't news).
            if !segments.isEmpty {
                diffSummaryText(segments)
                    .lineLimit(1)
                    .padding(.top, 8)
                    .accessibilityIdentifier("diffSummary")
            }

            Button {
                start(routine)
            } label: {
                Text("Start")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 11))
            }
            .accessibilityIdentifier("startStagedButton")
            .padding(.top, 12)
        }
        .padding(12)
        .background(Theme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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

    private func estimateText(for routine: Routine) -> String {
        let minutes = max(5, Int((Double(routine.estimatedSeconds) / 300).rounded()) * 5)
        return "~\(minutes) min"
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
                action: { scheduleEditTarget = scheduleEditRoutine },
                edit: { scheduleEditTarget = scheduleEditRoutine }
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
                action: { showingSetupCatalog = true },
                edit: { onGoToRoutines() }
            )
            SetupRow(
                state: equipmentStepDone ? .done : .ready,
                badge: "1 of 3",
                title: "What do you have access to?",
                doneTitle: "Equipment set",
                sub: equipmentStepDone ? equipmentDoneSub : "What you own filters the catalog everywhere",
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
        let count = equipment.filter(\.inLibrary).count
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
                // The schedule offer (#246): routines exist, none
                // scheduled, and nothing on Today ever said scheduling
                // exists — one offer-shaped line, gone the moment any
                // schedule does. During setup the scaffold's own step
                // is the offer.
                if !setupActive, !scheduledRoutinesExist,
                   let target = swapInCandidates.first {
                    Button {
                        scheduleEditTarget = target
                    } label: {
                        Text("schedule a routine — it appears here on its day")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.selected)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("scheduleOfferButton")
                }
                // No candidates → no dead tray (#208): offer creation
                // directly instead.
                if swapInCandidates.isEmpty {
                    Button {
                        showingNewRoutine = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(.caption, weight: .semibold))
                            Text("New routine")
                                .font(.system(.footnote, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderStrong))
                    }
                    .accessibilityIdentifier("restDayNewRoutineButton")
                } else {
                    Button {
                        showingSwapIn = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(.caption, weight: .semibold))
                            // Shares the tray's vocabulary ("Start a
                            // workout") since #266 retitled it.
                            Text("Start a routine")
                                .font(.system(.footnote, weight: .semibold))
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderStrong))
                    }
                    .accessibilityIdentifier("swapInButton")
                }
                // The no-plan path (#239): walk in, start logging, keep
                // the result as a routine at the finish if it earned it.
                Button {
                    startEmptySession()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(.caption, weight: .semibold))
                        Text("Start empty workout")
                            .font(.system(.footnote, weight: .semibold))
                    }
                    // Creation is green (#202) — this births a session
                    // (and maybe a routine) from nothing.
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderStrong))
                }
                .accessibilityIdentifier("startEmptyWorkoutButton")
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
                todayPath.append(routine)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(.caption, weight: .semibold))
                    Text("Add exercises")
                        .font(.system(.footnote, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderStrong))
            }
            .accessibilityIdentifier("emptyRoutineAddButton")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }

    private var scheduledRoutinesExist: Bool {
        routines.contains { $0.schedule.normalized != .unscheduled }
    }

    /// "Rest day" is a claim — don't make it while an empty scheduled
    /// routine is due (the card above names that state) or mid-setup.
    private var restDayTitle: String {
        if (setupActive && !allSetupDone) || !dueButEmptyRoutines.isEmpty {
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
            let state = routine.schedule.dueState(
                lastCompleted: lastCompleted(of: routine),
                today: today,
                calendar: calendar
            )
            if case .notDue(let next) = state {
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
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Circle()
                    .strokeBorder(node.strokeColor, lineWidth: 2)
                    .frame(width: 10, height: 10)
                    .background(Circle().fill(Theme.background))
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
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 11))
                }
                .accessibilityIdentifier(identifier)
                .padding(.top, 10)
            }
            .padding(12)
            .background(Theme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
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
            .background(Theme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .opacity(0.55)
        }
    }
}

/// Off-schedule session picker (§3): choosing a routine starts it —
/// it commits to the timeline like any other session.
private struct SwapInSheet: View {
    @Environment(\.dismiss) private var dismiss
    let routines: [Routine]
    let onPick: (Routine) -> Void
    let onCreate: () -> Void
    let onStartEmpty: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "Start a workout", not "Swap in": the header's start
            // button opens this same tray (#266), and starting is what
            // every path in it does.
            SheetHeader(title: "Start a workout", closeOnly: true, action: { dismiss() })

            ScrollView {
                VStack(spacing: 7) {
                    ForEach(routines) { routine in
                        Button {
                            onPick(routine)
                        } label: {
                            HStack {
                                Text(routine.name)
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(routine.schedule.shortLabel)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Theme.textFaint)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
                        }
                    }

                    // Creation from the tray (#208) — green, like every
                    // other birth-of-something affordance.
                    Button {
                        onCreate()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(.caption, weight: .semibold))
                            Text("New routine")
                                .font(.system(.footnote, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.controlRadius)
                                .strokeBorder(Theme.borderStrong)
                        )
                    }
                    .accessibilityIdentifier("swapInCreateRoutine")

                    // The third path (#239): no template at all — log
                    // what happens and decide at the end if it's worth
                    // keeping as a routine.
                    Button {
                        onStartEmpty()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(.caption, weight: .semibold))
                            Text("Start empty workout")
                                .font(.system(.footnote, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.controlRadius)
                                .strokeBorder(Theme.borderStrong)
                        )
                    }
                    .accessibilityIdentifier("swapInStartEmpty")
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.surface)
        .presentationDetents([.medium, .large])
    }
}
