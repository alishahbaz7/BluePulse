import 'dart:typed_data';

import 'byte_reader.dart';
import 'hex.dart';

/// Bluetooth AD types this app reads. Others are kept and shown by number.
abstract final class AdType {
  static const flags = 0x01;
  static const incompleteUuid16 = 0x02;
  static const completeUuid16 = 0x03;
  static const shortName = 0x08;
  static const completeName = 0x09;
  static const txPowerLevel = 0x0A;
  static const serviceData16 = 0x16;
  static const manufacturerData = 0xFF;

  static String name(int type) => switch (type) {
        flags => 'Flags',
        incompleteUuid16 => '16-bit UUIDs (incomplete)',
        completeUuid16 => '16-bit UUIDs',
        shortName => 'Short name',
        completeName => 'Name',
        txPowerLevel => 'TX power level',
        serviceData16 => 'Service data',
        manufacturerData => 'Manufacturer data',
        _ => 'AD type ${hexLabel(type)}',
      };
}

/// One `length · type · data` structure of an advertisement, with where it sat in the packet.
class AdStructure {
  AdStructure(this.type, this.data, {this.offset = 0});

  final int type;
  final Uint8List data;

  /// Offset of the length byte in the packet it came from.
  final int offset;

  /// Bytes on air, including the length and type bytes.
  int get size => data.length + 2;

  Uint8List toBytes() => Uint8List.fromList([data.length + 1, type, ...data]);

  @override
  String toString() => '${AdType.name(type)}: ${toHex(data, separator: ' ')}';
}

class AdParseResult {
  AdParseResult(this.structures, {this.error, Uint8List? tail}) : tail = tail ?? Uint8List(0);

  final List<AdStructure> structures;
  final String? error;

  /// Bytes after a structure that ran past the end.
  final Uint8List tail;
}

/// Splits a raw advertising or scan-response payload into AD structures.
///
/// A zero length byte is padding and ends the packet. A length that runs past the end is reported
/// as an error and the remaining bytes are kept as the tail.
AdParseResult parseAdStructures(Uint8List raw) {
  final out = <AdStructure>[];
  final r = ByteReader(raw);
  while (r.remaining > 0) {
    final offset = r.pos;
    final len = r.u8();
    if (len == 0) break;
    if (!r.has(len)) {
      r.pos = offset;
      return AdParseResult(
        out,
        error: 'AD structure at offset $offset declares $len bytes, ${raw.length - offset - 1} left',
        tail: r.rest(),
      );
    }
    final type = r.u8();
    out.add(AdStructure(type, r.take(len - 1), offset: offset));
  }
  return AdParseResult(out);
}
