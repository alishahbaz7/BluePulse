# Changelog

The version is declared once, in `pubspec.yaml`; each version is worked on a branch of the same name.
Releases are named `BluePulse-v<version>`.

## 1.0.3

In progress.

## 1.0.2

- **A pin counts only while its device is in the list.** Pins are kept between runs, so a device
  pinned in 1.0.0 that is not in range today stayed pinned: the top bar said *Pinned · 1* on every
  page, the Devices page showed nothing pinned (and so no *Unpin all*), and — worse — focus was on,
  so every device on screen was applied only every 2–10 s and the Packets page missed their
  packets, for a pin nobody could see. Now focus is on only while a pinned device is in the list
  (or a device's page is open); the pin waits, and counts again the moment that device is heard.
  Logs, sessions and recordings were never affected: they get every packet either way.
- **Every device stays live, like the EYE app.** Side by side on the same phone, the EYE app's
  values moved the instant a packet arrived while BluePulse could sit frozen for seconds. The cause:
  a device *out of focus* had its packets counted but its values left unchanged until its turn came
  round — every 2 s on a quiet radio, up to 10 s on a busy one — so in a crowded room a beacon could
  show the same reading for ten seconds while its packets kept pouring in. (With the pin above, one
  stale pin froze *every* device that way.) Now every packet is decoded and applied for every device,
  in focus or not, so the whole list is as current as the radio. Focus still matters, but only for
  how often the screen is redrawn: a pinned device, or an open device's page, is redrawn with every
  packet; the rest are redrawn once a second so a long list stays smooth. The Packets page, logs,
  sessions and recordings always got every packet — now the screen keeps up with them.
- **No *Pinned · N* chip in the top bar**: it repeated the Devices page, which shows the pinned
  devices in their own section with their count and the bar to unpin them.

## 1.0.1

- **The Windows title bar follows BluePulse's theme**, not the system's: on a laptop set to light
  mode, the dark app sat under a white title bar. The window code (`windows/runner`) now takes its
  colours from the app over a `bluepulse/window` channel — dark or light, and on Windows 11 the
  exact colour of the app's top bar, so the two read as one (checked: both `#0F1216`). The colours
  are sent before the window first shows, so it never flashes white, and again whenever the theme
  changes (Settings, or the system's on *Auto*); a change of Windows' own colours no longer
  overrides them. Windows 10 takes dark or light.
- **The side rail says who it is plainly**: *BluePulse*, then *Version 1.0.1* (and *DEV* on a
  development copy). Gone: the *Bluetooth workbench* tagline, the legend under the menu and the
  *BT* letters on menu items while Bluetooth is off — those items now carry a crossed-out
  Bluetooth mark that explains itself when hovered or held.
- **Tile view or list view, the same everywhere.** On a wide screen, Configure listed devices as
  tiles while the Devices page showed a table. A switch beside each device list's title (tile icon,
  list icon) now chooses for all of them at once — Devices, Configure's *Choose a device* and the
  Overview's *Strongest signals* — and is kept between runs. Tile view is the card a phone shows
  (signal bars, values as icons, sorted by the menu, pinned devices first); list view is the
  Devices table, with the same columns on Configure (without the pin). A phone always shows tiles.
- **Tiles in the order they were found, by default** (*Sort → As found*): each device keeps the
  place it took when the app first heard it, a new device joins at the bottom, and nothing jumps
  when signals change. A device no longer heard is greyed in place, its last values still readable —
  as a tile and as a table row, whatever the order. The order chosen (As found, Name, Strongest,
  Lowest battery, Last heard) is kept between runs and is the same on Devices and Configure.
- **Pinned devices in their own section**: tiles show *Pinned · N* above and *Other devices · N*
  below, each in the chosen order; the table draws a line under its last pinned row.
- **One BluePulse folder on each device, for everything it saves.** Laptop: `C:\Users\<you>\BluePulse`
  — beside Documents, not in it, because Documents is often synced by OneDrive (it is on the
  development laptop), which uploaded every session and would re-upload a growing 24-hour log every
  2 seconds. Phone: *Internal storage › Documents › BluePulse*, which the Files app shows and a laptop
  sees over USB (before, files sat inside the app where nobody could reach them; a development copy
  uses *BluePulse DEV*). Inside: `sessions`, `logs`, `BluePulse_errors.log` and a README. Sessions and
  logs from earlier versions are brought over once — copied on Windows (the OneDrive originals are
  left alone), moved on Android. **Settings → Files** shows the folder, opens it (Windows) and
  changes it: any folder on Windows (a picked `D:\Data` becomes `D:\Data\BluePulse`), Documents or
  Download on a phone (the only shared folders Android lets an app write its own files to). The
  files already saved can move along (on by default; a rename on the same drive, copy then delete
  across drives), a scan being recorded is closed and carries on in the new folder, and the change
  waits while a log or a device recording is writing. A chosen folder that cannot be written at a
  later start (a USB drive unplugged) gives way to the default for that run, and the error log says
  so. Update downloads stay where the system needs them: beside the installed versions on Windows,
  in the app's cache on Android.
- **Error log**, so a fault can be tracked down afterwards without anyone having watched it happen:
  `BluePulse_errors.log` in the BluePulse folder, one plain line per event — time, level, which part
  of the app, what happened, in words. Errors nobody handled are written with the top of their stack,
  in every build (before, only release builds recorded them, and only to the usage server). Failures
  the app handles quietly are written as warnings: an update check that could not reach GitHub, a
  usage report waiting for the next try, a scan the radio refused, the background scanning service
  refused, a GATT connection retried or failed, a setting not saved, a file not written, damaged
  saved settings. Each run starts with a line naming the version. The same event again is counted
  (*… 49 more times*), not repeated; past about 1 MB the file moves to `.1.log`, so two files at
  most. *Settings → Files* counts this run's problems; *View log* lists its events, newest first,
  with *Open file* (Windows) or *Share file* (phone). Nothing is ever shown unasked.
- **Updates and usage reporting never get in the way, whatever the network does.** Checked case by
  case: no network, GitHub or Supabase down, a server that accepts the connection and never answers,
  a connection dropped halfway, a proxy or Wi-Fi sign-in page answering instead, a broken
  `latest.json`. Fixed: a connection dropped mid-download left the update at *Downloading…* until
  the app restarted, and one dropped while reading `latest.json` — or a `latest.json` with a value of
  the wrong type — left it at *Checking for updates…*; every failure now ends as *failed* (shown only
  in Settings) and can be tried again, and the running version is never touched. The first-start
  name prompt no longer waits for the usage server (up to a minute on a slow network): the name is
  saved at once and sent in the background. One usage send gives up after 30 seconds instead of
  possibly never, so reporting cannot stall for the rest of a run; anything unexpected is caught and
  the reports wait on the device. While sends fail, the next try waits longer — 10, 20, then every
  30 minutes — instead of every 5. The server ignores a report it already has, so a send that timed
  out but arrived is harmless. New tests include a real HTTP server that drops the connection
  halfway through `latest.json` and halfway through the download.
- **Multi-device log made for long runs** (6 or 24 hours): rows reach the file every 2 seconds
  instead of at *Stop* (a crash loses seconds, not hours), and a file that reaches a million rows
  carries on in `…_part2.csv`, so each part opens in Excel; *Stop log* shares or shows every part.
- **Sessions**: every live scan is saved, from *Start scan* to *Stop scan*, so a test can be looked
  at afterwards without having pressed Record first. Each session is one CSV with the same columns
  as a device's packet log — every packet from every EYE device and beacon, in focus or not, with
  decoded values and raw bytes — in the BluePulse folder's `sessions`. The new *Sessions*
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
- **Simulator — finding the simulated device on a receiver.** Windows sends every burst from a new
  random address and no name, so a phone receiving a simulated EYE SENSOR listed a new device every
  2 s, none of them recognisable. Packets now carry the *BluePulse tag* (company `0xFFFF`, kept for
  tests: `B` `P` and a 4-byte ID, 10 bytes) wherever they have room, and BluePulse lists everything
  with the same tag as one device, `SIM-1A2B3C4D`, in place of the MAC — its *Pings* card works again.
  Beacon frames sent without the tag join it through their beacon ID. The Simulator page's new
  *Receiver* tile shows what to look for (that ID, else the name or beacon ID) and warns when nothing
  identifies the device; the device page shows *Simulator* and the last random address. A switch turns
  the tag off. On Windows the page no longer shows a name that is not sent.
- **Fixed — Android stopped hearing anything after 5 minutes.** Android moves an unfiltered scan
  that has run too long to "opportunistic" (results only while another app scans): on a moto g57 power
  (Android 17) every device turned *Lost* exactly 5 minutes after Start while the app still said it
  was scanning (logcat: `Moving unfiltered scan to opportunistic scan`; older Android allowed 30
  minutes). The scan now restarts itself every 4 minutes; the device list and the session carry on. Separately, Android runs an app's scan at low power while the
  screen is off or locked (`mode[LOW_LATENCY, used=LOW_POWER]`), so a phone hears far fewer pings then —
  keep the screen on for a measurement.
- **Fixed — Android simulator name.** Changing the interval, power or profile restarted the
  transmission by giving the phone its own Bluetooth name back and renaming it at once; Android could
  still report the old name, so the simulated name could be kept as the phone's "original" (and stay
  after Stop) or the real name went on air. A restart now keeps the name, and a quick Stop → Start
  remembers the name being put back.
