import 'dart:typed_data';

import 'byte_reader.dart';
import 'hex.dart';

/// CRC-16/IBM (a.k.a. CRC-16/ARC): reflected polynomial 0xA001, initial value 0 — the checksum
/// Teltonika puts at the end of every AVL packet.
int crc16Ibm(List<int> data) {
  var crc = 0;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
    }
  }
  return crc;
}

/// One IO element of an AVL record.
class IoElement {
  IoElement(this.id, this.value, {this.variableLength = false});

  final int id;
  final Uint8List value;

  /// From the variable-length (NX) group of Codec 8 Extended.
  final bool variableLength;

  int get size => value.length;
  String get hex => toHex(value);

  /// Unsigned big-endian value (any length).
  BigInt get unsigned {
    var v = BigInt.zero;
    for (final b in value) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }
}

class AvlRecord {
  AvlRecord({
    required this.timestamp,
    required this.priority,
    required this.longitude,
    required this.latitude,
    required this.altitude,
    required this.angle,
    required this.satellites,
    required this.speed,
    required this.eventIoId,
    required this.totalIo,
    required this.io,
  });

  final DateTime timestamp;
  final int priority;
  final double longitude;
  final double latitude;
  final int altitude;
  final int angle;
  final int satellites;
  final int speed;
  final int eventIoId;
  final int totalIo;
  final List<IoElement> io;

  IoElement? element(int id) {
    for (final e in io) {
      if (e.id == id) return e;
    }
    return null;
  }
}

/// A decoded Codec 8 (`0x08`) or Codec 8 Extended (`0x8E`) packet.
class AvlPacket {
  AvlPacket({
    required this.raw,
    required this.framed,
    this.dataLength,
    this.codecId,
    this.recordCount,
    this.recordCount2,
    this.records = const [],
    this.crcField,
    this.crcComputed,
    this.problems = const [],
  });

  final Uint8List raw;

  /// True when the input carried the TCP framing (preamble, length, CRC).
  final bool framed;
  final int? dataLength;
  final int? codecId;
  final int? recordCount;
  final int? recordCount2;
  final List<AvlRecord> records;
  final int? crcField;
  final int? crcComputed;

  /// Everything that did not check out, in words. Empty when the packet is sound.
  final List<String> problems;

  bool get crcOk => crcField != null && crcField == crcComputed;
  bool get ok => problems.isEmpty;

  String get codecName => switch (codecId) {
        0x08 => 'Codec 8',
        0x8E => 'Codec 8 Extended',
        null => '—',
        _ => 'Codec ${hexLabel(codecId!)}',
      };
}

/// True when [raw] looks like an AVL packet: TCP framing, or a bare data field starting with a
/// codec ID.
bool looksLikeAvlPacket(Uint8List raw) {
  if (raw.length >= 12 && raw[0] == 0 && raw[1] == 0 && raw[2] == 0 && raw[3] == 0) return true;
  return raw.length >= 2 && (raw[0] == 0x8E || raw[0] == 0x08);
}

/// Decodes a Codec 8 / 8 Extended packet.
///
/// Accepts the full TCP packet (`00000000` preamble, data length, data, CRC) or the bare data field
/// (from the codec ID to the second record count). Never throws: what could not be read is listed
/// in [AvlPacket.problems], and the records read before it are kept.
AvlPacket decodeAvlPacket(Uint8List raw) {
  final problems = <String>[];
  final framed = raw.length >= 12 && raw[0] == 0 && raw[1] == 0 && raw[2] == 0 && raw[3] == 0;
  final r = ByteReader(raw);
  int? dataLength;
  var bodyStart = 0;

  if (framed) {
    r.pos = 4;
    dataLength = r.u32();
    bodyStart = 8;
    final available = raw.length - 8 - 4;
    if (dataLength != available) {
      problems.add('Data length says $dataLength bytes; the packet holds $available');
    }
  } else if (raw.isEmpty || (raw[0] != 0x8E && raw[0] != 0x08)) {
    return AvlPacket(
      raw: raw,
      framed: false,
      problems: const ['Not an AVL packet — expected the 00000000 preamble or codec ID 08 / 8E'],
    );
  }

  int? codec;
  int? count;
  int? count2;
  final records = <AvlRecord>[];
  try {
    codec = r.u8('Codec ID');
    if (codec != 0x08 && codec != 0x8E) {
      problems.add('Unsupported codec ${hexLabel(codec)}');
    } else {
      final ext = codec == 0x8E;
      count = r.u8('Record count');
      for (var i = 0; i < count; i++) {
        records.add(_record(r, ext));
      }
      count2 = r.u8('Second record count');
      if (count2 != count) problems.add('Record counts differ: $count at the start, $count2 at the end');
    }
  } on TruncatedException catch (e) {
    problems.add('Truncated — $e');
  }

  int? crcField;
  int? crcComputed;
  if (framed && dataLength != null) {
    final end = bodyStart + dataLength;
    if (end + 4 <= raw.length) {
      crcComputed = crc16Ibm(raw.sublist(bodyStart, end));
      crcField = ByteReader(raw, end).u32();
      if (crcField != crcComputed) {
        problems.add('CRC mismatch: packet says ${hexLabel(crcField, digits: 4)}, '
            'computed ${hexLabel(crcComputed, digits: 4)}');
      }
    } else {
      problems.add('CRC missing');
    }
    if (problems.isEmpty && r.pos != end) {
      problems.add('${end - r.pos} unread bytes before the CRC');
    }
  }

  return AvlPacket(
    raw: Uint8List.fromList(raw),
    framed: framed,
    dataLength: dataLength,
    codecId: codec,
    recordCount: count,
    recordCount2: count2,
    records: records,
    crcField: crcField,
    crcComputed: crcComputed,
    problems: problems,
  );
}

AvlRecord _record(ByteReader r, bool ext) {
  int n(String what) => ext ? r.u16(what) : r.u8(what);

  final ts = r.u64('Timestamp');
  final priority = r.u8('Priority');
  final lon = r.i32('Longitude');
  final lat = r.i32('Latitude');
  final alt = r.i16('Altitude');
  final angle = r.u16('Angle');
  final sats = r.u8('Satellites');
  final speed = r.u16('Speed');
  final eventId = n('Event IO ID');
  final total = n('IO count');
  final io = <IoElement>[];
  for (final size in const [1, 2, 4, 8]) {
    final count = n('$size-byte IO count');
    for (var i = 0; i < count; i++) {
      final id = n('IO ID');
      io.add(IoElement(id, r.take(size, 'IO $id value')));
    }
  }
  if (ext) {
    final count = r.u16('Variable IO count');
    for (var i = 0; i < count; i++) {
      final id = r.u16('IO ID');
      final len = r.u16('IO $id length');
      io.add(IoElement(id, r.take(len, 'IO $id value'), variableLength: true));
    }
  }
  return AvlRecord(
    timestamp: DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true),
    priority: priority,
    longitude: lon / 1e7,
    latitude: lat / 1e7,
    altitude: alt,
    angle: angle,
    satellites: sats,
    speed: speed,
    eventIoId: eventId,
    totalIo: total,
    io: io,
  );
}
