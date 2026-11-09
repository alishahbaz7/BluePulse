# Changelog

The version is declared once, in `pubspec.yaml`; each version is worked on a branch of the same name.
Releases are named `BluePulse-v<version>`.

## 1.0.0

First version: see the live state of Teltonika EYE BEACON (BTSID1) and EYE SENSOR (BTSMP1) devices
on a Windows laptop or an Android phone from one codebase, and decode what Teltonika trackers report
about them.

- **Protocol decoders** (`packages/eye_protocol`, pure Dart): Eddystone-UID, iBeacon, the Teltonika
  `0x089A` block (flags, battery `2000 + value × 10` mV, low battery; EYE SENSOR values provisional
  until confirmed against the BTSMP1 page), Codec 8 / 8 Extended with CRC-16/IBM, AVL 385 and
  10828 / 10829 / 10831. Verified against both tracker packets on the BTSID1 wiki page.
- **Live scanning** through `universal_ble` (active scanning on Windows, so the scan response that
  carries the battery arrives), advertisement and scan response merged per MAC, repeats folded into
  one reading, RSSI smoothed like the tracker's averaging timeout, *not seen* after three intervals.
- **Pages**: Overview, Devices, Device detail with charts, Packets with every byte named, Proximity
  (tracker Near / Away / Lost thresholds), Decode (paste a tracker packet, AVL value or BLE packet),
  Settings. House utility look, dark and light, sidebar on the laptop and a drawer on the phone.
- **Demo data**: a labelled generator of EYE traffic as real packet bytes, for running without
  hardware; the web build uses it always.
- **Updates over the air**, so people keep one pinned program and update themselves: a 46 KB
  launcher (built with Windows' own C# compiler, no runtime to install) starts the newest version
  under `versions\`; the app checks the public releases repository's `latest.json` on every start
  (through GitHub's `latest/download` address, so no API rate limit), offers the update with its
  notes, downloads it, refuses it unless the SHA-256 matches, installs it beside the running one and
  restarts through the launcher. The previous version is kept (hold Shift on the launcher to pick
  it). Android downloads and verifies the APK and opens the system installer. `minimumVersion` in
  `latest.json` can make an update required; otherwise *Later* is always offered.
- **Release packaging**: `tool/package_release.dart` builds the zip (launcher + version folder), the
  APK, `latest.json` with checksums and the notes from this changelog.
- **Not yet**: on-air test with real devices (toolchains pending), Sessions / CSV export, Android
  background scanning, configuring devices over GATT.
