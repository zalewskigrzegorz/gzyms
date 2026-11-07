# Gzyms

Before you change anything a user sees (Settings, a popup, a banner, a pill, CLI output), read the Interface section in CONTRIBUTING.md and follow it. Run `scripts/check.sh` before you call a change done.

Neighbouring repos: `~/Code/personal/gzyms-claude-plugin` (the public Claude Code plugin) and `~/Code/personal/gzyms-site` (gzyms.dev and the appcast). Every plugin change bumps `version` in its `.claude-plugin/plugin.json` (not verified that the marketplace needs it to update).

Release: `whatsnew/<version>.md`, then `scripts/release.sh <empty out folder>`, then the steps it prints (GitHub release, `appcast.xml` into `gzyms-site/site/` and `wrangler deploy`, tap push). A published version is never replaced: a new zip under the same number breaks the cask's sha256 and the appcast signature, so a fix ships as the next version.
