import DesignSystem
import SwiftUI
import WorkoutStore

/// A superset's rest after each round, read and stepped through the routine, since every member
/// holds it.
struct RoundSteps {
    let value: () -> (text: String, spoken: String)
    /// The rest in seconds, which its digits roll up or down by.
    let seconds: () -> Double
    let canStep: (Int) -> Bool
    let step: (Int) -> Void
    /// Sets it by hand to a number of seconds, as its ruler is dragged; Auto goes off.
    let set: (Int) -> Void
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
    /// The weight as typed while its row is open.
    @State private var weightText = ""
    @State private var detent = PresentationDetent.medium
    /// The height the sheet grew to, to fit a row as it opened; a detent from then on, so the
    /// sheet stays there while it's open.
    @State private var fitted: CGFloat?
    /// A row is opening below the large height: the sheet grows to fit once its content has the
    /// row's open height.
    @State private var growsToFit = false
    /// The sheet's height inside its safe area, which a `.height` detent measures.
    @State private var sheetHeight: CGFloat = 0
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
                                number: number(of: part),
                                tag: auto == nil ? nil : "Auto",
                                showsTag: auto?.wrappedValue == true,
                                spokenValue: spokenValue(of: part),
                                isOpen: open == part,
                                canDecrease: canStep(part, by: -1),
                                canIncrease: canStep(part, by: 1),
                                onToggle: { toggle(part, scroller) },
                                onStep: { step(part, by: $0) },
                                entry: entry(for: part),
                                ruler: ruler(for: part),
                                accessory: auto.map(autoSwitch),
                                footer: auto.map { restFooter(isAuto: $0.wrappedValue, of: part) },
                            )
                            .id(part)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                }
                .onScrollGeometryChange(for: CGFloat.self, of: \.overflow) { _, overflow in
                    fit(overflow)
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
        .onChange(of: weightText) { _, text in
            item.setWeight(typed: text, locale: locale)
        }
        // A step moves the field with it; a number still being typed ("27.") stays as it is.
        .onChange(of: item.plan.weight) { _, _ in
            guard let entry = item.weightEntry(locale: locale),
                  RoutineExercise.typedAmount(weightText, locale: locale)
                  != item.plan.weight?.amount
            else { return }
            weightText = entry.number
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { sheetHeight = $0 }
        .presentationDetents(detents, selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.pp(.background))
    }

    /// How the open weight row sets any weight beside its − / + keys.
    enum WeightInput {
        /// The decimal pad comes up as the row opens, its number selected.
        case pad
        /// A ruler under the keys, dragged sideways, a tick each half of the weight's unit.
        case ruler
    }

    static let weightInput = WeightInput.ruler

    private var detents: Set<PresentationDetent> {
        var detents: Set<PresentationDetent> = [.medium, .large]
        if let fitted {
            detents.insert(.height(fitted))
        }
        return detents
    }

    /// At the medium height an open ruler sat near the screen's bottom edge, under the thumb's
    /// reach, and the rows under it were cut off. Any row that opens with the sheet below large
    /// grows it by what its content now overflows, in the row's own motion; the system holds a
    /// height past large to large. The content's size is the open row's from the first frame of
    /// its animation, so this lands a layout pass after the tap, not after the row has opened.
    private func fit(_ overflow: CGFloat) {
        guard growsToFit else { return }
        growsToFit = false
        guard overflow > 0, detent != .large else { return }
        let height = sheetHeight + overflow
        fitted = height
        withAnimation(ValueRow.motion) {
            detent = .height(height)
        }
    }

    /// Where the weight's − / + keys sit while the decimal pad is up: false, in the row under the
    /// value; true, in the bar above the pad.
    static let weightKeysAbovePad = false

    /// The weight, typed into its open row.
    private func entry(for part: SheetPart) -> ValueEntry? {
        guard Self.weightInput == .pad, part == .plan(.weight),
              let entry = item.weightEntry(locale: locale)
        else {
            return nil
        }
        return ValueEntry(
            text: $weightText,
            unit: entry.unit,
            keysAbovePad: Self.weightKeysAbovePad,
        )
    }

    /// The weight, a timed set's time, or a rest, dragged on a ruler in its open row.
    private func ruler(for part: SheetPart) -> ValueRuler? {
        switch part {
        case .plan(.weight):
            guard Self.weightInput == .ruler, let amount = item.plan.weight?.amount,
                  let range = item.weightRange
            else { return nil }
            return ValueRuler(value: amount, range: range) { item.setWeight($0) }
        case .plan(.target):
            guard case let .time(seconds) = item.plan.target else { return nil }
            return timeRuler(
                seconds,
                range: RoutineExercise.timeRange,
                tick: RoutineExercise.timeStep,
                marks: (15, 30),
                spacing: Self.timeSpacing,
            ) { item.setTime($0) }
        case .plan(.rest):
            return restRuler(item.rest) { item.setRest($0) }
        case .restAfterRound:
            return rounds.map { rounds in restRuler(Int(rounds.seconds()), set: rounds.set) }
        case .plan(.sets):
            return nil
        }
    }

    /// Room for a "10:00" label each 30 s, six 5 s ticks apart, with a gap between labels.
    private static let timeSpacing: CGFloat = 10
    /// Room for a "10:00" label each minute, four 15 s ticks apart.
    private static let restSpacing: CGFloat = 14

    private func restRuler(_ seconds: Int, set: @escaping (Int) -> Void) -> ValueRuler {
        timeRuler(
            seconds,
            range: RoutineExercise.restRange,
            tick: RoutineExercise.restStep,
            marks: (30, 60),
            spacing: Self.restSpacing,
            set: set,
        )
    }

    /// A ruler in seconds, its tall ticks labeled in minutes and seconds as the open row reads.
    private func timeRuler(
        _ seconds: Int,
        range: ClosedRange<Int>,
        tick: Int,
        marks: (medium: Int, major: Int),
        spacing: CGFloat,
        set: @escaping (Int) -> Void,
    ) -> ValueRuler {
        let locale = locale
        return ValueRuler(
            value: Double(seconds),
            range: Double(range.lowerBound) ... Double(range.upperBound),
            tick: Double(tick),
            medium: Double(marks.medium),
            major: Double(marks.major),
            spacing: spacing,
            label: { RoutineExercise.clock(Int($0), locale: locale) },
        ) { set(Int($0.rounded())) }
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

    /// While a ruler shows, its value keeps one shape, a weight one decimal and a time or rest
    /// minutes and seconds ("0:45 min"), so its digits don't come and go as it turns. The shape
    /// changes in the open's own transaction, so the value's numeric transition slides it in and
    /// out with the row.
    private func value(of part: SheetPart) -> String {
        let dialed = open == part && ruler(for: part) != nil
        switch part {
        case let .plan(plan) where dialed: return item.dialedValue(of: plan, locale: locale)
        case let .plan(plan): return item.value(of: plan, locale: locale)
        case .restAfterRound where dialed:
            return RoutineExercise.dialedTime(Int(rounds?.seconds() ?? 0), locale: locale)
        case .restAfterRound: return rounds?.value().text ?? ""
        }
    }

    private func number(of part: SheetPart) -> Double {
        switch part {
        case let .plan(plan): item.amount(of: plan)
        case .restAfterRound: rounds?.seconds() ?? 0
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
        if Self.weightInput == .pad, opening, part == .plan(.weight),
           let entry = item.weightEntry(locale: locale)
        {
            weightText = entry.number
            // The pad covers the lower half; the full sheet keeps the open row and its keys
            // above it.
            detent = .large
        }
        growsToFit = opening && detent != .large
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

private extension ScrollGeometry {
    /// How far the content runs past the visible height. In a sheet the container is already
    /// the height between the navigation bar and the home indicator (measured on iOS 27: 573 pt
    /// in a 643 pt sheet with insets of 70 and 34), so the insets don't count again.
    var overflow: CGFloat {
        contentSize.height - containerSize.height
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
