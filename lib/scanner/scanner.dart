import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/foundation.dart';

/// One advertisement or scan response, as a scanner received it.
class ScanEvent {
  ScanEvent({
    required this.deviceId,
    required this.time,
    required this.rssi,
    required this.data,
  });

  /// MAC address, upper case with colons.
  final String deviceId;
  final DateTime time;
  final int? rssi;
  final AdvertisementData data;
}

enum RadioState { unknown, on, off, unauthorized, unsupported }

@immutable
class ScannerStatus {
  const ScannerStatus({this.radio = RadioState.unknown, this.scanning = false, this.error});

  final RadioState radio;
  final bool scanning;

  /// The last failure, in words a person can act on.
  final String? error;

  ScannerStatus copyWith({RadioState? radio, bool? scanning, String? error, bool clearError = false}) =>
      ScannerStatus(
        radio: radio ?? this.radio,
        scanning: scanning ?? this.scanning,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Where advertisements come from: the Bluetooth radio, or the labelled demo generator.
abstract class BeaconScanner {
  bool get isDemo;
  ValueListenable<ScannerStatus> get status;
  Stream<ScanEvent> get events;

  /// Reads the radio state and starts watching it. Safe to call more than once.
  Future<void> init();
  Future<void> start();
  Future<void> stop();

  /// Android only: asks for the Bluetooth permissions again.
  Future<void> requestPermission() async {}

  /// Android only: asks the system to turn Bluetooth on.
  Future<void> enableRadio() async {}

  void dispose();
}

/// `AA:BB:CC:DD:EE:FF` from the forms platforms use (`aa:bb:…`, `aabbcc…`).
String normaliseMac(String id) {
  final hex = id.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
  if (hex.length != 12) return id.toUpperCase();
  return [for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2)].join(':');
}

final _baseUuid = RegExp(r'^0000([0-9a-f]{4})-0000-1000-8000-00805f9b34fb$');

/// The 16-bit form of a Bluetooth base UUID, or null for a full custom UUID.
int? uuid16(String uuid) {
  final s = uuid.toLowerCase();
  final m = _baseUuid.firstMatch(s);
  if (m != null) return int.parse(m.group(1)!, radix: 16);
  if (RegExp(r'^[0-9a-f]{4}$').hasMatch(s)) return int.parse(s, radix: 16);
  return null;
}
