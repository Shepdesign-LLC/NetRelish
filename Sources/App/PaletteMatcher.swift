// PaletteMatcher.swift — how ⌘K decides what you meant. A query matches if its letters appear
// in order (a subsequence), so "ctp" finds "Capture this page". The score favors, in order:
// a match at the very start, matches at word starts, and runs of adjacent letters.
// Pure and synchronous — the whole thing is tested without a window.

import Foundation

enum PaletteMatcher {
    /// Nil when `name` doesn't match. Higher is better. An empty query matches everything at 0.
    static func score(_ name: String, query: String) -> Int? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !q.isEmpty else { return 0 }
        let n = Array(name.lowercased())
        guard !n.isEmpty else { return nil }

        var score = 0
        var qi = 0
        var previousMatch: Int?
        for (i, char) in n.enumerated() {
            guard qi < q.count, char == q[qi] else { continue }
            if i == 0 {
                score += 12                        // the name starts with what you typed
            } else if !n[i - 1].isLetter && !n[i - 1].isNumber {
                score += 8                         // a word start
            }
            if let previous = previousMatch, previous == i - 1 {
                score += 5                         // adjacent to the last hit
            }
            score += 1
            previousMatch = i
            qi += 1
        }
        guard qi == q.count else { return nil }
        // Shorter names win ties: "New Tab" over "New Tab in Another Jar".
        return score * 100 - n.count
    }
}
