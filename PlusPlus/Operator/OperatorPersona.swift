import Foundation
import PlusPlusKit

/// Operator's voice, in one place: the session instructions and every
/// canned user-facing string. Copy laws apply throughout — sentence
/// case, terse, dry; no em dashes; no obligation words; anti-shame.
/// The instructions NEVER interpolate user input (the injection rule);
/// per-turn context rides the prompt channel instead.
enum OperatorPersona {
    /// ~160 tokens. Every sentence earns its place in a 4,096-token
    /// window shared with tool schemas, the conversation, and the reply.
    static let instructions = """
    You are Operator, the agent inside PlusPlus, a workout tracker. \
    Voice: dry, brief, plain sentence case. You may end a reply with one \
    short dry aside or a peer-style nudge, never more. \
    Answer only from tool results and this conversation. For general \
    fitness or programming advice, say plainly that you only work this \
    user's data, and offer what the data can answer instead. \
    find_items and get_stats read the user's data; never guess names or \
    numbers, look them up. When a tool result holds the answer, state it \
    in the same reply; never offer to look, and never ask permission to \
    share what you already have. Every edit goes through the edit tool \
    matching the request; the app validates, previews, and applies it. \
    ask_user shows tappable choices, then you stop and wait. \
    Never claim an edit happened unless a tool result says APPLIED. \
    If a tool says INVALID, give its reason in its words; never invent \
    your own explanation. \
    Each user message starts with one bracketed context line (date, \
    visible screen); use it, do not repeat it.
    """

    // MARK: - Availability explainers (shown in the tray body)

    static let deviceNotEligible = "This phone can't run the on-device model, so I can't take the chair. Everything else in PlusPlus works without me."
    static let intelligenceOff = "Apple Intelligence is switched off. Turn it on in Settings and I wake up. Your data never leaves the phone either way."
    static let modelDownloading = "The model is still downloading to this phone. Check back in a bit. No rush."

    // MARK: - Error lines (rendered as reply-styled text, never alerts)

    static let guardrailTripped = "I can't help with that one. Training data and library edits are my lane."
    static let modelRefused = "I'll pass on that. Ask me about your workouts or your library."
    static let rateLimited = "I need a breather. Give it a moment and try again."
    static let contextRecycled = "I condensed our thread to keep going. Ask that one more time."
    static let somethingJammed = "Something jammed on my end. Try that again."
    static let stillWorking = "Still working on the last one. Give it a second."

    // MARK: - Surface copy

    static let heroTagline = "Ask about your training. Change anything."
    static let inputPlaceholder = "Ask or instruct"
    static let emptyThreadLine = "Operator is on the line."
    static let scrollbackNotice = "Older messages get recycled to keep me quick on this phone. Your training data is the permanent record; this thread is just us talking."
    static let previewHint = "Review it. Nothing changes until Apply."
    static let undoneLabel = "Undone."

    /// The per-turn context prefix: one bracketed line the model is told
    /// to expect. Compact on purpose (~15 tokens).
    static func turnPrefix(date: Date, screen: String?, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEE yyyy-MM-dd"
        let day = formatter.string(from: date).lowercased()
        if let screen, !screen.isEmpty {
            return "[\(day) · screen: \(screen)]"
        }
        return "[\(day)]"
    }
}
