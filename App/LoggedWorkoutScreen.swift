import DesignSystem
import SwiftUI
import WorkoutStore

/// A finished workout, pushed onto Log, read-only: its routine's name as it was, its day, length,
/// and sets, then its exercises in the order done, each with its rounds' figures in purple, the
/// change from the time before it was done (a gain in green, anything else in gray), and a quiet
/// line for one done a side at a time or a set short of its plan.
struct LoggedWorkoutScreen: View {
    let workout: Workout
    let log: WorkoutLog
    let exercises: ExerciseList

    @Environment(\.locale) private var locale

    var body: some View {
        let rows = log.exercises(of: workout, in: exercises)
        let sets = rows.reduce(0) { $0 + $1.exercise.rounds.count }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(LogScreen.name(of: workout))
                        .ppFixedTitleFont()
                        .foregroundStyle(.pp(.textPrimary))
                        .accessibilityAddTraits(.isHeader)
                    Text(AttributedString.monoNumbers(
                        workout.logLine(sets: sets, locale: locale),
                        font: .ppRowDetailNumber,
                    ))
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
                    .accessibilityLabel(workout.spokenLogLine(sets: sets, locale: locale))
                }
                .padding(.bottom, Spacing.sm)
                ForEach(rows, id: \.exercise.id) { row in
                    LogRow(
                        row.exercise.name,
                        tag: LogScreen.tag(row.change, locale: locale),
                        figures: row.exercise.figures(locale: locale),
                        detail: row.exercise.detail(locale: locale),
                        spoken: row.exercise.spoken(change: row.change, locale: locale),
                    )
                    .overlay(alignment: .bottom) { RowLine() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.md)
        }
        .background { Color.pp(.background).ignoresSafeArea() }
        .navigationBarTitleDisplayMode(.inline)
    }
}
