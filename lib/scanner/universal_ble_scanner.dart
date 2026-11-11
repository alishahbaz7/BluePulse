import 'dart:async';

import 'package:eye_protocol/eye_protocol.dart';
import 'package:bluepulse_ble_android/bluepulse_ble_android.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';

import 'scanner.dart';
import '../core/error_log.dart';

/// Live scanning through `universal_ble` (WinRT watcher in active mode on Windows,
/// `BluetoothLeScanner` on Android). Every advertisement is reported — no de-duplication — because
/// RSSI over time is the point.
class UniversalBleScanner implements BeaconScanner {
  final _events = StreamController<ScanEvent>.broadcast();
  final _status = ValueNotifier(const ScannerStatus());
  StreamSubscription<BleDevice>? _scanSub;
  StreamSubscription<AvailabilityState>? _radioSub;
  bool _initialised = false;

  /// Android moves an unfiltered scan that has run too long to "opportunistic" — results only while
  /// another app scans — so a test went silent with the app still showing it scanning. Older Android
  /// allowed 30 minutes; the moto g57 power (Android 17) cut it at exactly 5 minutes (logcat
  /// `handleRegularScanTimeout … Moving unfiltered scan to opportunistic`, 17:33:02 → 17:38:02,
  /// 10-11-2026). Starting the scan again before then resets that clock.
  static const restartEvery = Duration(minutes: 4);
  Timer? _restart;

  /// Android: only what BluePulse reads, matched by the radio itself — Teltonika data, iBeacon,
  /// Eddystone (its frames list service 0xFEAA) and the simulator tag. With the screen off Android
  /// pauses unfiltered scans but keeps filtered ones, and the app is woken only for these packets.
  /// Every device BluePulse lists matches one; phones, earbuds and the rest were dropped anyway.
  static final androidFilter = ScanFilter(
    withServices: const ['0000feaa-0000-1000-8000-00805f9b34fb'],
    withManufacturerData: [
      ManufacturerDataFilter(companyIdentifier: teltonikaCompanyId),
      ManufacturerDataFilter(companyIdentifier: appleCompanyId, payloadPrefix: Uint8List.fromList(const [0x02, 0x15])),
      ManufacturerDataFilter(companyIdentifier: simulatorCompanyId, payloadPrefix: Uint8List.fromList(const [0x42, 0x50])),
    ],
  );

  static const _android = MethodChannel(bluepulseBleAndroidChannel);

  /// Android: a foreground service with a notification, so the scan carries on with the screen off
  /// or another app in front. A failure here leaves the scan as it is — on screen it works anyway.
  Future<void> _keepAlive(bool on) async {
    if (!_isAndroid) return;
    try {
      await _android.invokeMethod<void>(
        on ? 'keepAliveStart' : 'keepAliveStop',
        on ? {'text': 'Scanning for EYE devices and beacons'} : null,
      );
    } catch (e) {
      // No foreground service: the scan still runs while BluePulse is on screen.
      errorLog.warn('scanner', on ? 'Background scanning service did not start' : 'Background scanning service did not stop', error: e);
    }
  }

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  bool get isDemo => false;

  @override
  ValueListenable<ScannerStatus> get status => _status;

  @override
  Stream<ScanEvent> get events => _events.stream;

