import Foundation

/// A value the settings panel writes into `config.toml`.
public enum TOMLValue: Equatable, Sendable {
    case bool(Bool), int(Int), double(Double), string(String), ints([Int]), strings([String])

    var literal: String {
        switch self {
        case .bool(let b): String(b)
        case .int(let i): String(i)
        case .double(let d): String(d)
        case .string(let s): tomlString(s)
        case .ints(let a): "[" + a.map(String.init).joined(separator: ", ") + "]"
        case .strings(let a): "[" + a.map(tomlString).joined(separator: ", ") + "]"
        }
    }
}

/// Where a key lives. `.table([])` is the top level; `.row` picks one `[[array]]` entry by a key in it
/// (`[[workspaces.style]]` with `number = 3`).
public enum ConfigTable: Equatable, Sendable {
    case table([String])
    case row(String, key: String, value: TOMLValue)
}

/// Sets (or with `nil` removes) one key and leaves every other byte alone: comments, blank lines, order,
/// keys Gzyms does not know. A line scan, not a TOML rewrite, so the user's file stays theirs.
/// shortcut: a key whose current value spans several lines is not edited (the input comes back unchanged),
/// upgrade when a setting needs a multi-line array.
public func setting(_ key: String, to value: TOMLValue?, in table: ConfigTable, toml: String?) -> String {
    let toml = toml ?? ""
    var lines = toml.components(separatedBy: "\n")
    let headers = lines.indices.compactMap { i in tomlHeader(lines[i]).map { (i, $0) } }
    let firstHeader = headers.first?.0 ?? lines.count
    let newLine = value.map { "\(tomlKey(key)) = \($0.literal)" }

    // The line range of the target table (after its header), if it exists.
    var range: Range<Int>?
    switch table {
    case .table([]):
        range = 0..<firstHeader
    case .table(let path):
        if let h = headers.firstIndex(where: { !$0.1.array && $0.1.path == path }) {
            range = (headers[h].0 + 1)..<(h + 1 < headers.count ? headers[h + 1].0 : lines.count)
        }
    case .row(let array, let matchKey, let matchValue):
        let path = splitDotted(array)
        for (h, header) in headers.enumerated() where header.1.array && header.1.path == path {
            let r = (header.0 + 1)..<(h + 1 < headers.count ? headers[h + 1].0 : lines.count)
            if r.contains(where: { keyLine(lines[$0])?.key == [matchKey] && keyLine(lines[$0])?.value == matchValue.literal }) {
                range = r
                break
            }
        }
    }

    guard let range else {
        guard let newLine else { return toml }
        var out = toml
        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
        if !out.isEmpty && !out.hasSuffix("\n\n") { out += "\n" }
        switch table {
        case .table(let path): out += "[\(path.map(tomlKey).joined(separator: "."))]\n"
        case .row(let array, let k, let v): out += "[[\(splitDotted(array).map(tomlKey).joined(separator: "."))]]\n\(tomlKey(k)) = \(v.literal)\n"
        }
        return out + newLine + "\n"
    }

    if let i = range.first(where: { keyLine(lines[$0])?.key == [key] }), let found = keyLine(lines[i]) {
        guard !found.multiLine else { return toml }
        if let value { lines[i] = found.prefix + value.literal + found.comment } else { lines.remove(at: i) }
        return lines.joined(separator: "\n")
    }
    guard let newLine else { return toml }
    let last = range.last(where: { keyLine(lines[$0]) != nil })
    if case .table([]) = table, last == nil {
        // A key under no header at all; at the very top, so it never lands inside a table.
        return toml.isEmpty ? newLine + "\n" : newLine + "\n" + toml
    }
    lines.insert(newLine, at: (last ?? range.lowerBound - 1) + 1)
    return lines.joined(separator: "\n")
}

// MARK: - Line scanning

/// `[a.b]` or `[[a.b]]`, quoted parts unquoted.
private func tomlHeader(_ line: String) -> (array: Bool, path: [String])? {
    let t = line.trimmingCharacters(in: .whitespaces)
    guard t.hasPrefix("[") else { return nil }
    let array = t.hasPrefix("[[")
    let body = t.dropFirst(array ? 2 : 1)
    guard let close = firstUnquoted("]", in: body) else { return nil }
    return (array, splitDotted(String(body[..<close])))
}

/// `key = value  # comment`: the parsed key, the text up to the value, the value without its comment, and the comment
/// with the spaces before it.
private func keyLine(_ line: String) -> (key: [String], prefix: String, value: String, comment: String, multiLine: Bool)? {
    let t = line.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty, !t.hasPrefix("#"), !t.hasPrefix("["), let eq = firstUnquoted("=", in: line[...]) else { return nil }
    let afterEq = line[line.index(after: eq)...]
    let valueStart = afterEq.firstIndex { $0 != " " && $0 != "\t" } ?? line.endIndex
    let rest = line[valueStart...]
    let hash = firstUnquoted("#", in: rest) ?? rest.endIndex
    var valueEnd = hash
    while valueEnd > rest.startIndex, [" ", "\t"].contains(rest[rest.index(before: valueEnd)]) { valueEnd = rest.index(before: valueEnd) }
    let value = String(rest[..<valueEnd])
    let opens = value.filter { $0 == "[" }.count, closes = value.filter { $0 == "]" }.count
    let multiLine = value.hasPrefix("\"\"\"") || value.hasPrefix("'''") || (value.hasPrefix("[") && opens > closes)
    return (splitDotted(String(line[..<eq])), String(line[..<valueStart]), value, String(rest[valueEnd...]), multiLine)
}

/// The first `char` outside a "basic" or 'literal' string.
private func firstUnquoted(_ char: Character, in s: Substring) -> String.Index? {
    var quote: Character?
    var escaped = false
    for i in s.indices {
        let c = s[i]
        if let q = quote {
            if escaped { escaped = false } else if q == "\"" && c == "\\" { escaped = true } else if c == q { quote = nil }
        } else if c == "\"" || c == "'" {
            quote = c
        } else if c == char {
            return i
        }
    }
    return nil
}

/// `a . "b.c" . 'd'` → ["a", "b.c", "d"].
func splitDotted(_ s: String) -> [String] {
    var parts: [String] = []
    var rest = Substring(s)
    while let dot = firstUnquoted(".", in: rest) {
        parts.append(unquote(rest[..<dot]))
        rest = rest[rest.index(after: dot)...]
    }
    parts.append(unquote(rest))
    return parts
}

private func unquote(_ s: Substring) -> String {
    let t = s.trimmingCharacters(in: .whitespaces)
    if t.count >= 2, t.hasPrefix("'"), t.hasSuffix("'") { return String(t.dropFirst().dropLast()) }
    if t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") {
        return String(t.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }
    return t
}

private func tomlKey(_ k: String) -> String {
    k.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") } && !k.isEmpty ? k : tomlString(k)
}

private func tomlString(_ s: String) -> String {
    var out = "\""
    for u in s.unicodeScalars {
        switch u {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\t": out += "\\t"
        case "\r": out += "\\r"
        case _ where u.value < 0x20 || u.value == 0x7F: out += String(format: "\\u%04X", u.value)
        default: out.unicodeScalars.append(u)
        }
    }
    return out + "\""
}
