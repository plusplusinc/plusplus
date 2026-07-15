import Foundation

/// The one forgiving text-match rule for every search surface (exercise
/// and equipment catalogs, the routine catalog, Operator's find_items).
/// A query matches when EVERY query word finds a home somewhere in the
/// candidate — order-free, case- and diacritic-insensitive, tolerant of
/// small typos and missing spaces — and the score ranks how honest that
/// home is (exact > prefix > substring > initials > typo), so tolerant
/// matches never outrank literal ones.
///
/// Deliberately NOT used for Operator's write-target resolution: the
/// ChangeEngine keeps its exact-then-unique-substring rule (it asks,
/// it never guesses). Discovery is forgiving; applying changes is not.
public enum FuzzySearch {
    /// Match quality in 0...1, or nil when the query doesn't match.
    /// A query with no letters or digits (empty, whitespace, "-") is
    /// nil — callers decide what an absent query means.
    public static func score(query: String, candidate: String) -> Double? {
        let queryTokens = tokens(query)
        guard !queryTokens.isEmpty else { return nil }
        let candidateTokens = tokens(candidate)
        guard !candidateTokens.isEmpty else { return nil }
        // "pushup" must reach "Push-Up", "benchpress" reach "Bench
        // Press": the glued form is one more haystack token, at a small
        // demotion so the properly-spaced candidate still ranks first.
        let glued = candidateTokens.count > 1 ? candidateTokens.joined() : nil

        var total = 0.0
        for queryToken in queryTokens {
            var best = 0.0
            for candidateToken in candidateTokens {
                best = max(best, tokenScore(queryToken, against: candidateToken))
            }
            if let glued {
                best = max(best, tokenScore(queryToken, against: glued) - 0.05)
            }
            // "rd" and "rdl" find "Romanian Deadlift" — worth less than
            // a substring hit, more than a typo rescue.
            if best < 0.55, isAbbreviation(queryToken, of: candidateTokens) {
                best = 0.55
            }
            guard best > 0 else { return nil }
            total += best
        }
        // Weight in how much of the candidate the query spoke for, so
        // "Press" outranks "Leg Press" for the query "press" (and a
        // long haystack never outranks the name it was padding out).
        let coverage = min(1, Double(queryTokens.count) / Double(candidateTokens.count))
        return (total / Double(queryTokens.count)) * 0.9 + 0.1 * coverage
    }

    public static func matches(query: String, candidate: String) -> Bool {
        score(query: query, candidate: candidate) != nil
    }

    /// Matching items, best first; equal scores keep their incoming
    /// order (so an alphabetical input stays alphabetical within a
    /// tier). A query with no letters or digits returns the items
    /// unchanged — no query means nothing to narrow by.
    public static func ranked<T>(_ items: [T], query: String, key: (T) -> String) -> [T] {
        guard !tokens(query).isEmpty else { return items }
        return items.enumerated()
            .compactMap { index, item in
                score(query: query, candidate: key(item)).map { (item: item, score: $0, index: index) }
            }
            .sorted { a, b in a.score != b.score ? a.score > b.score : a.index < b.index }
            .map(\.item)
    }

    /// The single best-matching candidate, for resolving a spoken/typed
    /// name to its canonical form. Ties go to the earliest candidate.
    public static func bestMatch(query: String, in candidates: [String]) -> String? {
        ranked(candidates, query: query, key: { $0 }).first
    }

    // MARK: - Internals

