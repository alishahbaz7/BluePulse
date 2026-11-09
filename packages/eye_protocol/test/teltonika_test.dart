import 'package:eye_protocol/eye_protocol.dart';
import 'package:test/test.dart';

TeltonikaData t(String hex) => decodeTeltonika(parseHex(hex));

void main() {
  group('Teltonika block — BTSID1 (verified)', () {
    test('T-01 battery present, not low', () {
      final d = t('01 80 63');
      expect(d.ok, isTrue);
      expect(d.version, 1);
      expect(d.flags, 0x80);
      expect(d.batteryMv, 2990);
      expect(d.lowBattery, isFalse);
      expect(d.hasSensorBits, isFalse);
      expect(d.tail, isEmpty);
    });

    test('T-02 low battery flag with voltage', () {
      final d = t('01 C0 4B');
      expect(d.lowBattery, isTrue);
      expect(d.batteryMv, 2750);
    });

    test('T-03 no values', () {
      final d = t('01 00');
      expect(d.ok, isTrue);
      expect(d.batteryMv, isNull);
      expect(d.lowBattery, isFalse);
      expect(d.magnetDetected, isNull);
    });

    test('T-04 battery promised but missing → truncated', () {
      final d = t('01 80');
      expect(d.ok, isFalse);
      expect(d.error, contains('Battery voltage'));
      expect(d.batteryMv, isNull);
    });

    test('T-05 unsupported version keeps the raw bytes', () {
      final d = t('02 80 63');
      expect(d.error, contains('Unsupported protocol version 0x02'));
      expect(d.flags, isNull);
      expect(toHex(d.tail), '8063');
    });

    test('battery range ends: raw 0 and 255', () {
      expect(t('01 80 00').batteryMv, 2000);
      expect(t('01 80 FF').batteryMv, 4550);
    });

    test('flags missing', () {
      expect(t('01').error, contains('flags missing'));
    });

    test('empty block', () {
      expect(decodeTeltonika(parseHex('')).error, isNotNull);
    });

    test('trailing bytes are kept as the tail, not an error', () {
      final d = t('01 80 63 AA BB');
      expect(d.ok, isTrue);
      expect(toHex(d.tail), 'AABB');
      expect(d.fields.last.label, 'Unparsed');
    });

    test('byte fields cover version, flags and battery', () {
      final f = t('01 80 63').fields;
      expect(f.map((e) => e.label), ['Protocol version', 'Flags', 'Battery voltage']);
      expect(f[2].offset, 2);
      expect(f[2].value, '2990 mV');
    });
  });

  group('Teltonika block — EYE SENSOR (provisional layout)', () {
    test('T-06 every value present', () {
      final d = t('01 BF 08 B4 2D 80 0C F6 00 5A 64');
      expect(d.ok, isTrue);
      expect(d.temperatureC, closeTo(22.28, 1e-9));
      expect(d.humidity, 45);
      expect(d.magnetPresent, isTrue);
      expect(d.magnetDetected, isTrue);
      expect(d.moving, isTrue);
      expect(d.movementCount, 12);
      expect(d.pitch, -10);
      expect(d.roll, 90);
      expect(d.lowBattery, isFalse);
      expect(d.batteryMv, 3000);
      expect(d.hasSensorBits, isTrue);
      expect(d.tail, isEmpty);
    });

    test('T-07 negative temperature', () {
      expect(t('01 01 FF 38').temperatureC, closeTo(-2.0, 1e-9));
    });

    test('magnet present but no field', () {
      final d = t('01 04');
      expect(d.magnetPresent, isTrue);
      expect(d.magnetDetected, isFalse);
    });

    test('magnet state bit without presence bit is ignored', () {
      expect(t('01 08').magnetDetected, isNull);
    });

    test('still, count 32767', () {
      final d = t('01 10 7F FF');
      expect(d.moving, isFalse);
      expect(d.movementCount, 32767);
    });

    test('angle truncated after pitch', () {
      final d = t('01 20 F6 00');
      expect(d.error, contains('Roll'));
      expect(d.pitch, isNull, reason: 'pitch is only committed once both angles are read');
    });
  });
}
