import 'dart:convert';
import 'dart:typed_data';

import 'ad_structures.dart';
import 'byte_field.dart';
import 'eddystone.dart';
import 'hex.dart';
import 'ibeacon.dart';
import 'simulator_tag.dart';
import 'teltonika.dart';

/// A packet with every byte labelled — the model behind the packet inspector.
class AnnotatedPacket {
  AnnotatedPacket(this.bytes, this.fields, {this.error});

  final Uint8List bytes;

  /// Non-overlapping, in byte order.
  final List<ByteField> fields;
  final String? error;

  /// The field covering byte [index], if any.
  ByteField? fieldAt(int index) {
    for (final f in fields) {
      if (index >= f.offset && index < f.end) return f;
    }
    return null;
  }
}

String _companyName(int id) => switch (id) {
      teltonikaCompanyId => 'Teltonika',
      appleCompanyId => 'Apple',
      simulatorCompanyId => 'kept for tests',
      _ => 'company',
    };

/// Labels every byte of a list of AD structures laid end to end.
AnnotatedPacket annotateStructures(List<AdStructure> structures, {String? error}) {
  final bytes = <int>[];
  final fields = <ByteField>[];
  for (final s in structures) {
    final at = bytes.length;
    bytes.addAll(s.toBytes());
    fields.add(ByteField(at, 1, 'Length', '${s.data.length + 1}'));
    fields.add(ByteField(at + 1, 1, 'AD type', '${hexLabel(s.type)} ${AdType.name(s.type)}'));
    final body = at + 2;
    final d = s.data;
    switch (s.type) {
      case AdType.manufacturerData when d.length >= 2:
        final id = d[0] | (d[1] << 8);
        fields.add(ByteField(body, 2, 'Company ID', '${hexLabel(id, digits: 4)} ${_companyName(id)}'));
        final payload = Uint8List.fromList(d.sublist(2));
        final inner = switch (id) {
          teltonikaCompanyId => decodeTeltonika(payload).fields,
          appleCompanyId => decodeIBeacon(payload)?.fields ?? const <ByteField>[],
          simulatorCompanyId => _simulatorFields(payload),
          _ => const <ByteField>[],
        };
        _addInner(fields, inner, body + 2, payload.length);
      case AdType.serviceData16 when d.length >= 2:
        final uuid = d[0] | (d[1] << 8);
        final known = uuid == eddystoneServiceUuid ? ' Eddystone' : '';
        fields.add(ByteField(body, 2, 'Service UUID', '${hexLabel(uuid, digits: 4)}$known'));
        final payload = Uint8List.fromList(d.sublist(2));
        final inner = uuid == eddystoneServiceUuid
            ? (decodeEddystone(payload)?.fields ?? const <ByteField>[])
            : const <ByteField>[];
        _addInner(fields, inner, body + 2, payload.length);
      case AdType.completeName || AdType.shortName:
        if (d.isNotEmpty) {
          fields.add(ByteField(body, d.length, 'Name', '"${utf8.decode(d, allowMalformed: true)}"'));
        }
      case AdType.flags when d.isNotEmpty:
        fields.add(ByteField(body, 1, 'Flags', hexLabel(d[0])));
      default:
        if (d.isNotEmpty) fields.add(ByteField(body, d.length, 'Data', toHex(d, separator: ' ')));
    }
  }
  return AnnotatedPacket(Uint8List.fromList(bytes), fields, error: error);
}

/// Labels every byte of a raw advertising or scan-response payload.
AnnotatedPacket annotateRaw(Uint8List raw) {
  final parsed = parseAdStructures(raw);
  final packet = annotateStructures(parsed.structures, error: parsed.error);
  if (parsed.tail.isEmpty) return packet;
  final at = packet.bytes.length;
  return AnnotatedPacket(
    Uint8List.fromList([...packet.bytes, ...parsed.tail]),
    [...packet.fields, ByteField(at, parsed.tail.length, 'Unparsed', toHex(parsed.tail))],
    error: parsed.error,
  );
}

/// Shifts a decoder's payload-relative fields into place and labels any bytes they left out.
List<ByteField> _simulatorFields(Uint8List payload) {
  final id = decodeSimulatorTag(payload);
  if (id == null) return const [];
  return [
    const ByteField(0, 2, 'BluePulse simulator', 'BP'),
    ByteField(2, 4, 'Simulated device', simulatorKey(id)),
  ];
}

void _addInner(List<ByteField> out, List<ByteField> inner, int base, int length) {
  var covered = 0;
  for (final f in inner) {
    if (f.offset > covered) {
      out.add(ByteField(base + covered, f.offset - covered, 'Data', ''));
    }
    out.add(f.shift(base));
    if (f.end > covered) covered = f.end;
  }
  if (covered < length) out.add(ByteField(base + covered, length - covered, 'Data', ''));
}
