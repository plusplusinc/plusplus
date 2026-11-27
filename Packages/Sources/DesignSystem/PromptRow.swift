import SwiftUI

/// A one-time ask on a screen's ground, no card: one wide green pill (`.greenPill`), as tall as
/// `height`, filling the width, and an × trailing it, a tap target wide, in the secondary text
/// color, read by VoiceOver as "Dismiss". It draws nothing of its coming and going; whoever
/// shows it closes its room, as Log does with `CutAway`, and swaps it for its note
/// (`PromptNote`) with `promptSwap(reduceMotion:)`.
public struct PromptRow: View {
    private let title: String
    private let take: () -> Void
    private let dismiss: () -> Void

    /// The pill's height at the default text size, a step above a tap target's.
    static let height: CGFloat = 50
    @ScaledMetric(relativeTo: .body) private var closeWidth = PillButtonStyle.touchHeight

    public init(_ title: String, take: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.title = title
        self.take = take
        self.dismiss = dismiss
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            Button(title, action: take)
                .buttonStyle(.greenPill(height: Self.height, widens: true))
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.ppRowDetail)
                    .fontWeight(.semibold)
                    .foregroundStyle(.pp(.textSecondary))
                    .frame(width: closeWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// What a dismissed or answered prompt leaves for a moment in its place: its sentence leading, in
/// the secondary text color, and an OK pill trailing that fills with the done purple from its
/// leading edge as a rest's key does (`KeyFill`), from `fillDelay` after it shows, over
/// `fillLength`; full, the note calls `end` on its own, and OK calls it sooner. With Reduce
/// Motion on, or VoiceOver running, nothing fills and nothing times it: it stays until OK.
public struct PromptNote: View {
    private let text: String
    private let end: () -> Void

    static let fillDelay = 0.4
    static let fillLength = 5.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    /// When the fill is full; nil while nothing fills.
    @State private var fillEnds: Date?

    public init(_ text: String, end: @escaping () -> Void) {
        self.text = text
        self.end = end
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(text)
                .font(.ppRowDetail)
                .foregroundStyle(.pp(.textSecondary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button("OK", action: end)
                .buttonStyle(.pill(filling: fillEnds.map {
                    KeyFill(length: Self.fillLength, ends: $0)
                }))
                .fixedSize()
        }
        .frame(minHeight: PromptRow.height)
        .task {
            guard !reduceMotion, !voiceOver else { return }
            let ends = Date.now.addingTimeInterval(Self.fillDelay + Self.fillLength)
            fillEnds = ends
            do {
                try await Task.sleep(for: .seconds(ends.timeIntervalSinceNow), tolerance: .zero)
            } catch {
                return
            }
            end()
        }
    }
}

extension View {
    /// The prompt giving way to its note in its place (`PromptRow`, `PromptNote`): the row fades
    /// with a slight shrink, and the note fades in just after it, a little grown into its size;
    /// with Reduce Motion, a plain crossfade. Give it to both; `isNote` says which this is.
    public func promptSwap(isNote: Bool, reduceMotion: Bool) -> some View {
        transition(
            reduceMotion
                ? AnyTransition.opacity.animation(.cardCrossfade)
                : isNote
                ? AnyTransition.opacity.combined(with: .scale(scale: 0.97))
                .animation(.easeOut(duration: 0.3).delay(0.16))
                : AnyTransition.opacity.combined(with: .scale(scale: 0.96))
                .animation(.easeIn(duration: 0.22)),
        )
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        PromptRow("Sync to Apple Health", take: { }, dismiss: { })
        PromptNote("You can turn on Apple Health sync later in Settings.", end: { })
    }
    .padding(Spacing.md)
    .frame(maxHeight: .infinity)
    .background(Color.pp(.background))
}
