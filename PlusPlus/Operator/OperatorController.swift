import Foundation
import FoundationModels
import Observation
import SwiftData
import SwiftUI
import PlusPlusKit

/// Operator's conductor: owns the rolling thread, the model session
/// lifecycle (prewarm, one turn at a time, proactive recycle under the
/// tiny window), the preview→apply→receipt→undo bookkeeping, and the
/// chips. The MODEL only ever streams text and calls tools; everything
/// the tools do lands here, deterministically.
@Observable @MainActor
final class OperatorController {
    enum TurnState: Equatable {
        case idle
        case thinking
        case streaming
    }

    // MARK: - Observable surface (what the tray renders)

    private(set) var messages: [OperatorMessage] = []
    private(set) var turnState: TurnState = .idle
    /// The cumulative text of the reply being streamed right now.
    private(set) var streamingText = ""
    private(set) var availability: OperatorAvailability = .deviceNotEligible
    private(set) var chips: [OperatorChip] = []

    /// Messages the transcript shows; the store may hold more (the
    /// scroll-back cap, explained honestly by the notice row).
    var visibleMessages: [OperatorMessage] {
        Array(messages.suffix(OperatorThreadPolicy.visibleCap))
    }

    var hasHiddenHistory: Bool {
        messages.count > OperatorThreadPolicy.visibleCap
    }

    // MARK: - Internals

    let dataService: OperatorDataService
    let engine: ChangeEngine
    private let store: OperatorThreadStore
    private let makeModel: (OperatorController) -> any OperatorModel
    private var model: (any OperatorModel)?
    private var currentTurn: Task<Void, Never>?
    /// Depth-1 undo: only the newest applied change can revert, and
    /// only within this launch (inverses are never persisted).
    private var lastApplied: (receiptID: UUID, inverse: InverseChange)?
    /// Set when the session was recycled; prepended to the next prompt
    /// so context survives in the PROMPT channel, never instructions.
    private var pendingCarryover: String?
    /// Rough token bookkeeping for the proactive recycle (chars/3, the
    /// policy's estimate). Starts at the fixed session overhead —
    /// instructions plus four tool schemas, ~1,000 tokens — so the 70%
    /// threshold measures the whole window, not just the conversation.
    private static let sessionOverheadCharacters = 3_000
    private var sessionCharacters = OperatorController.sessionOverheadCharacters
    /// The screen line supplier (RootTabView's ViewContext).
    var contextLine: () -> String? = { nil }
    var hasWorkoutHistory: () -> Bool = { false }
    /// Availability seam: CI simulators have no Apple Intelligence, so
    /// controller tests inject `.ready` and a scripted model.
    var availabilityProvider: () -> OperatorAvailability = { .current() }

    init(
        context: ModelContext,
        store: OperatorThreadStore = OperatorThreadStore(),
        makeModel: ((OperatorController) -> any OperatorModel)? = nil
    ) {
        dataService = OperatorDataService(context: context)
        engine = ChangeEngine(context: context)
        self.store = store
        self.makeModel = makeModel ?? { controller in
            FoundationOperatorModel(
                tools: controller.makeTools(),
                instructions: OperatorPersona.instructions
            )
        }
        // Persisted receipts lose their Undo on load: depth-1 undo is
        // in-memory only, so a stale enabled key would be a silent no-op
        // (the dishonest kind).
        messages = Self.droppingStaleUndo(store.load())
        engine.afterApply = { [weak self] context in
            self?.runPostApplyHooks(context)
        }
        availability = availabilityProvider()
        refreshChips()
    }

    private static func droppingStaleUndo(_ loaded: [OperatorMessage]) -> [OperatorMessage] {
        loaded.map { message in
            guard case .receipt(var payload) = message.kind, payload.undoable else { return message }
            var sanitized = message
            payload.undoable = false
            sanitized.kind = .receipt(payload)
            return sanitized
        }
    }

    /// Mirrors PlusPlusApp's unit-test-host guard: the test host must
    /// never touch a real EKEventStore.
    private static let isUnitTestHost =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil

