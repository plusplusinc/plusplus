import DesignSystem
import SwiftUI
import WorkoutStore

/// A part's wheel, open under its row in the exercise sheet: the system's wheel picker over the
/// part's choices, its unit beside it, and for a time, minutes and seconds side by side. Each
/// value it settles on is the row's at once. The row's current value is always on the wheel, so
/// opening it changes nothing.
struct PlanWheel: View {
    @Binding var item: RoutineExercise
    let part: PlanPart

    /// The system wheel's own height, which the sheet's open detent makes room for.
    static let height: CGFloat = 216

    @ScaledMetric(relativeTo: .body) private var wheelWidth: CGFloat = 128
    /// Room in the band for a unit, "min" the widest.
    @ScaledMetric(relativeTo: .subheadline) private var unitWidth: CGFloat = 32
    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    var body: some View {
        HStack(spacing: Spacing.lg) {
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
        .frame(height: Self.height)
        .hotReloadable()
    }

    private func wheel<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        choices: [Value],
        unit: String?,
        text: @escaping (Value) -> String = { "\($0)" },
    ) -> some View {
        // The unit sits in the wheel's band, after the number, as the system's timer shows it.
        Picker(title, selection: selection) {
            ForEach(choices, id: \.self) { choice in
                Text(verbatim: text(choice))
                    .font(.ppPlanValue)
                    .padding(.trailing, unit == nil ? 0 : unitWidth)
                    .accessibilityLabel(unit.map { "\(text(choice)) \($0)" } ?? text(choice))
                    .tag(choice)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(width: wheelWidth)
        .overlay(alignment: .trailing) {
            if let unit {
                Text(unit)
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
                    .frame(width: unitWidth, alignment: .leading)
                    .padding(.trailing, Spacing.sm)
                    .accessibilityHidden(true)
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
