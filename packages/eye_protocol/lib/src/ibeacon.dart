import 'dart:typed_data';

import 'beacon_id.dart';
import 'byte_field.dart';

/// Apple's company ID, which carries iBeacon frames.
const appleCompanyId = 0x004C;

class IBeacon {
  IBeacon({
    required this.uuidBytes,
    required this.major,
    required this.minor,
    required this.measuredPower,
  });

  final Uint8List uuidBytes;
  final int major;
  final int minor;

  /// RSSI at 1 m, dBm.
  final int measuredPower;

  String get uuid => formatUuid(uuidBytes);
  BeaconId get id => BeaconId.iBeacon(uuidBytes, major, minor);

  /// Byte labels, offsets relative to the manufacturer payload (after the company ID).
  List<ByteField> get fields => [
        const ByteField(0, 2, 'iBeacon prefix', '02 15'),
        ByteField(2, 16, 'UUID', uuid),
        ByteField(18, 2, 'Major', '$major'),
        ByteField(20, 2, 'Minor', '$minor'),
        ByteField(22, 1, 'Measured power at 1 m', '$measuredPower dBm'),
      ];
}

/// Decodes an Apple manufacturer payload (after `4C 00`). Returns null when it is not an iBeacon.
IBeacon? decodeIBeacon(Uint8List payload) {
  if (payload.length < 23 || payload[0] != 0x02 || payload[1] != 0x15) return null;
  final power = payload[22] >= 0x80 ? payload[22] - 256 : payload[22];
  return IBeacon(
    uuidBytes: Uint8List.fromList(payload.sublist(2, 18)),
    major: (payload[18] << 8) | payload[19],
    minor: (payload[20] << 8) | payload[21],
    measuredPower: power,
  );
}
