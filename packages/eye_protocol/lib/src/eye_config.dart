import 'dart:convert';
import 'dart:typed_data';

import 'hex.dart';

/// Configuring EYE SENSORs (BTSMP1) and EYE BEACONs (BTSID1) over GATT: the characteristics, how each
/// value is encoded, its range, and the commands. From Teltonika's BTSMP1 page (GATT Characteristics)
/// and checked byte for byte against a session of Teltonika's EYE App with a BTSMP1 on firmware
/// 1.2.10, recorded in the phone's HCI log (10-11-2026):
///
/// * reads of the settings are refused (ATT "read not permitted") until the PIN is written, as six
///   ASCII digits, to [EyeGatt.password];
/// * numbers are little-endian (interval `98 08` = 2200 ms, `70 17` = 6000 ms);
/// * the name is written as 12 bytes, padded with NULs, and reads back NUL-padded;
/// * a save ends with the command `00 10` (Write to flash) on [EyeGatt.command];
/// * the sensor keeps the ATT MTU at 23, so one write carries at most 20 bytes.
abstract final class EyeGatt {
  static const service = 'e61c0000-7df2-4d4e-8e6d-c611745b92e9';
  static String char(int n) => 'e61c${n.toRadixString(16).padLeft(4, '0')}-7df2-4d4e-8e6d-c611745b92e9';

  static final command = char(0x0007);
  static final password = char(0x0008);

  /// Readable before the PIN: wrong-PIN count (byte 0) and lock-out timer (bytes 1–2).
  static final passwordCounter = char(0x0019);

  static const txPowerService = '00001804-0000-1000-8000-00805f9b34fb';
  static const txPower = '00002a07-0000-1000-8000-00805f9b34fb';

  static const deviceInfo = '0000180a-0000-1000-8000-00805f9b34fb';
  static const manufacturer = '00002a29-0000-1000-8000-00805f9b34fb';
  static const model = '00002a24-0000-1000-8000-00805f9b34fb';
  static const hardware = '00002a27-0000-1000-8000-00805f9b34fb';
  static const firmware = '00002a26-0000-1000-8000-00805f9b34fb';

  /// The MAC, in display order (`7c d9 f4 15 2d 01`). The PDF names `652143dc-…`; the sensor answered
  /// on this one.
  static const mac = 'a610249d-913e-46bd-b14f-c6dedc432165';

  /// The live Teltonika block (what the scan response carries), readable while connected.
  static const liveService = 'e61c0000-7df3-4d4e-8e6d-c611745b92e9';
  static const live = 'e61c0001-7df3-4d4e-8e6d-c611745b92e9';
}

/// Commands for [EyeGatt.command], two bytes as the EYE App sends them (`00 10`).
enum EyeCommand {
  writeToFlash(0x0010),
  reset(0x0012),
  keepAlive(0x0015),
  restoreDefaults(0x0016);

  const EyeCommand(this.code);
  final int code;

  Uint8List get bytes => Uint8List.fromList([code >> 8, code & 0xFF]);
}

/// How a setting's value is laid out on the characteristic.
enum EyeValueKind { text, u8, i8, u16, bytes }

/// One configurable setting.
enum EyeSetting {
  name('Name', 0x0016, EyeValueKind.text, max: 12),
  protocolType('Protocol type', 0x0001, EyeValueKind.u8, min: 0, max: 4),
  sensors('Sensors on', 0x0021, EyeValueKind.u8, min: 0, max: 15),
  interval('Advertising interval', 0x0002, EyeValueKind.u16, min: 1000, max: 10000, unit: 'ms'),
  subInterval('Repeat spacing', 0x0003, EyeValueKind.u16, min: 20, max: 1000, unit: 'ms'),
  repeats('Repeats', 0x0004, EyeValueKind.u16, min: 1, max: 10),
  txPower('TX power', 0, EyeValueKind.i8, min: -14, max: 8, unit: 'dBm'),
  iBeaconId('iBeacon ID', 0x0005, EyeValueKind.bytes, max: 20),
  eddystoneId('Eddystone ID', 0x0006, EyeValueKind.bytes, max: 16),
  movementStart('Movement start', 0x0013, EyeValueKind.u16, min: 0, max: 300, unit: 's'),
  movementStop('Movement stop', 0x0014, EyeValueKind.u16, min: 0, max: 300, unit: 's'),
  hibernate('Hibernate', 0x0018, EyeValueKind.u8, min: 0, max: 1),
  wakeUpAdvertising('Wake-up advertising', 0x0022, EyeValueKind.u16, min: 1, max: 300, unit: 's'),
  rssiCalibration('RSSI calibration', 0x0023, EyeValueKind.i8, min: -100, max: 127, unit: 'dBm');

  const EyeSetting(this.label, this.code, this.kind, {this.min, required this.max, this.unit});

  final String label;
  final int code;
  final EyeValueKind kind;
  final int? min;

