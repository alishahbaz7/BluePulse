# BluePulse

Bluetooth and BLE workbench for Windows and Android, in Flutter. First module: Teltonika
**EYE BEACON (BTSID1)** and **EYE SENSOR (BTSMP1)** — live scanning, decoding, charts — plus a decoder
for the beacon records Teltonika trackers send (Codec 8 / 8 Extended). Next: a BLE / Bluetooth Classic
serial terminal.

The plan, protocol reference, decisions and test cases are in [PLAN.md](PLAN.md). The protocol source
is the BTSID1 wiki page saved as PDF in this folder.

## Layout

```
packages/eye_protocol/   pure-Dart decoders (no Flutter) + tests
  lib/src/teltonika.dart    0x089A block: flags + values
  lib/src/eddystone.dart    Eddystone-UID
  lib/src/ibeacon.dart      iBeacon
  lib/src/advertisement.dart  AD structures → fields, merge, rebuild
  lib/src/inspect.dart      byte-by-byte labels for the packet inspector
  lib/src/codec8e.dart      Codec 8 / 8E framing + CRC-16/IBM
  lib/src/avl_beacons.dart  AVL 385 and 10828 / 10829 / 10831
lib/
  app/        settings (persisted), controller (scanner ↔ registry), AppScope
  scanner/    BeaconScanner · UniversalBleScanner (live) · DemoScanner (simulated)
  core/       DeviceRegistry, EyeDevice, RSSI smoothing, proximity, distance
  ui/         theme tokens, nav definition, shell (rail + top bar), pages, widgets
  update/     release channel: check, download, verify, install
  usage/      usage reports (who uses it and how) and their offline queue
backend/supabase/usage.sql   server side of usage reporting
test/         core logic + widget tests
```

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

**Android signing:** every APK must carry the same release key, or phones refuse the update. Create
it once (needs a JDK: `keytool -genkey -v -keystore eye-release.jks -keyalg RSA -keysize 2048
-validity 10000 -alias eye`), keep it **outside the repo and backed up**, and point
`android/key.properties` (git-ignored) at it:

```
storeFile=C:/Users/<you>/keys/eye-release.jks
storePassword=…
keyAlias=eye
keyPassword=…
```

Without it, release builds are debug-signed and the packaging tool will not publish an APK.

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
- Protocol fields not yet confirmed (EYE SENSOR value layouts) are marked provisional in PLAN.md §3.4
  and in `teltonika.dart`; never invent a field.
- Debug builds show a **DEV** badge and keep their own settings.
