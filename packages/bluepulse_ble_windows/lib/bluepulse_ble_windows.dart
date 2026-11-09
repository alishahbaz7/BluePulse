/// Raw BLE advertisement scanning on Windows: every advertisement and scan response as received,
/// with its raw AD sections — no caching, de-duplication or merging (BluePulse merges itself).
library;

import 'package:flutter/services.dart';

/// WinRT `BluetoothLEAdvertisementType`.
abstract final class WinAdvType {
  static const connectableUndirected = 0;
  static const connectableDirected = 1;
  static const scannableUndirected = 2;
  static const nonConnectableUndirected = 3;
  static const scanResponse = 4;
  static const extended = 5;
}

/// One received advertisement or scan response.
class RawAdvertisement {
  RawAdvertisement({required this.address, required this.rssi, required this.type, required this.sections});

  /// 48-bit Bluetooth address.
  final int address;
  final int rssi;

  /// See [WinAdvType].
  final int type;

  /// AD structures as (type, data) in the order received.
  final List<(int, Uint8List)> sections;

  bool get isScanResponse => type == WinAdvType.scanResponse;

  /// `AA:BB:CC:DD:EE:FF`.
  String get mac => [
        for (var i = 5; i >= 0; i--) ((address >> (8 * i)) & 0xFF).toRadixString(16).padLeft(2, '0'),
      ].join(':').toUpperCase();

  /// The packet's bytes on air: each section as `length · type · data`.
  Uint8List get rawBytes => Uint8List.fromList([
        for (final (t, d) in sections) ...[d.length + 1, t, ...d],
      ]);

  static RawAdvertisement? fromMessage(Object? message) {
    if (message is! Map) return null;
    final sections = <(int, Uint8List)>[];
    for (final s in (message['s'] as List?) ?? const []) {
      if (s is List && s.length == 2 && s[0] is int && s[1] is Uint8List) {
        sections.add((s[0] as int, s[1] as Uint8List));
      }
    }
    final a = message['a'], r = message['r'], t = message['t'];
    if (a is! int || r is! int || t is! int) return null;
    return RawAdvertisement(address: a, rssi: r, type: t, sections: sections);
  }
}

class BluePulseBleWindows {
  static const _methods = MethodChannel('bluepulse_ble_windows');
  static const _events = EventChannel('bluepulse_ble_windows/advertisements');
  static Stream<List<RawAdvertisement>>? _stream;

  /// Batches of advertisements, in arrival order.
  static Stream<List<RawAdvertisement>> get advertisements => _stream ??= _events
      .receiveBroadcastStream()
      .map((batch) => [
            for (final m in (batch as List)) ?RawAdvertisement.fromMessage(m),
          ]);

  /// Starts the watcher; returns whether Windows accepted low-latency scanning.
  static Future<bool> start({bool lowLatency = true}) async {
    final r = await _methods.invokeMapMethod<String, Object?>('start', {'lowLatency': lowLatency});
    return r?['lowLatency'] == true;
  }

  static Future<void> stop() => _methods.invokeMethod<void>('stop');

  /// Advertisements Windows delivered, and ones dropped because the app fell behind.
  static Future<({int received, int dropped})> stats() async {
    final r = await _methods.invokeMapMethod<String, Object?>('stats');
    return (received: (r?['received'] as int?) ?? 0, dropped: (r?['dropped'] as int?) ?? 0);
  }
}
