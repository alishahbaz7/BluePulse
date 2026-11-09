# BluePulse — Implementation Plan

**BluePulse** is one Bluetooth and BLE workbench for a Windows laptop and an Android phone. Its first
module scans Teltonika **EYE BEACON (BTSID1)** and **EYE SENSOR (BTSMP1)** devices, decodes what they
broadcast and shows it live, and decodes the beacon records a Teltonika tracker sends to its server
(Codec 8 Extended). Next: a serial terminal over BLE (UART-style services) and Bluetooth Classic (SPP).

Plan v1 · 09-11-2026

---

## 0. Status — 09-11-2026

| Phase | State |
|---|---|
| P0 | **Code-level checks passed** in `universal_ble` 3.2.0: Windows watcher runs in *active* mode (`universal_ble_plugin.cpp:339`), service data (Eddystone `0xFEAA`) is passed through keyed by 128-bit UUID, and `skipDuplicates: false` reports every advertisement. **On-air test with a real BTSID1 still to do** — blocked by the missing Windows and Android toolchains (§12). |
| P1 | **Done.** `packages/eye_protocol`: AD parser, Eddystone, iBeacon, Teltonika block, Codec 8 / 8E + CRC, AVL 385 / 10828 / 10829 / 10831, byte inspector. 53 tests; both wiki tracker packets verified (CRC `823F`, `8811`). |
| P2 | **Built, verified on demo data and tests** (26 app tests): scanners, registry, ADV + scan-response merge, repeats, interval, smoothing, not seen, proximity, distance. Real hardware pending. |
| P3 | **Built**: shell (rail / top bar / drawer), Overview, Devices, Device detail, Packets, Proximity, Decode, Settings. Checked by screenshot in dark, light, folded rail and phone width (web build, demo data). |
| **OTA** | **Built** (top priority, 09-11-2026): launcher, update check / download / verify / install / restart, Android APK install, release packaging. 27 update tests incl. end-to-end over real sockets with GitHub-style redirects; 4 launcher checks. Waiting for: the releases repository name, the Android signing key, and a real Windows build (§12). |
| P4–P6 | Not started (Sessions, Android hardening, Configure). |

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

Status marks: ✅ verified from the PDF · 🟡 provisional — EYE Sensor detail not on the BTSID1 page,
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
| 0 | temperature present | 2 | int16 big-endian ÷ 100 → °C | meaning ✅ · size 🟡 |
| 1 | humidity present | 1 | uint8 → % | meaning ✅ · size 🟡 |
| 2 | magnetic sensor present | 0 | — | ✅ |
| 3 | magnetic field detected (valid only when bit 2 is set) | 0 | — | ✅ |
| 4 | movement counter present | 2 | uint16 big-endian: bit 15 = moving now, bits 0–14 = count | meaning ✅ · layout 🟡 |
| 5 | movement angle present | 3 | pitch int8 °, roll int16 big-endian ° | meaning ✅ · layout 🟡 |
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

### 3.7 Inconsistencies in the source

- A note says "Lost Beacon Record (AVL ID:10829)"; the tables say 10829 is Found / Away and 10831 is
  Lost. The tables are followed.
- The BTSID1 page's protocol overview names BTSMP1 (shared text); it applies to both.
- The GATT table is garbled in the PDF export; re-read the live page before P6.
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

A session starts with *Start scan* and ends with *Stop scan*. Readings go to a CSV in the app's data
folder (time, MAC, name, model, RSSI, ID, battery, sensor values, raw hex). *Sessions* lists them with
*Export* and *Delete* (red, confirmed). Replay comes after export.

## 9. Test vectors

Teltonika block (decoder input = payload after the company ID, as both OS APIs return it):

| ID | Payload | Expected | Source |
|---|---|---|---|
| T-01 | `01 80 63` | v1 · battery 2990 mV · low no | ✅ formula |
| T-02 | `01 C0 4B` | battery 2750 mV · low yes | ✅ formula |
| T-03 | `01 00` | no values | ✅ |
| T-04 | `01 80` | truncated (battery promised) | rule |
| T-05 | `02 80 63` | unsupported version, raw kept | rule |
| T-06 | `01 BF 08 B4 2D 80 0C F6 00 5A 64` | 22.28 °C · 45 % · magnet present + detected · moving · count 12 · pitch −10° · roll 90° · 3000 mV | 🟡 |
| T-07 | `01 01 FF 38` | −2.00 °C | 🟡 |

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
| P5 | Android hardening: permission flow, foreground service, scan limits; Windows and Android release builds | 8 h unattended scan on a phone | 3–4 d |
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

## 11. Risks

| Risk | Mitigation |
|---|---|
| `universal_ble` scans passively on Windows → no battery | read its source in P0; native WinRT scanner if needed |
| Eddystone service data not exposed on a platform | same; native scanner for that platform only |
| Laptop adapter drops scan responses | test a second adapter; a beacon with the frame off sends the block in the advertisement |
| Android filters / throttling | rules in §5 |
| Sensor field layout (🟡) wrong | confirm with the BTSMP1 page and a capture before P2 ends |
| MAC is random on some firmware | key by beacon ID if the address changes between sessions |

## 12. Development setup

| Need | Status 09-11-2026 |
|---|---|
| Flutter SDK (stable) | **installed** — 3.47.9 / Dart 3.13.7 at `C:\Users\GT2575\develop\flutter`; add `...\flutter\bin` to PATH |
| Visual Studio 2022, workload *Desktop development with C++* | **missing** — needed to build the Windows app |
| Android Studio (SDK + platform tools) | **missing** — needed to build the Android app |
| Windows Developer Mode | **off** — Flutter plugins need it on Windows |
| Android phone, USB debugging on | needed — the emulator has no Bluetooth |
| Bluetooth LE radio in the laptop | present |

Commands: `flutter pub get` · `flutter analyze` · `flutter test` · `dart test` (in
`packages/eye_protocol`) · `flutter run -d windows` · `flutter run -d <phone>`.

## 13. Inputs still needed

1. **EYE SENSOR / BTSMP1 wiki page** saved as PDF here — confirms the 🟡 sensor fields.
2. **Raw captures** (nRF Connect → raw data) from one BTSID1 and one BTSMP1, advertisement and scan
   response.
3. If tracker records should carry sensor values: the tracker's AVL ID list for EYE sensor
   temperature, humidity, movement and angle.
