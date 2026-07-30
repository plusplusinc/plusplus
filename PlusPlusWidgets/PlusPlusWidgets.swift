import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

/// The widget extension (#147): the rest-countdown Live Activity plus
/// Home/Lock Screen widgets fed by the app's snapshot.
///
/// ⚠️ The private palette is GONE (2026-07-28, the colour audit). It
/// restated the brand hues in raw hex and — the part that actually cost
/// something — carried no high-contrast variants, so widgets ignored
/// Increase Contrast while the app honoured it. The hues come from
/// `BrandPalette` in PlusPlusShared, which compiles into this target too.
/// The Dynamic Island is ALWAYS dark, so the pieces that live only there
/// take `accentOnDark` rather than the adaptive value.

@main
struct PlusPlusWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        DueTodayWidget()
        StreakWidget()
    }
}

// MARK: - Workout Live Activity (#322)
// One activity spans the whole session: it rides in `.working` (current
// exercise, set progress, count-up elapsed) and swaps to `.resting`
// (countdown + controls) between sets.

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // Lock Screen / banner.
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.phase == .resting
                             ? (context.state.isTransition == true ? "SWITCH" : "REST")
                             : context.attributes.routineName.uppercased())
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            .kerning(0.8)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(context.state.phase == .resting
                             ? "Up next: \(context.state.positionLine)"
                             : context.state.positionLine)
                            .font(.system(.footnote, weight: .semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                    trailingTimer(context.state, size: 32)
                        .frame(maxWidth: 96)
                }
                if context.state.phase == .resting {
                    RestControlButtons()
                } else {
                    WorkoutProgressBar(completed: context.state.setsCompleted, total: context.state.totalSets)
                }
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.55))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.phase == .resting
                         ? (context.state.isTransition == true ? "SWITCH" : "REST")
                         : context.state.unitKicker)
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(context.state.exerciseName)
                            .font(.system(.footnote, weight: .semibold))
                            .lineLimit(1)
                        Text("\(context.state.setsCompleted)/\(context.state.totalSets) done")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    trailingTimer(context.state, size: 30)
                        .frame(maxWidth: 92)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.phase == .resting {
                        RestControlButtons()
                            .padding(.top, 6)
                    } else {
                        WorkoutProgressBar(completed: context.state.setsCompleted, total: context.state.totalSets)
                            .padding(.top, 4)
                    }
                }
            } compactLeading: {
                Text("++")
                    .font(.system(.footnote, design: .monospaced, weight: .bold))
                    .foregroundStyle(BrandPalette.accentOnDark)
            } compactTrailing: {
                compactTrailing(context.state)
            } minimal: {
                minimal(context.state)
            }
        }
    }

    /// Resting drains a countdown; working counts elapsed up from start.
    @ViewBuilder
    private func trailingTimer(_ state: WorkoutActivityAttributes.ContentState, size: CGFloat) -> some View {
        if state.phase == .resting, let restEnd = state.restEnd {
            Text(timerInterval: Date()...restEnd, countsDown: true)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(BrandPalette.accent)
        } else {
            Text(state.sessionStart, style: .timer)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func compactTrailing(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        if state.phase == .resting, let restEnd = state.restEnd {
            Text(timerInterval: Date()...restEnd, countsDown: true)
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(BrandPalette.accent)
                .frame(maxWidth: 44)
        } else {
            Text("\(state.setsCompleted)/\(state.totalSets)")
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(BrandPalette.accentOnDark)
                .frame(maxWidth: 44)
        }
    }

    @ViewBuilder
    private func minimal(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        if state.phase == .resting, let restEnd = state.restEnd {
            Text(timerInterval: Date()...restEnd, countsDown: true)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(BrandPalette.accent)
                .frame(maxWidth: 36)
        } else {
            Text("++")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(BrandPalette.accentOnDark)
        }
    }
}

/// A slim set-progress bar for the working phase.
struct WorkoutProgressBar: View {
    let completed: Int
    let total: Int

    var body: some View {
        GeometryReader { geo in
            let fraction = total > 0 ? min(1, Double(completed) / Double(total)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule().fill(BrandPalette.done)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 5)
    }
}

/// Skip · −15s · +15s on the island and Lock Screen (#157; the ±15
/// stepper since the rest screen gained one, 2026-07-27). Same order and
/// same emphasis as the phone: the pair is tinted, Skip is the quiet one
/// on the left. The intents run in the app's process and drive the same
/// code path as the on-screen keys, so island, notification, and app
/// can't disagree.
struct RestControlButtons: View {
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: SkipRestIntent()) {
                Text("Skip")
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

            Button(intent: ReduceRestTimeIntent()) {
                Text("−\(RestAdjustment.stepSeconds)s")
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
            }
            .buttonStyle(.bordered)
            // Blue, not green: interactive state, not data (#176).
            .tint(BrandPalette.selected)

            Button(intent: AddRestTimeIntent()) {
                Text("+\(RestAdjustment.stepSeconds)s")
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
            }
            .buttonStyle(.bordered)
            .tint(BrandPalette.selected)
        }
    }
}

