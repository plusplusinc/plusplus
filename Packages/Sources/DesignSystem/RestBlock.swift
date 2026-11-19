import SwiftUI

/// The rest under the exercise just finished: the word "Rest" as the current exercise's progress
/// line is drawn, the time left under it as its figures are, in bold SF Mono at about half their
/// size (`RestFigure`), then −15 s and +15 s. Nothing in it is green: the dot on the rail is the
/// rest's one green. The time ticks on whole seconds before `ends` on a timeline, as the
/// workout's time key does, drawing once while paused (`pausedLeft`), so nothing is written per
/// second. It reads "0:35", rounded up, so it shows the whole rest as it starts and 0:00 only as
/// it ends. To VoiceOver it is one element, "Rest", its value the time left in words, and the
/// two buttons.
public struct RestBlock: View {
    let ends: Date
    /// While paused, the seconds left; nil while running.
    let pausedLeft: Double?
    let onShorten: () -> Void
    let onExtend: () -> Void

    @ScaledMetric(relativeTo: CurrentFigure.textStyle) private var size = RestFigure.size
    @Environment(\.locale) private var locale

    public init(
        ends: Date,
        pausedLeft: Double?,
        onShorten: @escaping () -> Void,
        onExtend: @escaping () -> Void,
    ) {
        self.ends = ends
        self.pausedLeft = pausedLeft
        self.onShorten = onShorten
        self.onExtend = onExtend
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TimelineView(RestSchedule(ends: ends, isPaused: pausedLeft != nil)) { context in
                let left = pausedLeft ?? max(0, ends.timeIntervalSince(context.date))
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Rest")
                        .font(.ppCurrentProgress)
                        .foregroundStyle(.pp(.textSecondary))
                    Text(Self.text(left, locale: locale))
                        .font(.system(size: size, weight: .bold, design: .monospaced))
                        .foregroundStyle(.pp(.textPrimary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rest")
                .accessibilityValue(Self.spoken(left, locale: locale))
            }
            HStack(spacing: Spacing.sm) {
                Button(action: onShorten) { Text(AttributedString.monoNumbers(
                    "−15 s",
                    font: .ppButton,
                )) }
                .accessibilityLabel("Shorten rest by 15 seconds")
                Button(action: onExtend) { Text(AttributedString.monoNumbers(
                    "+15 s",
                    font: .ppButton,
                )) }
                .accessibilityLabel("Extend rest by 15 seconds")
            }
            .buttonStyle(RestStepStyle())
        }
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "0:35", the seconds rounded up.
    static func text(_ seconds: Double, locale: Locale) -> String {
        Duration.seconds(seconds.rounded(.up))
            .formatted(.time(pattern: .minuteSecond).locale(locale))
    }

    /// "35 seconds".
    static func spoken(_ seconds: Double, locale: Locale) -> String {
        Duration.seconds(seconds.rounded(.up))
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide).locale(locale))
    }
}

/// −15 s and +15 s: outlined capsules, 44 pt tall, in the text's own colors.
private struct RestStepStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.pp(.textPrimary))
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 44)
            .background(Capsule().strokeBorder(Color.pp(.borderStrong), lineWidth: 1))
            .contentShape(.capsule)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

/// Whole seconds counting down to `ends`, a tick as each second of the rest goes, so "0:35" turns
/// to "0:34" as a whole second has gone; one entry while paused.
private struct RestSchedule: TimelineSchedule {
    let ends: Date
    let isPaused: Bool

    func entries(from startDate: Date, mode _: Mode) -> AnyIterator<Date> {
        guard !isPaused else {
            var once = true
            return AnyIterator {
                defer { once = false }
                return once ? startDate : nil
            }
        }
        let left = ends.timeIntervalSince(startDate)
        var next = left > 0 ? ends.addingTimeInterval(-left.rounded(.down)) : ends
        var first = true
        return AnyIterator {
            if first {
                first = false
                return startDate
            }
            guard next <= ends else { return nil }
            defer { next = next.addingTimeInterval(1) }
            return next
        }
    }
}

#Preview {
    RestBlock(ends: .now.addingTimeInterval(35), pausedLeft: nil, onShorten: { }, onExtend: { })
        .padding()
        .background(Color.pp(.background))
}
