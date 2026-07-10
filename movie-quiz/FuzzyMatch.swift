//
//  FuzzyMatch.swift
//  movie-quiz
//
//  Spelling-tolerant matching of free text against a *bounded* candidate set
//  (the cast of the current movie, or the filmography of the current actor).
//  Because the candidate set is small and known, we can be strict and still
//  forgiving of spelling — no global search, no autocomplete spoilers.
//

import Foundation

enum FuzzyMatch {

    /// Normalize a string for comparison: lowercase, strip diacritics, elide
    /// apostrophes (so possessives/contractions collapse to one token —
    /// "Ocean's" -> "oceans", "O'Brien" -> "obrien"), turn remaining
    /// punctuation into spaces, and collapse whitespace.
    /// "Jóhn  Malkóvich!" -> "john malkovich"
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let elided = folded
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")   // ’ right single quote
            .replacingOccurrences(of: "\u{2018}", with: "")   // ‘ left single quote
            .replacingOccurrences(of: "`", with: "")
        let cleaned = elided.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                return Character(scalar)
            }
            return " "
        }
        return String(cleaned)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Levenshtein edit distance between two already-normalized strings.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,        // deletion
                    curr[j - 1] + 1,    // insertion
                    prev[j - 1] + cost  // substitution
                )
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }

    /// Similarity in [0, 1] where 1 is identical.
    static func similarity(_ a: String, _ b: String) -> Double {
        let na = normalize(a), nb = normalize(b)
        if na == nb { return 1 }
        let maxLen = max(na.count, nb.count)
        guard maxLen > 0 else { return 0 }
        let dist = editDistance(na, nb)
        return 1 - Double(dist) / Double(maxLen)
    }

    /// Result of matching input against a candidate set.
    struct Result<T> {
        let item: T
        let score: Double
    }

    /// Find the best candidate whose name matches `input`, if any clears the
    /// threshold. `nameOf` extracts the comparable name from a candidate.
    ///
    /// A generous default threshold (0.72) tolerates a few typos on a small,
    /// known set while keeping false positives negligible. Exact substring or
    /// last-name matches are also accepted, so "malkovich" matches
    /// "John Malkovich".
    static func bestMatch<T>(
        for input: String,
        in candidates: [T],
        nameOf: (T) -> String,
        threshold: Double = 0.72
    ) -> Result<T>? {
        let query = normalize(input)
        guard !query.isEmpty else { return nil }

        var best: Result<T>?

        for candidate in candidates {
            let name = normalize(nameOf(candidate))
            guard !name.isEmpty else { continue }

            var score = similarity(name, query)

            let nameWords = name.split(separator: " ").map(String.init)
            let nameWordSet = Set(nameWords)
            let queryWords = query.split(separator: " ").map(String.init)

            // A "content word" is one long enough to carry recall (a surname or
            // a real title keyword) rather than a stopword like "the"/"of"/"a".
            let hasContentWord = queryWords.contains { $0.count >= 4 }

            // Boost 1: every typed word is a whole word in the name AND at least
            // one is a content word. Matches "clooney" -> "george clooney" and
            // "the dark" -> "the dark knight", but not bare "the" or "a".
            if hasContentWord, !queryWords.isEmpty,
               queryWords.allSatisfy({ nameWordSet.contains($0) }) {
                score = max(score, 0.9)
            }

            // Boost 2: a single long-enough query word is a prefix of some word
            // in the name, tolerating truncation ("malkov" -> "malkovich").
            // Guarded by length so a one/two-letter fragment can't slip through.
            if queryWords.count == 1, query.count >= 4,
               nameWords.contains(where: { $0.hasPrefix(query) }) {
                score = max(score, 0.82)
            }

            // Boost 3: the typed text fully contains the candidate name (extra
            // words wrapped around a correct answer, e.g. "the movie inception").
            if name.count >= 4, query.contains(name) {
                score = max(score, 0.85)
            }

            if best == nil || score > best!.score {
                best = Result(item: candidate, score: score)
            }
        }

        if let best, best.score >= threshold { return best }
        return nil
    }
}
