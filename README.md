# BluePulse

Bluetooth and BLE workbench for Windows and Android, in Flutter. First module: Teltonika
**EYE BEACON (BTSID1)** and **EYE SENSOR (BTSMP1)** — live scanning, decoding, charts — plus a decoder
for the beacon records Teltonika trackers send (Codec 8 / 8 Extended). Next: a BLE / Bluetooth Classic
serial terminal.

The plan, protocol reference, decisions and test cases are in [PLAN.md](PLAN.md). The protocol sources
are the Teltonika wiki pages (BTSID1, BTSMP1, the MESH pages), saved as PDF in the project folder on
the development computer only: reference and training material is git-ignored and never pushed.

## Layout

```
packages/eye_protocol/   pure-Dart decoders and encoders (no Flutter) + tests
  lib/src/teltonika.dart    0x089A block: flags + values
  lib/src/eddystone.dart    Eddystone-UID
  lib/src/ibeacon.dart      iBeacon
  lib/src/encode.dart       the inverse: Teltonika block, Eddystone-UID, iBeacon (for the simulator)
  lib/src/advertisement.dart  AD structures → fields, merge, rebuild
  lib/src/inspect.dart      byte-by-byte labels for the packet inspector
  lib/src/codec8e.dart      Codec 8 / 8E framing + CRC-16/IBM
  lib/src/avl_beacons.dart  AVL 385 and 10828 / 10829 / 10831
packages/bluepulse_ble_windows/  Windows BLE (C++/WinRT): the scanner (every packet, raw) and the
                                 transmitter (a publisher per burst)
packages/bluepulse_ble_android/  Android BLE transmitter (Java, AdvertisingSet): exact interval, power, name
lib/
  app/        settings (persisted), controller (scanner ↔ registry), file folders, AppScope
  scanner/    BeaconScanner · WindowsBleScanner (live, Windows) · UniversalBleScanner (live,
              Android) · DemoScanner (simulated)
  core/       DeviceRegistry, EyeDevice, DeviceBook (names, focus, chart layout), ping stats,
              received-packet log, sessions, RSSI smoothing, proximity, distance
  simulator/  what to transmit (profiles, values that change by themselves), the per-platform
              advertiser, and the service that runs a simulation
  ui/         theme tokens, nav definition, shell (rail + top bar), pages, widgets
  update/     release channel: check, download, verify, install
  usage/      usage reports (who uses it and how) and their offline queue
backend/supabase/usage.sql   server side of usage reporting
test/         core logic + widget tests; test/visual renders screens to PNG (EYE_SHOTS)
```

## Simulator — transmitting to test receivers

*Transmit → Simulator* makes this device advertise as an **EYE SENSOR** (protocol *EYE Sensors*, or a
beacon frame + EYE Sensors), an **EYE BEACON** (Eddystone or iBeacon, battery block) or a plain
**iBeacon**, at an interval from 100 ms to 10 s, with values that change by themselves (*Auto*) or
stay as set. Receivers — BluePulse on another device (its *Pings* card shows the gaps), a Teltonika
tracker — show what really arrives. *Count updates* turns the EYE SENSOR movement count into a packet
counter, so missed updates can be counted exactly.

| | Android (8+) | Windows |
|---|---|---|
| Interval | exact, kept by the radio (AdvertisingSet) | Windows sets its own rate: one burst (60–500 ms, half the interval) every interval |
| Name | the phone's Bluetooth is renamed while transmitting and named back on Stop (also at the next start if the app was closed mid-run) | none — Windows refuses a name (tested: both the LocalName property and a raw 0x09 section) |
| Scan response | yes | none — the scan response's data goes out in alternate bursts |
| Transmit power | ultra low −21 / low −15 / medium −7 / high +1 dBm | taken as a preference where Windows supports it |
| Address | random, chosen by Android, changed every few minutes; apps cannot read it | random, a new one **for every burst**; apps cannot read it |

