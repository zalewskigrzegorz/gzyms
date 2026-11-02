# Gzyms for coding agents

Gzyms is a status bar for macOS. It has a bar at the top of the screen, an island that shows notifications, and a settings panel. The line above this text is the installed version. Everything below matches it.

## Pick the simplest way

1. **The CLI.** Notifications, settings and themes need no code: `gzyms notify`, `gzyms set`, `gzyms theme`. Try this first.
2. **A plugin.** Only when the CLI cannot do it: something that stays on the bar, reacts to a click, or runs in a loop. Start with `gzyms plugin new <name>` and read `gzyms skill plugins`.
3. **A feature request.** Only when neither the CLI nor a plugin can do it. Never send it yourself. Write it for the user to send to the author of Gzyms: what is missing, what you tried with the CLI and with a plugin, and why that fell short.

## Notifications: gzyms notify

```sh
gzyms notify --title "Deploy done" --body "api 1.4.2 is live" --sound success
gzyms notify --title "Tests failed" --level error --app com.mitchellh.ghostty --link "https://github.com/o/r/actions"
```

It prints the notification's id. Gzyms has to be running, else it exits 1 with a message.

| Flag | What it does |
|---|---|
| `--title <text>` | Required, except with `--compact`. |
| `--subtitle <text>` | A line under the title. |
| `--body <text>` | The text. |
| `--level <level>` | `info` (default, 6 s), `warning` (8 s), `error` (12 s), `critical` (stays until acted on), `armageddon` (takes the whole screen, use only when the user asks for it). |
| `--id <id>` | Reusing an id replaces the earlier notification with that id. Use it for progress or status that changes. |
| `--app <bundle id>` | Shows that app's icon. Opening the banner opens the app when there is no link. The user's per-app rules apply. |
| `--link <url>` | Opened when the user opens the banner. `file:` links are refused. |
| `--alt-link <url>` | Opened by the banner's second action (a shortcut). |
| `--sound <name>` | A Gzyms event: `message`, `success`, `fail`, `waiting`, `armageddon`. The user picks what each one sounds like. A macOS sound name (`Glass`, `Basso`) plays as it is. Without it, info and warning sound as `message`, error and critical as `fail`. |
| `--screen <part of a name>` | The screen to show it on (`built-in`, `dell`). Default: the focused screen. |
| `--compact` | The small island with only the app's icon. Needs `--app`. |
| `--reminder` | Stays until acted on, whatever the level. |

Short forms: `-t` `-s` `-b` `-l` `-i` `-a` `-c` `-r`. `--sound`, `--screen`, `--link` and `--alt-link` have none. `gzyms help notify` lists them side by side.

## Settings: gzyms set and gzyms unset

```sh
gzyms set appearance.animations false
gzyms set widgets.cpu false
gzyms set notifications.apps."com.mitchellh.ghostty".banner false
gzyms set calendar.points [5, 0]
gzyms unset widgets.cpu
```

The key is the dotted name as in `~/.config/gzyms/config.toml` (or `$XDG_CONFIG_HOME/gzyms/config.toml`). A value is `true`/`false`, a number, `[a, b]` or text. A wrong key or value writes nothing and exits 1 with the problem. `gzyms unset <key>` puts the default back. The running bar applies a change at once. Run `gzyms set` alone for its usage.

## Themes: gzyms theme

- `gzyms theme` prints the current theme.
- `gzyms theme --list` lists every theme.
- `gzyms theme <name>` switches to it.

## Other commands

