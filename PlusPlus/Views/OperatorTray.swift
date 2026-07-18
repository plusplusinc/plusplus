import SwiftUI
import UIKit
import PlusPlusKit

/// Operator's chat surface: a full-height tray off the reveal surface
/// (the GitHubSyncTray precedent — every keyboard-bearing flow on that
/// surface is a sheet, which brings native keyboard avoidance and full
/// width for free). The transcript is the persisted rolling thread;
/// cards render inline; unavailable states explain themselves here in
/// Operator's voice.
struct OperatorTray: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RevealController.self) private var reveal
    let controller: OperatorController

    @State private var draft = ""
    /// Opens tall (chat + keyboard want the height); draggable to half
    /// height so navigation and applied changes show behind it (Dave,
    /// build-85 round) — background stays interactive at medium.
    @State private var detent: PresentationDetent = .large

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
            if controller.availability == .ready {
                scrollTopBorder
                transcript
                inputBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            } else {
                unavailableBody
                    .padding(.horizontal, 20)
                Spacer()
            }
        }
        .background(Theme.surface)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onAppear {
            controller.refresh()
            controller.prewarmIfReady()
        }
    }

    /// The subtle seam between the fixed header and the scrolling
    /// transcript (Dave, build-85 round).
    private var scrollTopBorder: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.top, 6)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 9) {
            // The face, not a status dot — dots mean sync state (Dave,
            // build-85 round); readiness reads from the eyes' tint and
            // the status word.
            OperatorFaceGlyph(size: 26, ready: controller.availability == .ready)
            Text("Operator")
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            if let word = controller.availability.statusWord {
                Text(word)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
            }
            Spacer(minLength: 12)
            // One dismissal vocabulary across every tray (2026-07-18): a
            // text key, never a ✕ (✕ is the search-collapse glyph).
            SheetDismissKey(label: "Done", identifier: "closeOperator") {
                dismiss()
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // A plain VStack, not lazy: the transcript is capped at 60
                // rows, and a lazy stack would discard an options card's
                // in-progress multi-selection when scrolled out of window.
                VStack(alignment: .leading, spacing: 12) {
                    if controller.hasHiddenHistory {
                        OperatorNoticeRow(text: OperatorPersona.scrollbackNotice)
                    }
                    if controller.visibleMessages.isEmpty, controller.streamingText.isEmpty {
                        emptyThread
                    }
                    ForEach(controller.visibleMessages) { message in
                        row(for: message)
                            .id(message.id)
                    }
                    if controller.turnState == .thinking {
                        OperatorNoticeRow(text: "…")
                            .id("operatorLiveRow")
                    } else if controller.turnState == .streaming {
                        OperatorReplyView(text: controller.streamingText, streaming: true)
                            .id("operatorLiveRow")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: controller.streamingText) { _, _ in
                proxy.scrollTo("operatorLiveRow", anchor: .bottom)
            }
            .onChange(of: controller.messages.count) { _, _ in
                if let last = controller.visibleMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyThread: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(OperatorPersona.emptyThreadLine)
                .font(.system(.subheadline))
                .foregroundStyle(Theme.textSecondary)
            Text(OperatorPersona.heroTagline)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.top, 18)
    }

    @ViewBuilder
    private func row(for message: OperatorMessage) -> some View {
        switch message.kind {
        case .user(let text):
            OperatorUserBubble(text: text)
        case .reply(let text):
            OperatorReplyView(text: text)
        case .notice(let text):
            OperatorNoticeRow(text: text)
        case .preview(let payload):
            OperatorPreviewCard(
                payload: payload,
                onApply: { controller.applyPreview(messageID: message.id) },
                onCancel: { controller.cancelPreview(messageID: message.id) }
            )
        case .receipt(let payload):
            OperatorReceiptCard(
                payload: payload,
                onView: payload.destinations.isEmpty ? nil : {
                    // Re-post (the user may have wandered since the
                    // apply-time auto-navigation), then get out of the
                    // way: tray down, drawer closed, result on screen.
                    NotificationCenter.default.post(
                        name: .plusplusOperatorShow,
                        object: payload.destinations.first
                    )
                    reveal.close()
                    dismiss()
                },
                onUndo: { controller.undoReceipt(messageID: message.id) }
            )
        case .options(let payload):
            OperatorOptionsCard(payload: payload) { selection in
                controller.chooseOptions(messageID: message.id, selection: selection)
            }
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !controller.chips.isEmpty, controller.turnState == .idle {
                OperatorChipRow(chips: controller.chips) { chip in
                    controller.send(chip.text)
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(OperatorPersona.inputPlaceholder, text: $draft, axis: .vertical)
                    .font(.system(.subheadline))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1...4)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
                    .accessibilityIdentifier("operatorInput")
                sendKey
            }
        }
    }

    @ViewBuilder
    private var sendKey: some View {
        if controller.turnState == .idle {
            Button {
                // The draft only clears when the controller ACCEPTED the
                // text — a bounced send must not eat the user's typing.
                if controller.send(draft) {
                    draft = ""
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(width: 40, height: 40)
                    .background(Theme.primaryFill, in: Circle())
            }
            .buttonStyle(.raisedPrimaryKey(cornerRadius: 20))
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("operatorSend")
        } else {
            Button {
                controller.cancelTurn()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Theme.background, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.borderStrong))
            }
            .buttonStyle(.raisedKey(cornerRadius: 20))
            .accessibilityLabel("Stop")
            .accessibilityIdentifier("operatorStop")
        }
    }

    // MARK: - Unavailable

    private var unavailableBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(controller.availability.explanation ?? "")
                .font(.system(.subheadline))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if controller.availability.offersSettingsLink {
                QuietKey(label: "Open Settings", systemImage: "gear", identifier: "operatorOpenSettings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .padding(.top, 16)
    }
}
