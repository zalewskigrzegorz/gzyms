import CryptoKit
import Foundation

/// Ready plugins Gzyms ships: `gzyms plugin add <name>` copies one into the plugins folder.
/// Gzyms keeps the copy up to date until the user edits it (`syncCatalogPlugin`).
public struct CatalogPlugin: Sendable {
    public var name: String, summary: String, manifest: String, script: String
    public init(name: String, summary: String, manifest: String, script: String) {
        self.name = name; self.summary = summary; self.manifest = manifest; self.script = script
    }
}

public let pluginCatalog: [CatalogPlugin] = [logWatcher, ghPRs, ghBuilds, starWatcher]

/// Holds the hash of the catalog files Gzyms last wrote into the folder: files that differ from it are the user's edit.
public let catalogMarker = ".gzyms-catalog"

func catalogHash(manifest: String, script: String) -> String {
    SHA256.hash(data: Data((manifest + "\u{0}" + script).utf8)).map { String(format: "%02x", $0) }.joined()
}

public enum CatalogSync: Equatable, Sendable {
    case notCatalog, current, updated
    /// The user changed the files and the catalog has nothing newer than what was written.
    case edited
    /// The user changed the files (or an install from before markers differs) and the catalog has another version.
    case editedCatalogNewer
}

/// A copy of `<folder>` kept by "update from the catalog". Never run as a plugin.
public func isPluginBackup(_ folder: String) -> Bool { folder.contains(".bak-") }

/// Brings a catalog plugin's plugin.toml and plugin.sh up to the catalog, unless the user changed them.
/// config.toml's options are not in the folder, so they stay.
public func syncCatalogPlugin(in dir: URL, folder: String, catalog: [CatalogPlugin] = pluginCatalog) throws -> CatalogSync {
    guard let c = catalog.first(where: { $0.name == folder }) else { return .notCatalog }
    let f = dir.appendingPathComponent(folder)
    let read = { (n: String) in (try? String(contentsOf: f.appendingPathComponent(n), encoding: .utf8)) ?? "" }
    let now = catalogHash(manifest: read("plugin.toml"), script: read("plugin.sh"))
    let latest = catalogHash(manifest: c.manifest, script: c.script)
    let written = read(catalogMarker).trimmingCharacters(in: .whitespacesAndNewlines)
    if now == latest {
        if written != latest { try latest.write(to: f.appendingPathComponent(catalogMarker), atomically: true, encoding: .utf8) }
        return .current
    }
    guard now == written else { return written == latest ? .edited : .editedCatalogNewer }
    try writeCatalogFiles(c, to: f)
    return .updated
}

/// Puts the catalog version over the user's edit after copying the folder to `<folder>.bak-<date>`. Returns the copy.
public func replaceWithCatalog(in dir: URL, folder: String, now: Date, catalog: [CatalogPlugin] = pluginCatalog) throws -> URL {
    guard let c = catalog.first(where: { $0.name == folder }) else { throw NotifyArgsError(message: "\(folder) is not in the catalog") }
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "yyyy-MM-dd-HHmmss"
    let f = dir.appendingPathComponent(folder), bak = dir.appendingPathComponent("\(folder).bak-\(fmt.string(from: now))")
    try FileManager.default.copyItem(at: f, to: bak)
    try writeCatalogFiles(c, to: f)
    return bak
}

/// A folder's plugin.toml for its next start. A catalog plugin's files are brought up to date first,
/// so a start never runs the script the update is about to replace.
public func pluginTomlForStart(in dir: URL, folder: String, catalog: [CatalogPlugin] = pluginCatalog) -> (toml: String?, sync: Result<CatalogSync, Error>) {
    let sync = Result { try syncCatalogPlugin(in: dir, folder: folder, catalog: catalog) }
    return (try? String(contentsOf: dir.appendingPathComponent(folder).appendingPathComponent("plugin.toml"), encoding: .utf8), sync)
}

/// `installPlugin` plus the marker, so later catalog versions replace it.
public func installCatalogPlugin(in dir: URL, _ c: CatalogPlugin) throws {
    try installPlugin(in: dir, folder: c.name, manifest: c.manifest, script: c.script)
    try catalogHash(manifest: c.manifest, script: c.script)
        .write(to: dir.appendingPathComponent(c.name).appendingPathComponent(catalogMarker), atomically: true, encoding: .utf8)
}

