# Changelog

The version is declared once, in `pubspec.yaml`; each version is worked on a branch of the same name.
Releases are named `BluePulse-v<version>`.

## 1.0.1

- **Sessions**: every live scan is saved, from *Start scan* to *Stop scan*, so a test can be looked
  at afterwards without having pressed Record first. Each session is one CSV with the same columns
  as a device's packet log — every packet from every EYE device and beacon, in focus or not, with
  decoded values and raw bytes — in `Documents\BluePulse\sessions` on Windows. The new *Sessions*
  page lists them (start, duration, devices, packets, size) to open in Excel, save a copy (share on
  Android) or delete. Closing the window saves the session whole; a session the app could not close
  (a crash, the PC switched off) is kept up to its last second and marked *Interrupted*. A scan that
  heard nothing leaves no file, and demo data is never recorded. *Settings → Record every scan*
  turns it off.
- **Simulator** (*Transmit → Simulator*): this device transmits as an EYE SENSOR, EYE BEACON or
  iBeacon, so a receiver — BluePulse on another device, a Teltonika tracker — can be checked against
  a known signal: if it advertises every 2 s, every 2 s is what should arrive. Interval 100 ms – 10 s,
  transmit power, name, the EYE SENSOR protocol type (EYE Sensors, or Eddystone / iBeacon + EYE
  Sensors), Eddystone / iBeacon IDs, and values that change by themselves like a real sensor's
  (temperature and humidity drifting around the set value, movement events, angles shaking while
  moving, the battery sagging, a magnet coming and going) or stay as set. *Count updates* makes the
  movement count a packet counter, so a receiver can count exactly which updates it missed. The
  packets are built by encoders that are the decoders' exact inverse, and shown decoded on the page.
  Android keeps the interval exactly and advertises the name by renaming the phone's Bluetooth while
  it transmits (named back on Stop); Windows, which sets its own advertising rate and sends no name,
  sends a short burst every interval.
- **EYE SENSOR fields confirmed** against the BTSMP1 wiki page: temperature, humidity, movement and
  angle were decoded on the provisional layout, and the page's frame example (22.28 °C, 18 %, 3275
  movements, pitch 11°, roll −57°, 3030 mV) now decodes exactly — and the encoder rebuilds it byte
  for byte. Nothing changed in the decoding; it is no longer a guess.
- **A friendlier welcome**: the first-start question is now "Hi! May I have your name, please?",
  saying the name is used to greet you and improve BluePulse — and still where to see what is
  shared.
- **Fixed — Android could not reach the internet.** The 1.0.0 APK was built without Android's
  internet permission (Flutter's template grants it to development builds only, so every test run
  had it), so on a phone the update check said "No connection to github.com" and usage reports
  stayed queued. Phones on 1.0.0 therefore cannot update themselves: install 1.0.1 by hand once;
  from then on updates arrive in the app. Reports queued on those phones are sent after the update.
  A test now fails the build if the release manifest loses the permission. Windows was not affected.
- Fixed: on a narrow phone the page's section name under the title could wrap and spill out of the
  top bar.

## 1.0.0

First version: see the live state of Teltonika EYE BEACON (BTSID1) and EYE SENSOR (BTSMP1) devices
on a Windows laptop or an Android phone from one codebase, and decode what Teltonika trackers report
about them.

- **Protocol decoders** (`packages/eye_protocol`, pure Dart): Eddystone-UID, iBeacon, the Teltonika
  `0x089A` block (flags, battery `2000 + value × 10` mV, low battery; EYE SENSOR values provisional
  until confirmed against the BTSMP1 page), Codec 8 / 8 Extended with CRC-16/IBM, AVL 385 and
  10828 / 10829 / 10831. Verified against both tracker packets on the BTSID1 wiki page.
- **Live scanning on Windows through BluePulse's own native scanner** (`packages/bluepulse_ble_windows`,
  C++/WinRT): every advertisement and scan response exactly as Windows receives it, raw bytes included.
  Measured on real EYE sensors, `universal_ble`'s Windows scanner dropped every repeated advertisement
  with the same fields — the ones carrying new temperature, movement and battery values — and copied
  the old values into the scan responses it did pass, so readings looked live but stayed frozen.
  Android keeps `universal_ble`. Advertisement and scan response merged per MAC, repeats folded into
  one reading, RSSI smoothed like the tracker's averaging timeout, *not seen* after three intervals.
- **Your own names for devices**, kept on this computer and shown everywhere, so a device is easy to
  find; the Devices list sorts by name by default so it no longer reshuffles with every RSSI change.
- **Focus**: tick devices to give them every packet and up to ten screen refreshes a second; the rest
  fade and refresh every 2–10 s depending on how busy the radio is, while still being counted exactly.
  Opening a device's page focuses it for as long as the page is open. A packets-per-second column
  makes the received rate visible. Out of focus, a device's whole advertising event is applied when
  its turn comes, so an EYE BEACON in Eddystone mode (name and battery in the scan response) is still
  recognised and listed.
- **Device page**, for judging how well a beacon is heard:
  - *Pings* — a ping is one advertising event (advertisement + scan response): count, average,
    shortest, longest and last gap, jitter, and *Received %* against the advertising interval estimated
    from the shortest common gap; a gap-over-time chart shows dropouts.
  - One time window — 5, 10 or 15 min, in a bar that stays in view — for every chart and the pings.
  - Every chart shows Now · Avg · Min · Max for the window.
  - *Arrange*: order the charts, show or hide each, half or full width; kept per device type.
  - *Received packets*: every packet from the device, live, with gap, decoded values and raw bytes
    (the last 5,000 kept, also for devices out of focus). *Save log* writes a CSV (Excel-ready) of the
    window or of everything kept — a save dialog on Windows, the share sheet on Android — and *Record*
    writes each packet to a CSV while a long test runs.
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
  APK, `latest.json` with checksums and the notes from this changelog. The Microsoft C++ runtime
  (`msvcp140`, `vcruntime140`, `vcruntime140_1`) goes inside each version folder, so a fresh,
  locked-down PC needs nothing installed — only the build machine needs Flutter and Visual Studio.
  The APK is signed with BluePulse's own release key, so every later version installs over it; a
  phone holding an earlier test copy (development-signed) uninstalls that once.
- **Usage monitoring**, so the team knows who uses BluePulse and how: at the first start the app asks
  your name — and greets you by it on the Overview page — then reports it with the Windows sign-in
  and computer name (or the phone model), the version, each start (how long it was open, time
  scanning, how many devices it heard, which pages were opened), updates and app errors. Starts made
  offline are kept and sent later. Beacon addresses, packets and location are never reported.
  Settings → *Usage reporting* shows what this copy reports as.
- **Tested on air** with EYE BEACON and EYE SENSOR devices on a Windows 11 laptop and an Android phone
  (moto g57 power).
- **Not yet**: Sessions (saved scans to replay and compare), Android background scanning,
  configuring devices over GATT, the BLE / Bluetooth Classic serial terminal.
