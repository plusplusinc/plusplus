import WidgetKit
import SwiftUI
import ActivityKit

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
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        // Refresh at the next midnight so due-ness rolls over even if
        // the app never wakes; the app pokes reloads on real changes.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86400))
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

extension WidgetSnapshot {
    static let placeholder = WidgetSnapshot(
        generatedAt: .now,
        routineNames: ["Push Day"],
        due: [.init(name: "Push Day", caption: "due today", exerciseCount: 6)],
        streakWeeks: 4,
        weeklyCounts: [0, 1, 2, 1, 3, 2, 2, 1, 3, 2, 3, 1]
    )
}

// MARK: - Due Today widget

struct DueTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DueToday", provider: SnapshotProvider()) { entry in
            DueTodayView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Due today")
        .description("What the schedule says you owe.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DueTodayView: View {
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
            if let due = snapshot?.due, !due.isEmpty {
                Text(due[0].name)
                    .font(.system(.headline, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("\(due[0].caption) · \(due[0].exerciseCount) exercises")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                if due.count > 1 {
                    Text("+ \(due.count - 1) more due")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Rest day")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("nothing due")
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
            StreakView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Consecutive weeks trained, with the last 12 weeks.")
        .supportedFamilies([.systemSmall])
    }
}

struct StreakView: View {
    let snapshot: WidgetSnapshot?

    private var counts: [Int] { snapshot?.weeklyCounts ?? [] }
    private var maxCount: Int { max(counts.max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("STREAK")
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            (Text("\(snapshot?.streakWeeks ?? 0)")
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
