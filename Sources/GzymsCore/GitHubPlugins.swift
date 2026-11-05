import Foundation

// The two GitHub plugins of the catalog. Both are bash 3.2 + gh + /usr/bin/jq: one `gh api graphql` call per poll,
// one jq program that turns {state, response} into the new state and the protocol lines. Nothing goes to disk.

/// The part both share, after a script set PILL, ICON, ARGS (the gh call), PROG (jq), JQARGS and on_click.
/// A clock asks GitHub in the background; its answers, the clicks and its pid come down one pipe to the loop.
private let ghRun = #"""
GH="${GH_BIN:-$(command -v gh || { [ -x /opt/homebrew/bin/gh ] && echo /opt/homebrew/bin/gh; } || echo /usr/local/bin/gh)}"
every="${GZYMS_OPT_EVERY:-60}"; case "$every" in ''|*[!0-9]*|0) every=60;; esac
problem() {  # pill text, sentence: a pill that says what is missing, then wait for Gzyms to go
  echo "{\"item\":{\"id\":\"$PILL\",\"text\":\"$1\",\"icon\":\"$ICON\",\"color\":\"peach\",\"tooltip\":\"$2\",\"menu\":[{\"text\":\"$2\"}]}}"
  exec cat >/dev/null
}
[ -x "$GH" ] || problem "install gh" "Install the GitHub CLI (brew install gh), then turn this plugin off and on."

state='{}' last="" asked=-99 clockpid=""
step() {  # mode [err] [errpill], stdin = GitHub's answer or null. Prints what changed, keeps the state.
  local out l
  out=$("$JQ" -c --arg mode "$1" --arg err "${2:-}" --arg errpill "${3:-}" --argjson st "$state" "${JQARGS[@]}" "$PROG") || return
  { IFS= read -r state
    while IFS= read -r l; do
      case "$l" in '{"item"'*) [ "$l" != "$last" ] && echo "$l" && last=$l;; ?*) echo "$l";; esac
    done; } <<< "$out"
}

clock() {  # R <answer> after a good call, X auth|rate|net after a bad one. USR1 = ask now. Errors double the wait, up to 15 min.
  local pause=$every res ok sp=""
  trap 'kill $sp 2>/dev/null' USR1
  trap 'kill $sp 2>/dev/null; exit 0' TERM
  while :; do
    res=$("$GH" api graphql "${ARGS[@]}" 2>/dev/null)
    # A partial answer (one repo of the list gone) still has data: use it.
    ok=$(printf '%s' "$res" | "$JQ" -c 'select(.data | type == "object")' 2>/dev/null)
    if [ -n "$ok" ]; then
      printf 'R %s\n' "$ok"; pause=$every
    else
      case "$res" in
        *[Rr]ate\ limit*|*RATE_LIMITED*) echo "X rate";;
        *"Bad credentials"*) echo "X auth";;
        *) if "$GH" auth token >/dev/null 2>&1; then echo "X net"; else echo "X auth"; fi;;
      esac
      pause=$((pause * 2 > 900 ? 900 : pause * 2))
    fi
    sleep "$pause" & sp=$!
    wait $sp
  done
}

on_event() {
  local ev id
  IFS=$'\x1f' read -r ev id <<< "$(printf '%s' "$1" | "$JQ" -r '[.event // "", .id // ""] | join("\u001f")')"
  if [ "$ev" = open ]; then  # the list opened: what was new is seen now, and a fresh look unless one ran 15 s ago
    step seen <<< null
    [ -n "$clockpid" ] && [ $((SECONDS - asked)) -ge 15 ] && kill -USR1 "$clockpid" 2>/dev/null && asked=$SECONDS
    return
  fi
  on_click "$ev" "$id"
}

open_url() { case "$1" in https://*) open "$1";; esac; }

# One stream of three: P = the clock's pid, R/X = GitHub, E = an event from Gzyms. Stdin ends: the clock goes too.
{
  echo S
  clock & c=$!
  echo "P $c"
  while IFS= read -r e; do printf 'E %s\n' "$e"; done
  kill $c 2>/dev/null
} | while IFS= read -r msg; do
  case "$msg" in
    S) step render <<< null;;
    "P "*) clockpid=${msg#P };;
    "R "*) step poll <<< "${msg#R }";;
    "X auth") step error "Run gh auth login in a terminal. This pill updates by itself after that." "gh auth login" <<< null;;
    "X rate") step error "GitHub's rate limit is reached. Asking less often for a while." <<< null;;
    "X net") step error "GitHub did not answer. Trying again." <<< null;;
    "E "*) on_event "${msg#E }";;
  esac
