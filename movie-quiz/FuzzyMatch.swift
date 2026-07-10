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
    /// punctuation into spaces, canonicalize Roman-numeral tokens to Arabic
    /// digits, and collapse whitespace.
    /// "Jóhn  Malkóvich!" -> "john malkovich"
    /// "Mission: Impossible III" -> "mission impossible 3"
    ///
    /// Roman→Arabic matters because TMDB titles sequels in Roman ("Mission:
    /// Impossible III") while players type Arabic ("mission impossible 3").
    /// Character-level edit distance treats "3" as *closer* to "ii" (2 edits)
    /// than to "iii" (3 edits), so raw matching picks the wrong sequel.
    /// Folding both sides to a digit makes the right sequel an exact match, and
    /// because it is applied consistently, single-letter cases that are not
    /// sequels ("Malcolm X", "X-Men", "I Am Legend") still match themselves.
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
            .map { token -> String in
                if let value = romanToArabic(String(token)) { return String(value) }
                return String(token)
            }
            .joined(separator: " ")
    }

    /// Value of a *canonical* lowercase Roman-numeral token ("iii" -> 3), or
    /// `nil` if the token is not a well-formed Roman numeral. Validated by
    /// round-trip (convert back and compare) so malformed strings like "iiii"
    /// or "vv" — and ordinary words — are left untouched.
    private static func romanToArabic(_ token: String) -> Int? {
        let values: [Character: Int] = ["i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000]
        guard !token.isEmpty, token.count <= 15 else { return nil }
        var total = 0, prev = 0
        for ch in token.reversed() {
            guard let v = values[ch] else { return nil }
            if v < prev { total -= v } else { total += v; prev = v }
        }
        guard total > 0, arabicToRoman(total) == token else { return nil }
        return total
    }

    /// Canonical lowercase Roman numeral for `n` (1..<4000), used to validate
    /// `romanToArabic`. Empty string outside the representable range.
    private static func arabicToRoman(_ n: Int) -> String {
        guard n > 0, n < 4000 else { return "" }
        let table: [(Int, String)] = [
            (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"),
            (100, "c"), (90, "xc"), (50, "l"), (40, "xl"),
            (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
        ]
        var n = n, out = ""
        for (value, symbol) in table {
            while n >= value { out += symbol; n -= value }
        }
        return out
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

        // Track the raw (pre-boost) similarity alongside the boosted score so
        // that when two candidates tie on the boosted floor we can break the tie
        // on the closer literal match. Without this, "school of rock" boosts both
        // "The School of Rock" and "Making of School of Rock" to 0.9, and the
        // winner is decided by candidate order — so a "making of" featurette
        // listed first beats the real film.
        var best: (item: T, score: Double, base: Double)?

        for candidate in candidates {
            let name = normalize(nameOf(candidate))
            guard !name.isEmpty else { continue }

            let base = similarity(name, query)
            var score = base

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

            // Prefer a strictly higher boosted score; on an exact tie (both hit
            // the same boost floor) prefer the higher raw similarity — the title
            // with fewer extra words is the one the player meant.
            if best == nil || score > best!.score
                || (score == best!.score && base > best!.base) {
                best = (candidate, score, base)
            }
        }

        if let best, best.score >= threshold {
            return Result(item: best.item, score: best.score)
        }
        return nil
    }
}
