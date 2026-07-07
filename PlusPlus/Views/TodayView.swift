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

    @State private var showingSettings = false
    @State private var showingSwapIn = false
    @State private var swapInPick: Routine?
    @State private var showingEquipmentSetup = false
    @State private var showingStarterSeed = false
    @State private var scheduleEditTarget: Routine?
    @State private var activeSession: WorkoutSession?
    @State private var expandedDiffs: Set<PersistentIdentifier> = []
    /// Bumped on day change so every Date()-based computed re-evaluates
    /// — without it, an app resident overnight keeps rendering
    /// yesterday's due list (bug hunt).
    @State private var dayToken = 0

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }
    private var calendar: Calendar { Calendar.current }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    // Lazy: the committed section is the whole history —
                    // eager building made every render O(sessions) (bug
                    // hunt perf finding).
                    LazyVStack(spacing: 0) {
                        // The rest-day item yields to the setup scaffold
                        // until every step is done — "nothing scheduled"
                        // and "schedule it (3 of 3)" saying the same
                        // thing twice reads broken.
                        if dueRoutines.isEmpty && (!setupActive || allSetupDone) {
                            restDayItem
                        }
                        ForEach(dueRoutines) { routine in
                            TimelineItem(node: .pending) {
                                pendingCard(routine)
                            }
                        }
                        if setupActive {
                            setupSection
                        }
                        ForEach(sessions) { session in
                            TimelineItem(node: .committed) {
                                committedCard(session)
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
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingSwapIn, onDismiss: {
                // Start only once the sheet is fully gone: dismissing a
                // sheet and presenting a cover in one transaction can
                // drop the presentation — with the session already
                // inserted, that left an invisible orphan (bug hunt).
                if let routine = swapInPick {
                    swapInPick = nil
                    start(routine)
                }
            }) {
                SwapInSheet(routines: routines.filter { !$0.groups.isEmpty }) { routine in
                    swapInPick = routine
                    showingSwapIn = false
                }
            }
            .fullScreenCover(item: $activeSession) { session in
                ActiveSessionView(session: session)
            }
            .sheet(isPresented: $showingEquipmentSetup) {
                EquipmentAccessSheet()
            }
            .sheet(isPresented: $showingStarterSeed) {
                StarterSeedSheet()
            }
            .sheet(item: $scheduleEditTarget) { routine in
                RoutineSettingsSheet(routine: routine)
                    .presentationDetents([.medium, .large])
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                dayToken += 1
            }
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

    private func dueCaption(for routine: Routine) -> String {
        guard let since = routine.schedule.dueSince(
            lastCompleted: lastCompleted(of: routine),
            today: today,
            calendar: calendar
        ) else { return "due today" }
        if calendar.isDateInToday(since) { return "due today" }
        // Within the week a weekday reads naturally; older than that,
        // "due since thu" would lie about how long it's been.
        if let days = calendar.dateComponents([.day], from: since, to: calendar.startOfDay(for: today)).day, days <= 6 {
            return "due since " + since.formatted(.dateTime.weekday(.abbreviated)).lowercased()
        }
        return "due since " + since.formatted(.dateTime.month(.abbreviated).day()).lowercased()
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HeaderGlyph()
                Spacer()
                HeaderIconButton(systemImage: "slider.horizontal.3", identifier: "settingsButton") {
                    showingSettings = true
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
        let due = dueRoutines.count
        return due == 0 ? date : "\(date) · \(due) due"
    }

    // MARK: - Pending card

    private func pendingCard(_ routine: Routine) -> some View {
        let lines = diffLines(for: routine)
        let segments = RoutineDiff.summary(deltas: lines.map(\.delta), weightUnit: weightUnit)
        let expanded = expandedDiffs.contains(routine.persistentModelID)

        return VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: routine) {
                HStack(spacing: 8) {
                    Text(routine.name)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(dueCaption(for: routine))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .buttonStyle(.plain)

            Text(metaLine(for: routine))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 5)

            Button {
                if expanded {
                    expandedDiffs.remove(routine.persistentModelID)
                } else {
                    expandedDiffs.insert(routine.persistentModelID)
                }
            } label: {
                HStack(spacing: 5) {
                    diffSummaryText(segments)
                        .lineLimit(1)
                    Text(" details")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                    Image(systemName: "chevron.down")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .animation(.easeOut(duration: 0.15), value: expanded)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .accessibilityIdentifier("diffSummary")

            if expanded {
                VStack(spacing: 0) {
                    ForEach(lines) { line in
                        HStack(spacing: 8) {
                            Text(line.name)
                                .font(.system(.caption))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(line.target)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                            deltaText(line.delta)
                                .frame(minWidth: 52, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.top, 6)
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
            .padding(.top, 10)
        }
        .padding(12)
        .background(Theme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    private func metaLine(for routine: Routine) -> String {
        let count = routine.sortedGroups.reduce(0) { $0 + $1.sortedExercises.count }
        let minutes = max(5, Int((Double(routine.estimatedSeconds) / 300).rounded()) * 5)
        var parts = ["\(count) exercise\(count == 1 ? "" : "s")", "~\(minutes) min"]
        if routine.schedule.normalized != .unscheduled {
            parts.append(routine.schedule.shortLabel)
        }
        return parts.joined(separator: " · ")
    }

    /// The colored summary line, composed as one Text so it truncates
    /// gracefully. Up = data green; down = neutral gray (deloads are
    /// intentional — celebrate-up only); new = info; "n =" faint.
    private func diffSummaryText(_ segments: [RoutineDiff.Segment]) -> Text {
        var result = Text("")
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                result = result + Text(" · ").font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.textFaint)
            }
            result = result + Text(segment.text)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(color(for: segment.kind))
        }
        return result
    }

    private func color(for kind: RoutineDiff.Segment.Kind) -> Color {
        switch kind {
        case .up: Theme.accent
        case .down: Theme.textSecondary
        case .new: Theme.info
        case .unchanged: Theme.textFaint
        }
    }

    private func deltaText(_ delta: RoutineDiff.Delta) -> some View {
        let segment = RoutineDiff.summary(deltas: [delta], weightUnit: weightUnit)[0]
        let text: String
        switch delta {
        case .unchanged: text = "="
        case .new: text = "new"
        default: text = segment.text
        }
        return Text(text)
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .foregroundStyle(delta == .unchanged ? Theme.textFaint : color(for: segment.kind))
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
                sub: scheduleStepDone ? scheduleDoneSub : "Days or a pace — due routines stage here",
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
                sub: routineStepDone ? routineDoneSub : "A starter split from the catalog, or a blank slate",
                gatedSub: "Needs your equipment first",
                cta: "Seed or start empty",
                identifier: "setupRoutineStep",
                action: { showingStarterSeed = true },
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
        TimelineItem(node: .pending) {
            VStack(alignment: .leading, spacing: 8) {
                Text(scheduledRoutinesExist ? "Rest day" : "Nothing scheduled")
                    .font(.system(.body, weight: .semibold))
                Text(restDayCaption)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    showingSwapIn = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(.caption, weight: .semibold))
                        Text("Swap in a routine")
                            .font(.system(.footnote, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderStrong))
                }
                .accessibilityIdentifier("swapInButton")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        }
    }

    private var scheduledRoutinesExist: Bool {
        routines.contains { $0.schedule.normalized != .unscheduled }
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
        guard let best else { return "Nothing scheduled — swap one in whenever" }
        let day = best.date.formatted(.dateTime.weekday(.abbreviated)).lowercased()
        return "on pace · next due \(day) — \(best.name)"
    }
}

/// Push destination for a committed session record. A tiny wrapper so
/// the destination is Hashable without making the @Model itself the
/// path element in two different roles.
struct SessionRecordDestination: Hashable {
    let session: WorkoutSession
}

/// One row of the Today rail: node in a fixed-width gutter with a
/// continuous 2 px spine, card alongside. Pending = hollow 8 pt node
/// with a SOLID border (dashes are not rail vocabulary); committed =
/// filled green 10 pt.
private enum TimelineNode {
    case pending
    case committed
    /// A setup step whose prerequisite isn't met yet — hollow like
    /// pending, but border-faint so the rail reads "not yet yours".
    case gated
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
                switch node {
                case .pending:
                    Circle()
                        .strokeBorder(Theme.textFaint, lineWidth: 2)
                        .frame(width: 10, height: 10)
                        .background(Circle().fill(Theme.background))
                        .padding(.top, 18)
                case .gated:
                    Circle()
                        .strokeBorder(Theme.borderStrong, lineWidth: 2)
                        .frame(width: 10, height: 10)
                        .background(Circle().fill(Theme.background))
                        .padding(.top, 18)
                case .committed:
                    Circle()
                        .fill(Theme.committedFill)
                        .frame(width: 10, height: 10)
                        .background(Circle().fill(Theme.background).frame(width: 14, height: 14))
                        .padding(.top, 18)
                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Swap in a routine", action: { dismiss() })

            Text("Off-schedule session — it commits to the timeline like any other")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 8)

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
