# BluePulse — Implementation Plan

**BluePulse** is one Bluetooth and BLE workbench for a Windows laptop and an Android phone. Its first
module scans Teltonika **EYE BEACON (BTSID1)** and **EYE SENSOR (BTSMP1)** devices, decodes what they
broadcast and shows it live, and decodes the beacon records a Teltonika tracker sends to its server
(Codec 8 Extended). Next: a serial terminal over BLE (UART-style services) and Bluetooth Classic (SPP).

Plan v1 · 09-11-2026

---

## 0. Status — 11-11-2026

| Phase | State |
|---|---|
| P0 | **Done on Windows, 09-11-2026**, with 15–19 real EYE sensors (`MP1_…`, `MG1_…`). It found the gap D5 allowed for: `universal_ble`'s Windows scanner drops repeated advertisements (only a backfill, a scan response or a connectability change gets through — `scan_result_merge.h`), so new sensor values were lost and old ones re-sent. Replaced on Windows by `packages/bluepulse_ble_windows` (every packet, raw bytes). Separately, Windows itself listens 18 ms of every 118 ms (≈15 %) and makes the scan interval/window read-only for apps; the low-latency preset changed nothing on this laptop, so a laptop hears fewer packets than a phone. **Android on air: done 10-11-2026** on a moto g57 power (`universal_ble`). |
| P1 | **Done.** `packages/eye_protocol`: AD parser, Eddystone, iBeacon, Teltonika block, Codec 8 / 8E + CRC, AVL 385 / 10828 / 10829 / 10831, byte inspector. 53 tests; both wiki tracker packets verified (CRC `823F`, `8811`). |
| P2 | **Built, verified on demo data and tests** (26 app tests): scanners, registry, ADV + scan-response merge, repeats, interval, smoothing, not seen, proximity, distance. **Verified on air** on Windows and Android, 09/10-11-2026. |
| P3 | **Built**: shell (rail / top bar / drawer), Overview, Devices, Device detail, Packets, Proximity, Decode, Settings. Checked by screenshot in dark, light, folded rail and phone width (web build, demo data). |
| **OTA** | **Built** (top priority, 09-11-2026): launcher, update check / download / verify / install / restart, Android APK install, release packaging. 27 update tests incl. end-to-end over real sockets with GitHub-style redirects; 4 launcher checks. **Released: 1.0.0 published 10-11-2026** (github.com/alishahbaz7/BluePulse, tag `v1.0.0`); the APK is signed with BluePulse's release key (`keys/`, git-ignored). **Hardened for 1.0.1, 11-11-2026**: every failure — no network, GitHub down, a server that never answers, a connection dropped halfway through `latest.json` or the download, a `latest.json` with a wrong type — ends quietly as *failed* (Settings only), can be tried again, and never touches the running version (before: a dropped download left *Downloading…* until restart). Real-socket tests cut the connection halfway. The Windows title bar now follows the app theme (runner channel `bluepulse/window`). |
| **Usage** | **Monitoring live, 10-11-2026** (§10b): Supabase project *BluePulse* (Mumbai) set up, `tool/usage_check.dart` READY, the app's key confirmed unable to read anything, and a release build on the development laptop delivered its first report. Built: each copy reports who uses it (name and team asked once), its version, every start (time open, time scanning, devices heard, pages opened), updates and app errors; starts made offline are kept and sent later. Server side `backend/supabase/usage.sql` checked on Postgres 16 (25 checks: the app's key can write reports and read nothing); 30 app tests; screens checked by screenshot (`test/visual/usage_screens_test.dart`); `tool/usage_check.dart` checks a server without storing anything. Development runs report only when `USAGE_URL` is passed. **Next: control** (block, version per group, features) — the four answers in §10b first. **Silent by rule, 11-11-2026**: nothing waits for the server (the first-start name is saved at once and sent in the background), one send gives up after 30 s, anything unexpected is caught and kept, and failing sends back off 10 → 20 → 30 min. |
| P4 | **Sessions built for 1.0.1, 10-11-2026** (§8): every live scan recorded Start to Stop, listed, opened, exported or shared, deleted; checked on air on Windows (15 EYE devices) and by screenshot (wide, light, phone). Replay: next. |
| P5–P6 | **P6 Configure built 11-11-2026**: every setting in §3.8, PIN unlock, write-changed-only, read-back verify, save to flash, restart / restore defaults; protocol confirmed against a recorded EYE App session (HCI log: PIN as ASCII, little-endian UINT16, command `00 10`, MTU 23); tested against a simulated sensor and **on a real BTSMP1 (11-11-2026)**: connected from the moto g57 power, read every setting (interval 2000 ms, repeats 1, +8 dBm, firmware 1.2.10), renamed TestSensor1 → MP1_1EE137, read back, saved to flash; the sensor then advertised the new name. Two findings fixed on the way: the scan pauses while connected, and the session asks for the MTU and waits 1.2 s after discovery before the first read (a read during the sensor's connection-parameter change left it silent until the link timed out). P5: foreground service, radio filters, 1M legacy scanning and 4-minute restarts done 10-11-2026. |
| **Benchmark** | **10-11-2026, 2 real EYE SENSORs set to 2 s** (MP1_1EE137 7C:D9:F4:15:2D:01, MP1_1FE137 7C:D9:F4:15:2C:FF; measured intervals 2.22 s and 2.53 s), moto g57 power (Android 17) and this Windows laptop, same room, ~175 BLE reports/s around. Phone figures from the HCI snoop log (what the radio passed up), laptop from its session CSV. **BluePulse on the phone** (10 min): 40 % / 54 % of advertising events, average gap 5.5 s / 4.7 s, radio at 100 % the whole time (restart every 4 min). **Teltonika EYE App 1.6.0** (same scan settings: LOW_LATENCY, all matches, unfiltered): 48 % / 46 % for its first 5 min, then Android moved its scan to opportunistic and it heard **nothing** for the rest (43 116 results in 5 min, 95 in the next 5); its list kept showing the old values. **Laptop** (Windows): 11–15 % (gaps 13–22 s). Even at 100 % duty a phone hears ~45 % of events here — RF congestion / Wi-Fi coexistence, to test next with Wi-Fi off. |
| **Simulator** | **Built for 1.0.1, 10-11-2026**: this device transmits as an EYE SENSOR / EYE BEACON / iBeacon to test receivers (README *Simulator*). Encoders in `eye_protocol` (inverse of the decoders; BTSMP1 frame rebuilt byte for byte); Android plugin `packages/bluepulse_ble_android` (Java, AdvertisingSet: exact interval 100 ms – 10 s, power, name by renaming the phone's Bluetooth, restored on Stop or next start); Windows publisher in `bluepulse_ble_windows` (no interval control, no name, no scan response → a burst of half the interval, 60–500 ms, every interval (200 ms lost a third of the pings on a phone; Windows is on air ~20 ms after Start), scan-response data in alternate bursts). 14 tests; screens checked. **On air, laptop → phone (10-11-2026): Windows sends every burst from a new random address** and refuses a name (both checked on this PC's radio, which also accepted Eddystone's 0x03 / 0x16 sections despite Microsoft's list), so the phone listed a new device every 2 s. Answer: the *BluePulse tag* (`0xFFFF` `BP` + 4-byte ID) in every packet with room; a BluePulse receiver lists them as one device, `SIM-…`, and joins untagged beacon frames by beacon ID (README *Simulator*). **To test** — the same run with 1.0.1 on the phone; Android → laptop (laptop session measures the gaps). |
| **Files & errors** | **Built 11-11-2026**: one BluePulse folder per device (`lib/app/paths.dart`) — `C:\Users\<you>\BluePulse` (not OneDrive-synced Documents) and phone *Documents › BluePulse* (checked writable without permission on Android 17), changeable in *Settings → Files* (any folder on Windows; Documents or Download on a phone), earlier files brought over once. `BluePulse_errors.log`: one plain line per event, every build, handled failures as warnings, repeats counted, 2 × 1 MB at most. Long logs flush every 2 s and split at a million rows. |
| **Device lists** | **11-11-2026**: one Tile / List switch for Devices, Configure and the Overview (kept); tiles *As found* by default (new devices at the bottom, a device out of range greyed in place), pinned devices in their own section. Side rail: name and version only. |

## 1. Decisions

| # | Decision | Date |
|---|---|---|
| D1 | **Flutter**, one codebase for Windows desktop and Android | 09-11-2026 |
| D2 | Android is a **standalone app** | 09-11-2026 |
| D3 | Devices: **EYE BEACON (BTSID1) and EYE SENSOR (BTSMP1)** | 09-11-2026 |
| D4 | **Tracker record decoding** (Codec 8 Extended, AVL 385 / 10828 / 10829 / 10831) is in P1 | 09-11-2026 |
| D5 | BLE plugin **`universal_ble`**, behind a `BeaconScanner` interface; a native scanner per platform only if Phase 0 shows a gap | 09-11-2026 |
| D6 | UI follows the house utility look (sidebar workbench, tokens, chips, pills, tiles, data grid) rebuilt as Flutter widgets | 09-11-2026 |
| D7 | Protocol code is a **pure-Dart package** (`packages/eye_protocol`) with no Flutter dependency | 09-11-2026 |
| D8 | This folder is the repository (git); work happens on a branch named for the version, never on `main` | 09-11-2026 |
| D9 | **Version 1.0.0**, declared only in `pubspec.yaml`; releases named `BluePulse-v<version>` | 09-11-2026 |
| D10 | **Updates over the air**: a stable launcher + versioned folders on Windows, APK install on Android | 09-11-2026 |
| D11 | Releases published to the **public repo github.com/alishahbaz7/BluePulse** (source + releases; no token in the app) | 09-11-2026 |
| D13 | Name **BluePulse** — app, launcher, releases (`BluePulse-v<version>`), repo and folder | 09-11-2026 |
| D12 | Update check **inside the app** on every start; **Later always offered** unless `minimumVersion` requires it | 09-11-2026 |
| D14 | **Own native BLE scanner on Windows** (C++/WinRT plugin in `packages/bluepulse_ble_windows`); `universal_ble` stays for Android and the radio state | 09-11-2026 |
| D15 | **Device tags** (own names) and **focus** (every packet + fast refresh for chosen devices, slow refresh for the rest, the open device focused while its page is open), kept on the computer | 09-11-2026 |
| D16 | **Portable on Windows**: unzip and run, no installer, no admin (`asInvoker`), nothing to install on user PCs; keep the folder somewhere the user can write so updates can land | 09-11-2026 |
| D17 | **Usage monitoring first, control next**, on one channel: each copy reports who uses it and how; later the answer to that report carries what the copy may do | 09-11-2026 |
| D18 | Usage backend **Supabase** — open source, free tier, Mumbai region, self-hostable later. The app only POSTs one JSON document to one URL, so a self-hosted Supabase, PocketBase or our own server can replace it | 09-11-2026 |
| D19 | **Only the name is asked, once, at the first start**, with one line saying what is reported, and the home page greets the person by it ("Hello, Name"); Windows login, computer name and phone model are read, not asked | 09-11-2026, name only 10-11-2026 |
| D20 | **A ping is one advertising event** (advertisement + scan response, repeats folded); received % uses the 10th-percentile gap as the interval estimate | 10-11-2026 |
| D21 | Device page: **one time window (5 / 10 / 15 min)** for all charts and pings; **Now · Avg · Min · Max** on every chart; **charts arranged by the user** (order, shown, half/full), kept per device type | 10-11-2026 |
| D22 | **Received-packet log per device** (last 5,000, raw bytes), **Save log** as CSV (Windows save dialog, Android share sheet) and **Record** to CSV for long tests | 10-11-2026 |
| D23 | **One usage server for every app**: each report names its `app`, the views split by it, and `backend/supabase/README.md` is the report format the other apps (InTouch, uCANdo, …) follow | 10-11-2026 |
| D24 | **Each app's own counters go in a session's `metrics`** (an object under the app's names), never in new columns; the shared session fields are time open, pages opened and errors. The user list shows who, which app and version, when, how often and errors — no hours or device counts for now. Schema v3 | 10-11-2026 |
| D25 | The way to add monitoring (and, next, control) to any app is the **`app-control` skill** (`~/.claude/skills/app-control`); its copy of `usage.sql` is the master, `backend/supabase/usage.sql` here follows it | 10-11-2026 |

## 2. Scope

**In v1:** live scanning on Windows and Android · decoding Eddystone-UID, iBeacon and the Teltonika
`0x089A` block · device list, device detail with charts, raw packet inspector · proximity tuner
(tracker Near / Away / Lost thresholds) · tracker packet decoder (paste hex) · scan sessions with
CSV export.

**Later:** configuring devices over GATT (P6) · battery percentage (needs a discharge curve) ·
maps / positioning.

**Not planned:** iOS (iOS hides iBeacon frames and MAC addresses from apps).

---

## 3. Protocol reference

Source: [`EYE BEACON _ BTSID1 - Teltonika Telematics Wiki.pdf`](EYE%20BEACON%20_%20BTSID1%20-%20Teltonika%20Telematics%20Wiki.pdf)
(wiki revision `oldid=117310`), in this folder.

Status marks: ✅ verified from the PDF (the EYE SENSOR fields from the BTSMP1 page and its frame example, 10-11-2026) · 🟡 provisional —
to confirm against the EYE SENSOR / BTSMP1 page · 📘 public standard.

### 3.1 Packets ✅

| Packet | When | Contents |
|---|---|---|
| Advertising indication (`ADV_IND`) | always | flags + beacon ID frame (iBeacon or Eddystone-UID), or the Teltonika block when the beacon frame is off |
| Scan response (`SCAN_RSP`) | only to an **active** scanner | device name + Teltonika manufacturer data |

Each is at most 31 bytes. When the beacon frame is disabled, the scan-response data is sent as the
advertising indication with no scan response after it.

**Protocol type** (GATT setting): `0` iBeacon · `1` Eddystone (factory default) · `2` EYE Sensor ·
`3` iBeacon + EYE Sensor · `4` Eddystone + EYE Sensor. From firmware 01.02.10 the range is 0–2 and
sensors are switched by a separate *Activate / Deactivate Sensors* bitmask (bit 0 temperature,
1 humidity, 2 magnetic, 3 movement). 🟡 The PDF's table is garbled here; the decoder does not depend
on it — it decodes whatever is present.

**Device name** ✅ — default `ID1_XXXXXXX` on the beacon; users can rename it, so the prefix is a hint,
never an identity.

### 3.2 Eddystone-UID 📘

Service data (AD type `0x16`) for UUID `0xFEAA` (on air `AA FE`):

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | frame type `0x00` (UID). `0x10` URL, `0x20` TLM, `0x30` EID are recognised, not decoded |
| 1 | 1 | TX power at 0 m, int8 dBm |
| 2 | 10 | namespace |
| 12 | 6 | instance |
| 18 | 2 | reserved — may be absent |

### 3.3 iBeacon 📘

Manufacturer data (AD type `0xFF`), company `0x004C` (on air `4C 00`):

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | `02 15` |
| 2 | 16 | UUID |
| 18 | 2 | major, uint16 big-endian |
| 20 | 2 | minor, uint16 big-endian |
| 22 | 1 | measured power (RSSI at 1 m), int8 dBm |

### 3.4 Teltonika manufacturer data

AD type `0xFF`, company **`0x089A`** ✅ (on air `9A 08`, little-endian by BLE convention 📘 — confirm
with a capture), then:

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | protocol version `0x01` ✅ |
| 1 | 1 | flags ✅ |
| 2 | n | values, **in flag-bit order**, one for each bit that adds a value |

| Bit | Meaning | Value bytes | Decode | Status |
|---|---|---|---|---|
| 0 | temperature present | 2 | int16 big-endian ÷ 100 → °C | ✅ (BTSMP1) |
| 1 | humidity present | 1 | uint8 → % | ✅ (BTSMP1) |
| 2 | magnetic sensor present | 0 | — | ✅ |
| 3 | magnetic field detected (valid only when bit 2 is set) | 0 | — | ✅ |
| 4 | movement counter present | 2 | uint16 big-endian: bit 15 = moving now, bits 0–14 = count | ✅ (BTSMP1) |
| 5 | movement angle present | 3 | pitch int8 ° (−90…+90), roll int16 big-endian ° (−180…+180) | ✅ (BTSMP1) |
| 6 | low battery | 0 | — | ✅ |
| 7 | battery voltage present | 1 | **2000 + value × 10 → mV** | ✅ |

**BTSID1 only ever sets bits 6 and 7** ✅, so its block is `01 <flags> [battery]`.

Decoder rules: a version other than `0x01` is shown raw as *unsupported version*; flags that promise
more bytes than arrived give *truncated* and keep the raw bytes; extra trailing bytes are kept as an
unparsed tail. A field nobody has confirmed is never invented.

### 3.5 Tracker records — Codec 8 Extended ✅

| Field | Bytes | Note |
|---|---|---|
| preamble | 4 | `00000000` |
| data field length | 4 | codec ID through the second record count |
| codec ID | 1 | `0x8E` |
| number of records | 1 | |
| records | … | |
| number of records | 1 | must equal the first |
| CRC | 4 | CRC-16/IBM (poly `0xA001` reflected, init 0) over the data field — **verified on both PDF packets** |

Record: timestamp 8 (ms since epoch) · priority 1 · longitude 4 · latitude 4 (int32 ÷ 10⁷ 📘) ·
altitude 2 · angle 2 · satellites 1 · speed 2 · event IO ID 2 · total IO count 2 · then four groups
(1-, 2-, 4-, 8-byte values), each `count 2` + (`ID 2` + value) × count · then variable-length IO:
`count 2` + (`ID 2` + `length 2` + value) × count.

**AVL 385 — Beacon (simple mode)**

| Bytes | Field |
|---|---|
| 1 | high nibble = this part, low nibble = total parts (`0x11` = part 1 of 1) |
| then per beacon: 1 | flags: `0x21` iBeacon with RSSI · `0x01` Eddystone with RSSI |
| 20 or 16 | iBeacon UUID + major + minor · Eddystone namespace + instance |
| 1 | RSSI, int8 dBm |

Any other flag value (advanced mode) has an unknown length: parsing stops there and the rest is
shown raw.

**AVL 10828 / 10829 / 10831 — EYE beacon lists**

| AVL ID | Proximity mode | Lost & Found mode |
|---|---|---|
| 10828 | Near | Visible list (periodic) |
| 10829 | Away | Found (on change) |
| 10831 | Lost | Lost (on change) |

Value: constant `0x01`, then per beacon `length 1` + parameters as `ID 1` + `length 1` + data:

| Param | Name | Data |
|---|---|---|
| 0 | RSSI | int8 dBm |
| 1 | beacon ID | 16 B Eddystone namespace + instance · 20 B iBeacon UUID + major + minor |
| 13 | low battery | 0 / 1 |
| 14 | battery voltage | uint16 big-endian, mV |
| 15 | MAC | 6 B (only when enabled on the tracker) |

Unknown parameter IDs are skipped by length and kept raw.

### 3.6 Device settings that shape the app ✅

| Setting | Range | Default | Effect in the app |
|---|---|---|---|
| advertising interval | 1000–10000 ms | 5000 | expected gap between readings; drives *Not seen* timing |
| advertising repeats | 1–10 | 1 | a burst of repeats is one reading |
| sub-advertising interval | 20–1000 ms | 100 | gap inside a burst (only when interval > 2000 ms and repeats > 1) |
| TX power | −14, −11, −8, −5, −2, 2, 4, 8 dBm | 2 | distance estimate |
| RSSI calibration | int8, 127 = default table | 127 | reference for distance |
| GATT config service | `e61c0000-7df2-4d4e-8e6d-c611745b92e9` | PIN `123456` | P6 |

Hibernated devices wake with any magnet (LED blinks).

### 3.8 GATT configuration (BTSMP1 page, text layer) 📘

Config service `e61c0000-7df2-4d4e-8e6d-c611745b92e9`; characteristics `e61cXXXX-7df2-4d4e-8e6d-c611745b92e9`.

| Setting | Char | Type | Range | Default |
|---|---|---|---|---|
| Device name | `0016` | ASCII | 0–12 chars | unique |
| Protocol type | `0001` | UINT8 | 0–4 (0–2 from 01.02.10: 0 iBeacon, 1 Eddystone, 2 EYE Sensor; 3 iBeacon + EYE, 4 Eddystone + EYE before) | 1 beacon, 4 sensor |
| Activate sensors | `0021` | UINT8 bits | bit 0 temperature, 1 humidity, 2 magnetic, 3 movement (01.02.10+) | 4 beacon, 15 sensor |
| Advertising interval | `0002` | UINT16 | 1000–10000 ms | 5000 |
| Sub-advertising interval | `0003` | UINT16 | 20–1000 ms | 100 |
| Advertising repeats | `0004` | UINT16 | 1–10; only when interval > 2000 ms | 1 |
| iBeacon ID | `0005` | 20 B | UUID 16 · major 2 · minor 2 | unique |
| Eddystone ID | `0006` | 16 B | namespace 10 · instance 6 | unique |
| Command | `0007` | 2 B | `0x0010` write to flash · `0x0011` boot · `0x0012` reset · `0x0013` reset after disconnect · `0x0014` hw voltage · `0x0015` keep alive · `0x0016` restore defaults | — |
| Password | `0008` | 6 B | 6 digits | `123456` |
| Movement start / stop | `0013` / `0014` | UINT16 | 0–300 s | 5 / 5 |
| Hibernate | `0018` | UINT8 | 0 off, 1 on | 1 |
| Password counter | `0019` | UINT8 + 2 B | tries 0–10, timeout | 0 |
| Master password (PUK) | `0020` | 8 B | from the MAC | — |
| Wake-up advertising spam | `0022` | UINT16 | 1–300 s | 30 |
| RSSI calibration | `0023` | INT8 | −100…127, 127 = default table | 127 |
| TX power | service `1804` · `2a07` | SINT8 | −14, −11, −8, −5, −2, 2, 4, 8 dBm | 2 |

Read only (Device Information `180A`): manufacturer `2A29`, model `2A24`, hardware `2A27`, firmware
`2A26`, MAC `652143dc-dec6-4fb1-bd46-3e919d2410a6`, calibration ID `a610249f-913e-46bd-b14f-c6dedc432165`
(EN12830 devices). Scan-response data: service `e61c0000-7df3-…`, char `e61c0001-7df3-…`, 17 B.

**For a 2 s system:** repeats are the lever — an interval just over 2000 ms with 3 repeats 100 ms apart
gives three chances per window (≈ 83 % of windows at the 55 % loss measured, against ≈ 45 % today).

### 3.7 Inconsistencies in the source

- A note says "Lost Beacon Record (AVL ID:10829)"; the tables say 10829 is Found / Away and 10831 is
  Lost. The tables are followed.
- The BTSID1 page's protocol overview names BTSMP1 (shared text); it applies to both.
- The GATT table is garbled in the PDF's layout but whole in its text layer: reconstructed in §3.8 (10-11-2026). Byte order of the UINT16 values and the password / save sequence are still to be confirmed on a device (or from an EYE App session in the HCI log) before P6 writes anything.
- "RSSI below the first threshold → Near" does not say which way the sign runs; the tuner treats
  *stronger than T1* as Near. Confirm against the tracker configurator.

---

## 4. Architecture

| Layer | Choice |
|---|---|
| UI | Flutter (Material 3 base, house tokens as a `ThemeExtension`) |
| State | `ChangeNotifier` + `ListenableBuilder` — no state library |
| BLE | `universal_ble` behind `BeaconScanner` |
| Charts | hand-drawn with `CustomPainter` (house rule: no chart library) |
| Settings | `shared_preferences` |
| Sessions | CSV files in the app's data folder (SQLite only if replay needs it) |
| Usage | one HTTPS POST to Supabase (Postgres); server side in `backend/supabase/usage.sql` |

```
packages/eye_protocol/        pure Dart — no Flutter
  lib/src/ad_structures.dart  raw AD bytes → typed structures
  lib/src/eddystone.dart      Eddystone-UID (+ frame-type recognition)
  lib/src/ibeacon.dart        iBeacon
  lib/src/teltonika.dart      0x089A block: flags + values
  lib/src/codec8e.dart        Codec 8 Extended framing + CRC-16/IBM
  lib/src/avl_beacons.dart    AVL 385 and 10828/10829/10831
  test/                       every vector in §9
lib/
  scanner/   BeaconScanner · UniversalBleScanner · DemoScanner (labelled, for no-hardware runs)
  core/      DeviceRegistry · smoothing · proximity · classification
  ui/        nav definition · shell (rail, top bar) · pages · widgets · theme
  update/    release channel: check, download, verify, install
  usage/     usage reports: install, sessions, events · offline outbox · sender
backend/supabase/usage.sql   usage tables, the report function, the user-list views
test/        core logic + widget tests (nav, empty states, theme)
```

```
scanner ──Advertisement(mac, rssi, name, mfr data, service data, raw?)──► DeviceRegistry
                                                                             │ decode (eye_protocol)
                                                                             │ merge by MAC, drop repeats
                                                                             │ smooth RSSI, proximity state
                                                                             ▼
                                                  UI pages ◄── notifyListeners (throttled ~4 Hz)
```

## 5. Scanning per platform

**Windows** — WinRT watcher in **active** mode (needed for the scan response). Windows reports
the advertisement and the scan response as separate events; the registry joins them by MAC.
Check in Phase 0 that `universal_ble` sets active mode.

**Android**
- Permissions: Android 12+ `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT`; **do not** set
  `neverForLocation` (Android then filters beacon advertisements) and request
  `ACCESS_FINE_LOCATION`; Android ≤ 11 needs fine location and location services on.
- One long scan in low-latency mode; never restart more than 5 times in 30 s (Android blocks it).
- Unfiltered scans are downgraded after 30 min: use OR filters (manufacturer `0x089A`, manufacturer
  `0x004C`, service `0xFEAA`) or restart the scan every ~25 min.
- Continuous scanning with the screen off needs a foreground service (P5).

## 6. Core behaviour

- **Identity:** MAC. Model: name prefix `ID1_` or only bits 6–7 ever seen → EYE BEACON; any of bits
  0–5 seen → EYE SENSOR; otherwise *EYE device*. Non-Teltonika beacons are shown only when the
  *All beacons* filter is on.
- **Repeats:** packets from one MAC within 1 s with identical payload count as one reading.
- **RSSI:** raw and smoothed. Smoothing follows the tracker's *averaging timeout* (time for the
  value to reach a new level), as an exponential filter with that time constant.
- **Not seen:** no packet for 3 × the observed interval (minimum 15 s). Grey — not a fault.
- **Proximity:** T1 / T2 thresholds and averaging timeout, as on the tracker; Near / Away / Lost.
- **Distance:** shown as an estimate only (log-distance, path-loss exponent in Settings); the
  formula sits in the hold-tip.
- **Battery:** millivolts and the low-battery flag as sent. No percentage until a curve is agreed.

## 7. UI — the house look in Flutter

The rules come from the `utility-ui` skill. Flutter replaces the web stack; the look, words and
behaviour stay.

**Tokens** (from InTouch `app.css`), dark default, Auto / Light / Dark:

| Token | Dark | Light |
|---|---|---|
| bg | `#0f1216` | `#f6f7f9` |
| panel | `#171b21` | `#ffffff` |
| panel-2 | `#1d222a` | `#f0f2f5` |
| line | `#2a313b` | `#dde1e7` |
| text | `#e6e9ee` | `#14181d` |
| dim | `#aeb9c7` | `#445060` |
| muted | `#8794a5` | `#5f6b79` |
| accent | `#4d9dff` | `#1266d6` |
| ok / warn / bad | `#35c48a` / `#e0a83a` / `#e5544b` | same |

**Frame:** sidebar 240 px, folds to a 58 px rail (remembered); below 1000 px always a rail; on a
phone the same nav definition feeds a drawer. Top bar: ☰ · page title + module name (description as
a 5 s hold-tip) · the module's status chips · theme · primary action.

**One nav definition** (`lib/ui/nav.dart`) feeds the rail, the top bar and the tests.

| Module | Page | Pill |
|---|---|---|
| Live | Overview · Devices · Packets · Proximity | `BT` while Bluetooth is off or not permitted |
| Tracker | Decode | — |
| Data | Sessions | `Soon` until P4 |
| Device | Configure | `Soon` until P6 |
| — | Settings | — |

**Live chips:** *Bluetooth* (on / off / not permitted) · *Scan* (active · count / stopped / demo).
Primary action: *Start scan* / *Stop scan*.

**Pages**
- *Overview* — tiles (In view, Beacons, Sensors, Low battery, Not seen, Packets / min), then a
  *Needs attention* card (low battery, not seen) beside a readings-per-minute chart.
- *Devices* — data grid: name, MAC, model, ID, RSSI, smoothed, proximity, battery mV, low battery,
  temperature, humidity, movement, magnet, last seen, interval, packets. Every header sorts; a search
  box filters; a row opens *Device detail*.
- *Device detail* — header card (name, model, state pill, MAC, ID), RSSI chart (raw + smoothed),
  battery trend, sensor charts when the flags are present, recent packets.
- *Packets* — live raw log (time, MAC, RSSI, AD structures in hex); selecting one labels every byte.
- *Proximity* — T1 / T2 / averaging timeout; devices grouped Near / Away / Lost live.
- *Decode* — paste a whole Codec 8E packet or one AVL value; framing, CRC check, records, IO, beacons.

**Rules carried over:** no help text on pages (explanations are 5 s hold-tips) · mono IDs and MACs ·
tabular numbers · one name and colour per state (in view green, low battery amber, not seen grey,
decode error red) · empty states one line ("No EYE devices in range.") with the action as a button ·
every grey ≥ 4.5:1 · no text under 11.5 px · charts at a fixed height with a full time axis ·
debug builds show a **DEV** badge and keep separate settings from release.

## 8. Storage and export

A session starts with *Start scan* and ends with *Stop scan* (or the window closing, which stops the
scan first). Every packet from every tracked device — in focus or not — goes to one CSV with the
device-log columns (`RxCsv`: time UTC and local, MAC, name, tag, kind, RSSI, gap, decoded values, raw
hex), written once a second; a `.json` summary beside it (start, last write, end, packets, devices)
feeds the list. Folder: `Documents\BluePulse\sessions` on Windows, the app's documents on Android. A
session without an end is *Interrupted* and kept as far as it was written; one that heard nothing is
not kept; demo data is never recorded; *Settings → Record every scan* turns it off. *Sessions* lists
them with *Open* (Windows), *Save a copy* / *Share* and *Delete* (red, confirmed). Replay is next.

## 9. Test vectors

Teltonika block (decoder input = payload after the company ID, as both OS APIs return it):

| ID | Payload | Expected | Source |
|---|---|---|---|
| T-01 | `01 80 63` | v1 · battery 2990 mV · low no | ✅ formula |
| T-02 | `01 C0 4B` | battery 2750 mV · low yes | ✅ formula |
| T-03 | `01 00` | no values | ✅ |
| T-04 | `01 80` | truncated (battery promised) | rule |
| T-05 | `02 80 63` | unsupported version, raw kept | rule |
| T-06 | `01 BF 08 B4 2D 80 0C F6 00 5A 64` | 22.28 °C · 45 % · magnet present + detected · moving · count 12 · pitch −10° · roll 90° · 3000 mV | ✅ layout |
| T-07 | `01 01 FF 38` | −2.00 °C | ✅ layout |

BLE frames:

| ID | Input | Expected |
|---|---|---|
| T-10 | Eddystone service data `00 EE E39B606AA38255AA8E46 0B154E2D0055 00 00` | UID · TX@0 m −18 dBm · namespace `E39B606AA38255AA8E46` · instance `0B154E2D0055` |
| T-11 | iBeacon payload `02 15 6B817F8A274D4FBDB62D33E1842F8DF8 014D 022B C5` | UUID `6B817F8A-274D-4FBD-B62D-33E1842F8DF8` · major 333 · minor 555 · −59 dBm |
| T-12 | raw scan response `0C 09 4944315F41424344454647 06 FF 9A 08 01 80 63` | name `ID1_ABCDEFG` + T-01 |

Tracker (PDF):

| ID | Input | Expected |
|---|---|---|
| T-20 | AVL 385 `11 01 E39B606AA38255AA8E46 0B154E2D0055 CF` | part 1/1 · Eddystone · −49 dBm |
| T-21 | AVL 385 `11 21 6B817F8A274D4FBDB62D33E1842F8DF8 014D 022B BF 21 A579723675064DC396A7C3520129F619 0000 0000 BF` | iBeacon 333/555 −65 · iBeacon 0/0 −65 |
| T-22 | full packet, AVL 10831 (lost), CRC `823F` | 2022-09-23 04:22:29.011 UTC · 25.25975, 54.70086 · −92 dBm · Eddystone `eb47706aa38255aa96f2` / `1a154e2d0055` · low no · 3030 mV |
| T-23 | full packet, AVL 10828 (visible ×3), CRC `8811` | −64 / 3100 mV · −74 / 2990 mV · iBeacon `faffffff-34b6-f6aa-3825-5aa9ef619154` 53474/5 −91 / 2770 mV |
| T-24 | T-22 with one byte flipped | CRC error reported, records still shown and marked |

## 10. Phases

| # | Deliverable | Done when | Size |
|---|---|---|---|
| P0 | Toolchain + `universal_ble` check on both platforms | name, Eddystone ID, battery mV and RSSI of a real BTSID1 seen on laptop **and** phone; go / no-go written here | 1–2 d |
| P1 | `eye_protocol` package: AD parser, Eddystone, iBeacon, Teltonika block, Codec 8E + CRC, AVL 385 / 108xx | every §9 vector passes | 3–4 d |
| P2 | Scanners, registry, merge, repeats, smoothing, not-seen | 3 beacons + 1 sensor live on both platforms | 3–4 d |
| P3 | House UI: shell, Overview, Devices, Detail, Packets, Proximity, Decode | checked light / dark, wide / narrow, laptop / phone | 6–8 d |
| P4 | Sessions: CSV logging, list, export, delete; replay | a 1-hour session exported and reopened | 3–4 d |
| P5 | Android hardening: permission flow, foreground service, scan limits; Windows and Android release builds. Found 10-11-2026 (moto g57 power, Android 17): an unfiltered scan is moved to opportunistic after 5 min on this phone (30 min on older Android; fixed: restart every 4 min); with the screen off or locked a LOW_LATENCY scan runs as LOW_POWER, and unfiltered scans are paused — screen-off scanning needs scan filters (0x089A, 0xFEAA, 0x004C, 0xFFFF) and a foreground service | 8 h unattended scan on a phone | 3–4 d |
| P6 | Configure over GATT (PIN, name, TX power, interval, protocol type, IDs) | settings written and read back | 4–5 d |

## 10a. Updates over the air

```
<install>\BluePulse.exe                    launcher — pinned; no version; rarely changes
<install>\versions\BluePulse-v1.0.0\BluePulse-v1.0.0.exe
<install>\versions\BluePulse-v1.1.0\…      newest complete folder wins
```

1. The launcher starts the newest complete version folder and exits (`launcher/Launcher.cs`).
2. The app reads `https://github.com/<repo>/releases/latest/download/latest.json` on start
   (`lib/update/`): version, notes, `minimumVersion`, and per platform the file, URL, SHA-256, size.
3. Newer → the prompt (once per run; then a top-bar chip). *Update* downloads to
   `versions\.download`, verifies the SHA-256, unpacks to `<name>.partial`, renames it into place,
   refreshes the launcher if the zip carries a different one, and restarts through the launcher.
4. Next start cleans up: keeps the running version, the newest and the previous one.
5. Android: the APK is downloaded to the app cache, verified, and handed to the system installer.

Release: bump `pubspec.yaml` + a CHANGELOG section → `dart run tool/package_release.dart --repo
--build` → publish `dist/*` as release `v<version>`. Settings live in the user profile,
so versions share them.

## 10b. Usage monitoring and control

**State — live, 10-11-2026.** Phase 1 is built, tested and switched on: Supabase project
*BluePulse* (`zjudpkovgkavarcjxmmp`, Mumbai, free plan), `backend/supabase/usage.sql` run, the
address and publishable key are the defaults in `UsageConfig`, `tool/usage_check.dart` says READY,
the key cannot read the `usage` schema (checked against the live API), and a release build on the
development laptop delivered its first report. Every build from here carries it; development runs
report only when `USAGE_URL` is passed. Schema **v3** (D24) is written and tested but the live
project still runs **v2** until it is run in the SQL Editor — until then everything is stored except
BluePulse's own `metrics`. Next: phase 2.

**Why:** know who runs BluePulse, on which version, how often and how — then control it: block a copy
or a person, hold or push a version per group, switch features per group. Only copies that carry the
check-in can ever be monitored or controlled, so it ships in 1.0.0, the first release.

### Phase 1 — monitoring (built, switched off)

| Record | Fields | When |
|---|---|---|
| Install — one per copy | install ID (random, made at the first start, kept in the user profile so updated versions share it) · app name (`BluePulse`) · name (asked once) · Windows login (`DOMAIN\user`) and computer name · phone maker and model · platform, OS · app version · build · started from the launcher · time zone | with every report |
| Session — one per start | start · last active · end (when closed normally) · time on screen · opens per page · errors · BluePulse's own `metrics`: time scanning live / demo, devices heard live (a count), packets heard live, Bluetooth state (`lib/app/scan_metrics.dart`) | measured every minute; sent every 5 min, on minimise and on close |
| Event | `first_start` · `version_changed` (from → to: an update arrived) · `update_offered` / `update_postponed` / `update_started` / `update_installed` / `update_failed` / `update_check_failed` · `error` (message + top of the stack, 10 a session) | as they happen |

Not reported: beacon addresses or IDs, packet contents, location, files.

**Travel:** one HTTPS POST of `{install, sessions, events}` to `UsageConfig.url`, the key in `apikey`
(`lib/usage/`). Reports wait in the settings store until the server has them — sessions by ID, the
newest snapshot winning; up to 500 events and 100 sessions, oldest out first — so starts made offline
still count. A report the server refuses outright (HTTP 400) is dropped so it cannot block the
queue; any other failure keeps it. Web build: off. Debug runs keep their own install ID and report
only when `USAGE_URL` is passed.

**Server** (`backend/supabase/usage.sql`, run once in the SQL Editor; safe to run again): schema
`usage`, not served by the API — tables `installs`, `sessions`, `events`. The app's key can call only
`public.usage_report(install, sessions, events)`, which writes and never reads. A copy cannot
overwrite another copy's session, an older snapshot never replaces a newer one, an event is stored
once. The server serves every app (D23): each copy names its app, and the report format other apps
follow is in `backend/supabase/README.md`. Views, times in IST:

| View | Shows |
|---|---|
| `usage.apps` | one row per app: copies, seen in 7 / 30 days, starts in 7 days, newest version seen |
| `usage.users` | **the user list**: app, name, version, last seen, first seen, launches (all / 7 days), errors, login, computer, phone, OS |
| `usage.recent_sessions` | every start: app, who, version, minutes, closed normally, pages, errors, the app's `metrics` |
| `usage.daily` | people and starts per day |
| `usage.versions` | copies per version and platform, seen in the last 30 days |
| `usage.activity` | updates, errors, first starts, version changes |

**Setup, once** (done 10-11-2026; kept for a move to another project or a self-hosted server):
1. supabase.com → New project, region **Mumbai (ap-south-1)**, free plan.
2. SQL Editor → paste `backend/supabase/usage.sql` → Run.
3. Project Settings → API keys: copy the project URL and the **publishable** key (a legacy *anon*
   key also works).
4. `lib/usage/usage_config.dart`: make them the defaults — `url` =
   `<project URL>/rest/v1/rpc/usage_report`, `key` = the publishable key. Every build then carries
   them; `package_release.dart` warns while they are missing.
5. `dart run tool/usage_check.dart` → **READY** (it sends a report the server must refuse, so it
   proves the address, the key and the SQL without storing anything; otherwise it says which is
   wrong).
6. Run the app → Settings → Usage reporting → *Send now*: *Last sent* shows the time and the copy
   appears in `usage.users`.

**See the list:** Supabase → Table Editor → schema `usage` → `users` (sort, filter, export CSV), or
the SQL Editor.

### Phase 2 — control (next)

The same POST answers with this copy's policy; the app applies it and keeps the last one it got.

| Control | How |
|---|---|
| Block | a status per install or per person: active / blocked + a message. Blocked → a full-window notice with the message; the attempt is still reported |
| Version per group | each install in a ring (pilot / general); the answer names the version the ring may run and its files (GitHub `releases/download/v<version>/…`), in place of `latest.json` for that copy; one copy can be held at a version or required to reach one |
| Features | per ring or install, features on / off (Decode, Packets, Sessions, Configure…); off → the rail item is hidden |
| Admin | first by editing columns in Supabase; then an admin page |

To decide before phase 2:
1. New installs: usable at once (block later), or waiting for approval?
2. Users: MapmyIndia staff only, or customers and partners too (consent wording, DPDP Act 2023)?
3. Offline grace: days without a check-in before a copy stops working (7 proposed)?
4. Enforcement lives in the app. Source and releases are public (D11), so a block stops the official
   build, not someone who builds their own; real access control needs private releases behind a
   login.

## 11. Risks

| Risk | Mitigation |
|---|---|
| `universal_ble` scans passively on Windows → no battery | read its source in P0; native WinRT scanner if needed |
| Eddystone service data not exposed on a platform | same; native scanner for that platform only |
| Laptop adapter drops scan responses | test a second adapter; a beacon with the frame off sends the block in the advertisement |
| Android filters / throttling | rules in §5 |
| Sensor field layout wrong | **closed 10-11-2026**: confirmed by the BTSMP1 page's frame example (T-20, T-21) |
| MAC is random on some firmware | key by beacon ID if the address changes between sessions |
| A copy without the usage channel is unseen until it updates | it ships in 1.0.0, the first release; `package_release.dart` warns if `UsageConfig` is ever emptied |
| A free Supabase project pauses after 7 days without requests | reports wait on each copy and go out once it is restored; daily use keeps it awake; paid tier or self-hosting when it matters |
| The usage key ships in the app and the source is public | it can only call `usage_report` — write reports, never read them; fake reports are possible, acceptable for now; phase 2 can sign reports |

## 12. Development setup

| Need | Status 10-11-2026 |
|---|---|
| Flutter SDK (stable) | **installed** — 3.47.9 / Dart 3.13.7 at `C:\Users\GT2575\develop\flutter`; add `...\flutter\bin` to PATH |
| Visual Studio 2022, workload *Desktop development with C++* | **installed** (Build Tools 2022, Windows SDK 26100) |
| Android SDK (platform 36, build-tools 36.0.0) + JDK 21 | **installed** — SDK at `%LOCALAPPDATA%\Android\Sdk`, JDK at `C:\Users\GT2575\develop\jdk-21.0.13.0.2+1`; no Android Studio needed |
| Windows Developer Mode | **on** |
| Android phone | moto g57 power (Android 17, 411 dp wide); ADB over USB works once *USB debugging* is on (10-11-2026): release APKs install over the copy in place (`adb install -r`, same release key, data kept) |
| Bluetooth LE radio in the laptop | present |

Commands: `flutter pub get` · `flutter analyze` · `flutter test` · `dart test` (in
`packages/eye_protocol`) · `flutter run -d windows` · `flutter run -d <phone>`.

## 13. Inputs still needed

1. ~~EYE SENSOR / BTSMP1 wiki page~~ — received 10-11-2026 with the MESH pages; the sensor fields are confirmed.
2. **Raw captures** (nRF Connect → raw data) from one BTSID1 and one BTSMP1, advertisement and scan
   response.
3. If tracker records should carry sensor values: the tracker's AVL ID list for EYE sensor
   temperature, humidity, movement and angle.
4. **Supabase project** for usage monitoring — URL and publishable key (§10b *Setup*); and the four
   answers under §10b *Phase 2* before control is built.
