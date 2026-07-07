import SwiftUI

/// Shared building blocks for v2 sheets: the title bar and the small
/// typographic/control pieces every sheet composes. One place to change
/// the sheet language (#91).

/// Sheet title bar: centered title, optional Cancel on the left, and a
/// bold accent action (Done/Save) on the right. Pass `action:` with its
/// label — an unlabeled trailing closure would bind to `onCancel`.
struct SheetHeader: View {
    let title: String
    var actionLabel: String
    var actionEnabled: Bool
    var actionIdentifier: String?
    var onCancel: (() -> Void)?
    let action: () -> Void

    init(
        title: String,
        actionLabel: String = "Done",
        actionEnabled: Bool = true,
        actionIdentifier: String? = nil,
        onCancel: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.actionLabel = actionLabel
        self.actionEnabled = actionEnabled
        self.actionIdentifier = actionIdentifier
        self.onCancel = onCancel
        self.action = action
    }

    var body: some View {
        HStack {
            Spacer()
            Text(title).font(.system(.subheadline, weight: .bold))
            Spacer()
        }
        .overlay(alignment: .leading) {
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .font(.system(.subheadline))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .overlay(alignment: .trailing) {
            Button(actionLabel, action: action)
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(actionEnabled ? Theme.textPrimary : Theme.textFaint)
                .disabled(!actionEnabled)
                .accessibilityIdentifier(actionIdentifier ?? "")
        }
        .padding(.top, 24)
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
            }
            .disabled(onTapValue == nil)
            .accessibilityIdentifier("\(identifier)Value")

            HStack(spacing: 0) {
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 42, height: 28)
                }
                .accessibilityIdentifier("\(identifier)Decrement")
                Divider().frame(height: 28).overlay(Theme.border)
                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 42, height: 28)
                }
                .accessibilityIdentifier("\(identifier)Increment")
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
    }
}
