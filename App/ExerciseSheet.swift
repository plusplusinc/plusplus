import DesignSystem
import SwiftUI
import WorkoutStore

/// A routine row's values, one row for each part its exercise has: the label leading, the value
/// trailing, each row on its own rounded fill. Tapping a value opens a stepper
/// inside its row, under the value, one at a time. Changes apply as they're made; Delete is in
/// the menu.
struct ExerciseSheet: View {
    @Binding var item: RoutineExercise
    let onDelete: () -> Void

    @State private var open: PlanPart?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    /// The value's key and the stepper's keys sit this far inside their row on every side, so
    /// the row's corners are concentric with theirs.
    private static let inset = Spacing.sm
    private static let motion = Animation.snappy(duration: 0.25)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    ForEach(item.exercise.planParts, id: \.self) { part in
                        VStack(spacing: 0) {
                            partRow(part)
                            region(part)
                        }
                        .background(
                            Color.pp(.surface),
                            in: .rect(cornerRadius: Self.inset + Radius.key),
                        )
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

    /// The whole row opens and closes its stepper. It's a tap, not a `Button`: a button's label
    /// trailed its row's fill by a quarter second as rows above it opened or closed.
    private func partRow(_ part: PlanPart) -> some View {
        HStack {
            Text(label(of: part))
                .font(.ppRowTitle)
                .foregroundStyle(.pp(.textPrimary))
            Spacer()
            Text(value(of: part))
                .font(.ppRowTitle)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.pp(.textPrimary))
                .padding(.horizontal, Spacing.md - Spacing.xs)
                .padding(.vertical, Spacing.sm)
        }
        .padding(.leading, Spacing.md)
        .padding([.vertical, .trailing], Self.inset)
        .contentShape(.rect)
        .onTapGesture { toggle(part) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle(part) }
        .accessibilityHint(open == part ? "Closes the stepper." : "Opens a stepper.")
    }

    private func toggle(_ part: PlanPart) {
        withAnimation(Self.motion) {
            open = open == part ? nil : part
        }
    }

    /// The stepper under a row's value, always laid out: the region shows only as much of it as
    /// its height allows, so nothing draws past its edges, and the stepper, held to its top,
    /// fades in and out as it opens and closes.
    private func region(_ part: PlanPart) -> some View {
        let isOpen = open == part
        return stepper(part)
            .padding([.horizontal, .bottom], Self.inset)
            .opacity(isOpen ? 1 : 0)
            .allowsHitTesting(isOpen)
            .accessibilityHidden(!isOpen)
            .frame(maxWidth: .infinity)
            .frame(height: isOpen ? nil : 0, alignment: .top)
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
        Button {
            withAnimation(.snappy(duration: 0.15)) {
                step(part, by: direction)
            }
        } label: {
            // The whole key is the button, not just its glyph.
            Label(title, systemImage: image)
                .labelStyle(.iconOnly)
                .font(.ppButton)
                .foregroundStyle(.pp(.textPrimary))
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(Color.pp(.background), in: .rect(cornerRadius: Radius.key))
                .contentShape(.rect(cornerRadius: Radius.key))
        }
        .buttonStyle(.plain)
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
            text = (item.plan.weight?.text(locale: locale) ?? "")
                + (item.exercise.load == .pair ? "/side" : "")
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