  @override
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    _radioSub = UniversalBle.availabilityStream.listen(_onRadio,
        onError: (Object e) => errorLog.warn('scanner', 'Bluetooth state could not be read', error: e));
    try {
      _onRadio(await UniversalBle.getBluetoothAvailabilityState());
    } catch (e) {
      _status.value = _status.value.copyWith(radio: RadioState.unsupported, error: _describe(e));
    }
  }

  void _onRadio(AvailabilityState s) {
    final radio = switch (s) {
      AvailabilityState.poweredOn => RadioState.on,
      AvailabilityState.poweredOff => RadioState.off,
      AvailabilityState.unauthorized => RadioState.unauthorized,
      AvailabilityState.unsupported => RadioState.unsupported,
      _ => RadioState.unknown,
    };
    _status.value = _status.value.copyWith(
      radio: radio,
      scanning: radio == RadioState.on ? null : false,
    );
  }

  @override
  Future<void> start() async {
    await init();
    try {
      if (_isAndroid) {
        // Fine location: Android filters beacon advertisements from apps that disclaim location.
        await UniversalBle.requestPermissions(withAndroidFineLocation: true);
      }
      _scanSub ??= UniversalBle.scanStream.listen(_onDevice);
      await _startScan();
      _status.value = _status.value.copyWith(scanning: true, clearError: true);
      _restart?.cancel();
      if (_isAndroid) _restart = Timer.periodic(restartEvery, (_) => _restartScan());
      await _keepAlive(true);
    } catch (e) {
      final denied = e.toString().toLowerCase().contains('permission');
      _status.value = _status.value.copyWith(
        scanning: false,
        radio: denied ? RadioState.unauthorized : null,
        error: _describe(e),
      );
    }
  }

  Future<void> _startScan() => UniversalBle.startScan(
        scanFilter: _isAndroid ? androidFilter : null,
        platformConfig: PlatformConfig(
          android: AndroidOptions(
            scanMode: AndroidScanMode.lowLatency,
            callbackType: [AndroidScanCallbackType.allMatches],
            reportDelayMillis: 0,
            // Legacy scanning listens on the 1M PHY only. Left extended, the scan also listened on
            // Coded PHY (HCI log: scanning PHYs 0x05, 10-11-2026), sharing the radio's time with a
            // PHY no EYE device, beacon or BluePulse simulator transmits on; the EYE App scans
            // legacy. With hardware filters, every match is passed on (no per-filter cap).
            legacy: true,
            matchMode: AndroidScanMatchMode.aggressive,
            numOfMatches: AndroidScanNumOfMatches.max,
          ),
        ),
      );

  /// Stops and starts the platform scan without the app noticing: the scan stays on, the device
  /// list and the session carry on.
  Future<void> _restartScan() async {
    if (!_status.value.scanning) return;
    try {
      await UniversalBle.stopScan();
      await _startScan();
    } catch (e) {
      _status.value = _status.value.copyWith(error: _describe(e));
    }
  }

  @override
  Future<void> stop() async {
    _restart?.cancel();
    _restart = null;
    await _keepAlive(false);
    try {
      await UniversalBle.stopScan();
    } catch (_) {
      // Stopping a scan the platform already ended is not a failure worth showing.
    }
    _status.value = _status.value.copyWith(scanning: false);
  }

  @override
  Future<void> requestPermission() async {
    try {
      await UniversalBle.requestPermissions(withAndroidFineLocation: true);
      _onRadio(await UniversalBle.getBluetoothAvailabilityState());
    } catch (e) {
      _status.value = _status.value.copyWith(radio: RadioState.unauthorized, error: _describe(e));
    }
  }

  @override
  Future<void> enableRadio() async {
    try {
      await UniversalBle.enableBluetooth();
    } catch (e) {
      _status.value = _status.value.copyWith(error: _describe(e));
    }
  }

  void _onDevice(BleDevice d) {
    final svc = <int, Uint8List>{};
    d.serviceData.forEach((uuid, data) {
      final short = uuid16(uuid);
      if (short != null) svc[short] = data;
    });
    final uuids = <int>[
      for (final s in d.services) ?uuid16(s),
    ];
    final mfr = <int, Uint8List>{
      for (final m in d.manufacturerDataList) m.companyId: Uint8List.fromList(m.payload),
    };
    final data = AdvertisementData(
      name: (d.name?.isEmpty ?? true) ? null : d.name,
      serviceUuids16: uuids,
      manufacturerData: mfr,
      serviceData16: svc,
    );
    if (data.isEmpty) return;
    _events.add(ScanEvent(
      deviceId: normaliseMac(d.deviceId),
      time: DateTime.now(),
      rssi: d.rssi,
      data: data,
    ));
  }

  /// The exception type and a hint — never raw platform text on screen beyond its first line.
  String _describe(Object e) {
    final first = e.toString().split('\n').first;
    return first.length > 140 ? '${first.substring(0, 140)}…' : first;
  }

  @override
  void dispose() {
    _restart?.cancel();
    unawaited(_keepAlive(false));
    _scanSub?.cancel();
    _radioSub?.cancel();
    _events.close();
    _status.dispose();
  }
}
