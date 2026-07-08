import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

/// The widget extension (#147): the rest-countdown Live Activity plus
/// Home/Lock Screen widgets fed by the app's snapshot. The extension
/// can't import the app's Theme, so a minimal palette lives here —
/// values mirror Theme.swift's v3 tokens.
enum WTheme {
    static let green = Color(red: 0x46 / 255.0, green: 0xD1 / 255.0, blue: 0x7C / 255.0)
    static let greenLight = Color(red: 0x17 / 255.0, green: 0x91 / 255.0, blue: 0x4B / 255.0)

    static var accent: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0x46 / 255.0, green: 0xD1 / 255.0, blue: 0x7C / 255.0, alpha: 1)
                : UIColor(red: 0x17 / 255.0, green: 0x91 / 255.0, blue: 0x4B / 255.0, alpha: 1)
        })
    }

    /// v4 selection blue (#176): green is data, blue is interactive.
    /// Mirrors Theme.selected.
    static var selected: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0x62 / 255.0, green: 0xB6 / 255.0, blue: 0xDE / 255.0, alpha: 1)
                : UIColor(red: 0x1A / 255.0, green: 0x7F / 255.0, blue: 0xA8 / 255.0, alpha: 1)
        })
    }
}

@main
struct PlusPlusWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RestLiveActivity()
        DueTodayWidget()
        StreakWidget()
    }
}

// MARK: - Rest Live Activity

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            // Lock Screen / banner.
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("REST")
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            .kerning(0.8)
                            .foregroundStyle(.secondary)
                        Text("Up next: \(context.state.exerciseName) · set \(context.state.setNumber)")
                            .font(.system(.footnote, weight: .semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(WTheme.accent)
                        .frame(maxWidth: 96)
                }
                RestControlButtons()
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.55))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("REST")
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(context.state.exerciseName)
                            .font(.system(.footnote, weight: .semibold))
                            .lineLimit(1)
                        Text("set \(context.state.setNumber)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(WTheme.green)
                        .frame(maxWidth: 88)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RestControlButtons()
                        .padding(.top, 6)
                }
            } compactLeading: {
                Text("++")
                    .font(.system(.footnote, design: .monospaced, weight: .bold))
                    .foregroundStyle(WTheme.green)
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WTheme.green)
                    .frame(maxWidth: 44)
            } minimal: {
                Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WTheme.green)
                    .frame(maxWidth: 36)
            }
        }
    }
}

/// +15s / Skip on the island and Lock Screen (#157). The intents run in
/// the app's process and drive the same code path as the on-screen
/// buttons, so island, notification, and app can't disagree.
struct RestControlButtons: View {
    var body: some View {
        HStack(spacing: 10) {
            Button(intent: AddRestTimeIntent()) {
                Text("+15s")
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
            }
            .buttonStyle(.bordered)
            // Blue, not green: interactive state, not data (#176).
            .tint(WTheme.selected)

            Button(intent: SkipRestIntent()) {
                Text("Skip")
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
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
                    .foregroundStyle(WTheme.accent)
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
                .foregroundStyle(WTheme.accent)
                + Text(" wk")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary))
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(count > 0 ? WTheme.accent : Color.secondary.opacity(0.25))
                        .frame(height: 4 + 14 * CGFloat(count) / CGFloat(maxCount))
                }
            }
            .frame(height: 20, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "plusplus://today"))
    }
}
