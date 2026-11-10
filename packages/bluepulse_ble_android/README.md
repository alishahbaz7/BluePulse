# bluepulse_ble_android

BluePulse's Android BLE transmitter, used by the Simulator (`lib/simulator/advertiser.dart`). It
advertises the packets Dart builds with Android's `AdvertisingSet` (Android 8+): legacy, non-connectable,
scannable when there is a scan response, at the exact interval asked (in 0.625 ms steps, 100 ms
upwards) and transmit power. The data is updated in place while it runs.

Android advertises only the phone's own Bluetooth name, so a simulated name is set by renaming the
adapter for as long as it transmits. The original name is saved first and put back on stop — and, if
the app was closed mid-run, when the plugin next starts.

Channel `bluepulse_ble_android`: `capabilities`, `requestPermissions` (`BLUETOOTH_ADVERTISE` and
`BLUETOOTH_CONNECT` on Android 12+), `start`, `update`, `stop`; failures while running come back as
`error` calls.