// MARK: - Snapshot-fed timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        // The snapshot carries schedules (#159), so views compute
        // due-ness from each entry's date — a week of entries keeps the
        // widget honest even if the app never wakes. The app still pokes
        // reloads on real changes.
        let calendar = Calendar.current
        var entries = [SnapshotEntry(date: .now, snapshot: snapshot)]
        // Calendar day-adds, not 86 400-second hops: DST days are 23 or
        // 25 hours, and a fixed-interval midnight either skips the
        // transition day or hands WidgetKit a non-monotonic timeline.
        let todayStart = calendar.startOfDay(for: .now)
        for day in 1...7 {
            guard let midnight = calendar.date(byAdding: .day, value: day, to: todayStart),
                  midnight > entries[0].date else { continue }
            entries.append(SnapshotEntry(date: midnight, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .after(entries.last!.date)))
    }
}

extension WidgetSnapshot {
    static let placeholder = WidgetSnapshot(
        generatedAt: .now,
        routineNames: ["Push Day"],
        due: [.init(name: "Push Day", caption: "mon/thu", exerciseCount: 6)],
        streakWeeks: 4,
        weeklyCounts: [0, 1, 2, 1, 3, 2, 2, 1, 3, 2, 3, 1],
        scheduled: nil
    )
}

// MARK: - Today widget
// Struct + kind keep the old names — changing `kind` orphans installed
// widgets. Only the display strings dropped the "due" vocabulary (#172).

struct DueTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DueToday", provider: SnapshotProvider()) { entry in
            DueTodayView(entryDate: entry.date, snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Today's workout, straight from your schedule.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DueTodayView: View {
    let entryDate: Date
    let snapshot: WidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("++")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(BrandPalette.accent)
                Spacer()
            }
            Spacer(minLength: 0)
            if let due = snapshot?.dueList(at: entryDate), !due.isEmpty {
                Text(due[0].name)
                    .font(.system(.headline, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("\(due[0].caption) · \(due[0].exerciseCount) exercises")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                if due.count > 1 {
                    Text("+ \(due.count - 1) more")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Rest day")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("nothing scheduled")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "plusplus://today"))
    }
}

// MARK: - Streak widget

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Streak", provider: SnapshotProvider()) { entry in
            StreakView(entryDate: entry.date, snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Consecutive weeks trained, with the last 12 weeks.")
        .supportedFamilies([.systemSmall])
    }
}

struct StreakView: View {
    let entryDate: Date
    let snapshot: WidgetSnapshot?

    /// Rolled to the entry's date (#159): weeks that passed since the
    /// app last wrote the snapshot become empty buckets, so a stale
    /// snapshot can't overstate the streak.
    private var rolled: (weeks: Int, counts: [Int]) {
        snapshot?.rolledStreak(at: entryDate) ?? (0, [])
    }

    private var counts: [Int] { rolled.counts }
    private var maxCount: Int { max(counts.max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("STREAK")
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            (Text("\(rolled.weeks)")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundStyle(BrandPalette.accent)
                + Text(" wk")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary))
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
                    RoundedRectangle(cornerRadius: 1.5)
                        // Committed weeks are purple (#201), matching
                        // the app's committed rail nodes.
                        .fill(count > 0 ? BrandPalette.done : Color.secondary.opacity(0.25))
                        .frame(height: 4 + 14 * CGFloat(count) / CGFloat(maxCount))
                }
            }
            .frame(height: 20, alignment: .bottom)
            // The bar chart is drawn shape-only; give VoiceOver the summary
            // it can't read off the rectangles (#164, WCAG 1.1.1).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Last \(counts.count) weeks")
            .accessibilityValue("\(counts.filter { $0 > 0 }.count) weeks trained")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "plusplus://today"))
    }
}