    /// The live post-mutation hooks — the same trio the app fires on
    /// scenePhase transitions (PlusPlusApp), so an Operator change
    /// reaches the widget/watch/calendar without waiting for one.
    private func runPostApplyHooks(_ context: ModelContext) {
        WatchBridge.shared.pushPlan()
        WidgetSnapshotWriter.write(container: context.container)
        guard !Self.isUnitTestHost else { return }
        if let routines = try? context.fetch(FetchDescriptor<Routine>()) {
            Task {
                await CalendarSyncCoordinator.shared.reconcile(routines: routines)
            }
        }
    }

    private func makeTools() -> [any Tool] {
        // The narrow-tool surface: one tool per edit intent, so the 3B
        // model picks operations by NAME (classification) instead of
        // composing a spec algebra (reasoning it demonstrably lacks).
        [
            FindItemsTool(services: self),
            GetStatsTool(services: self),
            AddGearTool(services: self),
            RemoveGearTool(services: self),
            ReplaceGearTool(services: self),
            CreateLibraryTool(services: self),
            CreateRoutineTool(services: self),
            EditRoutineExercisesTool(services: self),
            SetScheduleTool(services: self),
            SetRestTool(services: self),
            CreateExerciseTool(services: self),
            EditExerciseTool(services: self),
            ConvertTrackingTool(services: self),
            FormSupersetTool(services: self),
            RenameItemTool(services: self),
            DeleteItemTool(services: self),
            AskUserTool(services: self),
        ]
    }

    // MARK: - Lifecycle

    /// Re-read availability (Settings can flip it while backgrounded)
    /// and refresh the chips. Called on tray open and scenePhase active.
    func refresh() {
        availability = availabilityProvider()
        refreshChips()
    }

    /// Create + warm the session ahead of the first turn (1–2 s saved).
    /// Never constructs a session while the model is unavailable.
    func prewarmIfReady() {
        availability = availabilityProvider()
        guard availability == .ready, model == nil else { return }
        let created = makeModel(self)
        model = created
        created.prewarm()
    }

    private func refreshChips() {
        let line = contextLine()
        let tab = line?.split(separator: "/").first.map(String.init) ?? (line ?? "today")
        chips = OperatorChips.chips(
            tab: tab,
            detail: line?.contains("/") == true ? line : nil,
            hasHistory: hasWorkoutHistory()
        )
    }

    // MARK: - Turns

    /// Starts a turn. Returns whether the text was ACCEPTED — a false
    /// means nothing entered the thread, so callers keep the user's
    /// input alive (the tray keeps the draft, an options card stays
    /// tappable) instead of silently losing it.
    @discardableResult
    func send(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard turnState == .idle, model?.isResponding != true else {
            // isResponding covers the cancel race: our task died but the
            // session is still winding down; a new request would only
            // bounce off .concurrentRequests.
            post(OperatorMessage(kind: .notice(OperatorPersona.stillWorking)))
            return false
        }
        prewarmIfReady()
        guard availability == .ready, model != nil else {
            post(OperatorMessage(kind: .notice(availability.explanation ?? OperatorPersona.somethingJammed)))
            return false
        }

        append(OperatorMessage(kind: .user(text)))
        runTurn(userText: text, isRetry: false)
        return true
    }

    func cancelTurn() {
        currentTurn?.cancel()
        currentTurn = nil
        if !streamingText.isEmpty {
            append(OperatorMessage(kind: .reply(streamingText)))
        }
        streamingText = ""
        turnState = .idle
    }

