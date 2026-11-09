import 'dart:typed_data';

import 'beacon_id.dart';
import 'byte_field.dart';
import 'hex.dart';

/// Eddystone's 16-bit service UUID.
const eddystoneServiceUuid = 0xFEAA;

/// A decoded Eddystone service-data frame.
sealed class EddystoneFrame {
  const EddystoneFrame(this.frameType, this.fields);

  final int frameType;

  /// Byte labels, offsets relative to the service data (after the UUID).
  final List<ByteField> fields;

  String get kind => eddystoneFrameName(frameType);
}

/// UID frame: the identity the EYE devices broadcast.
class EddystoneUid extends EddystoneFrame {
  EddystoneUid({
    required this.txPower0m,
    required this.namespace,
    required this.instance,
    required List<ByteField> fields,
  }) : super(0x00, fields);

  /// Calibrated TX power at 0 m, dBm.
  final int txPower0m;
  final Uint8List namespace;
  final Uint8List instance;

  BeaconId get id => BeaconId.eddystone(namespace, instance);

  /// TX power at 1 m, by Eddystone's convention of 41 dB loss over the first metre.
  int get txPower1m => txPower0m - 41;
}

/// A URL / TLM / EID or unknown frame, or a UID frame too short to read.
class EddystoneOther extends EddystoneFrame {
  EddystoneOther(int frameType, this.data, {this.error, List<ByteField>? fields})
      : super(frameType, fields ?? const []);

  final Uint8List data;
  final String? error;
}

String eddystoneFrameName(int frameType) => switch (frameType) {
      0x00 => 'UID',
      0x10 => 'URL',
      0x20 => 'TLM',
      0x30 => 'EID',
      _ => 'Unknown frame ${hexLabel(frameType)}',
    };

/// Decodes Eddystone service data (the bytes after the `AA FE` UUID). Returns null when empty.
EddystoneFrame? decodeEddystone(Uint8List data) {
  if (data.isEmpty) return null;
  final type = data[0];
  final typeField = ByteField(0, 1, 'Frame type', '${hexLabel(type)} ${eddystoneFrameName(type)}');
  if (type != 0x00) return EddystoneOther(type, data, fields: [typeField]);
  if (data.length < 18) {
    return EddystoneOther(type, data,
        error: 'UID frame is ${data.length} bytes, needs 18', fields: [typeField]);
  }
  final tx = data[1] >= 0x80 ? data[1] - 256 : data[1];
  final ns = Uint8List.fromList(data.sublist(2, 12));
  final inst = Uint8List.fromList(data.sublist(12, 18));
  return EddystoneUid(
    txPower0m: tx,
    namespace: ns,
    instance: inst,
    fields: [
      typeField,
      ByteField(1, 1, 'TX power at 0 m', '$tx dBm'),
      ByteField(2, 10, 'Namespace', toHex(ns)),
      ByteField(12, 6, 'Instance', toHex(inst)),
      if (data.length >= 20) const ByteField(18, 2, 'Reserved', ''),
    ],
  );
}
