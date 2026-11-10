import 'dart:typed_data';

import 'teltonika.dart';

/// Encoders — the inverse of the decoders — for transmitting simulated EYE devices and beacons.
/// Each is checked by decoding its output back (test/encode_test.dart).

/// The Teltonika `0x089A` block (without the company ID): version `0x01`, the flags, then one value
/// for each flag that carries one, in flag-bit order (PLAN.md §3.4). A null value leaves its flag off.
Uint8List encodeTeltonika({
  double? temperatureC,
  int? humidity,
  bool magnetPresent = false,
  bool magnetDetected = false,
  bool? moving,
  int? movementCount,
  int? pitch,
  int? roll,
  bool lowBattery = false,
  int? batteryMv,
}) {
  var flags = 0;
  final values = BytesBuilder();
  if (temperatureC != null) {
    flags |= EyeFlag.temperature;
    final v = (temperatureC * 100).round().clamp(-32768, 32767);
    values.add([(v >> 8) & 0xFF, v & 0xFF]);
  }
  if (humidity != null) {
    flags |= EyeFlag.humidity;
    values.addByte(humidity.clamp(0, 255));
  }
  if (magnetPresent) {
    flags |= EyeFlag.magnetPresent;
    if (magnetDetected) flags |= EyeFlag.magnetDetected;
  }
  if (movementCount != null || moving != null) {
    flags |= EyeFlag.movementCounter;
    final v = ((movementCount ?? 0) & 0x7FFF) | ((moving ?? false) ? 0x8000 : 0);
    values.add([(v >> 8) & 0xFF, v & 0xFF]);
  }
  if (pitch != null || roll != null) {
    flags |= EyeFlag.movementAngle;
    final p = (pitch ?? 0).clamp(-128, 127);
    final r = (roll ?? 0).clamp(-32768, 32767);
    values.add([p & 0xFF, (r >> 8) & 0xFF, r & 0xFF]);
  }
  if (lowBattery) flags |= EyeFlag.lowBattery;
  if (batteryMv != null) {
    flags |= EyeFlag.batteryVoltage;
    values.addByte(((batteryMv - 2000) / 10).round().clamp(0, 255));
  }
  return Uint8List.fromList([0x01, flags, ...values.takeBytes()]);
}

/// The battery a Teltonika block can carry, rounded to its 10 mV steps (2000–4550 mV).
int teltonikaBatteryStep(int mv) => 2000 + ((mv - 2000) / 10).round().clamp(0, 255) * 10;

/// Eddystone-UID service data (for UUID `0xFEAA`): frame type `0x00`, TX power at 0 m, the 10-byte
/// namespace, the 6-byte instance and two reserved bytes.
Uint8List encodeEddystoneUid({required List<int> namespace, required List<int> instance, int txPower0m = -4}) {
  if (namespace.length != 10) throw ArgumentError.value(namespace.length, 'namespace', 'must be 10 bytes');
  if (instance.length != 6) throw ArgumentError.value(instance.length, 'instance', 'must be 6 bytes');
  return Uint8List.fromList([0x00, txPower0m & 0xFF, ...namespace, ...instance, 0x00, 0x00]);
}

/// iBeacon manufacturer data (for Apple, `0x004C`): `02 15`, the 16-byte UUID, major and minor
/// big-endian, and the measured power at 1 m.
Uint8List encodeIBeacon({required List<int> uuid, required int major, required int minor, int measuredPower = -59}) {
  if (uuid.length != 16) throw ArgumentError.value(uuid.length, 'uuid', 'must be 16 bytes');
  return Uint8List.fromList([
    0x02, 0x15, ...uuid, //
    (major >> 8) & 0xFF, major & 0xFF,
    (minor >> 8) & 0xFF, minor & 0xFF,
    measuredPower & 0xFF,
  ]);
}