done

"""#

/// The checks of one commit, as both queries ask for them.
private let checksQuery = "contexts(first:30){nodes{__typename ... on CheckRun{name status conclusion detailsUrl} ... on StatusContext{context state targetUrl}}}"

/// `sounds` option: kind → file in that folder, for the kinds that have one. Bash, sets `snd` (JSON).
private let soundFiles = #"""
snd='{}'
dir="${GZYMS_OPT_SOUNDS:-}"; dir="${dir/#\~/$HOME}"
if [ -n "$dir" ]; then
  for k in $KINDS; do
    for x in mp3 m4a wav aiff; do
      [ -f "$dir/pr-$k.$x" ] && snd=$("$JQ" -c --arg k "$k" --arg f "$dir/pr-$k.$x" '. + {($k): $f}' <<< "$snd") && break
    done
  done
fi

"""#

let ghPRs = CatalogPlugin(
    name: "gh-prs",
    summary: "Your pull requests through the gh CLI: a glyph per state (fix, merge, comments, draft) with the number of PRs in it.",
    manifest: """
    name = "GitHub PRs"
    description = "Your pull requests through the gh CLI. One glyph per state with the number of PRs in it: fix, merge, comments, draft. A PR counts in every state it is in, a draft only as a draft. A notification on a new approval or comment."
    command = "./plugin.sh"
    icon = "arrow.triangle.branch"

    [[option]]
    key = "query"
    title = "Search"
    type = "text"
    default = "is:open is:pr author:@me archived:false"
    note = "a GitHub search. Add org:NAME or repo:OWNER/NAME to narrow it. Empty = nothing to show."

    [[option]]
    key = "every"
    title = "Ask every (s)"
    type = "number"
    default = 120
    note = "one GitHub call each time, about 26 points of the 5000 GitHub allows an hour. Opening the list asks at once."

    [[option]]
    key = "hide_idle"
    title = "Hide when idle"
    type = "toggle"
    default = false
    note = "on = no pill while none of your pull requests is in a state the pill shows. Off = an empty pill with the list."

    [[option]]
    key = "row_command"
    title = "Right click on a PR"
    type = "text"
    default = ""
    note = "a shell command with {repo} {branch} {url} {number} filled in, e.g. one that opens the branch in your editor. Empty = nothing."

    [[option]]
    key = "right_click"
    title = "Right click on the pill"
    type = "text"
    default = ""
    note = "a shell command, e.g. one that opens gh dash. Empty = github.com/pulls in the browser."

    [[option]]
    key = "sounds"
    title = "Sound folder"
    type = "text"
    default = ""
    note = "a folder with pr-approval.mp3 and pr-comment.mp3 (or .m4a .wav .aiff). Empty or a missing file = Gzyms' sounds."

    """,
    script: #"""
    #!/bin/bash
    # Gzyms GitHub PRs. Options arrive as GZYMS_OPT_<KEY>; see plugin.toml. Bash 3.2 (macOS), gh and /usr/bin/jq.
    # Lines go to Gzyms as JSON on stdout; clicks come back on stdin.
    PILL=prs ICON=arrow.triangle.branch KINDS="approval comment"
    JQ="$(command -v jq || echo /usr/bin/jq)"
    query="${GZYMS_OPT_QUERY:-}"
    : "${GZYMS_OPT_EVERY:=120}"
    if [ -z "$query" ]; then
      echo '{"item":{"id":"prs","text":"set a search","icon":"arrow.triangle.branch","color":"overlay","tooltip":"Settings → Plugins → GitHub PRs → Search"}}'
      exec cat >/dev/null
    fi
    ARGS=(-f "q=$query" -f 'query=query($q:String!){viewer{login} search(query:$q,type:ISSUE,first:25){nodes{... on PullRequest{
      number title url isDraft mergeable reviewDecision headRefName repository{nameWithOwner viewerPermission}
      latestReviews(first:10){nodes{state author{login}}}
      reviewThreads(last:100){nodes{isResolved comments(last:1){nodes{author{login __typename}}}}}
      comments(last:10){nodes{createdAt author{login __typename}}}
      commits(last:1){nodes{commit{statusCheckRollup{\#(checksQuery)}}}}}}}}')
    \#(soundFiles)
    JQARGS=(--argjson snd "$snd")

    # Modes: poll (stdin = GitHub's answer), seen (the list opened), error, render. Out: the new state, then lines.
    # The action chain is the one a PR needs from its author: the first that holds wins.
    read -r -d '' PROG <<'JQ'
    def foreign($me): (.author.login // "") as $l | (.author.__typename // "") != "Bot" and $l != $me and $l != "github-actions";
    def pr($me):
      (.commits.nodes[0].commit.statusCheckRollup.contexts.nodes // []) as $c
      | ([$c[] | select(.conclusion == "FAILURE" or .state == "FAILURE")] | length) as $failed
      | ([$c[] | select(((.status // "") != "" and .status != "COMPLETED") or (.state // "" | IN("PENDING", "EXPECTED")))] | length) as $pending
      # a required status that waits while nothing like e2e runs: someone has to start it
      | ([$c[] | select(.state == "EXPECTED")] | length) as $expected
      | ([$c[] | select((.status // "") != "" and .status != "COMPLETED" and (.name // "" | test("e2e"; "i")))] | length) as $e2e
      | (.reviewThreads.nodes // []) as $t
      | ([$t[] | select(.isResolved | not)] | length) as $unresolved
      | ([$t[] | select((.isResolved | not) and (.comments.nodes | last // {} | foreign($me)))] | length) as $threads
      | (.comments.nodes // []) as $conv
      | ([$conv[] | select(.author.login == $me) | .createdAt] | max // "") as $mine
      | ([$conv[] | select(foreign($me)) | .createdAt] | max // "") as $theirs
      | (if $failed > 0 then "fix CI"
         elif .mergeable == "CONFLICTING" then "conflict" elif .reviewDecision == "CHANGES_REQUESTED" then "changes req"
         elif .reviewDecision == "REVIEW_REQUIRED" then "needs review" elif $expected > 0 and $e2e == 0 then "run e2e"
         elif $pending > 0 then "CI…" elif .mergeable == "MERGEABLE" then "MERGE" else "blocked" end) as $a
      # GitHub blocks a merge on any open conversation, and on a repo where you cannot write
      | (if $a == "MERGE" and $unresolved > 0 then "resolve"
         elif $a == "MERGE" and (.repository.viewerPermission // "" | IN("ADMIN", "MAINTAIN", "WRITE") | not) then "blocked"
         else $a end) as $base
      | {key: "\(.repository.nameWithOwner)#\(.number)", repo: .repository.nameWithOwner, number, title, url, branch: .headRefName,
         draft: .isDraft, base: $base, action: (if .isDraft then "draft" else $base end),
         outstanding: ($threads + (if $theirs != "" and $theirs > $mine then 1 else 0 end)),
         approvers: ([.latestReviews.nodes[]? | select(.state == "APPROVED") | .author.login // "?"] | unique)};
    # The states of a PR, one glyph and one word each, on the pill and in the list. Not exclusive: a PR that needs a fix
    # can have comments too. A draft is a draft on the pill and nothing else, the list row still shows its other states.
    def fixing: .base | IN("fix CI", "conflict", "changes req", "run e2e");
    def states: [if fixing then "fix" else empty end, if .base == "MERGE" and (.draft | not) then "merge" else empty end,
      if .outstanding > 0 then "comments" else empty end, if .draft then "draft" else empty end];
    def pillStates: if .draft then ["draft"] else states end;
    def glyph: {fix: ":xmark.circle:", merge: ":checkmark.circle:", comments: ":bubble.left:", draft: ":square.and.pencil:"}[.];
    def why: {"fix CI": "CI failed", conflict: "conflict", "changes req": "changes requested", "run e2e": "run e2e"}[.base];
    def primary: if .draft then "draft" elif fixing then "fix" elif .action == "MERGE" then "merge" else "" end;
    def tag: {"fix CI": [":xmark.circle: fix", "peach"], "changes req": [":xmark.circle: fix", "peach"], "run e2e": [":xmark.circle: fix", "peach"],
      conflict: [":xmark.circle: fix", "red"], resolve: ["resolve", "sky"], "CI…": ["CI runs…", "gold"], MERGE: [":checkmark.circle: merge", "green"],
      draft: [":square.and.pencil: draft", "mauve"], "needs review": ["review?", "lavender"],
      blocked: ["blocked", "lavender"]}[.action] // [.action, "overlay"];
    def kind: {approval: [":hand.thumbsup: review", "green", "success"], comment: [":bubble.left: new", "sky", "message"]}[.kind];
    def what: if .kind == "approval" then "approved by \(.text)" else "new comment" end;
    def short($multi): (if $multi then .repo | split("/") | last else "" end) + "#\(.number)";
    def event($p; $c):
      ($c.approvers - ($p.approvers // [])) as $a
      | if $a != [] then {kind: "approval", text: ($a | join(", "))}
        elif $c.outstanding > ($p.outstanding // 0) then {kind: "comment", text: ""} else empty end;
    def notify: {notify: {id: "\(.kind)-\(.key)-\(now | floor)", title: "\(short(true)) \(what)", body: .title, link: .url,
      level: "info", sound: ($snd[.kind] // kind[2])}};
    def render($st):
      ($st.prs // null) as $prs | ($st.unseen // []) as $u | ($u + ($st.shown // [])) as $ev
      | if $st.errpill then {item: {id: "prs", text: $st.errpill, icon: "arrow.triangle.branch", color: "peach", tooltip: $st.err, menu: [{text: $st.err}]}}
        elif $prs == null then {item: {id: "prs", text: "…", icon: "arrow.triangle.branch", color: "overlay",
          tooltip: ($st.err // "Asking GitHub…"), menu: [{text: ($st.err // "Asking GitHub…")}]}}
        else
          ([$prs[].repo] | unique | length > 1) as $multi
          | [$prs[] | pillStates[]] as $all
          | [("fix", "merge", "comments", "draft") as $s | {s: $s, n: ([$all[] | select(. == $s)] | length)} | select(.n > 0)] as $cnt
          | ($cnt | map({(.s): .n}) | add // {}) as $n
          | [$cnt[] | "\(.s | glyph) \(.n)"] as $parts
          | (if $parts == [] and $u != [] then [":bell:"] else $parts end) as $parts
          | if $parts == [] and $ENV.GZYMS_OPT_HIDE_IDLE == "true" then {item: {id: "prs", remove: true}}
            else {item: {id: "prs", text: ($parts | join(" ")), icon: "arrow.triangle.branch",
              color: (if $n.fix then "peach" elif $n.comments or $u != [] then "sky" elif $n.merge then "green" else "overlay" end),
              tooltip: ($st.err // (if $cnt == [] then "\($prs | length) open pull requests" else ($cnt | map("\(.s) \(.n)") | join(", ")) end)),
              menu: ([if $st.err then {text: $st.err} else empty end]
                + [$ev | to_entries[] | .key as $i | .value
                   | {id: "ev\($i)", tag: kind[0], color: kind[1], text: "\(short($multi)) \(what)  \(.title)", detail: .at}]
                + (if $ev != [] then [{separator: true}] else [] end)
                + (if $prs == [] then [{text: "No open pull requests."}] else
                   [$prs | sort_by([(if (.draft | not) and (fixing or (.action | IN("MERGE", "resolve"))) then 0 else 1 end), -.number])[]
                    | tag as $t | primary as $p | {id: "pr:\(.key)", tag: $t[0], color: $t[1], text: "\(short($multi))  \(.title)",
                      detail: ([if $p == "fix" then why else empty end] + [states[] | select(. != $p) | "\(glyph) \(.)"] | join("  "))}] end))}}
            end
        end;
    if $mode == "poll" then
      .data.viewer.login as $me
      | [.data.search.nodes[]? | select(.number != null) | pr($me)] as $prs
      # the first answer after a start is the baseline: a restart tells nothing again
      | [if $st.prs == null then empty else $prs[] as $c | ($st.prs[] | select(.key == $c.key)) as $p
         | event($p; $c) + ($c | {key, repo, branch, number, title, url}) + {at: (now | strflocaltime("%H:%M"))} end] as $new
      | ($st + {prs: $prs, err: null, errpill: null,
          unseen: ($new + [($st.unseen // [])[] | select(.key as $k | $new | all(.key != $k))])[:10]}) as $s
      | $s, ($new[] | notify), render($s)
    elif $mode == "seen" then ($st + {unseen: [], shown: (($st.unseen // []) + ($st.shown // []))[:10]}) as $s | $s, render($s)
    elif $mode == "error" then ($st + {err: $err, errpill: (if $errpill == "" then null else $errpill end)}) as $s | $s, render($s)
    else $st, render($st) end
    JQ

    on_click() {  # event id. A row opens its PR; a right click runs your command on it.
      local row url repo branch number cmd
      if [ "$2" = prs ]; then
        [ "$1" = right_click ] || return
        if [ -n "${GZYMS_OPT_RIGHT_CLICK:-}" ]; then (sh -c "$GZYMS_OPT_RIGHT_CLICK" >/dev/null 2>&1 &); else open https://github.com/pulls; fi
        return
      fi
      row=$("$JQ" -r --arg id "$2" '(if ($id | startswith("ev")) then (.unseen + .shown)[$id[2:] | tonumber]
        else .prs[] | select("pr:\(.key)" == $id) end) // empty | [.url, .repo, .branch, (.number | tostring)] | join("\u001f")' <<< "$state")
      IFS=$'\x1f' read -r url repo branch number <<< "$row"
      [ -n "$url" ] || return
      if [ "$1" != right_click ]; then open_url "$url"; return; fi
      cmd="${GZYMS_OPT_ROW_COMMAND:-}"
      [ -n "$cmd" ] || return
      # The values go in as quoted variables, never as text: a branch name may hold ; or $.
      cmd=${cmd//\{repo\}/'"$REPO"'}; cmd=${cmd//\{branch\}/'"$BRANCH"'}; cmd=${cmd//\{url\}/'"$URL"'}; cmd=${cmd//\{number\}/'"$NUMBER"'}
      (REPO=$repo BRANCH=$branch URL=$url NUMBER=$number sh -c "$cmd" >/dev/null 2>&1 &)
    }

    \#(ghRun)
    """#
)

let ghBuilds = CatalogPlugin(
    name: "gh-builds",
    summary: "CI of your pull requests and of chosen branches through the gh CLI: how many failed and how many run, a note when it ends.",
    manifest: """
    name = "GitHub builds"
    description = "CI through the gh CLI: the checks of your pull requests and of chosen branches. A glyph for failed and one for running, each with the number of PRs or branches in that state, counted once by the worst one. A notification when a run fails or ends green."
    command = "./plugin.sh"
    icon = "hammer"

    [[option]]
    key = "query"
    title = "PRs to watch"
    type = "text"
    default = "is:open is:pr author:@me archived:false"
    note = "a GitHub search, the CI of these pull requests. Empty = no pull requests, only the branches."

    [[option]]
    key = "branches"
    title = "Branches"
    type = "list"
    default = []
    note = "owner/repo@branch, separated by commas, e.g. a deploy branch. Empty = only the pull requests."

    [[option]]
    key = "every"
    title = "Ask every (s)"
    type = "number"
    default = 60
    note = "one GitHub call each time, a few points of the 5000 GitHub allows an hour. Opening the list asks at once."

    [[option]]
    key = "notify"
    title = "Notify when"
    type = "choice"
    default = "finished"
    choices = ["finished", "failed", "all"]
    note = "finished: a run fails or ends green. failed: only failures. all: also when a run starts."

    [[option]]
    key = "hide_idle"
    title = "Hide when idle"
    type = "toggle"
    default = false
    note = "on = no pill while nothing runs or fails. Off = an empty pill with the list."

    [[option]]
    key = "sounds"
    title = "Sound folder"
    type = "text"
    default = ""
    note = "a folder with pr-ci_fail.mp3, pr-ci_success.mp3 and pr-ci_start.mp3 (or .m4a .wav .aiff). Empty or a missing file = Gzyms' sounds."

    """,
    script: #"""
    #!/bin/bash
    # Gzyms GitHub builds. Options arrive as GZYMS_OPT_<KEY>; see plugin.toml. Bash 3.2 (macOS), gh and /usr/bin/jq.
    # Lines go to Gzyms as JSON on stdout; clicks come back on stdin.
    PILL=builds ICON=hammer KINDS="ci_fail ci_success ci_start"
    JQ="$(command -v jq || echo /usr/bin/jq)"
    query="${GZYMS_OPT_QUERY:-}"
    : "${GZYMS_OPT_EVERY:=60}"
    CHECKS='\#(checksQuery)'
    decl="" sel="" vars=() br='[]' bad='[]' i=0
    if [ -n "$query" ]; then
      decl='$q:String!' vars=(-f "q=$query")
      sel="search(query:\$q,type:ISSUE,first:25){nodes{... on PullRequest{number title url repository{nameWithOwner} commits(last:1){nodes{commit{statusCheckRollup{$CHECKS}}}}}}}"
    fi
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      # Names go in as GraphQL variables, never into the query text.
      if [[ "$b" =~ ^([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)@([^[:space:]]+)$ ]]; then
        decl+=" \$o$i:String! \$n$i:String! \$r$i:String!"
        sel+=" b$i:repository(owner:\$o$i,name:\$n$i){object(expression:\$r$i){... on Commit{url statusCheckRollup{$CHECKS}}}}"
        vars+=(-f "o$i=${BASH_REMATCH[1]}" -f "n$i=${BASH_REMATCH[2]}" -f "r$i=${BASH_REMATCH[3]}")
        br=$("$JQ" -c --argjson i $i --arg repo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}" --arg ref "${BASH_REMATCH[3]}" '. + [{i: $i, repo: $repo, ref: $ref}]' <<< "$br")
        i=$((i + 1))
      else
        bad=$("$JQ" -c --arg b "$b" '. + [$b]' <<< "$bad")
      fi
    done <<< "${GZYMS_OPT_BRANCHES:-}"
    if [ -z "$sel" ]; then
      echo '{"item":{"id":"builds","text":"set a branch","icon":"hammer","color":"overlay","tooltip":"Settings → Plugins → GitHub builds → PRs to watch or Branches"}}'
      exec cat >/dev/null
    fi
    ARGS=(-f "query=query($decl){$sel}" "${vars[@]}")
    \#(soundFiles)
    JQARGS=(--argjson snd "$snd" --argjson br "$br" --argjson bad "$bad")

    # Modes as in gh-prs. A target is one PR or one branch, with the state of its checks.
    read -r -d '' PROG <<'JQ'
    def snap: (.contexts.nodes // []) as $c
      | [$c[] | select((.conclusion // "" | IN("FAILURE", "TIMED_OUT", "STARTUP_FAILURE")) or (.state // "" | IN("FAILURE", "ERROR")))
         | {name: (.name // .context // "check"), url: (.detailsUrl // .targetUrl // "")}] as $f
      | {failed: ($f | unique_by(.name)),
         pending: ($c | any(((.status // "") != "" and .status != "COMPLETED") or (.state // "" | IN("PENDING", "EXPECTED")))),
         # every check ended clean; none at all is not green
         green: ($c != [] and ($c | all((.conclusion // "" | IN("SUCCESS", "NEUTRAL", "SKIPPED")) or .state == "SUCCESS"))),
         checks: ($c | length)};
    def status: if .failed != [] then [":xmark.circle: failed", "red", 0] elif .pending then [":arrow.triangle.2.circlepath: running", "gold", 1]
      elif .green then ["green", "green", 2] elif .checks == 0 then ["no CI", "overlay", 4] else ["done", "overlay", 3] end;
    def kind: {ci_fail: [":xmark.circle: CI", "red", "fail", "warning"], ci_success: [":checkmark.circle: CI", "green", "success", "info"],
      ci_start: [":arrow.triangle.2.circlepath: CI", "gold", "message", "info"]}[.kind];
    def what: if .kind == "ci_fail" then "CI failed: \(.text)" elif .kind == "ci_success" then "CI green" else "CI started" end;
    def wanted: ($ENV.GZYMS_OPT_NOTIFY // "finished") as $n
      | $n == "all" or .kind == "ci_fail" or ($n != "failed" and .kind == "ci_success");
    def event($p; $c):
      ([$c.failed[] | select(.name as $n | $p.failed | all(.name != $n))] | first) as $nf
      | if $nf != null then {kind: "ci_fail", text: $nf.name, url: (if $nf.url | startswith("https://") then $nf.url else $c.url end)}
        elif $p.pending and ($c.pending | not) and $c.green then {kind: "ci_success", text: "", url: $c.url}
        elif $c.pending and ($p.pending | not) then {kind: "ci_start", text: "", url: $c.url}
        else empty end;
    def notify: {notify: {id: "\(.kind)-\(.key)-\(now | floor)", title: "\(.label) \(what)", body: .title, link: .url,
      level: kind[3], sound: ($snd[.kind] // kind[2])}};
    def render($st):
      ($st.targets // null) as $ts | ($st.unseen // []) as $u | ($u + ($st.shown // [])) as $ev
      | if $st.errpill then {item: {id: "builds", text: $st.errpill, icon: "hammer", color: "peach", tooltip: $st.err, menu: [{text: $st.err}]}}
        elif $ts == null then {item: {id: "builds", text: "…", icon: "hammer", color: "overlay",
          tooltip: ($st.err // "Asking GitHub…"), menu: [{text: ($st.err // "Asking GitHub…")}]}}
        else
          ([$ts[] | select(.failed != [])] | length) as $fail
          # a target counts once, by its worst state: failing while a check still runs is failing
          | ([$ts[] | select(.failed == [] and .pending)] | length) as $run
          | [if $fail > 0 then ":xmark.circle: \($fail)" else empty end, if $run > 0 then ":arrow.triangle.2.circlepath: \($run)" else empty end] as $parts
          | (if $parts == [] and $u != [] then [":bell:"] else $parts end) as $parts
          | if $parts == [] and $ENV.GZYMS_OPT_HIDE_IDLE == "true" then {item: {id: "builds", remove: true}}
            else {item: {id: "builds", text: ($parts | join(" ")), icon: "hammer",
              color: (if $fail > 0 then "red" elif $run > 0 then "gold" elif $u != [] then "sky" else "overlay" end),
              tooltip: ($st.err // "\($fail) failed, \($run) running"),
              menu: ([if $st.err then {text: $st.err} else empty end]
                + [$bad[] | {text: "Skipped, not owner/repo@branch: \(.)"}]
                + [$ev | to_entries[] | .key as $i | .value
                   | {id: "ev\($i)", tag: kind[0], color: kind[1], text: "\(.label) \(what)  \(.title)", detail: .at}]
                + (if $ev != [] then [{separator: true}] else [] end)
                + (if $ts == [] then [{text: "No open pull requests."}] else
                   [$ts | sort_by(status[2])[] | status as $s | {id: "t:\(.key)", tag: $s[0], color: $s[1], text: "\(.label)  \(.title)",
                     detail: ([.failed[].name] | join(", ") | .[:40])}] end))}}
            end
        end;
    if $mode == "poll" then
      . as $r
      | [(.data.search.nodes[]? | select(.number != null)
          | {key: "\(.repository.nameWithOwner)#\(.number)", label: "\(.repository.nameWithOwner | split("/") | last)#\(.number)",
             title, url} + (.commits.nodes[0].commit.statusCheckRollup // {} | snap)),
         ($br[] as $b | ($r.data["b\($b.i)"].object // null) as $o
          | {key: "\($b.repo)@\($b.ref)", label: "\($b.repo | split("/") | last)@\($b.ref)",
             title: (if $o == null then "not found" else "" end), url: ($o.url // "https://github.com/\($b.repo)/tree/\($b.ref)")}
            + ($o.statusCheckRollup // {} | snap))] as $ts
      # the first answer after a start is the baseline: a restart tells nothing again
      | [if $st.targets == null then empty else $ts[] as $c | ($st.targets[] | select(.key == $c.key)) as $p
         | event($p; $c) | select(wanted) | . + ($c | {key, label, title}) + {at: (now | strflocaltime("%H:%M"))} end] as $new
      | ($st + {targets: $ts, err: null, errpill: null,
          unseen: ($new + [($st.unseen // [])[] | select(.key as $k | $new | all(.key != $k))])[:10]}) as $s
      | $s, ($new[] | notify), render($s)
    elif $mode == "seen" then ($st + {unseen: [], shown: (($st.unseen // []) + ($st.shown // []))[:10]}) as $s | $s, render($s)
    elif $mode == "error" then ($st + {err: $err, errpill: (if $errpill == "" then null else $errpill end)}) as $s | $s, render($s)
    else $st, render($st) end
    JQ

    on_click() {  # event id. A row opens its failed check, or the PR or commit; an event row what it was about.
      local url
      url=$("$JQ" -r --arg id "$2" '(if ($id | startswith("ev")) then (.unseen + .shown)[$id[2:] | tonumber].url
        else .targets[] | select("t:\(.key)" == $id) | (.failed[0].url // "" | select(. != "")) // .url end) // empty' <<< "$state")
      open_url "$url"
    }

    \#(ghRun)
    """#
)
