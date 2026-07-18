import SwiftUI
import PlusPlusKit

/// The Operator thread's message renderers. Color grammar: a preview
/// card frames in advisory amber (a staged change is a heads-up, not
/// an alarm); a receipt accents in data green (the change IS data);
/// option rows are a genuine selection moment, the one legitimate blue.

// MARK: - The face

/// Operator's mark: a small face whose eyes are the ++ glyph (Dave,
/// build-85 design round). Green eyes when the model is ready — the ++
/// is the brand's data green; the face itself is quiet chrome.
struct OperatorFaceGlyph: View {
    var size: CGFloat = 32
    var ready: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32)
                .fill(Theme.background)
            RoundedRectangle(cornerRadius: size * 0.32)
                .strokeBorder(Theme.borderStrong, lineWidth: 1.5)
            HStack(spacing: size * 0.13) {
                Text("+")
                Text("+")
            }
            .font(.system(size: size * 0.44, weight: .bold, design: .monospaced))
            .foregroundStyle(ready ? Theme.accent : Theme.textFaint)
            .offset(y: -size * 0.05)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Sentence-case display

extension String {
    /// Display-time sentence casing for MODEL-authored text: the 3B
    /// writes "want to check them out?" no matter how firmly the
    /// instructions ask for sentence case (Dave, build-85 round). This
    /// only ever UPPERCASES a letter opening a sentence — names keep
    /// their casing, and the stored thread plus everything echoed back
    /// to the model stay verbatim.
    var operatorSentenceCased: String {
        var result = ""
        result.reserveCapacity(count)
        var atSentenceStart = true
        for character in self {
            if atSentenceStart, character.isLetter {
                result.append(contentsOf: character.uppercased())
                atSentenceStart = false
            } else {
                result.append(character)
                if character == "." || character == "?" || character == "!" || character.isNewline {
                    atSentenceStart = true
                } else if !character.isWhitespace {
                    atSentenceStart = false
                }
            }
        }
        return result
    }

    /// Sentence-case a short search query for a `Create "…"` / `Add "…"`
    /// label: capitalize ONLY the first letter, leaving the rest verbatim
    /// so "iPhone", "EZ-bar", and "e1RM" survive intact (2026-07-18).
    /// Deliberately not `operatorSentenceCased`, which upcases after every
    /// period and would mangle mid-word capitals.
    var sentenceCasedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

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
            (Text(text.operatorSentenceCased) + Text(streaming ? " ▍" : "").foregroundStyle(Theme.accent))
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
                    .accessibilityHidden(true)
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
            Text(payload.question.operatorSentenceCased)
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
                // Display casing only — the tap still sends the raw
                // option string so the model recognizes its own words.
                Text(option.operatorSentenceCased)
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

/// Suggested prompts, WRAPPING to as many lines as they need — a
/// horizontal scroll cut pills off at the screen edge (Dave, build-85
/// round: wrap, don't overflow). The pill's text IS the prompt it
/// sends, verbatim.
struct OperatorChipRow: View {
    let chips: [OperatorChip]
    let onTap: (OperatorChip) -> Void

    var body: some View {
        OperatorFlowLayout(spacing: 8) {
            ForEach(chips) { chip in
                Button {
                    onTap(chip)
                } label: {
                    Text(chip.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.background, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.border))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("operatorChip-\(chip.text)")
            }
        }
    }
}

/// Minimal leading-aligned flow layout: rows fill left to right and
/// wrap. Only what the chip row needs — not a general grid.
struct OperatorFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        guard let last = rows.last else { return .zero }
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: last.y + last.height
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(maxWidth: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    proposal: .unspecified
                )
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var height: CGFloat = 0
        var width: CGFloat = 0
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0
        var y: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !current.indices.isEmpty, x + size.width > maxWidth {
                current.width = max(0, x - spacing)
                rows.append(current)
                y += current.height + spacing
                current = Row(y: y)
                x = 0
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.indices.isEmpty {
            current.width = max(0, x - spacing)
            rows.append(current)
        }
        return rows
    }
}
