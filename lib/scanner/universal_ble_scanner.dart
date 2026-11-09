import 'dart:async';

import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'scanner.dart';

/// Live scanning through `universal_ble` (WinRT watcher in active mode on Windows,
/// `BluetoothLeScanner` on Android). Every advertisement is reported — no de-duplication — because
/// RSSI over time is the point.
class UniversalBleScanner implements BeaconScanner {
  final _events = StreamController<ScanEvent>.broadcast();
  final _status = ValueNotifier(const ScannerStatus());
  StreamSubscription<BleDevice>? _scanSub;
  StreamSubscription<AvailabilityState>? _radioSub;
  bool _initialised = false;

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
    _radioSub = UniversalBle.availabilityStream.listen(_onRadio, onError: (_) {});
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
      await UniversalBle.startScan(
        platformConfig: PlatformConfig(
          android: AndroidOptions(
            scanMode: AndroidScanMode.lowLatency,
            callbackType: [AndroidScanCallbackType.allMatches],
            reportDelayMillis: 0,
          ),
        ),
      );
      _status.value = _status.value.copyWith(scanning: true, clearError: true);
    } catch (e) {
      final denied = e.toString().toLowerCase().contains('permission');
      _status.value = _status.value.copyWith(
        scanning: false,
        radio: denied ? RadioState.unauthorized : null,
        error: _describe(e),
      );
    }
  }

  @override
  Future<void> stop() async {
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
    _scanSub?.cancel();
    _radioSub?.cancel();
    _events.close();
    _status.dispose();
  }
}
