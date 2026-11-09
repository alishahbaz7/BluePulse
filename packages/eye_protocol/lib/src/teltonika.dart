import 'dart:typed_data';

import 'byte_field.dart';
import 'byte_reader.dart';
import 'hex.dart';

/// Teltonika's Bluetooth SIG company ID.
const teltonikaCompanyId = 0x089A;

/// Flag bits of the Teltonika block (EYE BEACON / EYE SENSOR wiki, Table 1).
abstract final class EyeFlag {
  static const temperature = 0x01;
  static const humidity = 0x02;
  static const magnetPresent = 0x04;
  static const magnetDetected = 0x08;
  static const movementCounter = 0x10;
  static const movementAngle = 0x20;
  static const lowBattery = 0x40;
  static const batteryVoltage = 0x80;

  /// Bits only an EYE SENSOR sets; a BTSID1 only ever sets bits 6 and 7.
  static const sensorBits = 0x3F;

  static const names = <int, String>{
    temperature: 'Temperature',
    humidity: 'Humidity',
    magnetPresent: 'Magnet sensor',
    magnetDetected: 'Magnet detected',
    movementCounter: 'Movement counter',
    movementAngle: 'Movement angle',
    lowBattery: 'Low battery',
    batteryVoltage: 'Battery voltage',
  };
}

/// The decoded Teltonika manufacturer block.
///
/// Value layouts for temperature, humidity, movement and angle are provisional until confirmed
/// against the EYE SENSOR / BTSMP1 page (PLAN.md §3.4); battery and flag meanings are verified.
class TeltonikaData {
  TeltonikaData({
    required this.raw,
    this.version,
    this.flags,
    this.temperatureC,
    this.humidity,
    this.magnetDetected,
    this.moving,
    this.movementCount,
    this.pitch,
    this.roll,
    this.batteryMv,
    this.error,
    Uint8List? tail,
    this.fields = const [],
  }) : tail = tail ?? Uint8List(0);

  final Uint8List raw;
  final int? version;
  final int? flags;
  final double? temperatureC;
  final int? humidity;

  /// Null when the device has no magnet sensor (flag bit 2 clear).
  final bool? magnetDetected;
  final bool? moving;
  final int? movementCount;
  final int? pitch;
  final int? roll;
  final int? batteryMv;

  /// Why decoding stopped early; the values read before it are kept.
  final String? error;

  /// Bytes after the last value the flags announced.
  final Uint8List tail;

  /// Byte labels, offsets relative to the payload (after the company ID).
  final List<ByteField> fields;

  bool _bit(int mask) => flags != null && (flags! & mask) != 0;

  bool get lowBattery => _bit(EyeFlag.lowBattery);
  bool get magnetPresent => _bit(EyeFlag.magnetPresent);

  /// True when any EYE SENSOR-only bit (0–5) is set.
  bool get hasSensorBits => flags != null && (flags! & EyeFlag.sensorBits) != 0;

  bool get ok => error == null;
}

/// Decodes the Teltonika block: the manufacturer payload after the `9A 08` company ID.
TeltonikaData decodeTeltonika(Uint8List payload) {
  final raw = Uint8List.fromList(payload);
  if (payload.isEmpty) return TeltonikaData(raw: raw, error: 'Empty Teltonika block');

  final r = ByteReader(payload);
  final fields = <ByteField>[];
  final version = r.u8();
  fields.add(ByteField(0, 1, 'Protocol version', hexLabel(version)));
  if (version != 0x01) {
    return TeltonikaData(
      raw: raw,
      version: version,
      error: 'Unsupported protocol version ${hexLabel(version)}',
      tail: r.rest(),
      fields: fields,
    );
  }
  if (!r.has(1)) {
    return TeltonikaData(raw: raw, version: version, error: 'Truncated — flags missing', fields: fields);
  }
  final flags = r.u8();
  final set = EyeFlag.names.entries.where((e) => flags & e.key != 0).map((e) => e.value);
  fields.add(ByteField(1, 1, 'Flags', '${hexLabel(flags)} ${set.isEmpty ? 'none' : set.join(', ')}'));

  double? temperature;
  int? humidity;
  bool? moving;
  int? count;
  int? pitch;
  int? roll;
  int? battery;
  String? error;

  try {
    if (flags & EyeFlag.temperature != 0) {
      final at = r.pos;
      temperature = r.i16('Temperature') / 100.0;
      fields.add(ByteField(at, 2, 'Temperature', '${temperature.toStringAsFixed(2)} °C'));
    }
    if (flags & EyeFlag.humidity != 0) {
      final at = r.pos;
      humidity = r.u8('Humidity');
      fields.add(ByteField(at, 1, 'Humidity', '$humidity %'));
    }
    if (flags & EyeFlag.movementCounter != 0) {
      final at = r.pos;
      final v = r.u16('Movement counter');
      moving = (v & 0x8000) != 0;
      count = v & 0x7FFF;
      fields.add(ByteField(at, 2, 'Movement', '${moving ? 'moving' : 'still'} · count $count'));
    }
    if (flags & EyeFlag.movementAngle != 0) {
      final at = r.pos;
      final p = r.i8('Pitch');
      final ro = r.i16('Roll');
      pitch = p;
      roll = ro;
      fields.add(ByteField(at, 1, 'Pitch', '$pitch°'));
      fields.add(ByteField(at + 1, 2, 'Roll', '$roll°'));
    }
    if (flags & EyeFlag.batteryVoltage != 0) {
      final at = r.pos;
      final v = r.u8('Battery voltage');
      battery = 2000 + v * 10;
      fields.add(ByteField(at, 1, 'Battery voltage', '$battery mV'));
    }
  } on TruncatedException catch (e) {
    error = 'Truncated — ${e.what} missing';
  }

  final tail = r.rest();
  if (tail.isNotEmpty) {
    fields.add(ByteField(payload.length - tail.length, tail.length, 'Unparsed', toHex(tail)));
  }

  return TeltonikaData(
    raw: raw,
    version: version,
    flags: flags,
    temperatureC: temperature,
    humidity: humidity,
    magnetDetected: flags & EyeFlag.magnetPresent != 0 ? flags & EyeFlag.magnetDetected != 0 : null,
    moving: moving,
    movementCount: count,
    pitch: pitch,
    roll: roll,
    batteryMv: battery,
    error: error,
    tail: tail,
    fields: fields,
  );
}
