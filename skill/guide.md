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
| `--alt-link <url>` | Opened by the banner's second action (a shortcut, a right click or a two-finger click). |
| `--alt-label <text>` | The second action's name on the banner's hints, e.g. `Open in agent`. Without it the hint says `alt`. |
| `--sound <name>` | A Gzyms event: `message`, `success`, `fail`, `waiting`, `armageddon`. The user picks what each one sounds like. A macOS sound name (`Glass`, `Basso`) plays as it is. Without it, info and warning sound as `message`, error and critical as `fail`. |
| `--screen <part of a name>` | The screen to show it on (`built-in`, `dell`). Default: the focused screen. |
| `--compact` | The small island with only the app's icon. Needs `--app`. |
| `--reminder` | Stays until acted on, whatever the level. |

Short forms: `-t` `-s` `-b` `-l` `-i` `-a` `-c` `-r`. `--sound`, `--screen`, `--link`, `--alt-link` and `--alt-label` have none. `gzyms help notify` lists them side by side.

## Reading notifications: gzyms notifications

Run `gzyms notifications --json` before you guess what the user sees: when they mention "that notification", a banner, a waiting one, or ask why something did not show. It works with the bar off.

```sh
gzyms notifications            # grouped, the text cut to one line
gzyms notifications --json     # every field in full
gzyms notifications dismiss <id>
gzyms notifications clear      # empties every list; banners in the stack stay
```

Each row has `id`, `source` (an app's bundle id, `plugin:<folder>`, `meeting`, or `bell` for one with no app), `level`, `title`, `subtitle`, `body`, `at`, `place` and `position`. `place` is `stack` (position 1 is on screen, the rest wait in the stack), `waiting` (no room in the stack yet, in the order they come up), `list` (in its app's list) or `snoozed` (`back` says when it returns). `heard` says whether its sound played. `dnd` is set while Do Not Disturb is on. The small app-icon island that shows before a text arrives is never listed. The text is the user's private data: do not quote it outside the conversation, and dismiss or clear only when they ask. `gzyms hud` shows the same stack and waiting line on its Queues tab.

## Asking the running bar: gzyms debug

Run `gzyms debug` when something does not show or a key does nothing, before you guess. The running bar holds Full Disk Access and Accessibility, so it answers for you: one fact per line, never the text of a notification. It needs the bar running.

```
gzyms debug                  # notifications and keys
gzyms debug notifications    # how Gzyms reads macOS banners
gzyms debug keys             # the key tap and the keyboard mode
gzyms debug cpu              # what the bar costs right now (measures for 3 s)
gzyms debug --json           # one flat object, every value a string
```

- `cpu`: run it when Gzyms uses CPU while nothing moves on screen, before you restart it (a restart hides the cause). `cpu.percent` is the process over 3 s. `cpu.main_wakeups_per_s` is how often the main thread woke: a few per second is idle, 60 or more means an animation or a timeline runs every frame, and `cpu.hint` then says so. `cpu.panel_rebuilds` counts bar panels built again. `cpu.busy` lists the animations, timelines and timers running now (`settings: about cat, 30 fps`, `mic meter`, `system settings watch, every 1 s`). One `window.<kind>` line per kind of window says whether each is `on screen`, `covered` or `hidden`. A `cpu.busy` entry that belongs to a hidden window is the usual leak: SwiftUI keeps animating in a window that was only put away.

- `notifications`: the switches that matter (`config.banner_ax`, `config.open_original`, `config.signal`, `config.nc_auto_restart`), the Accessibility and Full Disk Access grants, whether the observer is attached to Notification Center (and its pid), whether the panel is open, whether the host window is parked off screen and by Gzyms, the last banner (app, how long ago, `via ax` or `via database`), the banner guard (deliveries counted with no banner after them, `guard.warns`), Notification Center restarts by Gzyms (`nc_restart.count`, `nc_restart.last`, `nc_restart.awaiting_banner`, `nc_restart.gave_up`), Do Not Disturb, and one `app.<bundle id>` line per app with what macOS says: `allow`, `banners` (temporary, persistent, off), `center`, `sound`, `previews`, and `problems:` when something there keeps Gzyms from reading its banner.
- `keys`: whether the tap exists and is enabled, how often macOS switched it off (`tap.disabled_by_macos`, with the reason, then Gzyms switches it on again), Secure Keyboard Entry (`secure_input`, and while it is held `secure_input.owner`, the process holding it, and how long), the leader, whether the mode is on, a popup open, a banner up, the frontmost app, and whether a Gzyms window is the key window.
- A tap switched off by macOS, or Secure Input held for a minute, also lands in `anomalies.jsonl` (`tap_disabled`, `secure_input_long`).
- Two or more apps sending the same text within 10 s land there as `duplicate_apps` (`apps`: bundle ids, `count`), never with the text. Gzyms then posts one notification per new pair of apps ("Apps send the same notification"), which opens Settings → Debug. There the apps are listed with how often and when last, each with a button to its macOS notification page, a Forget button and a switch to stop the notifications. Gzyms does not drop anything itself.

