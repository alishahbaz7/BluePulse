import 'dart:async';

import 'package:bluepulse/config/config_session.dart';
import 'package:bluepulse/config/gatt_link.dart';
import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A BTSMP1 as the HCI log showed one: settings unreadable until the PIN is written, wrong PINs
/// counted, values little-endian, the name NUL-padded to 13 bytes on read.
class FakeSensor implements GattLink {
  FakeSensor({this.pin = '123456', this.firmware = '1.2.10'}) {
    values
      ..[EyeSetting.name.characteristic] = parseHex('4d 50 31 5f 31 45 45 31 33 37 00 00 00')
      ..[EyeSetting.protocolType.characteristic] = parseHex('02')
      ..[EyeSetting.sensors.characteristic] = parseHex('0f')
      ..[EyeSetting.interval.characteristic] = parseHex('98 08')
      ..[EyeSetting.subInterval.characteristic] = parseHex('64 00')
      ..[EyeSetting.repeats.characteristic] = parseHex('01 00')
      ..[EyeSetting.txPower.characteristic] = parseHex('08')
      ..[EyeSetting.iBeaconId.characteristic] = parseHex('ffffffff1e4c306237e155aac9f6da0ce28b0055')
      ..[EyeSetting.eddystoneId.characteristic] = parseHex('1e4c306237e155aac9f6da0ce28b0055')
      ..[EyeSetting.movementStart.characteristic] = parseHex('05 00')
      ..[EyeSetting.movementStop.characteristic] = parseHex('05 00')
      ..[EyeSetting.hibernate.characteristic] = parseHex('01')
      ..[EyeSetting.wakeUpAdvertising.characteristic] = parseHex('1e 00')
      ..[EyeSetting.rssiCalibration.characteristic] = parseHex('7f')
      ..[EyeGatt.model] = Uint8List.fromList('BTSMP1'.codeUnits)
      ..[EyeGatt.firmware] = Uint8List.fromList([...firmware.codeUnits, 0, 0, 0])
      ..[EyeGatt.mac] = parseHex('7c d9 f4 15 2d 01')
      ..[EyeGatt.live] = parseHex('01 bf 09 bb 34 82 e1 30 ff fd 65');
  }

  final String pin;
  final String firmware;
  final values = <String, Uint8List>{};
  final writes = <(String, String)>[];
  final connectionCtl = StreamController<bool>.broadcast();
  bool unlocked = false;
  int wrongPins = 0;

  /// Characteristics whose written value the device replaces with this (a refused setting).
  final overrides = <String, Uint8List>{};

  static final _open = {EyeGatt.passwordCounter, EyeGatt.model, EyeGatt.firmware, EyeGatt.mac, EyeGatt.live};

  @override
  Duration get settle => Duration.zero;
  int mtuRequests = 0;
  @override
  Future<void> negotiateMtu(String id) async => mtuRequests++;

  /// Connections that fail before the services are known (Android does this now and then).
  int failConnects = 0;
  int connects = 0;

  @override
  Future<void> connect(String id) async {
    connects++;
    if (failConnects > 0) {
      failConnects--;
      throw Exception('device disconnected');
    }
    connectionCtl.add(true);
  }
  @override
  Future<void> discover(String id) async {}
  @override
  Future<void> disconnect(String id) async => connectionCtl.add(false);
  @override
  Stream<bool> connection(String id) => connectionCtl.stream;

  @override
  Future<Uint8List> read(String id, String service, String characteristic) async {
    if (characteristic == EyeGatt.passwordCounter) return Uint8List.fromList([wrongPins, 0, 0]);
    if (!unlocked && !_open.contains(characteristic)) throw Exception('read not permitted');
    final v = values[characteristic];
    if (v == null) throw Exception('no such characteristic');
    return v;
  }

  @override
  Future<void> write(String id, String service, String characteristic, Uint8List value) async {
    writes.add((characteristic, toHex(value)));
    if (characteristic == EyeGatt.password) {
      unlocked = String.fromCharCodes(value) == pin;
      if (!unlocked) wrongPins++;
      return;
    }
    if (!unlocked) throw Exception('write not permitted');
    if (characteristic == EyeGatt.command) return;
    values[characteristic] = overrides[characteristic] ?? value;
  }
}

