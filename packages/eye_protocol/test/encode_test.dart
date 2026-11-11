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

  group('BluePulse simulator tag', () {
    test('the ID comes back as sent, and the tag is 10 bytes on air', () {
      for (final id in [0, 1, 0x1A2B3C4D, 0xFFFFFFFF]) {
        expect(decodeSimulatorTag(encodeSimulatorTag(id)), id);
      }
      final ad = AdvertisementData(manufacturerData: {simulatorCompanyId: encodeSimulatorTag(0x1A2B3C4D)});
      expect(ad.toBytes(), hasLength(simulatorTagBytes));
      expect(decodeAdvertisement(AdvertisementData.parse(ad.toBytes())).simulatorId, 0x1A2B3C4D);
      expect(simulatorKey(0x1A2B3C4D), 'SIM-1A2B3C4D');
      expect(simulatorKey(0xAB), 'SIM-000000AB');
    });

    test("other devices' 0xFFFF data is not taken for the tag", () {
      expect(decodeSimulatorTag(parseHex('42 50 01 02')), isNull, reason: 'too short');
      expect(decodeSimulatorTag(parseHex('01 02 03 04 05 06')), isNull, reason: 'not BP');
      final other = AdvertisementData(manufacturerData: {simulatorCompanyId: parseHex('00 11 22')});
      expect(decodeAdvertisement(other).simulatorId, isNull);
    });

    test('a beacon gives the same simulator ID every time, and different beacons different IDs', () {
      final a = BeaconId.eddystone(parseHex('B1E5B1E5B1E5B1E5B1E5'), parseHex('0B154E2D0055'));
      final a2 = BeaconId.eddystone(parseHex('B1E5B1E5B1E5B1E5B1E5'), parseHex('0B154E2D0055'));
      final b = BeaconId.eddystone(parseHex('B1E5B1E5B1E5B1E5B1E5'), parseHex('0B154E2D0056'));
      final i = BeaconId.iBeacon(parseHex('B1E5A11C0B1E4F00A000000000000001'), 1, 1);
      expect(simulatorIdForBeacon(a), simulatorIdForBeacon(a2));
      expect({simulatorIdForBeacon(a), simulatorIdForBeacon(b), simulatorIdForBeacon(i)}, hasLength(3));
      for (final id in [a, b, i]) {
        expect(simulatorIdForBeacon(id), inInclusiveRange(0, 0xFFFFFFFF));
      }
    });

    test('FNV-1a matches the reference for a known input', () {
      // The kind's index (0, Eddystone) and sixteen 0x61 bytes, against the textbook FNV-1a loop
      // in 64-bit arithmetic.
      var h = 0x811C9DC5;
      for (final b in [0, ...List.filled(16, 0x61)]) {
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF;
      }
      final id = BeaconId.eddystone(Uint8List.fromList(List.filled(10, 0x61)), Uint8List.fromList(List.filled(6, 0x61)));
      expect(simulatorIdForBeacon(id), h);
    });

    test('the inspector names the tag', () {
      final ad = AdvertisementData(manufacturerData: {simulatorCompanyId: encodeSimulatorTag(0x1A2B3C4D)});
      final labels = annotateRaw(ad.toBytes()).fields.map((f) => '${f.label}=${f.value}').toList();
      expect(labels, containsAll(['BluePulse simulator=BP', 'Simulated device=SIM-1A2B3C4D']));
    });
  });
}
