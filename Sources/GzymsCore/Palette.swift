/// How well a palette query fits a row's text (title first, then its keywords, app, body); nil = it does not.
/// Every word of the query must fit one word of the text: as its start (best), inside it, or as letters in order
/// that begin with the same letter ("tst" fits "test"). A fit in the first word (the title) counts more, so a tab
/// beats a notification that only mentions it.
public func paletteScore(_ query: String, _ text: String) -> Int? {
    let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
    var score = 0
    for q in query.lowercased().split(separator: " ") {
        let fits = words.enumerated().compactMap { i, w -> Int? in
            let s = w.hasPrefix(q) ? 3 : w.contains(q) ? 2 : (w.first == q.first && isSubsequence(q, of: w)) ? 1 : 0
            return s == 0 ? nil : s + (i == 0 ? 2 : 0)
        }
        guard let best = fits.max() else { return nil }
        score += best
    }
    return score
}

private func isSubsequence(_ q: Substring, of w: Substring) -> Bool {
    var rest = w[...]
    for c in q {
        guard let i = rest.firstIndex(of: c) else { return false }
        rest = rest[rest.index(after: i)...]
    }
    return true
}

/// The rows that fit, best first; equal ones keep their order. An empty query keeps them all.
public func paletteRank<T>(_ query: String, _ items: [T], text: (T) -> String) -> [T] {
    guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
    return items.enumerated().compactMap { i, item in paletteScore(query, text(item)).map { (i, $0, item) } }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        .map(\.2)
}

/// "dnd 1h", "dnd 30", "dnd 45m", "dnd 1h30" → minutes of Do Not Disturb; nil = not that shape.
public func paletteDNDMinutes(_ query: String) -> Int? {
    let w = query.lowercased().split(separator: " ")
    guard w.count == 2, w[0] == "dnd" else { return nil }
    var s = w[1], total = 0
    if let h = s.firstIndex(of: "h") {
        guard let n = Int(s[..<h]) else { return nil }
        total = n * 60
        s = s[s.index(after: h)...]
    }
    if s.hasSuffix("m") { s = s.dropLast() }
    if !s.isEmpty {
        guard let n = Int(s) else { return nil }
        total += n
    }
    return total > 0 ? total : nil
}