## Settings: gzyms set and gzyms unset

```sh
gzyms set appearance.animations false
gzyms set appearance.banner_entry pop
gzyms set widgets.cpu false
gzyms set notifications.apps."com.mitchellh.ghostty".banner false
gzyms set calendar.points [5, 0]
gzyms unset widgets.cpu
```

The key is the dotted name as in `~/.config/gzyms/config.toml` (or `$XDG_CONFIG_HOME/gzyms/config.toml`). A value is `true`/`false`, a number, `[a, b]` or text. A wrong key or value writes nothing and exits 1 with the problem. `gzyms unset <key>` puts the default back. The running bar applies a change at once. Run `gzyms set` alone for its usage.

Phone push secrets are not in config.toml: `notifications.phone.url` (the ntfy topic or webhook address), `notifications.phone.pushover_user` and `notifications.phone.pushover_token` live in the macOS login Keychain. Set them in Settings → Notifications (Change, then Enter) or with `gzyms set` and no value, so the secret stays out of shell history and `ps`: `pbpaste | gzyms set notifications.phone.pushover_token` reads one line from the pipe, and `gzyms set notifications.phone.url` on a terminal asks with a hidden prompt. `-` as the value does the same, and an inline value still works. `gzyms unset` on one of them deletes it from the Keychain. Neither prints the value. The rest of `[notifications.phone]` (`format`, `after`, `levels`) stays in config.toml. One of the three keys left in config.toml is ignored and shows as a config problem.

Coding agents (Settings → Agents) are built in, one switch per source: `agents.tuios` (the agents tuios sees) and `agents.claude` (Claude Code sessions, through the Gzyms Claude Code plugin: `gzyms agents install claude`, or Install in Settings → Agents → Claude Code). Both are on by default. `agents.done_after` (minutes, default 3) is the shortest run that notifies when it ends, `agents.terminal` (default `Ghostty`) is the app tuios runs in. Each agent gets one row on the agents pill, what waits for you first with its question. It notifies once when it starts to wait and once when a long run ends, and the notification goes when the agent moves on. A Claude session in a tuios pane shows only through tuios.

How a banner arrives: `appearance.banner_entry` is `icon`, `drop` (the default), `notch`, `unroll`, `pop` or `fade`. `appearance.animation_speed` is `slow`, `normal` (the default) or `fast`. With `appearance.animations false` nothing moves. Under macOS Reduce motion every entry is a fade, unless `appearance.follow_reduce_motion` is false.

## Themes: gzyms theme

- `gzyms theme` prints the current theme.
- `gzyms theme --list` lists every theme.
- `gzyms theme <name>` switches to it.

## Other commands

