<div align="center">

<img src="assets/readme/icon.png" alt="Gzyms icon" width="128" height="128">

# gzyms

**A status bar for macOS developers drowning in notifications.**<br>
Glance, decide, move on.

[![Release](https://img.shields.io/github/v/release/zalewskigrzegorz/gzyms?color=b347ff)](https://github.com/zalewskigrzegorz/gzyms/releases/latest)

### [gzyms.dev](https://gzyms.dev)

https://github.com/user-attachments/assets/07ceddb4-2f56-4507-94c6-1b8b11555673

Works with [HyprMac](https://hyprmac.app): your workspaces and their apps live on the bar. [More tiling managers](https://gzyms.dev/docs/#tiling) are on the way.

</div>

## Install

```sh
brew install zalewskigrzegorz/tap/gzyms
```

Or download the zip from [Releases](https://github.com/zalewskigrzegorz/gzyms/releases/latest) and move Gzyms to Applications.

You need:

- macOS 26 on Apple Silicon
- Accessibility, for banner keys and Dock badges
- Full Disk Access, for notifications from other apps

A wizard asks for both on first launch. It is an early release, so expect rough edges.

## What it does

<img src="assets/readme/banner.png" alt="A banner with its key hints: o open, x dismiss, z snooze" width="420" align="right">

### Notifications

- [Five levels](https://gzyms.dev/docs/#levels). Info fades in 6 s. Critical waits for you. Armageddon turns the whole screen red until you click.
- [One banner at a time](https://gzyms.dev/docs/#stack). A burst of five? One banner, the rest wait in the order they came. Only armageddon cuts in.
- [Slack and WhatsApp, at once](https://gzyms.dev/docs/#instant-banners). Their banners land on the bar in under half a second. A click opens the exact chat or thread.
- [Snooze that comes back](https://gzyms.dev/docs/#snooze) as a reminder that stays until you deal with it.
- [Nothing gets lost](https://gzyms.dev/docs/#inbox). Banners you skip wait in a list under the app's icon. A bell holds the rest.
- [Rules per app](https://gzyms.dev/docs/#rules). Banner or just a count, sound or silence, raise it to critical.
- [Do Not Disturb](https://gzyms.dev/docs/#dnd). One click on the moon and banners go quiet. Everything still lands in its list.
- [Meetings](https://gzyms.dev/docs/#meetings). A meeting with a link gets a banner that won't go away. Check camera and mic, hit Enter to join.
- [Away from the Mac](https://gzyms.dev/docs/#phone). A banner nobody touched for 5 min goes out to ntfy, Pushover or any webhook.

### For developers

- [One CLI](https://gzyms.dev/docs/#cli). `gzyms notify --id deploy` updates one banner as your deploy moves. The config is one TOML file, keep it in your dotfiles.
- [Plugins are a small script](https://gzyms.dev/docs/#plugins). Any language, JSON on stdout. Every option you declare becomes a field in Settings.
- [GitHub on the bar](https://gzyms.dev/docs/#github). Your PRs to fix or merge, comments waiting, and a ping when CI fails or goes green.
- [Your agents on one pill](https://gzyms.dev/docs/#agents). Each agent's row says what it waits for, a click takes you there. tuios and Claude Code today.
- [Log watcher](https://gzyms.dev/docs/#log-watcher). Watches your logs and fires a banner, or armageddon, when a line matches.

### The bar

- [Tiling or not](https://gzyms.dev/docs/#tiling). Workspaces come from HyprMac. Without a tiling manager the bar shows one desktop with your Dock apps.
- [System pills](https://gzyms.dev/docs/#pills). CPU with top processes, memory, network that warns about a stray proxy, a battery that says the charger is too weak, caffeine, now playing.
- [The file shelf](https://gzyms.dev/docs/#shelf). Drop a file under the notch, it waits there. Drag it out where you need it.
- [⌃⌥M mutes the mic](https://gzyms.dev/docs/#mic) in every app. The pill shows the level, so you know it worked.
- [Command palette](https://gzyms.dev/docs/#palette). One search for settings, actions, themes and your notifications.
- [105 themes](https://gzyms.dev/docs/#settings), from Mocha Neon to Gruvbox Light.
- [No telemetry](https://gzyms.dev/docs/#telemetry). gzyms sends nothing home on its own.

## Keys

Every banner shows its keys, so you never have to remember them.

| Keys | What happens |
|------|--------------|
| <kbd>o</kbd> <kbd>x</kbd> <kbd>z</kbd> | Open, dismiss or snooze the banner |
| <kbd>n</kbd> <kbd>p</kbd> | Walk through the banners that wait |
| Leader, then <kbd>j</kbd> <kbd>k</kbd> <kbd>Enter</kbd> | A letter over every pill. Move, open, <kbd>x</kbd> clears, <kbd>Esc</kbd> leaves |
| Leader, then <kbd>Space</kbd> | Command palette. `dnd 30` works too |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>M</kbd> | Mute the mic in every app |

More in the [keyboard docs](https://gzyms.dev/docs/#keyboard).

## Feedback

Something broken, an idea or a question? Open a [Discussion](https://github.com/zalewskigrzegorz/gzyms/discussions): Problems, Ideas or Q&A. Issues are the to-do list, so a confirmed problem or a picked idea becomes one from there.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Before you open a PR, run `scripts/check.sh`. It runs a release build and all tests, and ends with `ALL GREEN`.

## License

MIT, see [LICENSE](LICENSE).

## Credits

- [NotificationNanny](https://github.com/chessper53/NotificationNanny): reading and hiding macOS notification banners, portions adapted. MIT, Copyright (c) 2026 chessper53.
- [Sparkle](https://github.com/sparkle-project/Sparkle): updates.
- [TOMLDecoder](https://github.com/dduan/TOMLDecoder): config parsing.