    private func runTurn(userText: String, isRetry: Bool) {
        prewarmIfReady()
        guard let model else {
            post(OperatorMessage(kind: .notice(availability.explanation ?? OperatorPersona.somethingJammed)))
            return
        }

        // Proactive recycle BEFORE the turn when the estimate says the
        // next exchange might not fit.
        let estimated = OperatorThreadPolicy.estimatedTokens(forCharacters: sessionCharacters)
        if OperatorThreadPolicy.shouldRecycle(usedTokens: estimated, contextSize: model.contextSize) {
            recycleSession()
        }

        var prompt = OperatorPersona.turnPrefix(date: Date(), screen: contextLine())
        if let carryover = pendingCarryover {
            prompt += "\n[earlier: \(carryover)]"
            pendingCarryover = nil
        }
        prompt += "\n\(userText)"
        sessionCharacters += prompt.count

        turnState = .thinking
        streamingText = ""
        currentTurn = Task { [weak self] in
            guard let self else { return }
            do {
                for try await cumulative in model.send(prompt) {
                    if Task.isCancelled { return }
                    self.streamingText = cumulative
                    self.turnState = .streaming
                }
                // A cancelled stream can end its loop normally; without
                // this guard the dead task would finish a NEWER turn.
                guard !Task.isCancelled else { return }
                self.finishTurn(reply: self.streamingText)
            } catch let error as OperatorModelError {
                guard !Task.isCancelled else { return }
                self.handleTurnError(error, userText: userText, isRetry: isRetry)
            } catch {
                if !Task.isCancelled {
                    self.finishTurn(reply: "", notice: OperatorPersona.somethingJammed)
                }
            }
        }
    }

    private func finishTurn(reply: String, notice: String? = nil) {
        if !reply.isEmpty {
            append(OperatorMessage(kind: .reply(reply)))
            sessionCharacters += reply.count
        }
        if let notice {
            append(OperatorMessage(kind: .notice(notice)))
        }
        streamingText = ""
        turnState = .idle
        currentTurn = nil
        refreshChips()
    }

    private func handleTurnError(_ error: OperatorModelError, userText: String, isRetry: Bool) {
        switch error {
        case .contextExceeded:
            // Recycle and retry the same turn once; the visible thread
            // never loses anything (store ≠ session).
            recycleSession()
            if isRetry {
                finishTurn(reply: "", notice: OperatorPersona.contextRecycled)
            } else {
                streamingText = ""
                runTurn(userText: userText, isRetry: true)
            }
        case .guardrail:
            finishTurn(reply: "", notice: OperatorPersona.guardrailTripped)
        case .refusal:
            finishTurn(reply: "", notice: OperatorPersona.modelRefused)
        case .rateLimited:
            finishTurn(reply: "", notice: OperatorPersona.rateLimited)
        case .busy:
            finishTurn(reply: "", notice: OperatorPersona.stillWorking)
        case .assetsUnavailable:
            model = nil
            availability = availabilityProvider()
            finishTurn(reply: "", notice: OperatorPersona.modelDownloading)
        case .other:
            finishTurn(reply: "", notice: OperatorPersona.somethingJammed)
        }
    }

    /// Fresh session; the deterministic carryover (last topic + recent
    /// applied changes) rides the next prompt.
    private func recycleSession() {
        var pieces: [String] = []
        let recentReceipts = messages.suffix(20).compactMap { message -> String? in
            if case .receipt(let payload) = message.kind { return payload.summary }
            return nil
        }
        if !recentReceipts.isEmpty {
            pieces.append("recent changes: \(recentReceipts.suffix(3).joined(separator: " "))")
        }
        if let lastUser = messages.last(where: {
            if case .user = $0.kind { return true }
            return false
        }), case .user(let text) = lastUser.kind {
            pieces.append("last topic: \(text.prefix(80))")
        }
        pendingCarryover = pieces.isEmpty ? nil : pieces.joined(separator: " · ")
        sessionCharacters = Self.sessionOverheadCharacters
        model?.recycle()
    }

    // MARK: - Card actions

    /// The preview card's Apply tap: re-resolve the stored spec and
    /// apply. The tap is the user's confirmation; tiering is bypassed.
    func applyPreview(messageID: UUID) {
        guard let index = indexOfMessage(messageID),
              case .preview(var payload) = messages[index].kind,
              payload.state == .pending
        else { return }
        let outcome = engine.applyStaged(payload.spec)
        switch outcome {
        case .applied(let change):
            payload.state = .applied
            messages[index].kind = .preview(payload)
            postReceipt(change)
        case .invalid(let reason):
            payload.state = .cancelled
            messages[index].kind = .preview(payload)
            append(OperatorMessage(kind: .notice("That change no longer applies: \(reason)")))
        case .staged:
            // applyStaged never re-stages; treat as a no-op.
            break
        }
        persist()
    }