- `gzyms settings [tab]` opens the settings panel, on a tab when given (a wrong tab lists them). In it `h`/`l` switch tabs, `j`/`k` walk the switches and menus, Enter or `o` flips one, Esc closes; a text field keeps its keys.
- `gzyms keys on|off` turns the keyboard mode on or off: hints over the bar, then j/k, Enter, x, a (second action) and Esc in a popup. Its own leader is `[keys] leader`.
- `[workspaces] source` picks where the bar's workspaces come from: `auto` (the default: HyprMac, else AeroSpace, else macOS Spaces), `hyprmac`, `aerospace` or `spaces` (Settings → General → "Workspaces from"). AeroSpace is read with its CLI every 3 s. For instant switches add `exec-on-workspace-change = ['/bin/bash', '-c', 'gzyms workspaces refresh']` to `~/.aerospace.toml`. AeroSpace names that are not 1 to 10 take the free numbers, the bar prints the name. macOS Spaces shows desktops (not full-screen apps). A click there presses the "Switch to Desktop N" shortcut when it is on in System Settings → Keyboard → Keyboard Shortcuts → Mission Control, else opens Mission Control.
- `gzyms dnd on [minutes]|off` turns Do Not Disturb on (for good, or for that many minutes) or off, the same as the moon pill on the bar. Banners then go quietly to their lists and counts, the phone push still works. `[dnd] breaks_through` lists what still shows: `armageddon`, `meetings` (the default pair) and `critical`.
- Notifications from other apps (Slack, Mail, WhatsApp) come from macOS's Notification Center. Gzyms reads each macOS banner through Accessibility the moment it shows (under half a second) and moves the real banner off screen, so only Gzyms's shows. The Notification Center database is the backup: it brings apps that show no banner, a few seconds later, under the same id, so nothing shows twice. Opening one in Gzyms opens the exact chat, thread or event, as the original would: Gzyms presses the macOS banner while it is up, and once it is gone, its row in the Notification Center panel, which it opens with 🌐 N and hides off screen. Only the app that sent a notification gets its data (the thread id and so on), so there is no other way. The count on an app's icon on the bar has three colours: red is the app's own Dock badge (only the app zeroes it, clearing in Gzyms does not), sky is Gzyms's list, mauve is both, and then it shows their sum. It is always the real number (up to `99+`), in a smaller font the more digits it has. Each app needs, in System Settings → Notifications: "Desktop" on (banners or alerts), "Notification Center" on, "Show previews" not Never (set it once at the top of Notifications to Always or When Unlocked, apps on Default follow it), and "Play sound for notification" off, because Gzyms plays its own ("Lock Screen" and "Badge" do not matter). It also needs Accessibility, Full Disk Access and the 🌐 N shortcut (System Settings → Keyboard → Keyboard Shortcuts → Mission Control → Show Notification Center). In Settings → Apps a warning next to an app says what is off ("Banners off", "Notification Center off", "Previews off", "Sound on"), and its gear opens that app's macOS page. NotificationNanny must not run at the same time. A macOS update can break the trick. Then the text comes from the database a few seconds later, and Gzyms just opens the app. `[notifications] banner_ax = false` (Settings → Hacks → "Instant banners") stops reading and hiding the banners. `[notifications] open_original = false` ("Open the exact chat") makes opening just open the app. `[notifications] signal = false` ("Instant app icons") stops the app icon that shows before the text. When apps send notifications and Notification Center shows no banner, Settings → Hacks → "Restart a hung Notification Center" restarts it with a button (`killall NotificationCenter`, macOS starts it again, nothing is lost, the screen flickers for a second). `[notifications] nc_auto_restart = true` (the switch there, off by default) does it by itself, at most once in 10 minutes and once per hang: if no banner shows after it, Gzyms warns and stops. Each restart is in the anomaly log. A macOS Focus (Sleep, Work, Do Not Disturb) holds every banner back on purpose: then nothing is instant, the text comes from the database a few seconds later, and the guard does not count it as a hung Notification Center. Turn the Focus off and banners are instant again.
- Updates: Gzyms checks for updates by itself (Sparkle) when it came from the website. Installed with Homebrew (`brew install --cask gzyms`, found by `Caskroom/gzyms` under `/opt/homebrew` or `/usr/local`), it does not: `brew upgrade gzyms` updates it. Settings → About → "Automatic updates" turns Sparkle on or off either way, and on a Homebrew install it warns that Sparkle and brew can both update the app, which can break an update. `[updates] automatic = true` or `false` is written only when it differs from that default. With Sparkle off, a Homebrew install still reads the appcast about once a day and installs nothing. A newer version gives one notification per version ("Gzyms 0.0.3 is out", a click opens the GitHub release), and Settings → About shows "Update to 0.0.3" with Copy for `brew upgrade gzyms` and the release link.
- Settings → Hacks lists everything that rides on a private macOS API or a trick, with its state. `[hacks] browser_media = true` starts a server on 127.0.0.1:47100 for the userscript at http://127.0.0.1:47100/gzyms-media.user.js (Tampermonkey): browser tabs with video then show in the music pill and popup with play, pause, next and Go to. A tab is one entry (what plays, else what played last); calls (Meet, Zoom, Teams, any WebRTC stream) and muted autoplay previews stay out. It pairs with `media.hardwaremediakeys.enabled = false` in a Firefox-based browser, so the media keys reach the music player. Docs: https://gzyms.dev/docs/#hacks
- The banner stack holds one on screen and three waiting, in the order they arrived. The level never reorders them: a banner on screen runs its time out, and a warning, an error or a critical waits its turn behind it. Only an armageddon takes the screen at once. More wait in their app's list (counted at once) and come up in order as room frees. A banner sounds when it enters the stack. `[notifications] priority` lists what sounds at once even while it waits: `armageddon`, `critical` (the default pair) and `meetings`. `[notifications] keep` (Settings → Notifications → "Keep in the lists") drops list rows older than `hour`, `day` or `week`, checked once a minute. Missing or `forever` keeps them all, the default. The stack and the snoozed are never cut: a snoozed one comes back on time, and once filed it ages from when it first arrived.
- On the banner: a two-finger click is the second action, a long sideways two-finger swipe dismisses it, an up or down swipe steps through the waiting ones. With the pointer over it the hints show and each one can be clicked. A dismissed banner plays `[sounds] dismiss`.

