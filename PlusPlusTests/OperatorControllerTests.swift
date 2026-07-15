import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// The Operator conductor, driven by a scripted model: Foundation
/// Models does not exist on CI, so every turn/card/recycle behavior is
/// proven against the `OperatorModel` seam. The REAL model's dispatch
/// quality is on-device validation, deliberately outside CI.
@MainActor
@Suite("Operator controller")
struct OperatorControllerTests {
    // MARK: - Scripted model

    @MainActor
    final class ScriptedOperatorModel: OperatorModel {
        enum Step {
            case reply([String])
            case failure(OperatorModelError)
            /// Yields one chunk and never finishes — a live turn.
            case hang
        }

        var steps: [Step]
        var prompts: [String] = []
        var recycleCount = 0
        var prewarmed = false
        let isResponding = false
        var contextSize: Int

        init(steps: [Step] = [], contextSize: Int = 4096) {
            self.steps = steps
            self.contextSize = contextSize
        }

        func prewarm() { prewarmed = true }
        func recycle() { recycleCount += 1 }

        func send(_ prompt: String) -> AsyncThrowingStream<String, Error> {
            prompts.append(prompt)
            let step = steps.isEmpty ? Step.reply(["ok."]) : steps.removeFirst()
            return AsyncThrowingStream { continuation in
                switch step {
                case .reply(let chunks):
                    var cumulative = ""
                    for chunk in chunks {
                        cumulative += chunk
                        continuation.yield(cumulative)
                    }
                    continuation.finish()
                case .failure(let error):
                    continuation.finish(throwing: error)
                case .hang:
                    continuation.yield("thinking")
                }
            }
        }
    }

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self,
            Routine.self, ExerciseGroup.self, RoutineExercise.self,
            WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("operator-controller-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func tempThreadDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("operator-thread-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeController(
        context: ModelContext,
        model: ScriptedOperatorModel
    ) -> OperatorController {
        let controller = OperatorController(
            context: context,
            store: OperatorThreadStore(directory: tempThreadDirectory()),
            makeModel: { _ in model }
        )
        controller.availabilityProvider = { .ready }
        controller.refresh()
        return controller
    }

    private func waitForIdle(_ controller: OperatorController) async throws {
        for _ in 0..<300 {
            if controller.turnState == .idle { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("turn never returned to idle")
    }

    private func lastNotice(_ controller: OperatorController) -> String? {
        for message in controller.messages.reversed() {
            if case .notice(let text) = message.kind { return text }
        }
        return nil
    }

    // MARK: - Turns

    @Test("A turn appends user + reply and returns to idle")
    func basicTurn() async throws {
        let container = try makeContainer()
        let model = ScriptedOperatorModel(steps: [.reply(["Push Day is ", "scheduled mon/thu."])])
        let controller = makeController(context: ModelContext(container), model: model)

        controller.send("When is Push Day?")
        try await waitForIdle(controller)

        guard case .user(let userText) = controller.messages.first?.kind else {
            Issue.record("expected a user message first"); return
        }
        #expect(userText == "When is Push Day?")
        guard case .reply(let reply) = controller.messages.last?.kind else {
            Issue.record("expected a reply last"); return
        }
        #expect(reply == "Push Day is scheduled mon/thu.")
        #expect(controller.streamingText.isEmpty)

        // The prompt carried the context prefix, not just the text.
        #expect(model.prompts.count == 1)
        #expect(model.prompts[0].hasPrefix("["))
        #expect(model.prompts[0].hasSuffix("When is Push Day?"))
    }

    @Test("Sends while busy bounce with a notice, not a second turn")
    func turnSerialization() async throws {
        let container = try makeContainer()
        let model = ScriptedOperatorModel()
        let controller = makeController(context: ModelContext(container), model: model)

        controller.send("first")
        // turnState flips to .thinking synchronously in send, so the
        // second send bounces deterministically.
        controller.send("second")
        try await waitForIdle(controller)

        let userCount = controller.messages.filter {
            if case .user = $0.kind { return true }
            return false
        }.count
        #expect(userCount == 1)
        #expect(lastNotice(controller) == OperatorPersona.stillWorking)
        #expect(model.prompts.count == 1)
    }

    @Test("Guardrail and refusal map to their in-voice lines")
    func errorCopy() async throws {
        let container = try makeContainer()
        let model = ScriptedOperatorModel(steps: [
            .failure(.guardrail),
            .failure(.refusal),
            .failure(.rateLimited),
        ])
        let controller = makeController(context: ModelContext(container), model: model)

        controller.send("one")
        try await waitForIdle(controller)
        #expect(lastNotice(controller) == OperatorPersona.guardrailTripped)

        controller.send("two")
        try await waitForIdle(controller)
        #expect(lastNotice(controller) == OperatorPersona.modelRefused)

        controller.send("three")
        try await waitForIdle(controller)
        #expect(lastNotice(controller) == OperatorPersona.rateLimited)
    }

    @Test("Context overflow recycles once and retries the turn")
    func contextOverflowRetries() async throws {
        let container = try makeContainer()
        let model = ScriptedOperatorModel(steps: [
            .failure(.contextExceeded),
            .reply(["Fresh session answer."]),
        ])
        let controller = makeController(context: ModelContext(container), model: model)

        controller.send("long question")
        try await waitForIdle(controller)

        #expect(model.recycleCount == 1)
        guard case .reply(let reply) = controller.messages.last?.kind else {
            Issue.record("expected the retried reply"); return
        }
        #expect(reply == "Fresh session answer.")
    }

    @Test("Proactive recycle carries recent context in the next prompt")
    func proactiveRecycleCarryover() async throws {
        let container = try makeContainer()
        // A tiny window: the first exchange overflows the 70% threshold.
        let model = ScriptedOperatorModel(
            steps: [.reply([String(repeating: "long reply. ", count: 40)]), .reply(["ok."])],
            contextSize: 120
        )
        let controller = makeController(context: ModelContext(container), model: model)

        controller.send("first")
        try await waitForIdle(controller)
        controller.send("second")
        try await waitForIdle(controller)

        #expect(model.recycleCount == 1)
        #expect(model.prompts.count == 2)
        #expect(model.prompts[1].contains("[earlier:"))
    }

    // MARK: - Tools → cards

    @Test("propose_change stages a preview card; Apply lands a receipt")
    func previewApplyFlow() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Routine(name: "Probe Push", order: 0))
        try context.save()
        let controller = makeController(context: context, model: ScriptedOperatorModel())

        let tool = ProposeChangeTool(services: controller)
        let digest = try await tool.call(arguments: ChangeArgs(
            operation: .delete, entity: .routine,
            targets: ["Probe Push"], filter: nil, values: nil
        ))
        #expect(digest.hasPrefix("STAGED:"))

        guard case .preview(let payload) = controller.messages.last?.kind else {
            Issue.record("expected a preview card"); return
        }
        #expect(payload.state == .pending)
        #expect(payload.headline == "Deletes 1 routine")
        // Staging touched nothing.
        #expect(try context.fetch(FetchDescriptor<Routine>()).count == 1)

        let previewID = try #require(controller.messages.last?.id)
        controller.applyPreview(messageID: previewID)
        #expect(try context.fetch(FetchDescriptor<Routine>()).isEmpty)
        guard case .receipt(let receipt) = controller.messages.last?.kind else {
            Issue.record("expected a receipt after Apply"); return
        }
        #expect(receipt.undoable)

        // Undo brings it back and flips the card.
        let receiptID = try #require(controller.messages.last?.id)
        controller.undoReceipt(messageID: receiptID)
        #expect(try context.fetch(FetchDescriptor<Routine>()).count == 1)
        let undone = controller.messages.compactMap { message -> Bool? in
            if case .receipt(let payload) = message.kind { return payload.undone }
            return nil
        }.last
        #expect(undone == true)
    }

    @Test("An applyNow change lands a receipt straight from the tool")
    func immediateApplyFlow() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let controller = makeController(context: context, model: ScriptedOperatorModel())

        let tool = ProposeChangeTool(services: controller)
        let digest = try await tool.call(arguments: ChangeArgs(
            operation: .create, entity: .routine,
            targets: [], filter: nil,
            values: ValuesArgs(name: "Probe Legs", scheduleDays: ["mon", "thu"])
        ))
        #expect(digest.hasPrefix("APPLIED:"))
        guard case .receipt(let receipt) = controller.messages.last?.kind else {
            Issue.record("expected a receipt card"); return
        }
        #expect(receipt.summary == "Created Probe Legs.")
        #expect(receipt.undoable)
        let routine = try #require(try context.fetch(FetchDescriptor<Routine>()).first)
        #expect(routine.schedule == .weekdays([2, 5]))
    }

