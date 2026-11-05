# Contributing

Start in [Discussions](https://github.com/zalewskigrzegorz/gzyms/discussions): Problems for bugs, Ideas for features. An issue gets opened from the discussion once it is confirmed or picked.

Run `scripts/check.sh` before every deploy. It ends with `ALL GREEN`.

## Feature list

`features.json` is a hand-kept list of what a user can do with Gzyms. The count on gzyms.dev comes from it.

- A new feature a user can name and use gets a new entry in `features.json`, in the same commit.
- Bump `count` to the length of the list and `updated` to today.
- Fixes, refactors, tests and dev tools do not count.
- `scripts/check.sh` fails when `count` and the list disagree.

## Interface

Gzyms is built for people who get lost in walls of text and in screens full of switches, people with ADHD first. Every screen follows these rules.

- **One line per row.** A row says what the thing does for you, plus its live state if it has one. How it works goes to the docs on gzyms.dev, behind a Docs link.
- **Details on demand.** A list shows names, a switch and a state. Options open when you pick a row, in a drawer, like Settings → Apps. Nothing long is open by default.
- **One decision at a time.** A dialog asks one thing. A wizard shows one step.
- **Short words.** Short sentences. No `;` and no `—` in UI text.
- **Errors stay visible.** Something that cannot get its data greys out and says what broke and how to fix it. It never shows old numbers as if they were fresh.
- **The same word everywhere.** A state has one name and one glyph on the bar, in its popup and in the docs.
- **Keys first.** Every new control is reachable with j k h l, Enter and Esc.
