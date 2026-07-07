import SwiftUI
import SwiftData
import PlusPlusKit

/// Today — the unified timeline (#110, Claude Design v3 §3): pending
/// (staged) workouts on top, committed sessions below, one scroll on a
/// continuous rail. A pending entry is a workout the schedule says is
/// due (one entry per workout, max — a missed day carries over until
/// the next occurrence supersedes it). Committed entries are the
/// append-only record; no delete affordances, ever.
struct TodayView: View {
    /// Switches the root to the Workouts tab (first-run empty state).
    var onGoToWorkouts: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @Query(sort: [SortDescriptor(\Workout.order), SortDescriptor(\Workout.createdAt, order: .reverse)])
    private var workouts: [Workout]
    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]
    )
    private var sessions: [WorkoutSession]

    @State private var showingSettings = false
    @State private var showingSwapIn = false
    @State private var activeSession: WorkoutSession?
    @State private var expandedDiffs: Set<PersistentIdentifier> = []

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }
    private var calendar: Calendar { Calendar.current }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 0) {
                        if workouts.isEmpty && sessions.isEmpty {
                            firstRunCard
                                .padding(.top, 8)
                        } else {
                            if dueWorkouts.isEmpty {
                                restDayItem
                            }
                            ForEach(dueWorkouts) { workout in
                                TimelineItem(node: .pending) {
                                    pendingCard(workout)
                                }
                            }
                            ForEach(sessions) { session in
                                TimelineItem(node: .committed) {
                                    committedCard(session)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Workout.self) { workout in
                WorkoutDetailView(workout: workout)
            }
            .navigationDestination(for: SessionRecordDestination.self) { destination in
                SessionDetailView(session: destination.session)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingSwapIn) {
                SwapInSheet(workouts: workouts) { workout in
                    showingSwapIn = false
                    start(workout)
                }
            }
            .fullScreenCover(item: $activeSession) { session in
                ActiveSessionView(session: session)
            }
        }
    }

    // MARK: - Data assembly

    private var dueWorkouts: [Workout] {
        workouts.filter { workout in
            workout.schedule.dueState(
                lastCompleted: lastCompleted(of: workout),
                today: Date(),
                calendar: calendar
            ) == .due
        }
    }

    private func lastCompleted(of workout: Workout) -> Date? {
        sessions.first { $0.workout === workout || $0.workoutName == workout.name }?.endedAt
    }

    private func dueCaption(for workout: Workout) -> String {
        guard let since = workout.schedule.dueSince(
            lastCompleted: lastCompleted(of: workout),
            today: Date(),
            calendar: calendar
        ) else { return "due today" }
        if calendar.isDateInToday(since) { return "due today" }
        return "due since " + since.formatted(.dateTime.weekday(.abbreviated)).lowercased()
    }

    /// The last time each staged exercise was actually performed —
    /// newest finished session containing it, top completed set weight,
    /// last set's reps/duration.
    private func prior(for workoutExercise: WorkoutExercise) -> WorkoutDiff.Prior? {
        let exercise = workoutExercise.exercise
        let name = exercise?.name ?? ""
        for session in sessions {
            let matches = session.completedSetLogs.filter { log in
                if let a = log.exercise, let b = exercise { return a === b }
                return log.exerciseName == name
            }
            guard let last = matches.last else { continue }
            return WorkoutDiff.Prior(
                weight: matches.compactMap(\.actualWeight).max() ?? last.actualWeight,
                reps: last.actualReps,
                durationSeconds: last.actualDuration
            )
        }
        return nil
    }

    private struct DiffLine: Identifiable {
        let id: PersistentIdentifier
        let name: String
        let target: String
        let delta: WorkoutDiff.Delta
    }

    private func diffLines(for workout: Workout) -> [DiffLine] {
        var lines: [DiffLine] = []
        for group in workout.sortedGroups {
            for entry in group.sortedExercises {
                guard let exercise = entry.exercise else { continue }
                let target = WorkoutDiff.Target(
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
                    delta: WorkoutDiff.delta(target: target, prior: prior(for: entry))
                ))
            }
        }
        // Changed first, unchanged (with =) after, both in workout order.
        return lines.filter { $0.delta.isChange } + lines.filter { !$0.delta.isChange }
    }

    private func targetText(_ entry: WorkoutExercise, exercise: Exercise, sets: Int) -> String {
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
        guard let previous = sessions.first(where: {
            $0.workoutName == session.workoutName
                && ($0.endedAt ?? .distantPast) < (session.endedAt ?? .distantPast)
        }) else { return nil }
        let gain = WorkoutDiff.netWeightGain(current: topWeights(session), previous: topWeights(previous))
        return gain > 0 ? gain : nil
    }

    private func start(_ workout: Workout) {
        // ActiveSessionView requests notification permission on appear.
        activeSession = WorkoutSession.start(from: workout, context: modelContext)
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
        let date = Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).lowercased()
        let due = dueWorkouts.count
        return due == 0 ? date : "\(date) · \(due) due"
    }

    // MARK: - Pending card

    private func pendingCard(_ workout: Workout) -> some View {
        let lines = diffLines(for: workout)
        let segments = WorkoutDiff.summary(deltas: lines.map(\.delta), weightUnit: weightUnit)
        let expanded = expandedDiffs.contains(workout.persistentModelID)

        return VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: workout) {
                HStack(spacing: 8) {
                    Text(workout.name)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(dueCaption(for: workout))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .buttonStyle(.plain)

            Text(metaLine(for: workout))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 5)

            Button {
                if expanded {
                    expandedDiffs.remove(workout.persistentModelID)
                } else {
                    expandedDiffs.insert(workout.persistentModelID)
                }
            } label: {
                HStack(spacing: 0) {
                    diffSummaryText(segments)
                        .lineLimit(1)
                    Text("  details \(expanded ? "▴" : "▾")")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
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
                                .font(.system(.caption2, design: .monospaced))
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
                start(workout)
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

    private func metaLine(for workout: Workout) -> String {
        let count = workout.sortedGroups.reduce(0) { $0 + $1.sortedExercises.count }
        let minutes = max(5, Int((Double(workout.estimatedSeconds) / 300).rounded()) * 5)
        var parts = ["\(count) exercise\(count == 1 ? "" : "s")", "~\(minutes) min"]
        if workout.schedule.normalized != .unscheduled {
            parts.append(workout.schedule.shortLabel)
        }
        return parts.joined(separator: " · ")
    }

    /// The colored summary line, composed as one Text so it truncates
    /// gracefully. Up = data green; down = neutral gray (deloads are
    /// intentional — celebrate-up only); new = info; "n =" faint.
    private func diffSummaryText(_ segments: [WorkoutDiff.Segment]) -> Text {
        var result = Text("")
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                result = result + Text(" · ").font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.textFaint)
            }
            result = result + Text(segment.text)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(color(for: segment.kind))
        }
        return result
    }

    private func color(for kind: WorkoutDiff.Segment.Kind) -> Color {
        switch kind {
        case .up: Theme.accent
        case .down: Theme.textSecondary
        case .new: Theme.info
        case .unchanged: Theme.textFaint
        }
    }

    private func deltaText(_ delta: WorkoutDiff.Delta) -> some View {
        let segment = WorkoutDiff.summary(deltas: [delta], weightUnit: weightUnit)[0]
        let text: String
        switch delta {
        case .unchanged: text = "="
        case .new: text = "new"
        default: text = segment.text
        }
        return Text(text)
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .foregroundStyle(delta == .unchanged ? Theme.textFaint : color(for: segment.kind))
    }

    // MARK: - Committed card

    private func committedCard(_ session: WorkoutSession) -> some View {
        NavigationLink(value: SessionRecordDestination(session: session)) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.workoutName)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(committedSubtitle(session))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                if let gain = netGain(for: session) {
                    Text(WorkoutDiff.summary(deltas: [.weight(gain)], weightUnit: weightUnit)[0].text)
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

    // MARK: - Empty states

    private var firstRunCard: some View {
        VStack(spacing: 10) {
            Text("Nothing staged yet")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Button {
                onGoToWorkouts()
            } label: {
                Text("Create a workout")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 11))
            }
            .accessibilityIdentifier("firstRunCreateWorkout")
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    /// A timeline ITEM, not a floating empty state: rest days are part
    /// of the record too.
    private var restDayItem: some View {
        TimelineItem(node: .pending) {
            VStack(alignment: .leading, spacing: 8) {
                Text(scheduledWorkoutsExist ? "Rest day" : "Nothing scheduled")
                    .font(.system(.body, weight: .semibold))
                Text(restDayCaption)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    showingSwapIn = true
                } label: {
                    Text("⇄ Swap in a workout")
                        .font(.system(.footnote, weight: .semibold))
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

    private var scheduledWorkoutsExist: Bool {
        workouts.contains { $0.schedule.normalized != .unscheduled }
    }

    private var restDayCaption: String {
        var best: (date: Date, name: String)?
        for workout in workouts {
            let state = workout.schedule.dueState(
                lastCompleted: lastCompleted(of: workout),
                today: Date(),
                calendar: calendar
            )
            if case .notDue(let next) = state {
                if best == nil || next < best!.date {
                    best = (next, workout.name)
                }
            }
        }
        guard let best else { return "nothing scheduled — swap one in whenever" }
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
private struct TimelineItem<Content: View>: View {
    enum Node {
        case pending
        case committed
    }

    let node: Node
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

/// Off-schedule session picker (§3): choosing a workout starts it —
/// it commits to the timeline like any other session.
private struct SwapInSheet: View {
    @Environment(\.dismiss) private var dismiss
    let workouts: [Workout]
    let onPick: (Workout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Swap in a workout", action: { dismiss() })

            Text("off-schedule session — it commits to the timeline like any other")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 7) {
                    ForEach(workouts) { workout in
                        Button {
                            onPick(workout)
                        } label: {
                            HStack {
                                Text(workout.name)
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(workout.schedule.shortLabel)
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