Neither platform lets an app choose or read the address it sends from, so a simulated device has no
MAC to look up. Instead each packet with room carries the **BluePulse tag** — manufacturer data for
company `0xFFFF` (kept by the Bluetooth SIG for tests), `B` `P` and a 4-byte ID, 10 bytes in all —
and a BluePulse receiver lists every packet with the same ID as **one device, `SIM-1A2B3C4D`**, in
place of a MAC (the *Receiver* tile on the Simulator page shows which). A simulated beacon's ID follows
from its beacon ID, so the beacon frames Windows sends in bursts of their own, with no room left for
the tag, join the same device. The tag never pushes out a name (on Android an EYE SENSOR's name
leaves it no room; that device is listed by its name and address as before). *BluePulse tag* off
sends only what a real device sends.

## Setup

| Need | For |
|---|---|
| Flutter SDK (stable; installed at `C:\Users\GT2575\develop\flutter`) — add `…\flutter\bin` to PATH | everything |
| Visual Studio 2022 with *Desktop development with C++* | Windows build |
| Windows **Developer Mode** on (`start ms-settings:developers`) | Windows build (plugins need symlinks) |
| Android Studio (SDK + platform tools), a phone with USB debugging | Android build — the emulator has no Bluetooth |

## Run it

The app starts from **main.dart in this folder** (it hands over to `lib/main.dart`, where Flutter
builds from). Three ways:

- **Double-click `run.bat`**, or type in a terminal here:
  ```
  run              browser (Edge) with demo data - works now
  run windows      Windows app with live Bluetooth (needs VS C++ workload + Developer Mode)
  run android      phone over USB (needs the Android SDK)
  run test         all tests: app, protocol decoders, launcher
  run doctor       what is installed and what is missing
  ```
  `run.bat` works even where PowerShell scripts are blocked, and finds Flutter on PATH or at
  `%USERPROFILE%\develop\flutter`.
- **VS Code:** open this folder, accept the *Flutter* extension it recommends, then press **F5** and
  pick *BluePulse - browser*, *Windows* or *Android* in Run and Debug.
- **Flutter on PATH:** `flutter run -t main.dart`.

While it runs: `r` hot reload, `R` restart, `q` quit.
## Commands

```powershell
flutter pub get
flutter analyze
flutter test                                   # app: core + widgets
cd packages/eye_protocol; dart test; cd ../..  # protocol decoders

flutter run -d windows                          # live scanning on the laptop
flutter run -d <android-device-id>              # live scanning on the phone
flutter run -d chrome                           # demo data only (browsers cannot scan)
```

## Demo data

*Settings → Scanning → Source → Demo data* swaps the radio for a generator of EYE BEACON and EYE
SENSOR traffic. It produces real advertisement bytes, so the decoders, registry and every page run
as they would on air. The top bar says **Demo data** whenever it is on. The web build always uses it.

The web build opens a given view from its URL, for demos and screenshots:
`?page=devices|deviceDetail|packets|proximity|decode|settings`, `&mac=DE:40:00:00:01:01`,
`&theme=light|dark|auto`, `&hex=<tracker packet or AVL value>`.

## Where files go

| What | Windows | Android |
|---|---|---|
| Sessions — every live scan, Start to Stop (`lib/core/session_store.dart`) | `C:\Users\<you>\BluePulse\sessions` | `Documents/BluePulse/sessions`, shared from the Sessions page |
| Device logs (*Record*, *Save log*) and multi-device logs (*Devices → Log*) | `…\BluePulse\logs` | `Documents/BluePulse/logs`, also through the share sheet |
| Error log — one line per event (`lib/core/error_log.dart`) | `…\BluePulse\BluePulse_errors.log` (+ `.1.log`) | `Documents/BluePulse/BluePulse_errors.log` |
| Update downloads | beside the installed versions (`versions\.download`) | the app's cache (the system installer reads it there) |

One folder per device, set in `lib/app/paths.dart`. On Windows it sits beside Documents, not in
it: Documents is often synced by OneDrive, which would upload a growing log every few seconds. On
Android, *Internal storage › Documents › BluePulse* is visible in the Files app and over USB; a
development build uses `BluePulse DEV` (Android lets each app open only the files it made). Where
that folder cannot be written, the app's own folder is used and the error log says so.
*Settings → Files* shows the folder, changes it (any folder on Windows; Documents or Download on a
phone, the files already saved moving along if wanted) and opens the error log.

