import DesignSystem
import SwiftUI
import WorkoutStore

/// A part's wheel, open under its row in the exercise sheet, on a region a step darker than
/// the sheet running edge to edge: the system's wheel picker over the part's choices, its unit
/// beside the number in the
/// band, and for a time, minutes and seconds side by side. The wheel takes the content's full
/// width,
/// so a drag anywhere across it turns the wheel rather than the sheet. Its numbers, with their
/// unit, are centered in it. Each value it settles on
/// is the row's at once. The row's current value is always on the wheel, so opening it changes
/// nothing.
struct PlanWheel: View {
    @Binding var item: RoutineExercise
    let part: PlanPart

    /// The system wheel's own height.
    private static let wheelHeight: CGFloat = 216
    /// The wheel's region and the gap above it, which the sheet's open detent makes room for.
    static let height: CGFloat = wheelHeight + Spacing.sm

    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    var body: some View {
        HStack(spacing: 0) {
            switch part {
            case .sets:
                wheel("Sets", selection: $item.plan.sets, choices: item.setChoices, unit: nil)
            case .target:
                switch item.plan.target {
                case .reps:
                    wheel("Reps", selection: reps, choices: item.repChoices, unit: nil)
                case .time:
                    wheel("Minutes", selection: minutes, choices: item.minuteChoices, unit: "min")
                    wheel(
                        "Seconds",
                        selection: seconds,
                        choices: item.secondChoices,
                        unit: "s",
                        text: {
                            $0.formatted(.number.precision(.integerLength(2...)).locale(locale))
                        },
                    )
                }
            case .weight:
                wheel(
                    "Weight",
                    selection: weight,
                    choices: item.weightChoices,
                    unit: item.plan.weight?.unit.rawValue,
                    text: { item.weightNumber($0, locale: locale) },
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.wheelHeight)
        // Edge to edge of the sheet, past the content's insets; the wheel's band stays inset.
        .background { Color.pp(.well).containerRelativeFrame(.horizontal) }
        .padding(.top, Spacing.sm)
        .hotReloadable()
    }

    private func wheel<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        choices: [Value],
        unit: String?,
        text: @escaping (Value) -> String = { "\($0)" },
    ) -> some View {
        // The unit sits in the wheel's band after the number, as the system's timer shows it. Each
        // row and the band's overlay lay out the same group, the number right-aligned in room for
        // the wheel's widest and the unit after it, centered in the wheel.
        let widest = choices.map(text).max { $0.count < $1.count } ?? ""
        return Picker(title, selection: selection) {
            ForEach(choices, id: \.self) { choice in
                group(number: text(choice), widest: widest, unit: unit, showsUnit: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(unit.map { "\(text(choice)) \($0)" } ?? text(choice))
                    .tag(choice)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .overlay {
            if unit != nil {
                group(number: nil, widest: widest, unit: unit, showsUnit: true)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// A number, right-aligned in room for `widest`, then the unit, if any, shown or holding its
    /// place: a row draws the number, the band's overlay the unit.
    private func group(number: String?, widest: String, unit: String?, showsUnit: Bool)
        -> some View
    {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            ZStack(alignment: .trailing) {
                Text(verbatim: widest).hidden()
                if let number {
                    Text(verbatim: number)
                }
            }
            .font(.ppPlanValue)
            if let unit {
                Text(unit)
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
                    .opacity(showsUnit ? 1 : 0)
            }
        }
    }

    private var reps: Binding<Int> {
        Binding {
            if case let .reps(reps) = item.plan.target {
                reps
            } else {
                0
            }
        } set: {
            item.plan.target = .reps($0)
        }
    }

    private var minutes: Binding<Int> {
        Binding {
            item.minutesAndSeconds.minutes
        } set: {
            item.setTime(minutes: $0, seconds: item.minutesAndSeconds.seconds)
        }
    }

    private var seconds: Binding<Int> {
        Binding {
            item.minutesAndSeconds.seconds
        } set: {
            item.setTime(minutes: item.minutesAndSeconds.minutes, seconds: $0)
        }
    }

    private var weight: Binding<Double> {
        Binding { item.plan.weight?.amount ?? 0 } set: { item.setWeight($0) }
    }
}
