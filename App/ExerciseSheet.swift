import DesignSystem
import SwiftUI
import WorkoutStore

/// A superset's rest after each round, read and stepped through the routine, since every member
/// holds it.
struct RoundSteps {
    let value: () -> (text: String, spoken: String)
    let canStep: (Int) -> Bool
    let step: (Int) -> Void
    /// Whether its rest is derived from the members, and a switch to set that.
    let isAuto: Binding<Bool>
    /// What a rest set by hand stays put through, by the members' sets: "reps", "the time", or
    /// "reps or time".
    let change: String
}

/// A routine row's values, a `ValueRow` for each part its exercise has, under the exercise's
/// equipment. A row's stepper opens one at a time. Changes apply as they're made; Delete is in
/// the menu.
struct ExerciseSheet: View {
    @Binding var item: RoutineExercise
    /// The names of the exercises in a superset with it, which share its round count, or nil.
    let partners: String?
    /// The values it steps, in order (`Routine.sheetParts(of:)`).
    let parts: [SheetPart]
    /// Its superset's rest; nil for a plain row.
    var rounds: RoundSteps?
    let onDelete: () -> Void

    @State private var open: SheetPart?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        let equipment = [item.exercise].equipment
                        if !equipment.isEmpty {
                            Capsules(equipment.map(\.name))
                                .padding(.bottom, Spacing.sm)
                        }
                        ForEach(parts, id: \.self) { part in
                            let auto = isAuto(part)
                            ValueRow(
                                label: label(of: part),
                                note: note(on: part),
                                value: value(of: part),
                                tag: auto == nil ? nil : "Auto",
                                showsTag: auto?.wrappedValue == true,
                                spokenValue: spokenValue(of: part),
                                isOpen: open == part,
                                canDecrease: canStep(part, by: -1),
                                canIncrease: canStep(part, by: 1),
                                onToggle: { toggle(part, scroller) },
                                onStep: { step(part, by: $0) },
                                accessory: auto.map(autoSwitch),
                                footer: auto.map { restFooter(isAuto: $0.wrappedValue, of: part) },
                            )
                            .id(part)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                }
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
    }

    /// In a superset, sets are rounds, shared with its partners.
    private func isRounds(_ part: SheetPart) -> Bool {
        part == .plan(.sets) && partners != nil
    }

    private func label(of part: SheetPart) -> String {
        switch part {
        case .plan where isRounds(part): "Rounds"
        case let .plan(plan): item.label(of: plan)
        case .restAfterRound: "Rest"
        }
    }

    private func value(of part: SheetPart) -> String {
        switch part {
        case let .plan(plan): item.value(of: plan, locale: locale)
        case .restAfterRound: rounds?.value().text ?? ""
        }
    }

    /// Rounds read as the bare count under their label, "Rounds, 3", not "3 sets".
    private func spokenValue(of part: SheetPart) -> String {
        switch part {
        case let .plan(plan) where isRounds(part): item.value(of: plan, locale: locale)
        case let .plan(plan): item.spokenValue(of: plan, locale: locale)
        case .restAfterRound: rounds?.value().spoken ?? ""
        }
    }

    private func canStep(_ part: SheetPart, by direction: Int) -> Bool {
        switch part {
        case let .plan(plan): item.canStep(plan, by: direction)
        case .restAfterRound: rounds?.canStep(direction) ?? false
        }
    }

    private func step(_ part: SheetPart, by direction: Int) {
        switch part {
        case let .plan(plan): item.step(plan, by: direction)
        case .restAfterRound: rounds?.step(direction)
        }
    }

    /// Whether a rest part is automatic, as a switch; nil for a part that isn't a rest. The
    /// switch animates the value and its tag as it goes.
    private func isAuto(_ part: SheetPart) -> Binding<Bool>? {
        switch part {
        case .plan(.rest): $item.isRestAuto.animation(Self.change)
        case .restAfterRound: rounds?.isAuto.animation(Self.change)
        case .plan: nil
        }
    }

    /// As a step changes a value.
    private static let change = Animation.snappy(duration: 0.15)

    /// Inside an open rest, under its keys.
    private func autoSwitch(_ isOn: Binding<Bool>) -> some View {
        Toggle("Auto", isOn: isOn)
            .font(.ppRowTitle)
            .foregroundStyle(.pp(.textPrimary))
            // The switch draws its track about 2 pt past its frame's trailing edge (measured on
            // iOS 27); this keeps the track itself as far from the row's edge as the label is.
            .padding(.trailing, Spacing.xxs)
    }

    /// Under an open rest: what automatic rest follows while it's on, and that a rest set by
    /// hand stays put while it's off. Both are laid out, the other one clear, so the footer keeps
    /// the taller one's height: the first step, which turns Auto off, moves nothing. Otherwise the
    /// sheet, scrolled to the open row, kept its end in view by sliding the row's keys from under
    /// the finger, and a second tap landed on the row and closed it.
    private func restFooter(isAuto: Bool, of part: SheetPart) -> some View {
        let change = rounds?.change ?? [item].restChange
        let held = "Stays at \(value(of: part)) when you change \(change)."
        let spokenHeld = "Stays at \(spokenValue(of: part)) when you change \(change)."
        return ZStack(alignment: .topLeading) {
            Text(explanation)
                .opacity(isAuto ? 1 : 0)
                .accessibilityHidden(!isAuto)
            Text(held)
                .opacity(isAuto ? 0 : 1)
                .accessibilityLabel(spokenHeld)
                .accessibilityHidden(isAuto)
        }
    }

    /// What automatic rest follows.
    private var explanation: String {
        if rounds != nil {
            return "Auto rest follows the exercises in this superset."
        }
        if case .time = item.plan.target {
            return "Auto rest matches the set's time."
        }
        return "Auto rest follows your reps and the exercise. Heavier sets rest longer."
    }

    /// What a part is for, in gray under its label, where the label alone doesn't say.
    private func note(on part: SheetPart) -> String? {
        switch part {
        case .plan(.sets): partners.map { "Shared with \($0)" }
        case .plan(.rest): "After each set"
        case .plan(.target), .plan(.weight): nil
        case .restAfterRound:
            "After each round" + (partners.map { ", shared with \($0)" } ?? "")
        }
    }

    /// Opens or closes a part's stepper. Once one has opened, the sheet scrolls only as far as
    /// it takes to show the whole row, its keys below its edge included, so a row in view stays
    /// put.
    private func toggle(_ part: SheetPart, _ scroller: ScrollViewProxy) {
        let opening = open != part
        withAnimation(ValueRow.motion) {
            open = opening ? part : nil
        } completion: {
            guard opening, open == part else { return }
            withAnimation(ValueRow.motion) {
                scroller.scrollTo(part)
            }
        }
    }
}

#Preview {
    @Previewable @State var item = RoutineExercise(
        exercise: Exercise.builtIn.first { $0.load == .pair && $0.isPerSide } ?? Exercise
            .builtIn[0],
        weightUnit: .pounds,
    )
    Color.pp(.background)
        .sheet(isPresented: .constant(true)) {
            ExerciseSheet(
                item: $item,
                partners: nil,
                parts: item.exercise.planParts.map(SheetPart.plan) + [.plan(.rest)],
            ) { }
        }
}
