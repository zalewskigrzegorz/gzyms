<div align="center">

<img src="assets/readme/icon.png" alt="Gzyms icon" width="128" height="128">

# gzyms

**A status bar for macOS developers drowning in notifications.**<br>
Glance, decide, move on.

[![Release](https://img.shields.io/github/v/release/zalewskigrzegorz/gzyms?color=b347ff)](https://github.com/zalewskigrzegorz/gzyms/releases/latest)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-8be9fd)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Homebrew tap](https://img.shields.io/badge/brew-zalewskigrzegorz%2Ftap-fbb040)](https://github.com/zalewskigrzegorz/homebrew-tap)

[gzyms.dev](https://gzyms.dev)

<img src="assets/readme/bar.png" alt="The gzyms bar: app counts, GitHub pull requests and builds, CPU, memory, network, battery and the clock" width="900">

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

A wizard asks for both on first launch. This is 0.0.1, so expect rough edges.

## What it does

<img src="assets/readme/banner.png" alt="A banner with its key hints: o open, x dismiss, z snooze" width="420" align="right">

- [Five notification levels](https://gzyms.dev/docs/#levels), from a quiet count to a full-screen alert.
- [One banner at a time](https://gzyms.dev/docs/#stack). The rest wait in a queue.
- [Rules per app](https://gzyms.dev/docs/#rules), and a bell with a list for what you skipped.
- [Keys first](https://gzyms.dev/docs/#keyboard). Open, dismiss and snooze without the mouse.
- [One CLI](https://gzyms.dev/docs/#cli) for scripts and coding agents.
- [Plugins that are a small script](https://gzyms.dev/docs/#plugins), in any language.
- [GitHub pull requests and builds](https://gzyms.dev/docs/#github) and [your coding agents](https://gzyms.dev/docs/#agents) as pills on the bar.

No telemetry.

## Feedback

Something broken, an idea or a question? Open a [Discussion](https://github.com/zalewskigrzegorz/gzyms/discussions): Problems, Ideas or Q&A. Issues are the to-do list, so a confirmed problem or a picked idea becomes one from there.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Before every deploy run `scripts/check.sh`. It runs a release build and all tests, and ends with `ALL GREEN`.

## License

MIT, see [LICENSE](LICENSE).

## Credits

- [NotificationNanny](https://github.com/chessper53/NotificationNanny): reading and hiding macOS notification banners, portions adapted. MIT, Copyright (c) 2026 chessper53.
- [Sparkle](https://github.com/sparkle-project/Sparkle): updates.
- [TOMLDecoder](https://github.com/dduan/TOMLDecoder): config parsing.