- `gzyms settings [tab]` opens the settings panel, on a tab when given (a wrong tab lists them). In it `h`/`l` switch tabs, `j`/`k` walk the switches and menus, Enter or `o` flips one, Esc closes; a text field keeps its keys.
- `gzyms keys on|off` turns the keyboard mode on or off: hints over the bar, then j/k, Enter, x, a (second action) and Esc in a popup. Its own leader is `[keys] leader`.
- `gzyms dnd on [minutes]|off` turns Do Not Disturb on (for good, or for that many minutes) or off, the same as the moon pill on the bar. Banners then go quietly to their lists and counts, the phone push still works. `[dnd] breaks_through` lists what still shows: `armageddon`, `meetings` (the default pair) and `critical`.
- Notifications from other apps (Slack, Mail, WhatsApp) come from macOS's Notification Center. Opening one in Gzyms opens the exact chat, thread or event, as the original would. It is a trick, not an Apple API: Gzyms opens the Notification Center panel with globe+N, moves it off screen, and presses the original there through Accessibility. Only the app that sent a notification gets its data (the thread id and so on), so there is no other way. It needs the app's "Notification Center" box ticked in System Settings → Notifications, and "Desktop" and "Play sound for notification" off, so nothing shows or sounds twice ("Lock Screen" does not matter). It also needs Accessibility and the globe+N shortcut. In Settings → Apps a warning next to an app says what is off ("Notification Center off", "Desktop on", "Sound on"), and its gear opens that app's macOS page. Mail cannot be set up for it: Settings → Apps says so, and a click opens just Mail. A macOS update can break it. Then Gzyms just opens the app. `[notifications] open_original = false` (Settings → Apps → "Open the exact chat") turns it off: opening then just opens the app.
- The banner stack holds one on screen and three waiting. More wait in their app's list (counted at once) and come up in order as room frees. A banner sounds when it enters the stack. `[notifications] priority` lists what sounds at once even while it waits: `armageddon`, `critical` (the default pair) and `meetings`.

## Keyboard: [keys]

- `[keys] leader` turns the keyboard mode on: an F key (`"f19"`, tap it, or hold it and press a letter), a chord (`"ctrl+alt+g"`, the default), a lone modifier (`"ctrl"`, `"alt"`, `"cmd"`: tap it alone; held, it takes only the banner's letters while a banner is up) or `"off"`.
- With a banner up, the mode's letters act on it: `o` open, `x` dismiss (gone for good; only a banner left to expire waits in its app's list), `a` second action (none: the banner says so, nothing is removed), `z` snooze (`zz` `zzz` `zzzz` for 5, 10, 30 min), `n`/`j` next and `p`/`k` previous waiting banner.
- In an open notification list (an app's or the 🔔's), `dd` is Clear all. Other popups ignore it.
- `[keys.verbs]` changes those letters: `open`, `dismiss`, `snooze`, `alt`, `next`, `prev`, `clear`, one letter each, not `h j k l f`. None of them is ever a hint letter. It replaces `[notifications.letters]`; that one and `[notifications] hold` and `keys` are still read but reported as old.
- No leader needed: Enter or the `open` letter opens an armageddon (no key dismisses it); in the meeting preview `c` `m` `s` step camera, mic, speakers, `t` plays a test sound, Enter or `o` joins, Esc closes.
- `[audio] banned` lists audio devices by exact name (`banned = ["Alex iPhone  Microphone"]`, or "Banned" in Settings → Appearance → Device icons). The bar's sound and mic popups and the meeting preview leave them out, `m` and `s` skip them, and a banned iPhone takes its Continuity camera with it. One that macOS picked by itself still shows, dimmed. Meeting apps follow it only when they use the system default device.
- `[keys] idle_timeout` (seconds, `0` = never) ends a forgotten mode, `[keys] hint_chars` sets the hint letters.
- `gzyms hud` opens the system HUD, a second call closes it.
- `gzyms report` puts a zip with the log, the config and the grants on the Desktop. Ask the user before sending it anywhere.
- `gzyms --version` (`-v`) prints the version. `gzyms theme -l`, `--yes` as `-y` and `--agents` as `-a` work too.
- `gzyms help [command]` lists the commands, or one command's flags. `gzyms completions install [shell]` turns on tab completion (it asks first), `gzyms completions <shell>` only prints the script.
- `gzyms skill` prints this guide. `gzyms skill plugins` prints the plugin guide.
- `gzyms skill install` puts a short SKILL.md for Claude Code (and Codex when `~/.agents` exists, or with `--agents`) that points here. It lists the paths and asks first, `--yes` skips the question.

## After the task: offer a short retro

When a task with Gzyms is done (a plugin written, notifications wired up), ask the user once whether to prepare a short retro for the author of Gzyms. It covers where you struggled: something missing from these docs, an unclear part of the plugin protocol, errors, workarounds.

- On a yes, write it as a mail to gzyms@mrglaszki.com: a subject and a body ready to send, or a `mailto:` link with both filled in.
- Show the user the whole text first. It is sent only after their clear yes, and by them. You never send it yourself.
- A no means no: do not ask again in this session.
- Leave out secrets, tokens, home paths, notification text and anything private. Name the Gzyms version (`gzyms --version`).