## Keyboard: [keys]

- `[keys] leader` turns the keyboard mode on: an F key (`"f19"`, tap it, or hold it and press a letter), a chord (`"ctrl+alt+g"`, the default), a lone modifier (`"ctrl"`, `"alt"`, `"cmd"`: tap it alone; held, it takes only the banner's letters while a banner is up) or `"off"`.
- With a banner up, the mode's letters act on it: `o` open, `x` dismiss (gone for good; only a banner left to expire waits in its app's list), `a` second action (none: the banner says so, nothing is removed), `z` snooze (`zz` `zzz` `zzzz` for 5, 10, 30 min), `n`/`j` next and `p`/`k` previous waiting banner.
- In an open notification list (an app's, the 🔔's, or a plugin pill's), `dd` is Clear all. Other popups ignore it.
- `[keys.verbs]` changes those letters: `open`, `dismiss`, `snooze`, `alt`, `next`, `prev`, `clear`, one letter each, not `h j k l f`. None of them is ever a hint letter. It replaces `[notifications.letters]`; that one and `[notifications] hold` and `keys` are still read but reported as old.
- No leader needed: Enter or the `open` letter opens an armageddon (no key dismisses it); in the meeting preview `c` `m` `s` step camera, mic, speakers, `t` plays a test sound, Enter or `o` joins, Esc closes.
- `[audio] banned` lists audio devices by exact name (`banned = ["Alex iPhone  Microphone"]`, or "Banned" in Settings → Appearance → Device icons). The bar's sound and mic popups and the meeting preview leave them out, `m` and `s` skip them, and a banned iPhone takes its Continuity camera with it. One that macOS picked by itself still shows, dimmed. Meeting apps follow it only when they use the system default device.
- `[keys] idle_timeout` (seconds, `0` = never) ends a forgotten mode, `[keys] hint_chars` sets the hint letters.
- `gzyms hud` opens the system HUD, a second call closes it.
- The bar logs to `~/Library/Logs/Gzyms/gzyms.log`. Past 5 MB it moves to `gzyms.log.1`, checked at start and once a day. CLI commands print in the terminal, not into that file.
- `gzyms report` puts a zip with the log, the config and the grants on the Desktop. Ask the user before sending it anywhere.
- `gzyms --version` (`-v`) prints the version. `gzyms theme -l`, `--yes` as `-y` and `--agents` as `-a` work too.
- `gzyms help [command]` lists the commands, or one command's flags. `gzyms completions install [shell]` turns on tab completion (it asks first), `gzyms completions <shell>` only prints the script.
- `gzyms agents status` prints which agent sources are on and whether the Gzyms Claude Code plugin is installed (`Installed, 0.1.1`, `Not installed`, `Off in Claude Code`, `Claude Code not found`).
- `gzyms agents install claude` installs that plugin through Claude Code's own CLI: `claude plugin marketplace add zalewskigrzegorz/gzyms-claude-plugin`, then `claude plugin install gzyms@gzyms` (and `claude plugin enable gzyms@gzyms` when it was off). It prints one line per step. A second run is safe. New Claude sessions pick it up, open ones need a restart or `/reload-plugins`. `gzyms agents remove claude` runs `claude plugin uninstall gzyms@gzyms` and leaves the marketplace. A failed step exits 1 with Claude's own line. Without Claude Code it says so and does nothing. Settings → Agents → Claude Code has the same Install or Remove button.
- `gzyms skill` prints this guide. `gzyms skill plugins` prints the plugin guide.
- `gzyms skill install` puts a short SKILL.md for Claude Code (and Codex when `~/.agents` exists, or with `--agents`) that points here. It lists the paths and asks first, `--yes` skips the question.

## After the task: offer a short retro

When a task with Gzyms is done (a plugin written, notifications wired up), ask the user once whether to prepare a short retro for the author of Gzyms. It covers where you struggled: something missing from these docs, an unclear part of the plugin protocol, errors, workarounds.

- On a yes, write it as a mail to gzyms@mrglaszki.com: a subject and a body ready to send, or a `mailto:` link with both filled in.
- Show the user the whole text first. It is sent only after their clear yes, and by them. You never send it yourself.
- A no means no: do not ask again in this session.
- Leave out secrets, tokens, home paths, notification text and anything private. Name the Gzyms version (`gzyms --version`).
