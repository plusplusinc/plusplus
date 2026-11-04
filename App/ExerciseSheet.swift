import DesignSystem
import SwiftUI
import WorkoutStore

/// A value the sheet steps: one of the row's plan, or one of its superset's gaps, shared with its
/// partners.
enum SheetPart: Hashable {
    case plan(PlanPart)
    case round(RoundPart)
}

/// A superset's gaps, read and stepped through the routine, since every member holds them.
struct RoundSteps {
    let value: (RoundPart) -> (text: String, spoken: String)
    let canStep: (RoundPart, Int) -> Bool
    let step: (RoundPart, Int) -> Void
    /// Whether its rest is derived from the members, and a switch to set that.
    let isAuto: Binding<Bool>
}

/// A routine row's values, a `ValueRow` for each part its exercise has, under the exercise's
/// equipment. A row's stepper opens one at a time. Changes apply as they're made; Delete is in
/// the menu.
struct ExerciseSheet: View {
    @Binding var item: RoutineExercise
    /// The names of the exercises in a superset with it, which share its round count, or nil.
    let partners: String?
    /// Its superset's gaps; nil for a plain row.
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
                            ) {
                                if let auto {
                                    Toggle("Auto", isOn: auto)
                                        .font(.ppRowTitle)
                                        .foregroundStyle(.pp(.textPrimary))
                                        // The switch draws its track about 2 pt past its frame's
                                        // trailing edge (measured on iOS 27); this keeps the track
                                        // itself as far from the row's edge as the label is.
                                        .padding(.trailing, Spacing.xxs)
                                }
                            } footer: {
                                if let auto {
                                    restFooter(isAuto: auto.wrappedValue, of: part)
                                }
                            }
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

    /// A plain row's parts, its rest included. A superset member's plan, then the superset's
    /// rest after each round; its own rest is kept, unread, for when it leaves.
    private var parts: [SheetPart] {
        guard rounds != nil else { return item.sheetParts.map(SheetPart.plan) }
        return item.exercise.planParts.map(SheetPart.plan) + [.round(.afterRound)]
    }

    /// In a superset, sets are rounds, shared with its partners.
    private func isRounds(_ part: SheetPart) -> Bool {
        part == .plan(.sets) && partners != nil
    }

    private func label(of part: SheetPart) -> String {
        switch part {
        case .plan where isRounds(part): "Rounds"
        case let .plan(plan): item.label(of: plan)
        case let .round(round): round.label
        }
    }

    private func value(of part: SheetPart) -> String {
        switch part {
        case let .plan(plan): item.value(of: plan, locale: locale)
        case let .round(round): rounds?.value(round).text ?? ""
        }
    }

    /// Rounds read as the bare count under their label, "Rounds, 3", not "3 sets".
    private func spokenValue(of part: SheetPart) -> String {
        switch part {
        case let .plan(plan):
            isRounds(part)
                ? item.value(of: plan, locale: locale)
                : item.spokenValue(of: plan, locale: locale)
        case let .round(round): rounds?.value(round).spoken ?? ""
        }
    }

    private func canStep(_ part: SheetPart, by direction: Int) -> Bool {
        switch part {
        case let .plan(plan): item.canStep(plan, by: direction)
        case let .round(round): rounds?.canStep(round, direction) ?? false
        }
    }

    private func step(_ part: SheetPart, by direction: Int) {
        switch part {
        case let .plan(plan): item.step(plan, by: direction)
        case let .round(round): rounds?.step(round, direction)
        }
    }

    /// Whether a rest part is automatic, as a switch; nil for a part that isn't a rest. The
    /// switch animates the value and its tag as it goes.
    private func isAuto(_ part: SheetPart) -> Binding<Bool>? {
        switch part {
        case .plan(.rest): $item.isRestAuto.animation(Self.change)
        case .round: rounds?.isAuto.animation(Self.change)
        case .plan: nil
        }
    }

    /// As a step changes a value.
    private static let change = Animation.snappy(duration: 0.15)

    /// Under an open rest: what automatic rest follows while it's on, and that a rest set by
    /// hand stays put while it's off. Both are laid out, the other one clear, so the footer keeps
    /// the taller one's height: the first step, which turns Auto off, moves nothing. Otherwise the
    /// sheet, scrolled to the open row, kept its end in view by sliding the row's keys from under
    /// the finger, and a second tap landed on the row and closed it.
    private func restFooter(isAuto: Bool, of part: SheetPart) -> some View {
        let timed = if case .time = item.plan.target, rounds == nil { true } else { false }
        let change = timed ? "the time" : "reps"
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
        case .round(.afterRound): "After each round" + (partners.map { ", shared with \($0)" } ?? "")
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
            ExerciseSheet(item: $item, partners: "Pull-up") { }
        }
}
