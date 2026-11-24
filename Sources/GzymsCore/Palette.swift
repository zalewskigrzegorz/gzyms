/// How well a palette query fits a row: its title, then its keywords (app, body); nil = it does not.
/// Every word of the query must fit one word: as its start (best), inside it, or as letters in order that begin with the
/// same letter ("tst" fits "test"). A fit in the title beats any fit only in the keywords (Greg, 2026-11-24: "battery"
/// puts "Stop on battery under" above the General tab, which has it only as a keyword). In the title the first word
/// counts more, so a tab beats a notification that only mentions it.
public func paletteScore(_ query: String, _ title: String, words: String = "") -> Int? {
    func split(_ s: String) -> [Substring] { s.lowercased().split { !$0.isLetter && !$0.isNumber } }
    let t = split(title), w = split(words)
    var score = 0
    for q in query.lowercased().split(separator: " ") {
        // Title fits sit above the best keyword fit (4): +3, and +2 more in the first word.
        let inTitle = t.enumerated().compactMap { i, word in wordFit(q, word).map { $0 + 3 + (i == 0 ? 2 : 0) } }
        guard let best = (inTitle + w.compactMap { wordFit(q, $0) }).max() else { return nil }
        score += best
    }
    return score
}

/// 4 = the word starts with it, 2 = inside it, 1 = its letters in order from the first one, nil = no fit.
private func wordFit(_ q: Substring, _ w: Substring) -> Int? {
    w.hasPrefix(q) ? 4 : w.contains(q) ? 2 : (w.first == q.first && isSubsequence(q, of: w)) ? 1 : nil
}

private func isSubsequence(_ q: Substring, of w: Substring) -> Bool {
    var rest = w[...]
    for c in q {
        guard let i = rest.firstIndex(of: c) else { return false }
        rest = rest[rest.index(after: i)...]
    }
    return true
}

/// The rows that fit, best first. On an equal score the lower `tier` goes first (Settings and actions before plugin
/// rows), then the order they came in. An empty query keeps them all. `text` is the title, `words` the keywords.
public func paletteRank<T>(_ query: String, _ items: [T], tier: (T) -> Int = { _ in 0 }, words: (T) -> String = { _ in "" },
                           text: (T) -> String) -> [T] {
    guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
    typealias Fit = (order: Int, score: Int, tier: Int, item: T)
    let fits: [Fit] = items.enumerated().compactMap { i, item in paletteScore(query, text(item), words: words(item)).map { (i, $0, tier(item), item) } }
    return fits.sorted { a, b in
        if a.score != b.score { return a.score > b.score }
        if a.tier != b.tier { return a.tier < b.tier }
        return a.order < b.order
    }.map(\.item)
}

/// "dnd 1h", "caffeine 30", "dnd 45m", "dnd 1h30" → minutes after that word; nil = not that shape.
public func paletteMinutes(_ query: String, after word: String) -> Int? {
    let w = query.lowercased().split(separator: " ")
    guard w.count == 2, w[0] == word else { return nil }
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

/// 90 → "1 h 30 min", 120 → "2 h", 45 → "45 min".
public func paletteSpan(_ minutes: Int) -> String {
    minutes % 60 == 0 ? "\(minutes / 60) h" : minutes > 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
}

/// When a meeting starts, in words for its palette row: "now", "in 25 min", "in 2 h", "in 1 h 30 min", "10 min ago".
public func paletteWhen(start: Double, now: Double) -> String {
    let d = Int(((start - now) / 60).rounded())
    return d == 0 ? "now" : d > 0 ? "in \(paletteSpan(d))" : "\(paletteSpan(-d)) ago"
}

/// A row of a plugin's popup the palette can run: one with an id that is not a separator or a block
/// (headline, chart, stats). The agents pill is left out, its agents get their own rows.
public struct PalettePluginRow: Equatable, Sendable {
    public var plugin: String, id: String, title: String, words: String
    public var alt: RowAlt?
}

public func palettePluginRows(_ pills: [PluginPill], skip: String) -> [PalettePluginRow] {
    var seen = Set<String>()
    return pills.filter { $0.plugin != skip }.flatMap { p in
        (p.item.menu ?? []).compactMap { r -> PalettePluginRow? in
            guard let id = r.id, !r.separator, r.headline == nil, r.chart == nil, r.stats == nil, !r.text.isEmpty,
                  seen.insert("\(p.plugin)/\(id)").inserted else { return nil }
            return PalettePluginRow(plugin: p.plugin, id: id, title: r.text,
                                    words: [r.tag, r.detail, p.item.text].compactMap { $0 }.joined(separator: " "), alt: r.alt)
        }
    }
}
