# 🕵️ GhostPrint — FiveM Browser Fingerprinting & Ban System

> **Catch ban evaders by their CEF UUIDs, not their license.**

> ⚠️ **Proof of concept only. Not production-ready. Modify before deploying. Use your brain.**

---

## What is this?

GhostPrint is a player identification system built on top of CEF (Chromium Embedded Framework) — the browser engine embedded inside the FiveM client. Instead of relying solely on Rockstar identifiers (which can be spoofed), it collects additional signals directly from the player's operating system and hardware.

There's no such thing as a 100% effective ban system. This tool **raises the bar** — it doesn't build a wall.

---

## How it works

```
[Player connects to the server]
         │
         ▼
[playerSpawned → client.lua]
         │
         ▼
[SendNUIMessage → hidden HTML running in background]
         │
         ├─► FingerprintJS → visitorId (hash from ~60 signals)
         │
         └─► enumerateDevices() → hardware UUIDs (audio/video devices)
                  │
                  ▼
         [fetch NUI callback → server.lua]
                  │
                  ▼
         [checkBan with single IN() query]
                  │
         ┌────────┴────────┐
         │                 │
       BAN               CLEAN
         │                 │
         ▼                 ▼
  saveBanFingerprints   Player joins
  (new UUIDs → ban_id)
         │
         ▼
     DropPlayer()
```

---

## Collected identifiers

| Identifier | Source | Spoof difficulty |
|---|---|---|
| `license` | Rockstar / FiveM | Medium (account) |
| `visitorId` | FingerprintJS (~60 signals) | High |
| `deviceId` audioinput | Media Devices API | High |
| `deviceId` audiooutput | Media Devices API | High |
| `deviceId` videoinput | Media Devices API | High |

**visitorId** is a hash generated from signals including:
- Canvas fingerprint (GPU rendering output)
- WebGL renderer / vendor (graphics card)
- Audio fingerprint (DAC characteristics)
- Installed fonts
- Screen resolution, color depth, pixel ratio
- System language, timezone, hardware concurrency
- ~50 other signals

---

## Database schema

```sql
-- Main bans table
bans
├── id           UUID  PK
├── license      TEXT
├── name         TEXT
├── reason       TEXT
├── banned_by    TEXT
├── banned_at    TIMESTAMP
├── expires_at   TIMESTAMP (NULL = permanent)
└── active       BOOLEAN

-- Fingerprint identifiers (N-to-1 with bans)
ban_fingerprints
├── id         UUID  PK
├── ban_id     UUID  FK → bans.id
├── type       TEXT  ('license' | 'visitorId' | 'deviceId:audioinput' | ...)
├── value      TEXT  (the identifier itself)
└── created_at TIMESTAMP
```

### Why a separate table for fingerprints?

One player can have **multiple identifiers** (license + visitorId + 3x deviceId = 5 rows). If everything lived in the `bans` table, you'd need 5 columns or 5 separate SELECT queries. Instead:

```sql
-- One query checks ALL identifiers at once
SELECT ... FROM ban_fingerprints
WHERE value IN ('license:xxx', 'visitorId:yyy', 'uuid-aaa', 'uuid-bbb')
```

---

## Ban evasion — how the system responds

When a banned player tries to reconnect with a **new account or different hardware**:

1. One of their identifiers matches in the database (e.g. `visitorId`)
2. The system **saves their new identifiers** under the same `ban_id`
3. Player gets `DropPlayer()`
4. On the next attempt — even with yet another new account — more identifiers will catch them

```
Attempt 1: license=AAA → BANNED (match: visitorId)
           → saves license=AAA to ban_id

Attempt 2: license=BBB → BANNED (match: visitorId OR license=AAA)
           → saves license=BBB to ban_id

Attempt 3: license=CCC, new PC → BANNED (match: deviceId)
```

---

## Loading screen trick

FiveM supports full NUI during the loading screen. You can move the entire fingerprinting logic to the loading phase instead of waiting for `playerSpawned`:

```lua
-- fxmanifest.lua
loading_screen 'ui/main.html'
-- add this line to the fxmanifest.lua and that is
-- there you must to figure out how to send uuids to server
```

This is the correct way to do it. Most servers don't bother.

---

## Requirements

- **PostgreSQL** — the code uses `RETURNING id` and `ON CONFLICT DO NOTHING`, both incompatible with MySQL 5.x
- `oxmysql` resource (or your own wrapper, adjust accordingly)
- FiveM server with NUI support
- `@fingerprintjs/fingerprintjs` v5 — download locally from `openfpcdn.io/fingerprintjs/v5/umd.min.js` and place it in `ui/fp.js`

> FiveM NUI has no internet access by default. **Do not use a CDN import** — it will silently fail. Host the library locally inside your resource.

---

## What you need to modify before using this

```
❌ No /ban command                        → hook into your existing system
❌ oxmysql is hardcoded                   → adapt to your DB wrapper
❌ No input validation on NUI data        → player can send garbage
❌ No rate limiting on the server event   → add throttling
❌ visitorId can be spoofed inside CEF    → treat as one signal, not the only one
```

---

## File structure

```
ghostprint/
├── ui/
│   ├── index.html       ← NUI page (hidden, runs on spawn)
│   └── fp.js            ← FingerprintJS v5 (host locally!)
├── client.lua
├── server.lua
├── schema.sql
└── fxmanifest.lua
```

---

## License / disclaimer

Released for **educational purposes only** as a proof of concept.  
The author takes no responsibility for how this is used.  
Use your brain.