    func cancelPreview(messageID: UUID) {
        guard let index = indexOfMessage(messageID),
              case .preview(var payload) = messages[index].kind,
              payload.state == .pending
        else { return }
        payload.state = .cancelled
        messages[index].kind = .preview(payload)
        persist()
    }

    /// The receipt card's Undo tap. Depth 1: only the latest applied
    /// change is undoable, and the receipt's flag flips as soon as a
    /// newer change supersedes it.
    func undoReceipt(messageID: UUID) {
        guard let last = lastApplied, last.receiptID == messageID else { return }
        let outcome = engine.undo(last.inverse)
        if case .applied = outcome {
            lastApplied = nil
            if let index = indexOfMessage(messageID),
               case .receipt(var payload) = messages[index].kind {
                payload.undone = true
                payload.undoable = false
                messages[index].kind = .receipt(payload)
            }
            append(OperatorMessage(kind: .notice(undoSummary(from: outcome))))
        } else if case .invalid(let reason) = outcome {
            append(OperatorMessage(kind: .notice(reason)))
        }
        persist()
    }

    private func undoSummary(from outcome: ChangeEngine.ChangeOutcome) -> String {
        if case .applied(let change) = outcome { return change.receipt.summary }
        return OperatorPersona.undoneLabel
    }

    /// An options card tap: send the selection as the next user turn
    /// (ask_user is non-blocking by design). The card is only marked
    /// answered when the send is ACCEPTED — a tap while a turn is still
    /// streaming leaves the card live instead of eating the answer.
    func chooseOptions(messageID: UUID, selection: [String]) {
        guard let index = indexOfMessage(messageID),
              case .options(var payload) = messages[index].kind,
              payload.selection == nil
        else { return }
        guard send(selection.joined(separator: ", ")) else { return }
        payload.selection = selection
        messages[index].kind = .options(payload)
        persist()
    }

    // MARK: - OperatorToolServices plumbing

    private func postReceipt(_ change: ChangeEngine.AppliedChange) {
        // A new applied change supersedes the previous undo.
        if let previous = lastApplied, let index = indexOfMessage(previous.receiptID),
           case .receipt(var payload) = messages[index].kind {
            payload.undoable = false
            messages[index].kind = .receipt(payload)
        }
        let undoable = !change.inverse.isEmpty
        let message = OperatorMessage(kind: .receipt(.init(
            summary: change.receipt.summary,
            destinations: change.receipt.destinations,
            undoable: undoable
        )))
        lastApplied = undoable ? (message.id, change.inverse) : nil
        append(message)
        // Outcome navigation (Dave): the main surface steers to what the
        // change touched, BEHIND the still-open drawer — closing it (or
        // the receipt's View key) lands on the result. Deterministic and
        // engine-driven; the model has no navigation primitives.
        if let destination = change.receipt.destinations.first {
            NotificationCenter.default.post(name: .plusplusOperatorShow, object: destination)
        }
    }

    private func indexOfMessage(_ id: UUID) -> Int? {
        messages.lastIndex { $0.id == id }
    }

    private func append(_ message: OperatorMessage) {
        messages.append(message)
        persist()
    }

    private func persist() {
        store.save(messages)
    }
}

extension OperatorController: OperatorToolServices {
    func post(_ message: OperatorMessage) {
        append(message)
    }

    func handle(_ outcome: ChangeEngine.ChangeOutcome) {
        switch outcome {
        case .staged(let preview):
            append(OperatorMessage(kind: .preview(.init(
                spec: preview.spec,
                headline: preview.headline,
                lines: preview.lines
            ))))
        case .applied(let change):
            postReceipt(change)
        case .invalid:
            // The digest alone steers the model; nothing to render.
            break
        }
    }
}