private func writeCatalogFiles(_ c: CatalogPlugin, to f: URL) throws {
    try c.manifest.write(to: f.appendingPathComponent("plugin.toml"), atomically: true, encoding: .utf8)
    let file = f.appendingPathComponent("plugin.sh")
    try c.script.write(to: file, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    try catalogHash(manifest: c.manifest, script: c.script).write(to: f.appendingPathComponent(catalogMarker), atomically: true, encoding: .utf8)
}

/// Writes a plugin folder: its plugin.toml and an executable plugin.sh. Never over an existing folder.
public func installPlugin(in dir: URL, folder name: String, manifest: String, script: String) throws {
    let folder = dir.appendingPathComponent(name)
    guard !FileManager.default.fileExists(atPath: folder.path) else {
        throw NotifyArgsError(message: "\(folder.path) already exists")
    }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try manifest.write(to: folder.appendingPathComponent("plugin.toml"), atomically: true, encoding: .utf8)
    let file = folder.appendingPathComponent("plugin.sh")
    try script.write(to: file, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
}

private let logWatcher = CatalogPlugin(
    name: "log-watcher",
    summary: "Watches log files and notifies on lines that match a rule, from info up to armageddon.",
    manifest: """
    name = "Log watcher"
    description = "Watches log files. A line that matches a rule becomes a notification of that level."
    command = "./plugin.sh"
    icon = "doc.text.magnifyingglass"

    [[option]]
    key = "files"
    title = "Files"
    type = "list"
    default = []
    note = "paths separated by commas, ~ works, Return saves. A file that does not exist yet is picked up when it appears."

    [[option]]
    key = "armageddon"
    title = "Armageddon when"
    type = "text"
    default = ""
    note = "a regex (extended). Empty = never. The whole screen flashes red until clicked."

    [[option]]
    key = "critical"
    title = "Critical when"
    type = "text"
    default = "FATAL|PANIC|panic:"

    [[option]]
    key = "error"
    title = "Error when"
    type = "text"
    default = "ERROR|Exception"

    [[option]]
    key = "warning"
    title = "Warning when"
    type = "text"
    default = ""

    [[option]]
    key = "info"
    title = "Info when"
    type = "text"
    default = ""
    note = "the first rule that matches wins, from armageddon down"

    [[option]]
    key = "ignore_case"
    title = "Ignore case"
    type = "toggle"
    default = false

    [[option]]
    key = "quiet"
    title = "Quiet for (s)"
    type = "number"
    default = 30
    note = "after a notification, the same level only counts on the pill for this long. Armageddon too."

    """,
    script: #"""
    #!/bin/bash
    # Gzyms log watcher. Options arrive as GZYMS_OPT_<KEY>; see plugin.toml. Bash 3.2 (macOS), so no associative arrays.
    # Lines go to Gzyms as JSON on stdout; clicks come back on stdin.
    levels="armageddon critical error warning info"
    files=()
    while IFS= read -r f; do [ -n "$f" ] && files+=("${f/#\~/$HOME}"); done <<< "${GZYMS_OPT_FILES:-}"
    quiet="${GZYMS_OPT_QUIET:-30}"
    [ "${GZYMS_OPT_IGNORE_CASE:-false}" = true ] && shopt -s nocasematch

    rule() { case "$1" in armageddon) echo "${GZYMS_OPT_ARMAGEDDON:-}";; critical) echo "${GZYMS_OPT_CRITICAL:-}";;
      error) echo "${GZYMS_OPT_ERROR:-}";; warning) echo "${GZYMS_OPT_WARNING:-}";; info) echo "${GZYMS_OPT_INFO:-}";; esac; }
    color() { case "$1" in armageddon) echo mauve;; critical|error) echo red;; warning) echo peach;; *) echo sky;; esac; }
    rank() { case "$1" in armageddon) echo 5;; critical) echo 4;; error) echo 3;; warning) echo 2;; info) echo 1;; *) echo 0;; esac; }
    # JSON string body: backslashes, quotes, control characters out, at most 300 characters.
    j() { local s="${1:0:300}"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '%s' "${s//[[:cntrl:]]/ }"; }

    unseen=0 worst="" n=0 file="${files[0]:-}"
    last_armageddon=-99999 last_critical=-99999 last_error=-99999 last_warning=-99999 last_info=-99999
    m_level=() m_line=() m_file=() m_time=()

    pill() {
      if [ ${#files[@]} -eq 0 ]; then
        echo '{"item":{"id":"logs","text":"set a file","icon":"doc.text.magnifyingglass","color":"overlay","tooltip":"Settings → Plugins → Log watcher → Files"}}'
        return
      fi
      local rows="" i
      for ((i = ${#m_line[@]} - 1; i >= 0; i--)); do
        rows+="{\"id\":\"m$i\",\"tag\":\"${m_level[$i]}\",\"color\":\"$(color "${m_level[$i]}")\",\"text\":\"$(j "${m_line[$i]:0:90}")\",\"detail\":\"$(j "$(basename "${m_file[$i]}") ${m_time[$i]}")\"},"
      done
      [ -z "$rows" ] && rows='{"text":"Nothing matched yet."},'
      rows+='{"separator":true},{"id":"clear","text":"Clear the list"}'
      local text="" c=overlay err="" f
      [ "$unseen" -gt 0 ] && text="$unseen" && c=$(color "$worst")
      # tail would stay silent about it: a pill that says nothing matched would be a lie
      for f in "${files[@]}"; do
        [ -e "$f" ] && [ ! -r "$f" ] && { err=",\"error\":\"$(j "Cannot read $f. Check its permissions.")\""; break; }
      done
      echo "{\"item\":{\"id\":\"logs\",\"text\":\"$text\",\"icon\":\"doc.text.magnifyingglass\",\"color\":\"$c\",\"tooltip\":\"$(j "${#files[@]} file(s) watched")\",\"menu\":[$rows]$err}}"
    }

    matched() {  # level line
      local level="$1" line="$2" now=$SECONDS last
      m_level+=("$level"); m_line+=("$line"); m_file+=("$file"); m_time+=("$(date +%H:%M:%S)")
      if [ ${#m_line[@]} -gt 10 ]; then m_level=("${m_level[@]:1}"); m_line=("${m_line[@]:1}"); m_file=("${m_file[@]:1}"); m_time=("${m_time[@]:1}"); fi
      unseen=$((unseen + 1))
      [ "$(rank "$level")" -gt "$(rank "$worst")" ] && worst="$level"
      pill
      eval "last=\$last_$level"
      # Armageddon too: a line that repeats every second would bring the red screen back right after each click.
      if [ $((now - last)) -ge "$quiet" ]; then
        eval "last_$level=$now"
        n=$((n + 1))
        echo "{\"notify\":{\"id\":\"$level-$$-$n\",\"level\":\"$level\",\"title\":\"$(j "$level in $(basename "$file")")\",\"body\":\"$(j "$line")\"}}"
      fi
    }

    on_line() {
      case "$1" in "==> "*" <==") file="${1#==> }"; file="${file% <==}"; return;; esac
      local level re
      for level in $levels; do
        re="$(rule "$level")"
        [ -n "$re" ] && [[ $1 =~ $re ]] && { matched "$level" "$1"; return; }
      done
    }

    on_event() {
      case "$1" in
        *'"open"'*) unseen=0; worst=""; pill;;
        *'"clear"'*) m_level=(); m_line=(); m_file=(); m_time=(); unseen=0; worst=""; pill;;
        *'"id":"m'*) i="${1#*\"id\":\"m}"; i="${i%%\"*}"; [ -n "${m_file[$i]:-}" ] && open -a Console "${m_file[$i]}";;
      esac
    }

    pill
    # One stream of both: L = a log line, E = an event from Gzyms. When Gzyms goes (stdin ends), tail goes too.
    {
      tpid=""
      if [ ${#files[@]} -gt 0 ]; then
        tail -F -n 0 "${files[@]}" 2>/dev/null > >(while IFS= read -r l; do printf 'L %s\n' "$l"; done) &
        tpid=$!
      fi
      while IFS= read -r e; do printf 'E %s\n' "$e"; done
      [ -n "$tpid" ] && kill "$tpid" 2>/dev/null
    } | while IFS= read -r msg; do
      case "$msg" in "L "*) on_line "${msg#L }";; "E "*) on_event "${msg#E }";; esac
    done

    """#
)
