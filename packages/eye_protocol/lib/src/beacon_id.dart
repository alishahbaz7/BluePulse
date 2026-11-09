import 'dart:typed_data';

import 'hex.dart';

enum BeaconIdKind { eddystone, iBeacon }

/// A beacon's broadcast identity — the same value whether it was scanned over BLE or read out of
/// a tracker record, so the two can be matched.
///
/// * Eddystone: 10-byte namespace + 6-byte instance (16 bytes).
/// * iBeacon: 16-byte UUID + major + minor (20 bytes).
class BeaconId {
  BeaconId._(this.kind, this.bytes);

  /// Builds an ID from 16 (Eddystone) or 20 (iBeacon) bytes; any other length returns null.
  static BeaconId? fromBytes(Uint8List bytes) {
    if (bytes.length == 16) return BeaconId._(BeaconIdKind.eddystone, Uint8List.fromList(bytes));
    if (bytes.length == 20) return BeaconId._(BeaconIdKind.iBeacon, Uint8List.fromList(bytes));
    return null;
  }

  factory BeaconId.eddystone(Uint8List namespace, Uint8List instance) {
    assert(namespace.length == 10 && instance.length == 6);
    return BeaconId._(BeaconIdKind.eddystone, Uint8List.fromList([...namespace, ...instance]));
  }

  factory BeaconId.iBeacon(Uint8List uuid, int major, int minor) {
    assert(uuid.length == 16);
    return BeaconId._(
      BeaconIdKind.iBeacon,
      Uint8List.fromList([...uuid, major >> 8, major & 0xFF, minor >> 8, minor & 0xFF]),
    );
  }

  final BeaconIdKind kind;
  final Uint8List bytes;

  bool get isEddystone => kind == BeaconIdKind.eddystone;
  bool get isIBeacon => kind == BeaconIdKind.iBeacon;

  String get kindLabel => isEddystone ? 'Eddystone' : 'iBeacon';

  // Eddystone parts.
  String get namespaceHex => isEddystone ? toHex(bytes.sublist(0, 10)) : '';
  String get instanceHex => isEddystone ? toHex(bytes.sublist(10, 16)) : '';

  // iBeacon parts.
  String get uuid => isIBeacon ? formatUuid(bytes.sublist(0, 16)) : '';
  int get major => isIBeacon ? (bytes[16] << 8) | bytes[17] : 0;
  int get minor => isIBeacon ? (bytes[18] << 8) | bytes[19] : 0;

  /// One line for tables: `NAMESPACE · INSTANCE` or `UUID · major · minor`.
  String get display =>
      isEddystone ? '$namespaceHex · $instanceHex' : '$uuid · $major · $minor';

  String get hex => toHex(bytes);

  @override
  bool operator ==(Object other) =>
      other is BeaconId && other.kind == kind && other.hex == hex;

  @override
  int get hashCode => Object.hash(kind, hex);

  @override
  String toString() => '$kindLabel($display)';
}

/// `6B817F8A-274D-4FBD-B62D-33E1842F8DF8`.
String formatUuid(List<int> sixteen) {
  final h = toHex(sixteen);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
