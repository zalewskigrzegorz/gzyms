import Foundation

/// Ready plugins Gzyms ships: `gzyms plugin add <name>` copies one into the plugins folder, then it is the user's.
public struct CatalogPlugin: Sendable {
    public var name: String, summary: String, manifest: String, script: String
}

public let pluginCatalog: [CatalogPlugin] = [logWatcher, agents, ghPRs, ghBuilds]

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
      local text="" c=overlay
      [ "$unseen" -gt 0 ] && text="$unseen" && c=$(color "$worst")
      echo "{\"item\":{\"id\":\"logs\",\"text\":\"$text\",\"icon\":\"doc.text.magnifyingglass\",\"color\":\"$c\",\"tooltip\":\"$(j "${#files[@]} file(s) watched")\",\"menu\":[$rows]}}"
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

private let agents = CatalogPlugin(
    name: "agents",
    summary: "Your coding agents from tuios on one pill. A notification when one waits for you or ends a long run.",
    manifest: """
    name = "Agents"
    description = "The coding agents tuios sees (Claude Code, Codex and others). Tells you when one waits for you."
    command = "./plugin.sh"
    icon = "sparkles"

    [[option]]
    key = "done_after"
    title = "Done after (min)"
    type = "number"
    default = 3
    note = "a run at least this long gets a notification when it ends. 0 = every run."

    [[option]]
    key = "terminal"
    title = "Terminal"
    type = "text"
    default = "Ghostty"
    note = "the app tuios runs in. A click on an agent brings it to the front on that agent's pane."

    [[option]]
    key = "source"
    title = "How it learns"
    type = "choice"
    default = "live"
    choices = ["live", "poll"]
    note = "live: tuios tells it the moment an agent changes. poll: it asks tuios every few seconds."

    [[option]]
    key = "every"
    title = "Poll every (s)"
    type = "number"
    default = 3
    note = "only for poll"

    """,
    script: #"""
    #!/bin/bash
    # Gzyms agents: the agents tuios sees, on one pill. Options arrive as GZYMS_OPT_<KEY>; see plugin.toml.
    # Bash 3.2 (macOS), so no associative arrays. Lines go to Gzyms as JSON on stdout; clicks come back on stdin.
    # tuios lists panes, so a subagent never shows up or pings on its own.
    TUIOS="${TUIOS_BIN:-$(command -v tuios || echo /opt/homebrew/bin/tuios)}"
    JQ="$(command -v jq || echo /usr/bin/jq)"
    every="${GZYMS_OPT_EVERY:-3}"
    source="${GZYMS_OPT_SOURCE:-live}"
    done_after=$(( ${GZYMS_OPT_DONE_AFTER:-3} * 60 ))
    terminal="${GZYMS_OPT_TERMINAL:-Ghostty}"
    j() { local s="${1:0:300}"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '%s' "${s//[[:cntrl:]]/ }"; }
    color() { case "$1" in waits) echo peach;; working) echo sky;; done) echo green;; *) echo overlay;; esac; }

    if [ ! -x "$TUIOS" ]; then
      echo '{"item":{"id":"agents","text":"no tuios","icon":"sparkles","color":"overlay","tooltip":"This plugin reads tuios. Without it there is nothing to show."}}'
      exec cat >/dev/null  # stays until Gzyms closes stdin
    fi

    prev=""   # what the last check saw: id, state, needs you, working since (s)
    rows=""   # id, session, state, needs you, name, message
    # n starts from the clock: after a bar restart a counter from 0 reused ids still in the bell, and the new note replaced the old one silently.
    first=1 last="" n=$(date +%s)000

    say() {  # level id session title body
      # A fresh id each time: the same id again would only update the old note in the bell, without a banner.
      n=$((n + 1))
      local sound=success; [ "$1" = warning ] && sound=waiting  # waits for you, or done
      echo "{\"notify\":{\"id\":\"agent-$2-$n\",\"level\":\"$1\",\"sound\":\"$sound\",\"title\":\"$(j "$4")\",\"subtitle\":\"$(j "$3") · click to go there\",\"body\":\"$(j "$5")\"}}"
    }

    poll() {
      local now id session state needs name msg ostate oneeds since tag waiting=0 working=0 menu="" next=""
      now=$(date +%s)
      rows=$("$TUIOS" list-agents --all-sessions --json 2>/dev/null | "$JQ" -r '.agents[] | [.window_id, .session, .state,
        (.needs_you | tostring), .name, (if (.message // "") != "" then .message else (.meta.prompt // "") end)] | @tsv' 2>/dev/null) || return
      while IFS=$'\t' read -r id session state needs name msg; do
        [ -n "$id" ] || continue
        IFS=$'\t' read -r ostate oneeds since <<< "$(printf '%s\n' "$prev" | awk -F'\t' -v id="$id" '$1 == id { print $2 "\t" $3 "\t" $4 }')"
        [ "$state" = working ] && [ "$ostate" != working ] && since=$now
        # The first check after a start only looks: a Gzyms restart must not ping for every agent again.
        if [ "$needs" = true ]; then
          waiting=$((waiting + 1))
          [ $first = 0 ] && [ "$oneeds" != true ] && say warning "$id" "$session" "$name waits for you" "$msg"
        elif [ $first = 0 ] && [ "$ostate" = working ] && [ "$state" != working ] && [ -n "$since" ] && [ $((now - since)) -ge $done_after ]; then
          say info "$id" "$session" "$name is done" "after $(( (now - since + 59) / 60 )) min"
        fi
        [ "$state" = working ] && working=$((working + 1))
        tag=$state; [ "$needs" = true ] && tag=waits
        menu+="{\"id\":\"$id\",\"tag\":\"$tag\",\"color\":\"$(color "$tag")\",\"text\":\"$(j "$name")\",\"detail\":\"$(j "$session")\"},"
        next+="$id"$'\t'"$state"$'\t'"$needs"$'\t'"$since"$'\n'
      done <<< "$rows"
      prev="$next" first=0
      local text="" c=overlay
      if [ $waiting -gt 0 ]; then text=$waiting c=peach; elif [ $working -gt 0 ]; then text=$working c=sky; fi
      [ -z "$menu" ] && menu='{"text":"No agents in tuios."},'
      local pill="{\"item\":{\"id\":\"agents\",\"text\":\"$text\",\"icon\":\"sparkles\",\"color\":\"$c\",\"tooltip\":\"$waiting waiting, $working working\",\"menu\":[${menu%,}]}}"
      [ "$pill" != "$last" ] && echo "$pill" && last="$pill"
    }

    on_event() {  # a row or a notification click: that agent's session and pane, in front
      local id="${1#*\"id\":\"}" session
      id="${id%%\"*}"
      case "$1" in *'"notify_open"'*) id="${id#agent-}"; id="${id%-*}";; esac  # agent-<pane>-<n>
      # The pane may have closed since the notification: then a click does nothing.
      session=$(printf '%s\n' "$rows" | awk -F'\t' -v id="$id" '$1 == id { print $2 }')
      [ -n "$session" ] || return
      "$TUIOS" switch-session "$session" >/dev/null 2>&1
      "$TUIOS" focus-window -s "$session" "$id" >/dev/null 2>&1
      open -a "$terminal"
    }

    # live: every agent-state change tuios pushes means "look again". A tuios restart ends the stream, so it starts again.
    # The TERM trap takes the subscribe down too, or it would outlive the plugin.
    live() {
      local sub=""
      trap 'kill $sub 2>/dev/null; exit 0' TERM
      while :; do
        echo T
        "$TUIOS" subscribe --types agent-state 2>/dev/null > >(while IFS= read -r _; do echo T; done) &
        sub=$!
        wait $sub
        sleep 2 >/dev/null
      done
    }

    # One stream of both: T = time to look again, E = an event from Gzyms. When Gzyms goes (stdin ends), the clock goes too.
    {
      if [ "$source" = poll ]; then
        while :; do echo T; sleep "$every" >/dev/null; done &
        clock=$!
      else
        live &
        clock=$!
        # A slow look as well: a closed pane or a new name sends no agent-state.
        while :; do sleep 60 >/dev/null; echo T; done &
        slow=$!
      fi
      while IFS= read -r e; do printf 'E %s\n' "$e"; done
      kill $clock ${slow:-} 2>/dev/null
    } | while IFS= read -r msg; do
      case "$msg" in T) poll;; "E "*) on_event "${msg#E }";; esac
    done

    """#
)
