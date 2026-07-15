import Foundation
import FoundationModels

/// What the controller needs from a language model, small enough to
/// fake: Foundation Models does not exist on Linux CI and is absent on
/// CI simulators, so every controller behavior is tested against a
/// scripted implementation of this protocol; `FoundationOperatorModel`
/// is the only type in the app that talks to a real session.
@MainActor
protocol OperatorModel: AnyObject {
    var isResponding: Bool { get }
    /// The model's total window (input + output). Read at runtime,
    /// never hard-coded (4,096 on the 26-cycle on-device model).
    var contextSize: Int { get }
    /// Warm the session so the first turn skips 1–2 s of setup.
    func prewarm()
    /// One turn: streams the CUMULATIVE reply text. Tool calls run as
    /// side effects mid-stream (the tools post their own cards).
    /// Throws `OperatorModelError`.
    func send(_ prompt: String) -> AsyncThrowingStream<String, Error>
    /// Replace the session with a fresh one (same tools, same
    /// instructions, empty transcript). The controller carries context
    /// forward in the next PROMPT, not in instructions — user-derived
    /// text stays out of the instruction channel.
    func recycle()
}

/// The controller-facing error vocabulary; the Foundation Models error
/// surface maps into it so persona copy and tests never touch the
/// framework enum (whose spelling changes across OS cycles).
enum OperatorModelError: Error, Equatable {
    case contextExceeded
    case guardrail
    case refusal
    case rateLimited
    case busy
    case assetsUnavailable
    case other
}

/// The real thing: wraps one `LanguageModelSession` with the Operator
/// tools and persona instructions.
@MainActor
final class FoundationOperatorModel: OperatorModel {
    private let tools: [any Tool]
    private let instructions: String
    private var session: LanguageModelSession

    init(tools: [any Tool], instructions: String) {
        self.tools = tools
        self.instructions = instructions
        session = LanguageModelSession(tools: tools, instructions: instructions)
    }

    var isResponding: Bool { session.isResponding }

    /// @backDeployed(before: iOS 26.4): runs on 26.0 devices, but the
    /// DECLARATION needs the Xcode 26.4+ SDK to compile (CI's "newest
    /// Xcode 26" qualifies).
    var contextSize: Int { SystemLanguageModel.default.contextSize }

    func prewarm() {
        session.prewarm()
    }

    func send(_ prompt: String) -> AsyncThrowingStream<String, Error> {
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    let stream = session.streamResponse(to: prompt)
                    for try await snapshot in stream {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func recycle() {
        session = LanguageModelSession(tools: tools, instructions: instructions)
    }

    /// The 26-cycle error surface (`LanguageModelSession.GenerationError`)
    /// mapped to the app vocabulary. `@unknown`-safe: anything new reads
    /// as `.other` and gets the generic in-voice line.
    static func map(_ error: any Error) -> OperatorModelError {
        guard let generation = error as? LanguageModelSession.GenerationError else {
            return .other
        }
        switch generation {
        case .exceededContextWindowSize: return .contextExceeded
        case .guardrailViolation: return .guardrail
        case .refusal: return .refusal
        case .rateLimited: return .rateLimited
        case .concurrentRequests: return .busy
        case .assetsUnavailable: return .assetsUnavailable
        default: return .other
        }
    }
}
