import DesignSystem
import SwiftUI
import WorkoutStore

/// A part's wheel, open under its row in the exercise sheet, in a rounded well a step off the
/// sheet: the system's wheel picker over the part's choices, its unit beside the number in the
/// band, and for a time, minutes and seconds side by side. The wheel takes the well's full width,
/// so a drag anywhere across it turns the wheel rather than the sheet. Each value it settles on
/// is the row's at once. The row's current value is always on the wheel, so opening it changes
/// nothing.
struct PlanWheel: View {
    @Binding var item: RoutineExercise
    let part: PlanPart

    /// The system wheel's own height.
    private static let wheelHeight: CGFloat = 216
    /// The wheel's well and the gap above it, which the sheet's open detent makes room for.
    static let height: CGFloat = wheelHeight + Spacing.sm

    /// Room for a number, "142.5" the widest, its digits right-aligned beside the unit.
    @ScaledMetric(relativeTo: .body) private var numberWidth: CGFloat = 56
    /// Room for a unit, "min" the widest.
    @ScaledMetric(relativeTo: .subheadline) private var unitWidth: CGFloat = 32
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
        .background(.pp(.surface), in: .rect(cornerRadius: Radius.card))
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
        // The unit sits in the wheel's band after the number, as the system's timer shows it: each
        // row and the band's overlay lay out the same number-and-unit columns, centered.
        Picker(title, selection: selection) {
            ForEach(choices, id: \.self) { choice in
                columns(number: Text(verbatim: text(choice)).font(.ppPlanValue), unit: unit) {
                    Color.clear
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(unit.map { "\(text(choice)) \($0)" } ?? text(choice))
                .tag(choice)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .overlay {
            if let unit {
                columns(number: Color.clear, unit: unit) {
                    Text(unit)
                        .font(.ppRowDetail)
                        .foregroundStyle(.pp(.textSecondary))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    /// A number's column, right-aligned, then, with a unit, the unit's.
    private func columns(
        number: some View,
        unit: String?,
        @ViewBuilder unitColumn: () -> some View,
    ) -> some View {
        HStack(spacing: Spacing.xs) {
            number.frame(width: numberWidth, alignment: .trailing)
            if unit != nil {
                unitColumn().frame(width: unitWidth, alignment: .leading)
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
