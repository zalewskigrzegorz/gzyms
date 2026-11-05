# Writing a Gzyms plugin

A plugin is a folder with a `plugin.toml` and a program in any language. Gzyms starts the program, reads JSON lines from its stdout and writes JSON lines to its stdin. Use one only when the CLI is not enough (see `gzyms skill`).

## Commands

- `gzyms plugin new <name>` makes `~/.config/gzyms/plugins/<name>/` with a working click counter in bash. Start from it. The name is lowercase letters, digits, `-` and `_`.
- `gzyms plugin list` lists the plugins with `on`, `off` or `broken` and why.
- `gzyms plugin add <name>` installs a ready plugin from the built-in catalog. Without a name it lists them: `log-watcher` (log lines to notifications), `agents` (coding agents from tuios), `gh-prs` (your pull requests through the gh CLI: a glyph per state, fix, merge, comments and draft, with the number of PRs in it) and `gh-builds` (CI of your pull requests and chosen branches: a glyph for failed and one for running, with the number of PRs or branches). Each is a plain script you can read and change after `add`.
- `gzyms plugin remove <name>` moves the folder to the Trash.

Gzyms watches the plugins folder, so a new or removed folder needs no restart. Gzyms keeps running the program it started: after editing it, turn the plugin off and on with `gzyms set plugins.<name>.enabled false` and then `gzyms set plugins.<name>.enabled true` (or in Settings → Plugins).

## plugin.toml

```toml
name = "PR watch"
description = "Open pull requests on one pill."
command = "./plugin.sh"
icon = "arrow.triangle.pull"

[[option]]
key = "repos"
title = "Repos"
type = "list"
default = ["owner/repo"]
note = "one owner/repo per line"

[[option]]
key = "style"
title = "Style"
type = "choice"
choices = ["short", "long"]
default = "short"
```

- `command =` is required. It runs with `/bin/sh -c` inside the plugin's folder, so `./plugin.sh` needs to be executable (`chmod +x`).
- `name =` defaults to the folder name. `icon =` is an SF Symbol name.
- Each `[[option]]` becomes a field in Settings → Plugins, no UI code needed. `key =` is lowercase letters, digits and `_`, and `enabled` is taken. `type =` is `toggle`, `choice` (with `choices =`), `text` (default), `number` or `list`. `title =`, `default =` and `note =` are optional.
- The user's values live in config.toml as `[plugins.<name>]`, so `gzyms set plugins.<name>.<key> <value>` sets one. A change restarts the plugin.

## Environment

- `GZYMS_PLUGIN`: the folder name.
- `GZYMS_OPT_<KEY>`: each option, the user's value or the default. A list has one item per line, a toggle is `true` or `false`.
- `GZYMS_OPTIONS`: all options as one JSON object.

## Plugin to Gzyms: stdout, one JSON object per line

A pill on the bar. A line with the same `"id"` updates it.

```json
{"item":{"id":"prs","text":"3 open","icon":"arrow.triangle.pull","color":"green","tooltip":"3 pull requests wait for review"}}
```

`"color"` is a theme colour name (`green`, `peach`, `red`, `gold`, `sky`, `mauve`) or a hex. In `"text"`, and in a menu row's `"tag"`, `"text"` and `"detail"`, `:name:` with an SF Symbol name inside draws that symbol in the text's colour: `":xmark.circle: 2 :clock: 1"`. Use it instead of emoji, so the pill looks like the rest of the bar. Remove a pill:

```json
{"item":{"id":"prs","remove":true}}
```

A pill with `"menu"` opens a list on click. A row with an `"id"` can be clicked, a row without one is a label, `"separator":true` draws a line. `"tag"` is a coloured tag on the left, `"detail"` sits on the right.

```json
{"item":{"id":"prs","text":"3 open","menu":[{"id":"pr:12","tag":"review","color":"peach","text":"#12 fix login","detail":"2h"},{"separator":true},{"text":"updated just now"}]}}
```

A notification, with the same fields as `gzyms notify`. Its `"level"` is one of `info`, `warning`, `error`, `critical`, `armageddon`. A notification with the same `"id"` replaces the earlier one from this plugin. `"sound"` is an event name (`message`, `success`, `fail`, `waiting`), a macOS sound name, or a path to an audio file (`.mp3`, `.m4a`, `.wav`, `.aiff`).

```json
{"notify":{"id":"deploy","title":"Deploy done","subtitle":"api","body":"1.4.2 is live","level":"info","sound":"success","link":"https://example.com"}}
```

A second action: `"alt_label"` names it on the banner's hints, `"alt_link"` is the URL it opens. With `"alt_label"` and no `"alt_link"`, the second action sends `notify_alt` back to the plugin, so the plugin does the work itself.

```json
{"notify":{"id":"agent-3","title":"Agent waits","alt_label":"Open in agent"}}
```

## Gzyms to plugin: stdin, one JSON object per line

```json
{"event":"click","id":"prs"}
```

`"event"` is one of:

- `"click"` and `"right_click"`: on a pill without a menu, or on a menu row (the row's id).
- `"open"`: its menu opened, a good moment to refresh.
- `"notify_open"`: the user opened one of its notifications that has no link (the id is the plugin's own).
- `"notify_alt"`: the user took the second action of one of its notifications that has `"alt_label"` and no `"alt_link"` (the id is the plugin's own).

## Rules

- Print only when something changed. Gzyms redraws on every line.
- When stdin ends, Gzyms is gone: exit.
- Long work (network, a slow command) runs in the background, so clicks are still read.
- A plugin that exits is started again after 1 s, 2 s, 4 s and so on, up to a minute.
- A line that is not a message, and the first 20 lines of stderr, go to `~/Library/Logs/Gzyms/gzyms.log` as `plugin <name>: …`. Read it when a pill does not show up.
