import DesignSystem
import SwiftUI
import WorkoutStore

/// A routine row's values, one row for each part its exercise has: the label leading, the value
/// on a rounded key trailing, a hairline between rows. Tapping a value opens a stepper under its
/// row, one at a time, as the hairline below widening into a region of its color. Changes apply
/// as they're made; Delete is in the menu.
struct ExerciseSheet: View {
    @Binding var item: RoutineExercise
    let onDelete: () -> Void

    @State private var open: PlanPart?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    private static let hairline: CGFloat = 1 / 3

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    let parts = item.exercise.planParts
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        partRow(part)
                        // The last row has no hairline under it, so its region grows from nothing.
                        seam(part, closedHeight: index < parts.count - 1 ? Self.hairline : 0)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
            }
            .background(Color.pp(.background))
            .navigationTitle(item.exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            dismiss()
                            onDelete()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.pp(.background))
        .hotReloadable()
    }

    private func partRow(_ part: PlanPart) -> some View {
        HStack {
            Text(label(of: part))
                .font(.ppRowTitle)
                .foregroundStyle(.pp(.textPrimary))
            Spacer()
            Button {
                withAnimation(.snappy) {
                    open = open == part ? nil : part
                }
            } label: {
                Text(value(of: part))
                    .font(.ppRowTitle)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.pp(.textPrimary))
                    .padding(.horizontal, Spacing.md - Spacing.xs)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        Color.pp(open == part ? .borderStrong : .surface),
                        in: .rect(cornerRadius: Radius.key),
                    )
            }
            .buttonStyle(.plain)
            .accessibilityHint(open == part ? "Closes the stepper." : "Opens a stepper.")
        }
        .padding(.vertical, Spacing.sm)
    }

    /// The hairline under a row, or, while its stepper is open, the region it widens into: the
    /// stepper is always laid out, and the region shows only as much of it as its height allows,
    /// so nothing draws past its edges.
    private func seam(_ part: PlanPart, closedHeight: CGFloat) -> some View {
        let isOpen = open == part
        return stepper(part)
            .padding(Spacing.sm)
            .opacity(isOpen ? 1 : 0)
            .allowsHitTesting(isOpen)
            .accessibilityHidden(!isOpen)
            .frame(maxWidth: .infinity)
            .frame(height: isOpen ? nil : closedHeight, alignment: .top)
            .background(Color.pp(.borderStrong))
            .clipped()
    }

    private func stepper(_ part: PlanPart) -> some View {
        HStack(spacing: Spacing.sm) {
            stepKey("Decrease", "minus", part, by: -1)
            stepKey("Increase", "plus", part, by: 1)
        }
    }

    private func stepKey(
        _ title: String,
        _ image: String,
        _ part: PlanPart,
        by direction: Int,
    ) -> some View {
        Button(title, systemImage: image) {
            withAnimation(.snappy(duration: 0.15)) {
                step(part, by: direction)
            }
        }
        .labelStyle(.iconOnly)
        .font(.ppButton)
        .foregroundStyle(.pp(.textPrimary))
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(Color.pp(.background), in: .rect(cornerRadius: Radius.key))
        .contentShape(.rect)
        .buttonRepeatBehavior(.enabled)
        .sensoryFeedback(.selection, trigger: value(of: part))
    }

    private func label(of part: PlanPart) -> String {
        switch part {
        case .sets: "Sets"
        case .target:
            if case .time = item.plan.target {
                "Time"
            } else {
                "Reps"
            }
        case .weight: "Weight"
        }
    }

    private func value(of part: PlanPart) -> String {
        let text: String
        var qualifier: String?
        switch part {
        case .sets:
            text = item.plan.sets.formatted(.number.locale(locale))
        case .target:
            switch item.plan.target {
            case let .reps(reps): text = reps.formatted(.number.locale(locale))
            case let .time(seconds): text = TimeText.text(seconds: seconds, locale: locale)
            }
            qualifier = item.exercise.isPerSide ? "per side" : nil
        case .weight:
            text = item.plan.weight?.text(locale: locale) ?? ""
            qualifier = item.exercise.load == .pair ? "each" : nil
        }
        return [text, qualifier].compactMap(\.self).joined(separator: " ")
    }

    private func step(_ part: PlanPart, by direction: Int) {
        switch part {
        case .sets:
            item.plan.sets = min(max(item.plan.sets + direction, 1), 99)
        case .target:
            switch item.plan.target {
            case let .reps(reps):
                item.plan.target = .reps(min(max(reps + direction, 1), 999))
            case let .time(seconds):
                item.plan.target = .time(seconds: min(max(seconds + direction * 5, 5), 5999))
            }
        case .weight:
            guard var weight = item.plan.weight else { return }
            let lightest = item.exercise.load == .bar ? Weight.emptyBar(weight.unit).amount : weight
                .unit.step
            weight.amount = max(weight.amount + Double(direction) * weight.unit.step, lightest)
            item.plan.weight = weight
        }
    }
}
