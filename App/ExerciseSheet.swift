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
                            ValueRow(
                                label: label(of: part),
                                note: note(on: part),
                                value: value(of: part),
                                spokenValue: spokenValue(of: part),
                                isOpen: open == part,
                                canDecrease: canStep(part, by: -1),
                                canIncrease: canStep(part, by: 1),
                                onToggle: { toggle(part, scroller) },
                                onStep: { step(part, by: $0) },
                            )
                            .id(part)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
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

    /// A plain row's parts, its gaps included. A superset member's plan, its own switch between
    /// sides if per side, then the superset's gaps, the rest after a round only past one round;
    /// its own rest and transition are kept, unread, for when it leaves.
    private var parts: [SheetPart] {
        guard rounds != nil else { return item.sheetParts.map(SheetPart.plan) }
        var parts = item.exercise.planParts.map(SheetPart.plan)
        if item.exercise.isPerSide {
            parts.append(.plan(.switchSides))
        }
        parts.append(.round(.switchPartners))
        if item.plan.sets > 1 {
            parts.append(.round(.afterRound))
        }
        parts.append(.round(.transition))
        return parts
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

    /// What a part is for, in gray under its label, where the label alone doesn't say.
    private func note(on part: SheetPart) -> String? {
        switch part {
        case .plan(.sets): partners.map { "Shared with \($0)" }
        case .plan(.rest): "Between sets"
        case .plan(.switchSides): "Between left and right"
        case .plan(.transition): "Before the next exercise"
        case .plan(.target), .plan(.weight): nil
        case .round(.switchPartners): partners.map { "Between this and \($0)" }
        case .round(.afterRound): partners.map { "Shared with \($0)" }
        case .round(.transition): "After the superset, before the next exercise"
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
