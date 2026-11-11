import 'dart:typed_data';

import 'package:eye_protocol/eye_protocol.dart';
import 'package:test/test.dart';

/// Bytes are those of an EYE App session with a BTSMP1 (firmware 1.2.10), from the phone's HCI log.
void main() {
  Uint8List b(String hex) => parseHex(hex);

  test('the values the sensor sent decode to what the EYE App showed', () {
    expect(EyeSetting.interval.decode(b('98 08')), 2200);
    expect(EyeSetting.interval.decode(b('70 17')), 6000);
    expect(EyeSetting.interval.decode(b('d0 07')), 2000);
    expect(EyeSetting.name.decode(b('4d 50 31 5f 31 45 45 31 33 37 00 00 00')), 'MP1_1EE137');
    expect(EyeSetting.name.decode(b('54 65 73 74 53 65 6e 73 6f 72 31 00 00')), 'TestSensor1');
    expect(EyeSetting.protocolType.decode(b('02')), 2);
    expect(EyeSetting.sensors.decode(b('0f')), 15);
    expect(EyeSetting.txPower.decode(b('08')), 8);
    expect(EyeSetting.txPower.decode(b('f2')), -14);
    expect(EyeSetting.eddystoneId.decode(b('1e 4c 30 62 37 e1 55 aa c9 f6 da 0c e2 8b 00 55')), hasLength(16));
  });

  test('and encode to exactly the bytes the EYE App wrote', () {
    expect(toHex(EyeSetting.interval.encode(6000)), toHex(b('70 17')));
    expect(toHex(EyeSetting.interval.encode(2000)), toHex(b('d0 07')));
    expect(toHex(EyeSetting.name.encode('TestSensor1')), toHex(b('54 65 73 74 53 65 6e 73 6f 72 31 00')));
    expect(toHex(EyeSetting.name.encode('MP1_1EE137')), toHex(b('4d 50 31 5f 31 45 45 31 33 37 00 00')));
    expect(toHex(EyeSetting.txPower.encode(8)), '08');
    expect(toHex(EyeSetting.txPower.encode(-14)), 'F2');
    expect(toHex(encodePin('123456')), toHex(b('31 32 33 34 35 36')));
    expect(toHex(EyeCommand.writeToFlash.bytes), toHex(b('00 10')));
    expect(toHex(EyeCommand.keepAlive.bytes), toHex(b('00 15')));
  });

  test('values outside what the device accepts are refused before anything is written', () {
    expect(EyeSetting.interval.problem(999), contains('1000–10000'));
    expect(EyeSetting.interval.problem(10001), isNotNull);
    expect(EyeSetting.repeats.problem(11), isNotNull);
    expect(EyeSetting.subInterval.problem(19), isNotNull);
    expect(EyeSetting.txPower.problem(3), contains('-14, -11'));
    expect(EyeSetting.name.problem('A_NAME_TOO_LONG'), contains('12'));
    expect(EyeSetting.name.problem(''), isNotNull);
    expect(EyeSetting.name.problem('café'), isNotNull);
    expect(EyeSetting.eddystoneId.problem(List.filled(15, 0)), contains('16 bytes'));
    expect(() => EyeSetting.interval.encode(500), throwsArgumentError);
    expect(() => encodePin('12345'), throwsArgumentError);
    expect(() => encodePin('12a456'), throwsArgumentError);
    for (final v in [1000, 2000, 2200, 10000]) {
      expect(EyeSetting.interval.problem(v), isNull);
      expect(EyeSetting.interval.decode(EyeSetting.interval.encode(v)), v);
    }
  });

  test('every setting lives on the config service, except TX power on the Tx Power service', () {
    expect(EyeSetting.interval.characteristic, 'e61c0002-7df2-4d4e-8e6d-c611745b92e9');
    expect(EyeSetting.name.characteristic, 'e61c0016-7df2-4d4e-8e6d-c611745b92e9');
    expect(EyeSetting.sensors.characteristic, 'e61c0021-7df2-4d4e-8e6d-c611745b92e9');
    expect(EyeSetting.txPower.service, EyeGatt.txPowerService);
    expect(EyeGatt.password, 'e61c0008-7df2-4d4e-8e6d-c611745b92e9');
    expect(EyeGatt.command, 'e61c0007-7df2-4d4e-8e6d-c611745b92e9');
  });

  test('firmware 1.2.10 and later switch sensors separately', () {
    expect(parseFirmware('1.2.10\u0000\u0000'), [1, 2, 10]);
    expect(hasSensorSwitches('1.2.10'), isTrue);
    expect(hasSensorSwitches('1.3.0'), isTrue);
    expect(hasSensorSwitches('1.2.9'), isFalse);
    expect(hasSensorSwitches('1.1.0-beta'), isFalse);
  });

  test('repeats: three chances per window lift delivery from 45 % to over 80 %', () {
    expect(deliveredShare(intervalMs: 2000, repeats: 3, heard: 0.45), closeTo(0.45, 1e-9), reason: 'no repeats at 2000 ms');
    expect(deliveredShare(intervalMs: 2200, repeats: 3, heard: 0.45), closeTo(0.834, 0.001));
    expect(deliveredShare(intervalMs: 2200, repeats: 1, heard: 0.45), closeTo(0.45, 1e-9));
  });

  test('the live block the sensor serves decodes with the advertisement decoder', () {
    final t = decodeTeltonika(b('01 bf 09 bb 34 82 e1 30 ff fd 65'));
    expect(t.ok, isTrue);
    expect(t.temperatureC, 24.91);
    expect(t.humidity, 52);
    expect(t.batteryMv, 3010);
  });
}