Both are CSV with the same columns (`RxCsv` in `lib/core/rx_log.dart`); a session's summary (start,
end, packets, devices) sits beside it as `.json`.

## Versions

The version is declared **once**, in `pubspec.yaml` (`version: 1.0.0+1`); the app reads it at run
time (package_info_plus) and the Windows and Android builds take it from there too. Each version is
worked on a branch of the same name (`1.0.0`), never on `main`, and gets a section in
[CHANGELOG.md](CHANGELOG.md). Releases are named `BluePulse-v<version>`.
`test/version_test.dart` fails the build if any of this drifts.

## Updates and releases

People pin one program, the launcher; the app updates itself (PLAN.md §10a).

```powershell
powershell -File launcher\build.ps1          # launcher (46 KB, Windows' own C# compiler)
powershell -File launcher\test-launcher.ps1  # launcher checks
dart run tool/package_release.dart --build   # dist\: zip, apk, latest.json
```

Releases are published to the public repository **github.com/alishahbaz7/BluePulse** (source and
releases together), set once in `lib/update/update_config.dart`; the packaging tool reads it too.
To try updates against a local server: `--dart-define=UPDATE_MANIFEST_URL=http://127.0.0.1:8000/latest.json`.

**Publishing a release** (in the browser, no tools needed): on github.com/alishahbaz7/BluePulse →
*Releases* → *Draft a new release*, tag `v<version>` on the version's commit, title
`BluePulse <version>`, paste `dist\notes.md`, attach `BluePulse-v<version>.zip`, `.apk` and
`latest.json`, and publish it as the **latest** release (not a pre-release) — copies find updates
through `releases/latest/download/latest.json`. With the GitHub CLI signed in, the packaging tool
prints the one-line equivalent.

**Android signing:** every APK must carry the same release key, or phones refuse the update. The key
was created once for 1.0.0 (`keytool -genkeypair -keystore bluepulse-release.jks -storetype PKCS12
-alias bluepulse -keyalg RSA -keysize 2048 -validity 10000`) and lives in this folder's `keys\`
(git-ignored, never pushed) beside a copy of its properties, which the build reads as
`android/key.properties` (git-ignored). To build on another machine, copy `keys\` with the project
and copy `keys\bluepulse-key.properties` to `android\key.properties`:

```
storeFile=../../keys/bluepulse-release.jks
storePassword=…
keyAlias=bluepulse
keyPassword=…
```

Without it, release builds are debug-signed and the packaging tool will not publish an APK. A phone
holding a debug-signed test copy must uninstall it once before installing a release.

## Usage monitoring

Each copy reports who uses it and how to a Supabase project (PLAN.md §10b): the name asked at the
first start (the Overview page then greets the person by it), Windows login and computer name or
phone model, version, every start, updates and errors. The same server serves every app; each report
names its app, and `backend/supabase/README.md` is the format for adding it to another app.

The server is the Supabase project *BluePulse* (Mumbai); its address and publishable key are the
defaults in `lib/usage/usage_config.dart`, and `dart run tool/usage_check.dart` checks it without
storing anything. The key is public by design: it can write reports, never read them. Development
runs (`run.ps1`, `flutter run`) report nothing unless `--dart-define=USAGE_URL=…` is passed. To move
to another project or a self-hosted server: run `backend/supabase/usage.sql` there and change the two
defaults (PLAN.md §10b *Setup*).

**The user list:** Supabase → Table Editor → schema `usage` → `users`. Also `recent_sessions`,
`daily`, `versions` and `activity`. To try another server: `--dart-define=USAGE_URL=…
--dart-define=USAGE_KEY=…`.

## Conventions

- UI follows the house utility look (`utility-ui` skill): tokens in `lib/ui/theme.dart`, one nav
  definition in `lib/ui/nav.dart`, no help text on pages (hold-tips instead), mono IDs, data grids.
- Protocol fields are marked verified or provisional in PLAN.md §3 (the EYE SENSOR layout is verified from
  the BTSMP1 page); never invent a field.
- Debug builds show a **DEV** badge and keep their own settings.
