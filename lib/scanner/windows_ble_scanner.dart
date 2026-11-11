import 'dart:async';

import 'package:bluepulse_ble_windows/bluepulse_ble_windows.dart';
import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'scanner.dart';
import '../core/error_log.dart';

/// Live scanning on Windows through BluePulse's own native scanner: every advertisement and scan
/// response exactly as Windows receives it, raw bytes included. (universal_ble's Windows scanner
/// drops repeated advertisements, which loses new EYE sensor values — PLAN.md §11.) The radio state
/// still comes from universal_ble.
class WindowsBleScanner implements BeaconScanner {
  final _events = StreamController<ScanEvent>.broadcast();
  final _status = ValueNotifier(const ScannerStatus());
  StreamSubscription<List<RawAdvertisement>>? _scanSub;
  StreamSubscription<AvailabilityState>? _radioSub;
  bool _initialised = false;

  /// Whether Windows accepted low-latency scanning on the last start.
  bool lowLatency = false;

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
    _status.value = _status.value.copyWith(radio: radio, scanning: radio == RadioState.on ? null : false);
  }

  @override
  Future<void> start() async {
    await init();
    try {
      _scanSub ??= BluePulseBleWindows.advertisements.listen(_onBatch, onError: (Object e) {
        _status.value = _status.value.copyWith(error: _describe(e));
      });
      lowLatency = await BluePulseBleWindows.start(lowLatency: true);
      _status.value = _status.value.copyWith(scanning: true, clearError: true);
    } catch (e) {
      _status.value = _status.value.copyWith(scanning: false, error: _describe(e));
    }
  }

  @override
  Future<void> stop() async {
    try {
      await BluePulseBleWindows.stop();
    } catch (_) {
      // Already stopped.
    }
    _status.value = _status.value.copyWith(scanning: false);
  }

  void _onBatch(List<RawAdvertisement> batch) {
    final now = DateTime.now();
    for (final a in batch) {
      _events.add(scanEventFromRaw(a, now));
    }
  }

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> enableRadio() async {}

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

/// A native packet as the app's scan event: the sections become AD structures, the raw bytes are
/// kept for the packet inspector.
ScanEvent scanEventFromRaw(RawAdvertisement a, DateTime time) {
  final structures = <AdStructure>[];
  var offset = 0;
  for (final (type, data) in a.sections) {
    structures.add(AdStructure(type, Uint8List.fromList(data), offset: offset));
    offset += data.length + 2;
  }
  return ScanEvent(
    deviceId: a.mac,
    time: time,
    rssi: a.rssi,
    data: AdvertisementData.fromStructures(structures),
    raw: a.rawBytes,
    scanResponse: a.isScanResponse,
  );
}