- **Configure** (*Device → Configure*, or *Configure* on a device's page): every setting of an EYE
  SENSOR or EYE BEACON over Bluetooth — name, protocol type, sensors on/off, advertising interval,
  repeats and their spacing, TX power, iBeacon and Eddystone IDs, movement start/stop, hibernation,
  wake-up advertising, RSSI calibration — with the device's model, firmware and live readings. Enter
  the PIN (123456 unless changed) and Connect; changed fields show what they were; values the device
  would refuse are marked and never sent; *Save* writes only what changed, reads each back from the
  device and then saves to flash, and says which settings took. Restart and Restore factory settings
  are in the device menu, behind a confirmation. *Reporting* shows what the settings give a receiver:
  a reading every interval and, with repeats, several chances at it (≈ 83 % on time with 3 repeats,
  against ≈ 45 % with one, at the reception measured on a phone). The protocol follows Teltonika's
  table, checked byte for byte against a recorded EYE App session (PIN as ASCII digits, little-endian
  numbers, `00 10` to save).
- **Settings → About** replaces the Updates, Usage reporting and About cards: BluePulse and its
  version, one line saying whether it is up to date (or which version is available, with *Update*),
  *Check for updates*, and the name it greets and reports as with *Edit name*. *Details* holds only
  the latest version, the last check, the platform, the build and the install ID, for support.
- **Cleaner screens**: search is a small button that opens a box (an active search shows as a chip to
  clear); every other row of a table or list is tinted; the top bar's *Bluetooth on* chip, *Scanning ·
  N* chip and module subtitle are gone. A phone turned sideways keeps the phone layout, with cards two
  to a row.
- **Android keeps scanning with the screen off or another app in front.** A foreground service
  (notification "BluePulse is scanning") holds the scan, and the scan is filtered at the radio to
  what BluePulse reads (Teltonika data, iBeacon, Eddystone, the simulator tag): Android pauses
  unfiltered scans with the screen off but keeps filtered ones, and the app is woken only for those
  packets. Scanning is now legacy, on the 1M PHY only — it had also listened on Coded PHY, which no
  EYE device uses (HCI log). Benchmarked on a moto g57 power against Teltonika's EYE App 1.6.0 with
  the same two sensors: same reception while both scan (average gap 4.7 s for a sensor sending every
  2.2 s), but the EYE App's scan is cut by Android after 5 minutes and it then hears nothing while
  still showing the old values; BluePulse carries on.
- **Device cards and tiles read at a glance**: signal bars, distance, thermometer, droplet, moving or
  still with the movement count, magnet, battery level in volts and a live / lost dot replace labelled
  figures (the meanings are hold-tips); tiles carry icons. On a phone the Overview drops *Readings /
  min* and its chart and puts *Needs attention* last.
- **Simulator on Windows: fewer missed pings.** A phone receiving a 2 s simulation saw gaps of up to
  10 s (3 s on average): each 200 ms burst held only one or two advertisements. Windows is on air
  ~20 ms after a burst starts (measured), so bursts are now half the interval, up to 500 ms — still
  one ping each on the receiver, which folds anything within 600 ms.
- **Smoothed and Rate removed** from the device page tiles and the Devices table; the Overview's
  *Strongest signals* shows and sorts by RSSI (the signal chart still draws the smoothed line).
- **Log several sensors** (*Devices*: pin them, then *Log*): every packet from the pinned devices, as it
  arrives, to one CSV — time (local, to the millisecond, and UTC), MAC, the interval since that
  device's previous packet, its name, every value it carried (temperature, humidity, battery and the
  low-battery flag, moving, movement count, pitch, roll, magnet), RSSI, advertisement or scan response,
  the beacon ID, the Teltonika version and flags, and the raw bytes. A gap on air shows as a longer
  interval. The bar shows the log running (devices, time, packets) until *Stop log*, which saves it to
  the logs folder (*Open folder* on Windows, the share sheet on Android).
