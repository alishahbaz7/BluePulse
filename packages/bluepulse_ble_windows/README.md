# bluepulse_ble_windows

BluePulse's Windows BLE scanner. It hands every advertisement and scan response to Dart exactly as
Windows receives it (address, RSSI, type, raw AD sections), batched on the platform thread. There is no
caching, de-duplication or merging; the app does that. Low-latency scanning is requested where Windows
supports it (Windows 11 24H2+), and the default is used elsewhere.

Why it exists: `universal_ble`'s Windows scanner drops an advertisement when it carries the same kinds of
fields as the cached one, which discards new sensor values from EYE devices (PLAN.md §11).

It also transmits, for the Simulator: `advertiseStart` publishes one packet (manufacturer data, 16-bit
service UUIDs and service data) with a `BluetoothLEAdvertisementPublisher`, `advertiseStop` ends it and
`advertiseStatus` reports the publisher's state and error. Windows sets its own advertising rate and
publishes no name or scan response, so the app sends a short burst every interval.