    /// Fold and split: lowercase, diacritics stripped, anything that
    /// isn't a letter or digit is a separator ("Push-Up" → push, up).
    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// The tier ladder for one folded query word against one folded
    /// candidate word. Length ratios grade within a tier so "curls"
    /// outranks "curling" for the query "curl".
    private static func tokenScore(_ query: String, against candidate: String) -> Double {
        if query == candidate { return 1.0 }
        let ratio = Double(query.count) / Double(candidate.count)
        if candidate.hasPrefix(query) { return 0.7 + 0.2 * ratio }
        // The over-typed direction: "presses" still finds "Press". The
        // 3-char floor keeps single-letter candidate words ("T Bar")
        // from swallowing every query word that shares the letter, and
        // the 2-char leftover cap keeps it to inflections — without it
        // "deadlft" calls "Dead Bug" a better home than "Deadlift".
        if candidate.count >= 3, query.count - candidate.count <= 2, query.hasPrefix(candidate) {
            return 0.55 + 0.15 / ratio
        }
        // Mid-word substrings need 3+ chars — one or two letters occur
        // inside almost everything and would just be noise.
        if query.count >= 3, candidate.contains(query) { return 0.5 + 0.2 * ratio }
        let budget = typoBudget(query.count)
        if budget > 0 {
            let edits = prefixEditDistance(query, candidate, cap: budget)
            if edits <= budget { return 0.45 - 0.1 * Double(edits - 1) }
        }
        return 0
    }

    /// How many edits a typo may spend: none on short words (at four
    /// letters, one edit made "carl" match the entire Cable family),
    /// one on everyday words, two on long ones.
    private static func typoBudget(_ length: Int) -> Int {
        switch length {
        case ..<5: 0
        case 5...8: 1
        default: 2
        }
    }

    /// Word-anchored subsequence, the abbreviation shape: each query
    /// letter either enters the next candidate word at its FIRST letter
    /// or continues inside the current word in order ("rdl" walks
    /// Romanian, then Deadlift's d…l; "ohp" reaches Overhead Press).
    /// Must consume the whole query across at least two words — inside
    /// one word it's just a prefix, and the prefix tier already prices
    /// that. Capped at four letters: past that the user is spelling
    /// words, and a misspelled word ("benhc") must fall to the typo
    /// tier, not sneak up here and outrank its honest match.
    private static func isAbbreviation(_ query: String, of candidateTokens: [String]) -> Bool {
        guard (2...4).contains(query.count), candidateTokens.count >= 2 else { return false }
        var remaining = Substring(query)
        var wordsEntered = 0
        for token in candidateTokens {
            guard let first = remaining.first, first == token.first else { continue }
            wordsEntered += 1
            remaining = remaining.dropFirst()
            var inWord = Substring(token).dropFirst()
            while let next = remaining.first, let found = inWord.firstIndex(of: next) {
                remaining = remaining.dropFirst()
                inWord = inWord[inWord.index(after: found)...]
            }
            if remaining.isEmpty { break }
        }
        return remaining.isEmpty && wordsEntered >= 2
    }

    /// Damerau-Levenshtein (adjacent transpositions count as one edit)
    /// from `query` to the BEST-matching prefix of `candidate` — trailing
    /// candidate letters are free, so "benhc" is one edit from "bench"
    /// AND from "benchpress". Returns cap + 1 as soon as the distance
    /// provably exceeds `cap`.
    private static func prefixEditDistance(_ query: String, _ candidate: String, cap: Int) -> Int {
        let q = Array(query), c = Array(candidate)
        guard !q.isEmpty else { return c.isEmpty ? 0 : cap + 1 }
        guard !c.isEmpty else { return min(q.count, cap + 1) }
        // dp[j] = distance between q[0..<i] and c[0..<j] for the current row i.
        var previous = [Int](0...c.count)
        var current = [Int](repeating: 0, count: c.count + 1)
        var beforePrevious = previous
        for i in 1...q.count {
            current[0] = i
            for j in 1...c.count {
                let substitution = previous[j - 1] + (q[i - 1] == c[j - 1] ? 0 : 1)
                var best = min(previous[j] + 1, current[j - 1] + 1, substitution)
                if i > 1, j > 1, q[i - 1] == c[j - 2], q[i - 2] == c[j - 1] {
                    best = min(best, beforePrevious[j - 2] + 1)
                }
                current[j] = best
            }
            // The whole row can only grow by 1 per step; once even its
            // minimum exceeds the cap no suffix can recover.
            if current.min() ?? 0 > cap { return cap + 1 }
            (beforePrevious, previous, current) = (previous, current, previous)
        }
        // min over the final row = query against every prefix of candidate.
        return min(previous.min() ?? cap + 1, cap + 1)
    }
}