void main() {
  test('the right PIN opens every setting, the device information and the live reading', () async {
    final sensor = FakeSensor();
    final s = ConfigSession(link: sensor, mac: '7C:D9:F4:15:2D:01', livePeriod: const Duration(hours: 1));
    await s.open('123456');
    expect(s.state, ConfigState.ready);
    expect(sensor.writes.first, (EyeGatt.password, '313233343536'));
    expect(s.original[EyeSetting.name], 'MP1_1EE137');
    expect(s.original[EyeSetting.interval], 2200);
    expect(s.original[EyeSetting.txPower], 8);
    expect(s.original[EyeSetting.sensors], 15);
    expect(s.info.model, 'BTSMP1');
    expect(s.info.firmware, '1.2.10');
    expect(s.info.mac, '7C:D9:F4:15:2D:01');
    expect(s.live!.temperatureC, 24.91);
    expect(s.failedAttempts, 0);
    expect(sensor.mtuRequests, 1, reason: 'as the EYE App does, before the first read');
    expect(s.changes, isEmpty);
    expect(s.unsupported, isEmpty);
    await s.close();
  });

  test('a wrong PIN stops there: nothing read, the session says so, and one attempt is spent', () async {
    final sensor = FakeSensor();
    final s = ConfigSession(link: sensor, mac: 'X', livePeriod: const Duration(hours: 1));
    await s.open('000000');
    expect(s.state, ConfigState.failed);
    expect(s.wrongPin, isTrue);
    expect(s.error, contains('Wrong PIN'));
    expect(s.original.length, lessThanOrEqualTo(1));
    expect(sensor.wrongPins, 1);
    expect(() => s.open('12345'), throwsArgumentError, reason: 'a malformed PIN is refused before anything is sent');
  });

  test('save writes only what changed, reads each back, then saves to flash', () async {
    final sensor = FakeSensor();
    final s = ConfigSession(link: sensor, mac: 'X', livePeriod: const Duration(hours: 1));
    await s.open('123456');
    sensor.writes.clear();
    s
      ..edit(EyeSetting.interval, 2100)
      ..edit(EyeSetting.repeats, 3)
      ..edit(EyeSetting.name, 'TestSensor1')
      ..edit(EyeSetting.txPower, 8); // unchanged: not written
    expect(s.changes, [EyeSetting.name, EyeSetting.interval, EyeSetting.repeats]);
    expect(await s.save(), isTrue);
    expect(s.state, ConfigState.saved);
    expect(sensor.writes, [
      (EyeSetting.name.characteristic, toHex('TestSensor1'.codeUnits + [0])),
      (EyeSetting.interval.characteristic, '3408'),
      (EyeSetting.repeats.characteristic, '0300'),
      (EyeGatt.command, '0010'),
    ]);
    expect(s.original[EyeSetting.interval], 2100);
    expect(s.changes, isEmpty);
    await s.close();
  });

  test('values the device would refuse are not sent at all', () async {
    final sensor = FakeSensor();
    final s = ConfigSession(link: sensor, mac: 'X', livePeriod: const Duration(hours: 1));
    await s.open('123456');
    sensor.writes.clear();
    s
      ..edit(EyeSetting.interval, 500)
      ..edit(EyeSetting.txPower, 3);
    expect(s.problems.keys, containsAll([EyeSetting.interval, EyeSetting.txPower]));
    expect(await s.save(), isFalse);
    expect(sensor.writes, isEmpty);
    await s.close();
  });

  test('a setting the device does not keep is reported, and the rest are still saved', () async {
    final sensor = FakeSensor()..overrides[EyeSetting.repeats.characteristic] = parseHex('01 00');
    final s = ConfigSession(link: sensor, mac: 'X', livePeriod: const Duration(hours: 1));
    await s.open('123456');
    s
      ..edit(EyeSetting.repeats, 3)
      ..edit(EyeSetting.movementStart, 6);
    expect(await s.save(), isFalse);
    expect(s.saveErrors.keys, [EyeSetting.repeats]);
    expect(s.saveErrors[EyeSetting.repeats], contains('kept 1'));
    expect(s.savedSettings, [EyeSetting.movementStart]);
    expect(sensor.writes.last, (EyeGatt.command, '0010'), reason: 'what did take is saved to flash');
    await s.close();
  });

  test('older firmware has no sensor switches; a dropped connection ends the session', () async {
    final sensor = FakeSensor(firmware: '1.1.0');
    final s = ConfigSession(link: sensor, mac: 'X', livePeriod: const Duration(hours: 1));
    await s.open('123456');
    expect(s.unsupported, contains(EyeSetting.sensors));
    sensor.connectionCtl.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(s.state, ConfigState.failed);
    expect(s.error, contains('closed the connection'));
    s.dispose();
  });

  test('a connection lost before the PIN is tried once more, without spending a PIN attempt', () async {
    final sensor = FakeSensor()..failConnects = 1;
    final s = ConfigSession(link: sensor, mac: 'X', livePeriod: const Duration(hours: 1));
    await s.open('123456');
    expect(s.state, ConfigState.ready);
    expect(sensor.connects, 2);
    expect(sensor.wrongPins, 0);
    await s.close();

    final twice = FakeSensor()..failConnects = 2;
    final s2 = ConfigSession(link: twice, mac: 'X', livePeriod: const Duration(hours: 1));
    await s2.open('123456');
    expect(s2.state, ConfigState.failed);
    expect(s2.error, contains('Could not connect'));
    expect(twice.writes, isEmpty, reason: 'no PIN was sent');
  });

  test('hex for the ID fields', () {
    expect(hexOrNull('1e 4c:30-62'), parseHex('1e4c3062'));
    expect(hexOrNull('abc'), isNull);
    expect(hexOrNull('zz'), isNull);
    expect(listEquals(hexOrNull('00ff'), [0, 255]), isTrue);
  });
}
