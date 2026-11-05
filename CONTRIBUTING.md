# Contributing

Start in [Discussions](https://github.com/zalewskigrzegorz/gzyms/discussions): Problems for bugs, Ideas for features. An issue gets opened from the discussion once it is confirmed or picked.

Run `scripts/check.sh` before every deploy. It ends with `ALL GREEN`.

## Feature list

`features.json` is a hand-kept list of what a user can do with Gzyms. The count on gzyms.dev comes from it.

- A new feature a user can name and use gets a new entry in `features.json`, in the same commit.
- Bump `count` to the length of the list and `updated` to today.
- Fixes, refactors, tests and dev tools do not count.
- `scripts/check.sh` fails when `count` and the list disagree.
