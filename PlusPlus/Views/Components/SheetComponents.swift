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
                    // Wrap to two lines rather than growing the row unbounded
                    // (2026-07-18): a long sheet title used to have no limit.
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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
                // A view-only sheet dismisses with a text key, never a ✕:
                // ✕ is reserved for collapsing an expanded search, so the two
                // never read alike (2026-07-18). Label defaults to "Done".
                SheetDismissKey(label: actionLabel ?? "Done", identifier: actionIdentifier, action: action)
            } else {
                if let onCancel {
                    Button(cancelLabel, action: onCancel)
                        .font(.system(.subheadline))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44)
                        .keyboardShortcut(.cancelAction)
                }
                if let actionLabel {
                    Button(action: action) {
                        Text(actionLabel)
                            .font(.system(.subheadline, weight: .bold))
                            .foregroundStyle(actionEnabled ? Theme.onPrimary : Theme.textFaint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 36)
                            .background(actionEnabled ? Theme.primaryFill : Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(actionEnabled ? Color.clear : Theme.borderStrong, lineWidth: 1))
                    }
                    .disabled(!actionEnabled)
                    // Return commits the sheet's primary action.
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(actionIdentifier ?? "")
                }
            }
        }
    }
}

/// The one sheet/tray dismissal key (2026-07-18): a plain text key —
/// "Cancel" to abandon edits, "Done"/"Close" to leave a view-only sheet.
/// Retires the circular ✕ close so every top-of-sheet button reads the
/// same, and so ✕ can mean ONLY "collapse the expanded search". Matches
/// `SheetHeader`'s cancel styling; reused by the hand-built trays
/// (Operator, GitHub, the start tray) so they stop drifting.
struct SheetDismissKey: View {
    var label: String = "Done"
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(label, action: action)
            .font(.system(.subheadline))
            .foregroundStyle(Theme.textSecondary)
            .frame(minHeight: 44)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier(identifier ?? "")
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
                RoundedRectangle(cornerRadius: Theme.keyRadius)
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

    /// A tap-editable value (it opens a wheel or the duration tape).
    /// Those read as an outlined text input so the picker behind them is
    /// discoverable — the value was ALWAYS tappable, but as bare mono
    /// text it looked like a readout, so the picker (and the whole tape
    /// scrubber) went unfound even by Dave. A non-tappable value (Sets,
    /// nudged only by the ± pair) stays a plain readout.
    private var isValueTappable: Bool { onTapValue != nil }

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
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // Rolling digits on step (#216).
                    .contentTransition(.numericText())
                    .animation(Theme.Anim.standard, value: value)
                    // Field chrome only when tappable: same 36 pt height
                    // and radius as the ± control beside it, so the two
                    // read as a matched pair of inputs (Dave, 2026-07-16).
                    .padding(.horizontal, isValueTappable ? 12 : 7)
                    .padding(.vertical, isValueTappable ? 0 : 3)
                    .frame(minWidth: isValueTappable ? 60 : nil, minHeight: isValueTappable ? 36 : nil)
                    .overlay {
                        if isValueTappable {
                            RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border)
                        }
                    }
            }
            .disabled(onTapValue == nil)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint(onTapValue == nil ? "" : "Opens a picker")
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
                .accessibilityLabel("Decrease \(label)")
                .accessibilityIdentifier("\(identifier)Decrement")
                Divider().frame(height: 36).overlay(Theme.border)
                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle().inset(by: -4))
                }
                .accessibilityLabel("Increase \(label)")
                .accessibilityIdentifier("\(identifier)Increment")
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
    }
}
