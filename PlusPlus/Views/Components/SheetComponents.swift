import SwiftUI

/// Shared building blocks for v2 sheets: the title bar and the small
/// typographic/control pieces every sheet composes. One place to change
/// the sheet language (#91).

/// Sheet title bar (v4 §C): title upper-left with an optional context
/// subtitle; on the right, auxiliary text (Cancel/Clear) beside the
/// tray's single commit — a primaryFill capsule, because committing a
/// form is an ACTION, not a selection (ink, never blue). The ✕ variant
/// exists only for pickers where tapping a row IS the action.
struct SheetHeader: View {
    let title: String
    var subtitle: String?
    var actionLabel: String?
    var actionEnabled: Bool
    var actionIdentifier: String?
    var onCancel: (() -> Void)?
    var cancelLabel: String
    var closeOnly: Bool
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        actionLabel: String? = "Done",
        actionEnabled: Bool = true,
        actionIdentifier: String? = nil,
        onCancel: (() -> Void)? = nil,
        cancelLabel: String = "Cancel",
        closeOnly: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionLabel = actionLabel
        self.actionEnabled = actionEnabled
        self.actionIdentifier = actionIdentifier
        self.onCancel = onCancel
        self.cancelLabel = cancelLabel
        self.closeOnly = closeOnly
        self.action = action
    }

    var body: some View {
        // The title centers against the buttons row (#211 — with a
        // subtitle it used to ride high); the subtitle hangs beneath.
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 14) {
                Text(title)
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 12)
                headerButtons
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
        }
        .padding(.top, 14)
    }

    @ViewBuilder
    private var headerButtons: some View {
        Group {
            if closeOnly {
                Button(action: action) {
                    Image(systemName: "xmark")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.border))
                        .padding(6)
                        .contentShape(Circle())
                }
                .accessibilityIdentifier(actionIdentifier ?? "")
            } else {
                if let onCancel {
                    Button(cancelLabel, action: onCancel)
                        .font(.system(.subheadline))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44)
                }
                if let actionLabel {
                    Button(action: action) {
                        Text(actionLabel)
                            .font(.system(.subheadline, weight: .bold))
                            .foregroundStyle(actionEnabled ? Theme.onPrimary : Theme.textFaint)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(actionEnabled ? Theme.primaryFill : Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(actionEnabled ? Color.clear : Theme.borderStrong, lineWidth: 1))
                    }
                    .disabled(!actionEnabled)
                    .accessibilityIdentifier(actionIdentifier ?? "")
                }
            }
        }
    }
}

/// Mono section caption used inside v2 sheets.
struct SheetSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .kerning(0.7)
            .padding(.bottom, 6)
    }
}

/// Bordered full-width action button used in v2 sheets.
struct SheetActionButton: View {
    let title: String
    var systemImage: String?
    var destructive = false
    var dimmed = false
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, destructive: Bool = false, dimmed: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.destructive = destructive
        self.dimmed = dimmed
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(.caption, weight: .semibold))
                }
                Text(title)
                    .font(.system(.footnote, weight: .semibold))
            }
            .foregroundStyle(destructive ? Theme.destructive : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(destructive ? Theme.destructive.opacity(0.4) : Theme.borderStrong)
            )
        }
        .opacity(dimmed ? 0.35 : 1)
        .disabled(dimmed)
    }
}

/// Metric row in the v2 sheet style: label, tappable mono value, and a
/// bordered −/+ pair. Increment/decrement identifiers are derived from
/// `identifier` ("weightIncrement" etc.) for the UI tests.
struct MetricStepperRow: View {
    let label: String
    let value: String
    let identifier: String
    var onTapValue: (() -> Void)?
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(.footnote))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                onTapValue?()
            } label: {
                Text(value)
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    // Rolling digits on step (#216).
                    .contentTransition(.numericText())
                    .animation(Theme.Anim.standard, value: value)
            }
            .disabled(onTapValue == nil)
            .accessibilityIdentifier("\(identifier)Value")

            // 44-wide targets with the hit carried to 44 pt tall by the
            // row (§H: 44×36 visual, 44×44 hit, 52 pt row).
            HStack(spacing: 0) {
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle().inset(by: -4))
                }
                .accessibilityIdentifier("\(identifier)Decrement")
                Divider().frame(height: 36).overlay(Theme.border)
                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle().inset(by: -4))
                }
                .accessibilityIdentifier("\(identifier)Increment")
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
    }
}
