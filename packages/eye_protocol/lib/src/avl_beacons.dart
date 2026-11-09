import 'dart:typed_data';

import 'beacon_id.dart';
import 'byte_reader.dart';
import 'hex.dart';

/// AVL IDs that carry beacons.
abstract final class BeaconAvlId {
  static const beacon = 385;
  static const eyeVisibleOrNear = 10828;
  static const eyeFoundOrAway = 10829;
  static const eyeLost = 10831;

  static const all = {beacon, eyeVisibleOrNear, eyeFoundOrAway, eyeLost};

  /// The tracker's feature mode decides what 10828 / 10829 mean (PLAN.md §3.5).
  static String? name(int id) => switch (id) {
        beacon => 'Beacon',
        eyeVisibleOrNear => 'EYE beacons · Visible / Near',
        eyeFoundOrAway => 'EYE beacons · Found / Away',
        eyeLost => 'EYE beacons · Lost',
        _ => null,
      };
}

/// One beacon as a tracker reported it.
class TrackerBeacon {
  TrackerBeacon({
    this.id,
    this.idBytes,
    this.rssi,
    this.lowBattery,
    this.batteryMv,
    this.mac,
    this.flags,
    this.otherParams = const {},
  });

  final BeaconId? id;

  /// Raw ID when its length matched neither Eddystone (16) nor iBeacon (20).
  final Uint8List? idBytes;
  final int? rssi;
  final bool? lowBattery;
  final int? batteryMv;
  final Uint8List? mac;

  /// AVL 385 per-beacon flags (`0x21` iBeacon, `0x01` Eddystone).
  final int? flags;

  /// Parameters of AVL 108xx this decoder does not know, by parameter ID.
  final Map<int, Uint8List> otherParams;

  String? get macText => mac == null ? null : formatMac(mac!);
}

class BeaconListValue {
  BeaconListValue({
    required this.beacons,
    this.part,
    this.totalParts,
    this.error,
    Uint8List? tail,
  }) : tail = tail ?? Uint8List(0);

  final List<TrackerBeacon> beacons;

  /// AVL 385 only: this part and the total (`0x11` = 1 of 1).
  final int? part;
  final int? totalParts;
  final String? error;

  /// Bytes left unread after [error].
  final Uint8List tail;
}

/// Decodes the value of AVL 385 (Beacon, simple mode).
BeaconListValue decodeAvl385(Uint8List value) {
  if (value.isEmpty) return BeaconListValue(beacons: const [], error: 'Empty value');
  final r = ByteReader(value);
  final first = r.u8();
  final beacons = <TrackerBeacon>[];
  String? error;
  while (r.remaining > 0) {
    final at = r.pos;
    final flags = r.u8();
    final idLen = switch (flags) {
      0x21 => 20,
      0x01 => 16,
      _ => null,
    };
    if (idLen == null) {
      r.pos = at;
      error = 'Beacon flags ${hexLabel(flags)} at offset $at are not simple-mode '
          '(21 iBeacon / 01 Eddystone) — the rest is shown raw';
      break;
    }
    try {
      final id = r.take(idLen, 'Beacon ID');
      final rssi = r.i8('RSSI');
      beacons.add(TrackerBeacon(id: BeaconId.fromBytes(id), rssi: rssi, flags: flags));
    } on TruncatedException catch (e) {
      r.pos = at;
      error = 'Truncated — $e';
      break;
    }
  }
  return BeaconListValue(
    beacons: beacons,
    part: first >> 4,
    totalParts: first & 0x0F,
    error: error,
    tail: r.rest(),
  );
}

/// Parameter IDs inside AVL 10828 / 10829 / 10831.
abstract final class EyeParam {
  static const rssi = 0;
  static const beaconId = 1;
  static const lowBattery = 13;
  static const batteryVoltage = 14;
  static const mac = 15;
}

/// Decodes the value of AVL 10828 / 10829 / 10831 (EYE beacon lists).
BeaconListValue decodeEyeBeaconList(Uint8List value) {
  if (value.isEmpty) return BeaconListValue(beacons: const [], error: 'Empty value');
  final r = ByteReader(value);
  final constant = r.u8();
  String? error =
      constant == 0x01 ? null : 'First byte is ${hexLabel(constant)}, expected 0x01';
  final beacons = <TrackerBeacon>[];
  while (r.remaining > 0) {
    final at = r.pos;
    Uint8List body;
    try {
      final len = r.u8('Beacon length');
      body = r.take(len, 'Beacon data');
    } on TruncatedException catch (e) {
      r.pos = at;
      error = 'Truncated — $e';
      break;
    }
    final b = ByteReader(body);
    BeaconId? id;
    Uint8List? idBytes;
    int? rssi;
    bool? low;
    int? mv;
    Uint8List? mac;
    final other = <int, Uint8List>{};
    try {
      while (b.remaining > 0) {
        final pid = b.u8('Parameter ID');
        final plen = b.u8('Parameter length');
        final data = b.take(plen, 'Parameter $pid');
        switch (pid) {
          case EyeParam.rssi when plen == 1:
            rssi = data[0] >= 0x80 ? data[0] - 256 : data[0];
          case EyeParam.beaconId:
            id = BeaconId.fromBytes(data);
            if (id == null) idBytes = data;
          case EyeParam.lowBattery when plen == 1:
            low = data[0] != 0;
          case EyeParam.batteryVoltage when plen == 2:
            mv = (data[0] << 8) | data[1];
          case EyeParam.mac when plen == 6:
            mac = data;
          default:
            other[pid] = data;
        }
      }
    } on TruncatedException catch (e) {
      error = 'Beacon at offset $at: $e';
    }
    beacons.add(TrackerBeacon(
      id: id,
      idBytes: idBytes,
      rssi: rssi,
      lowBattery: low,
      batteryMv: mv,
      mac: mac,
      otherParams: other,
    ));
  }
  return BeaconListValue(beacons: beacons, error: error, tail: r.rest());
}

/// Decodes a beacon AVL value by its AVL ID; null for IDs that do not carry beacons.
BeaconListValue? decodeBeaconAvl(int avlId, Uint8List value) => switch (avlId) {
      BeaconAvlId.beacon => decodeAvl385(value),
      BeaconAvlId.eyeVisibleOrNear ||
      BeaconAvlId.eyeFoundOrAway ||
      BeaconAvlId.eyeLost =>
        decodeEyeBeaconList(value),
      _ => null,
    };
