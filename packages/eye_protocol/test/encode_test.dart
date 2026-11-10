import 'dart:typed_data';

import 'package:eye_protocol/eye_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Teltonika encoder — round trip through the decoder', () {
    test('BTSID1 battery block matches the wiki bytes', () {
      expect(toHex(encodeTeltonika(batteryMv: 2990)), toHex(parseHex('01 80 63')));
      expect(toHex(encodeTeltonika(batteryMv: 2750, lowBattery: true)), toHex(parseHex('01 C0 4B')));
    });

    test('every EYE SENSOR value comes back as sent', () {
      final bytes = encodeTeltonika(
        temperatureC: -12.34,
        humidity: 57,
        magnetPresent: true,
        magnetDetected: true,
        moving: true,
        movementCount: 1234,
        pitch: -45,
        roll: 170,
        batteryMv: 3050,
      );
      final d = decodeTeltonika(bytes);
      expect(d.ok, isTrue, reason: d.error);
      expect(d.temperatureC, -12.34);
      expect(d.humidity, 57);
      expect(d.magnetPresent, isTrue);
      expect(d.magnetDetected, isTrue);
      expect(d.moving, isTrue);
      expect(d.movementCount, 1234);
      expect(d.pitch, -45);
      expect(d.roll, 170);
      expect(d.batteryMv, 3050);
      expect(d.lowBattery, isFalse);
      expect(d.tail, isEmpty);
    });

    test('a value left out leaves its flag off and takes no bytes', () {
      final d = decodeTeltonika(encodeTeltonika(temperatureC: 21.5));
      expect(d.flags, EyeFlag.temperature);
      expect(d.raw, hasLength(4));
      expect(d.humidity, isNull);
    });

    test('values beyond what the fields hold are clamped, not wrapped', () {
      final d = decodeTeltonika(encodeTeltonika(movementCount: 40000, batteryMv: 9000, humidity: 300, pitch: 200));
      expect(d.movementCount, 40000 & 0x7FFF);
      expect(d.batteryMv, 4550);
      expect(d.humidity, 255);
      expect(d.pitch, 127);
      expect(teltonikaBatteryStep(3047), 3050);
    });
  });

  test('Eddystone-UID frame decodes to the same namespace, instance and power', () {
    final ns = parseHex('E39B606AA38255AA8E46');
    final inst = parseHex('0B154E2D0055');
    final f = decodeEddystone(encodeEddystoneUid(namespace: ns, instance: inst, txPower0m: -4));
    expect(f, isA<EddystoneUid>());
    final uid = f! as EddystoneUid;
    expect(toHex(uid.namespace), toHex(ns));
    expect(toHex(uid.instance), toHex(inst));
    expect(uid.txPower0m, -4);
    expect(() => encodeEddystoneUid(namespace: [1, 2], instance: inst), throwsArgumentError);
  });

  test('iBeacon payload decodes to the same UUID, major, minor and power', () {
    final uuid = Uint8List.fromList(List.generate(16, (i) => i * 7));
    final b = decodeIBeacon(encodeIBeacon(uuid: uuid, major: 513, minor: 65535, measuredPower: -61))!;
    expect(toHex(b.uuidBytes), toHex(uuid));
    expect(b.major, 513);
    expect(b.minor, 65535);
    expect(b.measuredPower, -61);
  });
}