    @Test("A newer applied change supersedes the previous undo")
    func undoDepthOne() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let controller = makeController(context: context, model: ScriptedOperatorModel())
        let tool = ProposeChangeTool(services: controller)

        _ = try await tool.call(arguments: ChangeArgs(
            operation: .create, entity: .routine,
            targets: ["Probe A"], filter: nil, values: nil
        ))
        let firstReceiptID = try #require(controller.messages.last?.id)
        _ = try await tool.call(arguments: ChangeArgs(
            operation: .create, entity: .routine,
            targets: ["Probe B"], filter: nil, values: nil
        ))

        // The first receipt lost its undo; poking it does nothing.
        controller.undoReceipt(messageID: firstReceiptID)
        #expect(try context.fetch(FetchDescriptor<Routine>()).count == 2)
        let firstReceipt = controller.messages.compactMap { message -> OperatorMessage.ReceiptPayload? in
            guard message.id == firstReceiptID, case .receipt(let payload) = message.kind else { return nil }
            return payload
        }.first
        #expect(firstReceipt?.undoable == false)
    }

    @Test("Bad model strings come back INVALID without touching the engine")
    func argumentMappingFailures() async throws {
        let container = try makeContainer()
        let controller = makeController(context: ModelContext(container), model: ScriptedOperatorModel())
        let tool = ProposeChangeTool(services: controller)

        let badDay = try await tool.call(arguments: ChangeArgs(
            operation: .update, entity: .routine, targets: ["Anything"],
            filter: nil, values: ValuesArgs(scheduleDays: ["someday"])
        ))
        #expect(badDay == "INVALID: unknown weekday someday; use names like mon, thu")

        let badMode = try await tool.call(arguments: ChangeArgs(
            operation: .update, entity: .exercise, targets: ["Anything"],
            filter: nil, values: ValuesArgs(trackBy: "sideways")
        ))
        #expect(badMode.hasPrefix("INVALID: unknown trackBy"))
    }

    @Test("ask_user posts an options card; a tap becomes the next turn")
    func askUserFlow() async throws {
        let container = try makeContainer()
        let model = ScriptedOperatorModel(steps: [.reply(["Noted."])])
        let controller = makeController(context: ModelContext(container), model: model)
        let tool = AskUserTool(services: controller)

        let digest = try await tool.call(arguments: AskUserTool.Arguments(
            question: "Which press?",
            options: ["Bench Press", "Overhead Press"],
            allowMultiple: false
        ))
        #expect(digest.contains("Choices shown"))
        guard case .options(let payload) = controller.messages.last?.kind else {
            Issue.record("expected an options card"); return
        }
        #expect(payload.options == ["Bench Press", "Overhead Press"])

        let optionsID = try #require(controller.messages.last?.id)
        controller.chooseOptions(messageID: optionsID, selection: ["Bench Press"])
        try await waitForIdle(controller)

        // The selection was recorded AND became the next user message.
        let userTexts = controller.messages.compactMap { message -> String? in
            if case .user(let text) = message.kind { return text }
            return nil
        }
        #expect(userTexts.contains("Bench Press"))
        #expect(model.prompts.count == 1)
    }

    @Test("find_items and get_stats answer through the tools")
    func readTools() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Routine(name: "Probe Push", order: 0))
        try context.save()
        let controller = makeController(context: context, model: ScriptedOperatorModel())

        let find = FindItemsTool(services: controller)
        let findDigest = try await find.call(arguments: FindItemsTool.Arguments(
            kind: .routine, nameContains: nil, muscleGroup: nil, inLibraryOnly: nil, limit: nil
        ))
        #expect(findDigest.contains("Probe Push"))

        let stats = GetStatsTool(services: controller)
        let statsDigest = try await stats.call(arguments: GetStatsTool.Arguments(
            question: .workoutCount, exerciseName: nil, routineName: nil, days: nil
        ))
        #expect(statsDigest == "workouts in last 30 days: 0")
    }

    @Test("An options tap during a live turn keeps the card unanswered")
    func optionsTapWhileBusy() async throws {
        let container = try makeContainer()
        let model = ScriptedOperatorModel(steps: [.hang])
        let controller = makeController(context: ModelContext(container), model: model)

        let tool = AskUserTool(services: controller)
        _ = try await tool.call(arguments: AskUserTool.Arguments(
            question: "Which?", options: ["A", "B"], allowMultiple: false
        ))
        let optionsID = try #require(controller.messages.last?.id)

        controller.send("kick off the hanging turn")
        #expect(controller.turnState != .idle)

        controller.chooseOptions(messageID: optionsID, selection: ["A"])
        let payload = controller.messages.compactMap { message -> OperatorMessage.OptionsPayload? in
            guard message.id == optionsID, case .options(let value) = message.kind else { return nil }
            return value
        }.first
        // The answer was NOT eaten: the card stays live for a retry.
        #expect(payload?.selection == nil)
        #expect(lastNotice(controller) == OperatorPersona.stillWorking)
        controller.cancelTurn()
    }

    @Test("A bounced send reports rejection so callers keep the input")
    func sendRejectionContract() async throws {
        let container = try makeContainer()
        let model = ScriptedOperatorModel(steps: [.hang])
        let controller = makeController(context: ModelContext(container), model: model)

        #expect(controller.send("first") == true)
        #expect(controller.send("second") == false)
        controller.cancelTurn()
    }

    @Test("Persisted receipts lose their Undo on load; depth-1 undo is in-memory")
    func staleUndoDropsOnLoad() throws {
        let container = try makeContainer()
        let directory = tempThreadDirectory()
        OperatorThreadStore(directory: directory).save([
            OperatorMessage(kind: .receipt(.init(summary: "Created X.", destinations: [], undoable: true))),
        ])

        let controller = OperatorController(
            context: ModelContext(container),
            store: OperatorThreadStore(directory: directory),
            makeModel: { _ in ScriptedOperatorModel() }
        )
        guard case .receipt(let payload) = controller.messages.last?.kind else {
            Issue.record("expected the loaded receipt"); return
        }
        #expect(payload.undoable == false)
    }

    // MARK: - Thread persistence

    @Test("The thread survives a relaunch through the store")
    func threadPersistence() async throws {
        let container = try makeContainer()
        let directory = tempThreadDirectory()
        let store = OperatorThreadStore(directory: directory)

        let first = OperatorController(
            context: ModelContext(container),
            store: store,
            makeModel: { _ in ScriptedOperatorModel() }
        )
        first.availabilityProvider = { .ready }
        first.refresh()
        first.send("remember me")
        try await waitForIdle(first)
        let savedCount = first.messages.count
        #expect(savedCount >= 2)

        let second = OperatorController(
            context: ModelContext(container),
            store: OperatorThreadStore(directory: directory),
            makeModel: { _ in ScriptedOperatorModel() }
        )
        #expect(second.messages.count == savedCount)
    }
}