  /// The largest value, or for text and bytes the length.
  final int max;
  final String? unit;

  String get service => this == txPower ? EyeGatt.txPowerService : EyeGatt.service;
  String get characteristic => this == txPower ? EyeGatt.txPower : EyeGatt.char(code);

  /// The TX powers the device accepts, dBm.
  static const txPowers = [-14, -11, -8, -5, -2, 2, 4, 8];

  /// The value as read: a String (name), an int, or bytes (IDs).
  Object decode(Uint8List raw) => switch (kind) {
        EyeValueKind.text => latin1.decode(raw.takeWhile((b) => b != 0).toList()).trim(),
        EyeValueKind.u8 => raw.isEmpty ? 0 : raw[0],
        EyeValueKind.i8 => raw.isEmpty ? 0 : (raw[0] >= 0x80 ? raw[0] - 256 : raw[0]),
        EyeValueKind.u16 => raw.length < 2 ? (raw.isEmpty ? 0 : raw[0]) : raw[0] | raw[1] << 8,
        EyeValueKind.bytes => Uint8List.fromList(raw),
      };

  /// The bytes to write. Throws [ArgumentError] for a value [problem] would refuse.
  Uint8List encode(Object value) {
    final why = problem(value);
    if (why != null) throw ArgumentError(why);
    return switch (kind) {
      EyeValueKind.text => Uint8List.fromList([...ascii.encode(value as String), ...List.filled(max - value.length, 0)]),
      EyeValueKind.u8 => Uint8List.fromList([value as int]),
      EyeValueKind.i8 => Uint8List.fromList([(value as int) & 0xFF]),
      EyeValueKind.u16 => Uint8List.fromList([(value as int) & 0xFF, value >> 8]),
      EyeValueKind.bytes => Uint8List.fromList(value as List<int>),
    };
  }

  /// Why a value cannot be written, or null.
  String? problem(Object value) {
    switch (kind) {
      case EyeValueKind.text:
        if (value is! String) return '$label: text expected';
        if (value.isEmpty) return '$label: cannot be empty';
        if (value.length > max) return '$label: at most $max characters';
        if (!RegExp(r'^[\x20-\x7E]+$').hasMatch(value)) return '$label: letters, digits and plain symbols only';
        return null;
      case EyeValueKind.bytes:
        if (value is! List<int>) return '$label: bytes expected';
        if (value.length != max) return '$label: exactly $max bytes (${max * 2} hex digits)';
        return null;
      case EyeValueKind.u8 || EyeValueKind.i8 || EyeValueKind.u16:
        if (value is! int) return '$label: a whole number expected';
        if (this == txPower && !txPowers.contains(value)) return '$label: one of ${txPowers.join(', ')} dBm';
        if (value < min! || value > max) return '$label: $min–$max${unit == null ? '' : ' $unit'}';
        return null;
    }
  }

  /// The value for a screen: hex for IDs.
  String show(Object? value) => switch (value) {
        null => '—',
        final List<int> b => toHex(b),
        _ => '$value',
      };
}

/// The protocol types, as the device names them.
String protocolTypeLabel(int t) => switch (t) {
      0 => 'iBeacon',
      1 => 'Eddystone',
      2 => 'EYE Sensor',
      3 => 'iBeacon + EYE Sensor',
      4 => 'Eddystone + EYE Sensor',
      _ => 'Type $t',
    };

/// The PIN as written: six ASCII digits.
Uint8List encodePin(String pin) {
  if (!RegExp(r'^\d{6}$').hasMatch(pin)) throw ArgumentError('The PIN is six digits');
  return Uint8List.fromList(ascii.encode(pin));
}

/// A firmware version as numbers (`1.2.10` → [1, 2, 10]); missing parts are 0.
List<int> parseFirmware(String v) {
  final parts = RegExp(r'\d+').allMatches(v).map((m) => int.parse(m[0]!)).toList();
  while (parts.length < 3) {
    parts.add(0);
  }
  return parts.take(3).toList();
}

/// From 01.02.10 the protocol type runs 0–2 and sensors are switched by [EyeSetting.sensors].
bool hasSensorSwitches(String firmware) {
  final f = parseFirmware(firmware);
  return f[0] > 1 || (f[0] == 1 && (f[1] > 2 || (f[1] == 2 && f[2] >= 10)));
}

/// What a reading every [intervalMs] with [repeats] repeats [spacingMs] apart gives a receiver that
/// hears each packet with probability [heard]: the share of intervals with at least one packet heard.
/// Repeats only apply above 2000 ms (Teltonika's rule).
double deliveredShare({required int intervalMs, required int repeats, required double heard}) {
  final n = intervalMs > 2000 ? repeats.clamp(1, 10) : 1;
  var missAll = 1.0;
  for (var i = 0; i < n; i++) {
    missAll *= 1 - heard;
  }
  return 1 - missAll;
}
