import SwiftUI
import SwiftData
import PlusPlusKit

/// Mid-workout overview (#66): every block of the session on a rail with
/// per-set pips, the live block highlighted. Tapping a block opens its
/// sheet for target edits and jump/redo navigation.
struct SessionOverviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: WorkoutSession
    /// Called after any jump so the presenter can clear a running rest.
    let onJumped: () -> Void

    @State private var selectedBlockKey: String?

    /// One row per exercise-within-group, in rotation order.
    struct Block: Identifiable {
        let key: String
        let name: String
        let groupIndex: Int
        let logs: [SetLog]
        var id: String { key }
    }

    private var blocks: [Block] {
        var order: [String] = []
        var byKey: [String: (name: String, groupIndex: Int, logs: [SetLog])] = [:]
        for log in session.sortedSetLogs {
            let key = "\(log.groupIndex)|\(log.exerciseName)"
            if byKey[key] == nil {
                byKey[key] = (log.exerciseName, log.groupIndex, [])
                order.append(key)
            }
            byKey[key]?.logs.append(log)
        }
        return order.compactMap { key in
            byKey[key].map { Block(key: key, name: $0.name, groupIndex: $0.groupIndex, logs: $0.logs) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.borderStrong).frame(width: 36, height: 4)
                .padding(.top, 8)

            HStack(alignment: .firstTextBaseline) {
                Text("Session").font(.system(.body, weight: .bold))
                Spacer()
                Text("elapsed \(elapsedText)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 6)

            List {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    blockRow(block, index: index)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 14))
                }
                Text("tap any row for detail · jump from there")
                    .font(.system(.caption2))
                    .foregroundStyle(Theme.textFaint)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 10)

            Button {
                dismiss()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(.footnote, weight: .bold))
                    Text("Back to now · \(backLabel)")
                        .font(.system(.subheadline, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 13))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .presentationBackground(Theme.surface)
        .sheet(item: selectedBlockBinding) { block in
            SessionExerciseSheet(session: session, block: block) {
                onJumped()
                selectedBlockKey = nil
                dismiss()
            }
            .presentationDetents([.fraction(0.84)])
        }
    }

    private var selectedBlockBinding: Binding<Block?> {
        Binding(
            get: { blocks.first { $0.key == selectedBlockKey } },
            set: { selectedBlockKey = $0?.key }
        )
    }

    private var elapsedText: String {
        let reference = session.endedAt ?? Date()
        let elapsed = max(0, Int(reference.timeIntervalSince(session.startedAt)))
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

    private var backLabel: String {
        guard let current = session.currentLog else { return "done" }
        return "\(current.exerciseName) · set \(current.setNumber)"
    }

    private func blockRow(_ block: Block, index: Int) -> some View {
        let isLive = session.currentLog.map { current in
            block.logs.contains { $0.order == current.order }
        } ?? false
        let allDone = block.logs.allSatisfy(\.isCompleted)

        return Button {
            selectedBlockKey = block.key
        } label: {
            HStack(spacing: 13) {
                RailGlyph(role: railRole(for: block, at: index), height: 52, dotY: 26)
                    .frame(width: 24, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(block.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(allDone ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(1)
                    Text(subText(for: block, isLive: isLive))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(isLive ? Theme.accent : Theme.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                HStack(spacing: 3) {
                    ForEach(Array(block.logs.enumerated()), id: \.offset) { _, log in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(pipColor(for: log))
                            .frame(width: 5, height: 13)
                    }
                }
            }
            .frame(height: 52)
            .background(isLive ? Theme.accent.opacity(0.09) : .clear)
        }
        .buttonStyle(.plain)
    }

    private func railRole(for block: Block, at index: Int) -> RailRole {
        let siblings = blocks.filter { $0.groupIndex == block.groupIndex }
        guard siblings.count > 1 else { return .solo }
        if siblings.first?.key == block.key { return .supersetFirst }
        if siblings.last?.key == block.key { return .supersetLast }
        return .supersetMiddle
    }

    private func pipColor(for log: SetLog) -> Color {
        if log.isCompleted { return Theme.accent }
        if let current = session.currentLog, current.order == log.order {
            return Theme.accent.opacity(0.45)
        }
        return Theme.border
    }

    private func subText(for block: Block, isLive: Bool) -> String {
        let done = block.logs.filter(\.isCompleted)
        if isLive, let current = session.currentLog {
            return "live · set \(current.setNumber)/\(block.logs.count)"
        }
        if !done.isEmpty {
            return done.map { resultFragment($0) }.joined(separator: " · ")
        }
        guard let template = block.logs.first else { return "" }
        if template.exerciseType == .duration {
            return "\(block.logs.count)×\(WorkoutMetric.duration.formatted(template.targetDuration.map(Double.init)))"
        }
        var text = "\(block.logs.count)×\(template.targetReps.display)"
        if let weight = template.targetWeight {
            text += " \(WorkoutMetric.weight.formatted(weight))"
        }
        return text
    }

    private func resultFragment(_ log: SetLog) -> String {
        log.exerciseType == .duration
            ? WorkoutMetric.duration.formatted(log.actualDuration.map(Double.init))
            : (log.actualReps.map(String.init) ?? "—")
    }
}

// MARK: - Session exercise sheet

/// Per-block sheet (#66): edit the remaining sets' targets, see each
/// set's outcome, and jump — Redo a logged set, Do now a pending one, or
/// skip straight to the block.
struct SessionExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @Bindable var session: WorkoutSession
    let block: SessionOverviewSheet.Block
    /// Called after any jump; the presenter unwinds to the live screen.
    let onJumped: () -> Void

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

    private var logs: [SetLog] {
        session.sortedSetLogs.filter { "\($0.groupIndex)|\($0.exerciseName)" == block.key }
    }

    private var pending: [SetLog] { logs.filter { !$0.isCompleted } }
    private var isLive: Bool {
        session.currentLog.map { current in logs.contains { $0.order == current.order } } ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.borderStrong).frame(width: 36, height: 4)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(statusText)
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(isLive ? Theme.accent : Theme.textSecondary)
                        .kerning(0.7)
                        .padding(.top, 10)
                    Text(block.name)
                        .font(.system(.title3, weight: .bold))
                        .padding(.top, 3)

                    if !pending.isEmpty {
                        targetEditor
                            .padding(.top, 12)
                        Text("edits apply to the remaining sets")
                            .font(.system(.caption2))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 5)
                    }

                    SheetSectionLabel("SETS")
                        .padding(.top, 14)
                    setRows

                    if let notes = logs.first?.exercise?.notes {
                        NotesBlock(notes)
                            .padding(.top, 13)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
            }

            VStack(spacing: 8) {
                if !isLive, let first = pending.first, !session.isFinished {
                    Button {
                        session.jump(to: first)
                        onJumped()
                        dismiss()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.right.to.line")
                                .font(.system(.footnote, weight: .bold))
                            Text("Skip to this exercise")
                                .font(.system(.subheadline, weight: .bold))
                        }
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .presentationBackground(Theme.surface)
    }

    private var statusText: String {
        if isLive, let current = session.currentLog {
            return "LIVE · SET \(current.setNumber) OF \(logs.count)"
        }
        return logs.allSatisfy(\.isCompleted) ? "DONE" : "UPCOMING"
    }

    // MARK: - Target editing (remaining sets)

    private var targetEditor: some View {
        VStack(spacing: 0) {
            if logs.first?.exerciseType == .duration {
                MetricStepperRow(
                    label: "Duration",
                    value: WorkoutMetric.duration.displayText(reference?.targetDuration.map(Double.init)),
                    identifier: "sxDuration",
                    onDecrement: { editPending { $0.targetDuration = stepDuration($0.targetDuration, -1) } },
                    onIncrement: { editPending { $0.targetDuration = stepDuration($0.targetDuration, 1) } }
                )
            } else {
                MetricStepperRow(
                    label: "Weight",
                    value: WorkoutMetric.weight.displayText(reference?.targetWeight, weightUnit: weightUnit),
                    identifier: "sxWeight",
                    onDecrement: { editPending { $0.targetWeight = WorkoutMetric.weight.decremented($0.targetWeight, weightUnit: weightUnit, stepOverride: $0.exercise?.weightStepOverride) } },
                    onIncrement: { editPending { $0.targetWeight = WorkoutMetric.weight.incremented($0.targetWeight, weightUnit: weightUnit, stepOverride: $0.exercise?.weightStepOverride) } }
                )
                MetricStepperRow(
                    label: "Reps",
                    value: reference.map { RepTarget(lower: $0.targetRepsLower, upper: $0.targetRepsUpper).display } ?? "—",
                    identifier: "sxReps",
                    onDecrement: { editPending { apply(RepTarget(lower: $0.targetRepsLower, upper: $0.targetRepsUpper).decremented(), to: $0) } },
                    onIncrement: { editPending { apply(RepTarget(lower: $0.targetRepsLower, upper: $0.targetRepsUpper).incremented(), to: $0) } }
                )
            }
        }
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    private var reference: SetLog? { pending.first ?? logs.first }

    private func editPending(_ mutate: (SetLog) -> Void) {
        for log in pending { mutate(log) }
    }

    private func apply(_ target: RepTarget, to log: SetLog) {
        log.targetRepsLower = target.lower
        log.targetRepsUpper = target.upper
    }

    private func stepDuration(_ value: Int?, _ direction: Double) -> Int {
        let stepped = direction > 0
            ? WorkoutMetric.duration.incremented(value.map(Double.init))
            : WorkoutMetric.duration.decremented(value.map(Double.init))
        return Int(stepped.rounded())
    }

    // MARK: - Set rows

    private var setRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                let isCurrent = session.currentLog?.order == log.order
                HStack(spacing: 10) {
                    Text("Set \(log.setNumber)")
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, alignment: .leading)
                    Text(setResult(log, isCurrent: isCurrent))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(setColor(log, isCurrent: isCurrent))
                    Spacer()
                    if !session.isFinished && !isCurrent {
                        Button {
                            session.jump(to: log, redo: log.isCompleted)
                            onJumped()
                            dismiss()
                        } label: {
                            Text(log.isCompleted ? "Redo" : "Do now")
                                .font(.system(.caption, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
            }
        }
    }

    private func setResult(_ log: SetLog, isCurrent: Bool) -> String {
        if log.isCompleted { return log.resultSummary(weightUnit: weightUnit) }
        if isCurrent { return "current set" }
        return "pending"
    }

    private func setColor(_ log: SetLog, isCurrent: Bool) -> Color {
        if log.isCompleted { return Theme.textPrimary }
        if isCurrent { return Theme.accent }
        return Theme.textFaint
    }
}
