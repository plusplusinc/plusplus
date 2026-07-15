import SwiftUI
import PlusPlusKit

/// The Operator thread's message renderers. Color grammar: a preview
/// card frames in advisory amber (a staged change is a heads-up, not
/// an alarm); a receipt accents in data green (the change IS data);
/// option rows are a genuine selection moment, the one legitimate blue.

// MARK: - Text rows

struct OperatorUserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(.system(.subheadline))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
        }
    }
}

struct OperatorReplyView: View {
    let text: String
    var streaming = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            (Text(text) + Text(streaming ? " ▍" : "").foregroundStyle(Theme.accent))
                .font(.system(.subheadline))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(streaming ? .updatesFrequently : [])
            Spacer(minLength: 32)
        }
    }
}

struct OperatorNoticeRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }
}

// MARK: - Preview card (staged change: Apply / Cancel)

struct OperatorPreviewCard: View {
    let payload: OperatorMessage.PreviewPayload
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STAGED CHANGE")
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(Theme.notes)
                .kerning(0.5)
            Text(payload.headline)
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            ForEach(payload.lines, id: \.self) { line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            switch payload.state {
            case .pending:
                Text(OperatorPersona.previewHint)
                    .font(.system(.caption2))
                    .foregroundStyle(Theme.textFaint)
                HStack(spacing: 10) {
                    Button(action: onApply) {
                        Text("Apply")
                            .font(.system(.subheadline, weight: .bold))
                            .foregroundStyle(Theme.onPrimary)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 40)
                            .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.raisedPrimaryKey())
                    .accessibilityIdentifier("operatorApply")
                    QuietKey(label: "Cancel", identifier: "operatorCancelPreview", action: onCancel)
                }
            case .applied:
                statusLine("applied", color: Theme.accent)
            case .cancelled:
                statusLine("cancelled", color: Theme.textFaint)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.cardRadius - 2))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius - 2)
                .strokeBorder(payload.state == .pending ? Theme.notes.opacity(0.6) : Theme.border)
        )
    }

    private func statusLine(_ word: String, color: Color) -> some View {
        Text(word)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(color)
    }
}

// MARK: - Receipt card (applied change: View / Undo)

struct OperatorReceiptCard: View {
    let payload: OperatorMessage.ReceiptPayload
    let onView: (() -> Void)?
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                // Purple, not green: the grammar says done is purple; the
                // seal literally reads DONE (green stays on the data the
                // summary describes, not the completion mark).
                Circle()
                    .fill(payload.undone ? Theme.textFaint : Theme.done)
                    .frame(width: 7, height: 7)
                Text(payload.undone ? "UNDONE" : "DONE")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .foregroundStyle(payload.undone ? Theme.textFaint : Theme.done)
                    .kerning(0.5)
            }
            Text(payload.summary)
                .font(.system(.subheadline))
                .foregroundStyle(payload.undone ? Theme.textSecondary : Theme.textPrimary)
                .strikethrough(payload.undone, color: Theme.textFaint)
            if !payload.undone, payload.undoable || onView != nil {
                HStack(spacing: 10) {
                    if let onView {
                        QuietKey(label: "View", systemImage: "arrow.up.right", identifier: "operatorView", action: onView)
                    }
                    if payload.undoable {
                        QuietKey(label: "Undo", systemImage: "arrow.uturn.backward", identifier: "operatorUndo", action: onUndo)
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.cardRadius - 2))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius - 2).strokeBorder(Theme.border))
    }
}

// MARK: - Options card (ask_user: radio / checkboxes)

struct OperatorOptionsCard: View {
    let payload: OperatorMessage.OptionsPayload
    let onChoose: ([String]) -> Void

    @State private var picked: Set<String> = []

    private var answered: Bool { payload.selection != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(payload.question)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            ForEach(payload.options, id: \.self) { option in
                optionRow(option)
            }
            if payload.allowMultiple, !answered {
                Button {
                    guard !picked.isEmpty else { return }
                    onChoose(payload.options.filter(picked.contains))
                } label: {
                    Text("Confirm")
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(picked.isEmpty ? Theme.textFaint : Theme.onPrimary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 38)
                        .background(picked.isEmpty ? Theme.surface : Theme.primaryFill, in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(picked.isEmpty ? Theme.borderStrong : Color.clear))
                }
                .buttonStyle(.raisedPrimaryKey())
                .disabled(picked.isEmpty)
                .accessibilityIdentifier("operatorConfirmOptions")
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.cardRadius - 2))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius - 2).strokeBorder(Theme.border))
    }

    @ViewBuilder
    private func optionRow(_ option: String) -> some View {
        let chosen = payload.selection?.contains(option) ?? picked.contains(option)
        Button {
            guard !answered else { return }
            if payload.allowMultiple {
                if !picked.insert(option).inserted { picked.remove(option) }
            } else {
                onChoose([option])
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: payload.allowMultiple
                    ? (chosen ? "checkmark.square.fill" : "square")
                    : (chosen ? "largecircle.fill.circle" : "circle"))
                    .font(.system(.subheadline))
                    .foregroundStyle(chosen ? Theme.selected : Theme.textSecondary)
                Text(option)
                    .font(.system(.subheadline))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(chosen ? Theme.selectedTint : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(chosen ? Theme.selectedRing : Theme.border)
            )
        }
        .buttonStyle(.plain)
        .disabled(answered)
        .opacity(answered && !chosen ? 0.55 : 1)
    }
}

// MARK: - Chips row

struct OperatorChipRow: View {
    let chips: [OperatorChip]
    let onTap: (OperatorChip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button {
                        onTap(chip)
                    } label: {
                        Text(chip.label)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.background, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.border))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("operatorChip-\(chip.label)")
                }
            }
            .padding(.horizontal, 1)
        }
    }
}