@Suite("Operator thread store")
struct OperatorThreadStoreTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("operator-store-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Round-trips messages including cards")
    func roundTrip() {
        let store = OperatorThreadStore(directory: tempDirectory())
        let messages = [
            OperatorMessage(kind: .user("hello")),
            OperatorMessage(kind: .reply("hi.")),
            OperatorMessage(kind: .receipt(.init(summary: "Created X.", destinations: [.exercisesTab], undoable: true))),
            OperatorMessage(kind: .options(.init(question: "Which?", options: ["a", "b"], allowMultiple: false))),
        ]
        store.save(messages)
        #expect(store.load() == messages)
    }

    @Test("Caps the stored thread at the policy limit")
    func capEnforcement() {
        let store = OperatorThreadStore(directory: tempDirectory())
        let messages = (0..<(OperatorThreadPolicy.storeCap + 30)).map {
            OperatorMessage(kind: .user("message \($0)"))
        }
        store.save(messages)
        let loaded = store.load()
        #expect(loaded.count == OperatorThreadPolicy.storeCap)
        #expect(loaded.last == messages.last)
    }

    @Test("A corrupt file reads as an empty thread")
    func corruptFile() throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("thread.json"))
        let store = OperatorThreadStore(directory: directory)
        #expect(store.load().isEmpty)
    }
}

@Suite("Operator chips")
struct OperatorChipsTests {
    @Test("Routine detail context yields routine-specific chips")
    func routineDetailChips() {
        let chips = OperatorChips.chips(tab: "routines", detail: "routines/Push Day", hasHistory: true)
        #expect(chips.count <= 3)
        #expect(chips.contains { $0.prompt.contains("Push Day") })
    }

    @Test("A fresh install teaches instead of querying empty history")
    func freshInstallChips() {
        let chips = OperatorChips.chips(tab: "today", detail: nil, hasHistory: false)
        #expect(chips.contains { $0.label == "What can you do?" })
        #expect(!chips.contains { $0.label == "Last 30 days" })
    }

    @Test("Deterministic for the same inputs")
    func determinism() {
        let a = OperatorChips.chips(tab: "exercises", detail: nil, hasHistory: true)
        let b = OperatorChips.chips(tab: "exercises", detail: nil, hasHistory: true)
        #expect(a == b)
    }
}
