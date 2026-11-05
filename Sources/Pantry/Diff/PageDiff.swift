// PageDiff.swift — what changed between two seals of the same page (Reseal & diff, Pro).
//
// It compares the text frozen at each Seal, never the live page or its DOM (non-negotiable 4;
// the plan's risk table: "diff extracted text, not DOM"). That text is stored as one run of
// words, so pages are lined up sentence by sentence, and a changed sentence is then compared
// word by word. Pure Swift, no model, nothing leaves the Mac.

import Foundation

public struct PageDiff: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case same, removed, added
    }

    /// A run of words that are all the same kind.
    public struct Span: Sendable, Equatable {
        public let text: String
        public let kind: Kind

        public init(_ text: String, _ kind: Kind) {
            self.text = text
            self.kind = kind
        }
    }

    /// One line of the side-by-side view: the older seal on the left, the newer on the right.
    /// A nil side has nothing there (the sentence was added, or removed).
    public struct Row: Sendable, Equatable, Identifiable {
        public let id: Int
        public let old: [Span]?
        public let new: [Span]?
        public let isChange: Bool
    }

    public let rows: [Row]

    /// Rows that differ between the two seals.
    public var changeCount: Int { rows.lazy.filter(\.isChange).count }
    public var isUnchanged: Bool { !rows.contains(where: \.isChange) }

    public init(old: String, new: String) {
        rows = PageDiff.align(PageDiff.sentences(old), PageDiff.sentences(new))
    }

    // MARK: Sentences

    /// A run without sentence punctuation is cut at a space after this many characters, so one
    /// long block (a list, a table flattened to text) doesn't become one giant row.
    static let maxSentence = 400

    /// The text, whitespace collapsed, cut into sentences: after `.`, `!` or `?` and a space,
    /// when the next character starts a sentence (a capital, a digit, an opening quote).
    static func sentences(_ text: String) -> [String] {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let s = Array(flat.unicodeScalars)
        var out: [String] = []
        var start = 0
        var i = 0

        func flush(_ end: Int) {
            guard end > start else { return }
            var view = String.UnicodeScalarView()
            view.append(contentsOf: s[start..<end])
            let piece = String(view).trimmingCharacters(in: .whitespaces)
            if !piece.isEmpty { out.append(piece) }
        }

        while i < s.count {
            let c = s[i]
            if c == "." || c == "!" || c == "?", i + 2 < s.count, s[i + 1] == " ", startsSentence(s[i + 2]) {
                flush(i + 1)
                start = i + 2
                i += 2
                continue
            }
            if c == " ", i - start >= maxSentence {
                flush(i)
                start = i + 1
            }
            i += 1
        }
        flush(s.count)
        return out
    }

    private static let openers = CharacterSet(charactersIn: "\"“‘'(«")

    private static func startsSentence(_ c: Unicode.Scalar) -> Bool {
        CharacterSet.uppercaseLetters.contains(c) || CharacterSet.decimalDigits.contains(c) || openers.contains(c)
    }

    // MARK: Lining up

    /// Sentences in both seals line up as unchanged rows. Between them, the removed and added
    /// sentences pair up in order: a pair is one changed row, compared word by word, and what
    /// is left over is a row with one side empty.
    static func align(_ a: [String], _ b: [String]) -> [Row] {
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in b.difference(from: a) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var rows: [Row] = []
        var i = 0
        var j = 0
        func add(_ old: [Span]?, _ new: [Span]?, change: Bool) {
            rows.append(Row(id: rows.count, old: old, new: new, isChange: change))
        }

        while i < a.count || j < b.count {
            if i < a.count, j < b.count, !removed.contains(i), !inserted.contains(j) {
                add([Span(a[i], .same)], [Span(b[j], .same)], change: false)
                i += 1
                j += 1
                continue
            }
            var gone: [String] = []
            var came: [String] = []
            while i < a.count, removed.contains(i) { gone.append(a[i]); i += 1 }
            while j < b.count, inserted.contains(j) { came.append(b[j]); j += 1 }
            if gone.isEmpty, came.isEmpty {
                // Only reachable if the difference and the arrays disagree; never loop on it.
                if i < a.count { add([Span(a[i], .removed)], nil, change: true); i += 1 }
                else if j < b.count { add(nil, [Span(b[j], .added)], change: true); j += 1 }
                continue
            }
            for k in 0..<max(gone.count, came.count) {
                if k < gone.count, k < came.count {
                    let (old, new) = words(gone[k], came[k])
                    add(old, new, change: true)
                } else if k < gone.count {
                    add([Span(gone[k], .removed)], nil, change: true)
                } else {
                    add(nil, [Span(came[k], .added)], change: true)
                }
            }
        }
        return rows
    }

    // MARK: Words

    /// Above this many word pairs, a changed sentence is shown as replaced whole.
    static let maxWordPairs = 4_000_000

    /// Two versions of a sentence, word by word: what the older one lost, what the newer gained.
    static func words(_ old: String, _ new: String) -> (old: [Span], new: [Span]) {
        let ow = old.split(separator: " ").map(String.init)
        let nw = new.split(separator: " ").map(String.init)
        guard ow.count * nw.count <= maxWordPairs else {
            return ([Span(old, .removed)], [Span(new, .added)])
        }
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in nw.difference(from: ow) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        let oldSpans = merge(ow.enumerated().map { ($0.element, removed.contains($0.offset) ? Kind.removed : .same) })
        let newSpans = merge(nw.enumerated().map { ($0.element, inserted.contains($0.offset) ? Kind.added : .same) })
        return (oldSpans, newSpans)
    }

    /// Neighboring words of the same kind, joined into one span.
    static func merge(_ words: [(String, Kind)]) -> [Span] {
        var spans: [Span] = []
        var text = ""
        var kind: Kind?
        for (word, k) in words {
            if k == kind {
                text += " " + word
            } else {
                if let kind { spans.append(Span(text, kind)) }
                text = word
                kind = k
            }
        }
        if let kind { spans.append(Span(text, kind)) }
        return spans
    }
}