- **Pin devices to the top** (*Devices*): the pin on a card or in the table keeps a device above the
  rest in any sort order; pinned devices also get every packet and the fastest refresh, and are what
  *Log* records. Nothing else fades any more. *Unpin all* clears them.
- **One Bluetooth button** in the top bar starts and stops the scan and shows the radio: glowing while
  scanning, plain while Bluetooth is on and idle, grey while it is off or not permitted (a tap turns it
  on or asks for the permission). The separate *Start scan* / *Stop scan* button is gone.
- **Devices** shows how many once, in the list title ("Devices 16", "3 of 16" while searching), with
  search and sort in the list's header; the filter chips are gone.
- **Readable on a phone.** The Devices list, the Overview's *Strongest signals* and the Packets log
  were desktop tables: on a phone only the name and half the MAC showed, the rest off to the right. On
  a phone each device is now a card — name and model, MAC and when it was last heard, then signal,
  proximity, battery, temperature and humidity in larger type — with a *Sort* menu (name, strongest,
  lowest battery, last heard) in place of the column headers; each packet shows who sent it, its
  signal, time, address and what it carried. Wide screens keep the tables.
- **Clear** on the Overview and Devices pages (top bar; an icon on a phone): after asking, empties the
  device and packet lists so a busy place does not bury the devices being tested. A scan keeps running
  and what is still in range comes back as it is heard; the saved session is kept. To make room on a
  phone's bar, the theme button moves to Settings on the scanning pages and the *Focus* chip is left to
  the Devices page — the bar ran 136 px off a 360 px screen with a device in focus.
- **Fixed — device page on a phone**: the *Name* / *Keep in focus* buttons left the device's name and
  pills a column one letter wide, and the window choice ran 100 px off the screen; on a phone the
  buttons now go under the name and the window is a drop-down.
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
