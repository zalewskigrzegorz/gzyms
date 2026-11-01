# Spike S1 verdict: reading macOS notifications live

**Answer: partly yes.** Gzyms can read every notification, but each one shows up about **5 s** after macOS delivers it.

Tested 2026-10-30 on macOS 27.0.1, MacBook, with `NCSpike.app` (this folder) and Full Disk Access granted to that app only.

## What works

- The database `~/Library/Group Containers/group.com.apple.usernoted/db2/db` opens read-only once the app has Full Disk Access. Without it: `authorization denied` (SQLite rc 23).
- The `data` blob is a plain binary plist. `req.titl`, `req.subt`, `req.body` and the app id (`app.identifier`) are readable. Spark mail rows had title, subtitle and body. Script Editor rows had title and body.
- Watching `db-wal` with a DispatchSource catches every new row. No polling needed.
- **Notifications are recorded even when the app's notifications are turned off** in System Settings (Script Editor, "Allow notifications" off: rows still appeared, same 5 s). So the onboarding can tell people to turn macOS notifications off for an app and let Gzyms show them. **To confirm with a real app (Slack) before relying on it.**

## Numbers

| Case | Delay until the row exists |
|---|---|
| single notification, banner on | 5.0 s, 5.0 s |
| three in a row, banner on | 5.0 s, 9.1 s, 13.2 s (all written in one batch) |
| single notification, notifications off | 5.0 s, 5.0 s |
| single notification, previews off | 5.0 s, 5.0 s |

The 5 s is the same with and without a banner, so it looks like `usernoted` batches its writes, not the banner duration.

## What it changes in the spec

- Notifications from other apps: **in v1, with a ~5 s delay** (pass criterion was ≤ 3 s, so this is a partial pass).
- Onboarding: "turn off macOS notifications for apps Gzyms should handle" instead of "set the style to None", once confirmed with Slack.
- Open question: a faster source (e.g. a long-running unified-log stream from `usernoted`). Only worth a spike if 5 s feels too slow in use.

## Faster source: research (Perplexity deep research, 2026-10-30) + our own log check

- **The unified log is instant but has no text.** `log stream --process usernoted` printed `Delivering <NotificationRecord app:"com.apple.ScriptEditor2" … uuid:"BC05670B" …>` at the same millisecond the notification was sent. Title and body are not in it.
- **No supported way to get title/body instantly when the app's banners are off.** Forcing an earlier db write, private XPC (`UserNotificationsCore`, usernoted mach services), Darwin/distributed notifications and Endpoint Security give nothing usable or need Apple-only entitlements.
- **Instant text only via Accessibility on the visible banner** (`com.apple.notificationcenterui` window, as NotificationNanny and boring.notch do). Needs the system banner on screen, breaks between macOS versions (subroles changed in 26, grouped "piles"), and merges notifications sent a few hundred ms apart.
- **Unredacting private log data** needs an admin-installed configuration profile that uncensors the whole system log. Not acceptable for an app people install themselves.
- Other apps that read the db poll it every 1–30 s (AhPushIt, Nonja, notification_history).

**Conclusion:** the db stays the source of truth (works with banners off and in Focus). The log can be an instant "something arrived from app X" signal. Not verified yet: whether the log's `uuid:"BC05670B"` is the first 4 bytes of `record.uuid` (match on app id + time as well).
