# Usage server — one for every app

The master copy of `usage.sql`, this format, a Python client and the checks live in the
**`app-control` skill** (`~/.claude/skills/app-control`); this folder keeps BluePulse's copy.

One Supabase project (*BluePulse*, Mumbai, free plan) records who uses each of our apps and how.
Every app sends the same report; the `app` field keeps them apart. `usage.sql` here is the whole
server side: run it in the project's SQL Editor (safe to run again — it upgrades and keeps rows).

| Where | What |
|---|---|
| Address | `https://zjudpkovgkavarcjxmmp.supabase.co/rest/v1/rpc/usage_report` |
| Key | publishable key, in BluePulse `lib/usage/usage_config.dart` — public by design: it can call `usage_report` and nothing else, so it may ship inside an app |
| User list | Supabase → Table Editor → schema `usage` → `users` (also `apps`, `recent_sessions`, `daily`, `versions`, `activity`; times in IST) |

## The report

`POST <address>` with headers `apikey: <key>` and `Content-Type: application/json`:

```json
{
  "install":  { "id": "c2efcfab076ef6977f3d1586adf0a595", "app": "InTouch OTA Analytics", "name": "Shahbaz Khan",
                "login": "MMI\\shahbaz", "computer": "GT2575", "platform": "windows",
                "os": "Windows 11 Pro (build 26300)", "appVersion": "2.0.2", "build": "release",
                "timeZone": "India Standard Time (UTC+05:30)" },
  "sessions": [ { "id": "…32 hex…", "appVersion": "2.0.2", "startedAt": "2026-11-10T04:18:09Z",
                  "lastActiveAt": "2026-11-10T04:48:09Z", "endedAt": null, "openSeconds": 1800,
                  "pages": { "jobs": 4, "devices": 2 }, "errors": 0,
                  "metrics": { "jobsStarted": 2, "devicesTargeted": 140 } } ],
  "events":   [ { "id": "…32 hex…", "sessionId": "…32 hex…", "at": "2026-11-10T04:18:10Z",
                  "kind": "first_start", "data": {} } ]
}
```

**install** — one copy of one app. Sent whole with every report; the server keeps the latest.

| Field | |
|---|---|
| `id` | **required.** 32 lower-case hex digits, random, made at the copy's first start and kept where updates do not remove it |
| `app` | **required.** The app's name as it should appear in the list: `BluePulse`, `InTouch OTA Analytics`, `uCANdo` |
| `appVersion` | **required.** The running version |
| `name` | as the person typed it at the first start (ask once; say what is reported) |
| `login`, `computer` | Windows sign-in (`DOMAIN\user` on a domain PC) and computer name |
| `platform`, `os`, `device` | `windows` / `android` / …, the OS in words, a phone's maker and model |
| `build` | `release` or `debug` — development runs should not report at all |
| `launcher`, `timeZone` | optional |

**sessions** — one per start of the app; send the newest snapshot of each until the server has it
(it keeps the one with the latest `lastActiveAt`). Times are ISO 8601 UTC. Every app sends
`openSeconds`, `pages` (times each page or view was opened) and `errors`; anything an app wants to
count for itself goes in **`metrics`**, an object under its own names (up to 4,000 characters), so
no app ever needs a new column. BluePulse's: `liveSeconds`, `demoSeconds`, `devices`, `packets`,
`bluetooth`.

**events** — something that happened, stored once per `id`: `kind` is lower-case with underscores
(`first_start`, `version_changed` with `{from, to}`, `update_offered`, `update_installed`,
`update_failed`, `error` with `{message, stack}`, …), `data` an object.

**Sending:** at start, every few minutes and on close; keep unsent reports on disk and send them
later, so starts made offline still count. At most 200 sessions and 500 events in one report.

| Answer | Meaning | Do |
|---|---|---|
| 200 `{"ok": true}` | stored | forget what was sent |
| 400 | the report itself is wrong (message says why) | drop it, so it cannot block the rest |
| 401 | key missing or wrong | keep it, fix the key |
| 404 | `usage_report` not installed | keep it, run `usage.sql` |
| no answer | offline, or a free project paused after 7 quiet days | keep it, try later |

**Check a project** without storing anything — a report with no install ID must be refused:

```
curl -s -X POST "<address>" -H "apikey: <key>" -H "Content-Type: application/json" -d "{\"install\":{}}"
→ {"code":"22023",…,"message":"install.id is missing or not 32 hex digits"}
```

BluePulse does the same with `dart run tool/usage_check.dart`.

## Adding it to another app

1. Make and keep a 32-hex install ID; ask the name once at the first start, with one line saying
   what is reported; greet the person by name on the home page.
2. Send the report above with `app` set to the app's name, from release builds only.
3. Queue unsent reports on disk; follow the answers table.
4. The person's own name for the copy is all that is asked — everything else is read from the machine.
