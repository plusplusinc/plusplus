import Foundation

/// Sizing policy for the Operator thread: what the STORE keeps, what the
/// UI shows, and when the model-side session should be recycled. The
/// visible thread and the model transcript are deliberately independent —
/// the store is the user's record, the session is a scratch context that
/// gets rebuilt under a tiny on-device window (4,096 tokens on the
/// 26-cycle model; always read `contextSize` at runtime).
public enum OperatorThreadPolicy {
    /// Messages the on-device store keeps (oldest trimmed on save).
    public static let storeCap = 120
    /// Messages the transcript UI renders; scrolling past the end shows
    /// the honest limit notice instead of more history.
    public static let visibleCap = 60
    /// Recycle the session once estimated usage crosses this share of
    /// the context window — before the window overflows mid-turn.
    public static let recycleFraction = 0.7

    /// The ~3 characters/token English estimate from the Foundation
    /// Models sizing guidance. Deliberately conservative (rounds up).
    public static func estimatedTokens(forCharacters characters: Int) -> Int {
        guard characters > 0 else { return 0 }
        return (characters + 2) / 3
    }

    public static func shouldRecycle(usedTokens: Int, contextSize: Int) -> Bool {
        guard contextSize > 0 else { return true }
        return Double(usedTokens) >= Double(contextSize) * recycleFraction
    }

    /// Which trailing window of transcript entries survives a recycle:
    /// the largest suffix whose estimated tokens fit `budgetTokens`.
    /// Always keeps at least the final entry (the turn being answered),
    /// even if it alone exceeds the budget.
    public static func trimmedRange(entryCharacterCounts: [Int], budgetTokens: Int) -> Range<Int> {
        guard !entryCharacterCounts.isEmpty else { return 0..<0 }
        var start = entryCharacterCounts.count - 1
        var tokens = estimatedTokens(forCharacters: entryCharacterCounts[start])
        while start > 0 {
            let next = estimatedTokens(forCharacters: entryCharacterCounts[start - 1])
            if tokens + next > budgetTokens { break }
            tokens += next
            start -= 1
        }
        return start..<entryCharacterCounts.count
    }
}
