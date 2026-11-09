import 'package:bluepulse/app/settings.dart';
import 'package:bluepulse/core/device.dart';
import 'package:bluepulse/core/registry.dart';
import 'package:bluepulse/core/signal.dart';
import 'package:bluepulse/scanner/scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late AppSettings settings;
  late DeviceRegistry r;
  final t0 = DateTime(2026, 11, 9, 12);

  setUp(() {
    settings = AppSettings(null, false);
    r = DeviceRegistry(settings);
  });
  tearDown(() => r.dispose());

  test('advertisement and scan response merge into one EYE BEACON', () {
    r.ingest(event('AA:00:00:00:00:01', beaconAdv, at: t0));
    r.ingest(event('AA:00:00:00:00:01', beaconRsp, at: t0.add(const Duration(milliseconds: 12))));
    final d = r.device('AA:00:00:00:00:01')!;
    expect(d.name, 'ID1_ABCDEFG');
    expect(d.model, DeviceModel.eyeBeacon);
    expect(d.beaconId!.instanceHex, '0B154E2D0055');
    expect(d.batteryMv, 2990);
    expect(d.txPower1m, -59);
    expect(d.packets, 2);
    expect(d.readings, 1, reason: 'ADV + scan response 12 ms apart are one advertising event');
    expect(r.packets.length, 2);
  });

  test('sensor flags make an EYE SENSOR', () {
    r.ingest(event('AA:00:00:00:00:02', sensorRsp, at: t0));
    final d = r.device('AA:00:00:00:00:02')!;
    expect(d.model, DeviceModel.eyeSensor);
    expect(d.teltonika!.temperatureC, closeTo(22.28, 1e-9));
    expect(d.temperatureHistory.length, 1);
    expect(d.movementHistory.single.value, 12);
  });

  test('third-party beacons are hidden unless all beacons are shown; phones are ignored', () {
    r.ingest(event('AA:00:00:00:00:03', foreignAdv, at: t0));
    r.ingest(event('AA:00:00:00:00:04', phoneAdv, at: t0));
    expect(r.device('AA:00:00:00:00:03')!.model, DeviceModel.otherBeacon);
    expect(r.device('AA:00:00:00:00:04'), isNull);
    expect(r.devices, isEmpty);
    settings.update((s) => s.showAllBeacons = true);
    expect(r.devices.length, 1);
  });

  test('interval is the median gap between advertising events', () {
    for (var i = 0; i < 6; i++) {
      final at = t0.add(Duration(milliseconds: 5000 * i + (i.isEven ? 20 : -20)));
      r.ingest(event('AA:00:00:00:00:01', beaconAdv, at: at));
      r.ingest(event('AA:00:00:00:00:01', beaconRsp, at: at.add(const Duration(milliseconds: 10))));
    }
    final d = r.device('AA:00:00:00:00:01')!;
    expect(d.readings, 6);
    expect(d.intervalMs, inInclusiveRange(4960, 5040));
  });

  test('not seen after three intervals, or the minimum', () {
    for (var i = 0; i < 4; i++) {
      r.ingest(event('AA:00:00:00:00:01', beaconRsp, at: t0.add(Duration(seconds: 5 * i))));
    }
    final d = r.device('AA:00:00:00:00:01')!;
    final last = d.lastSeen;
    expect(d.isNotSeen(last.add(const Duration(seconds: 14)), 15), isFalse);
    expect(d.isNotSeen(last.add(const Duration(seconds: 16)), 15), isTrue);
    expect(r.proximityOf(d, last.add(const Duration(seconds: 16))), Proximity.lost);
  });

  test('readings per minute', () {
    final now = DateTime(2026, 11, 9, 12, 10, 30);
    r.ingest(event('AA:00:00:00:00:01', beaconRsp, at: DateTime(2026, 11, 9, 12, 9, 10)));
    r.ingest(event('AA:00:00:00:00:01', beaconRsp, at: DateTime(2026, 11, 9, 12, 9, 40)));
    r.ingest(event('AA:00:00:00:00:01', beaconRsp, at: DateTime(2026, 11, 9, 12, 10, 5)));
    expect(r.readingsPerMinute(now, 3), [0, 2, 1]);
  });

  group('signal', () {
    test('smoothing off returns raw', () {
      final s = RssiSmoother(0);
      expect(s.add(-60, t0), -60);
      expect(s.add(-80, t0.add(const Duration(seconds: 1))), -80);
    });

    test('smoothing reaches ~95 % of a step after the timeout', () {
      final s = RssiSmoother(9);
      s.add(-60, t0);
      final v = s.add(-80, t0.add(const Duration(seconds: 9)));
      expect(v, closeTo(-60 - 20 * 0.95, 0.2));
    });

    test('proximity zones', () {
      expect(classifyProximity(-60, nearDbm: -65, awayDbm: -85), Proximity.near);
      expect(classifyProximity(-65, nearDbm: -65, awayDbm: -85), Proximity.near);
      expect(classifyProximity(-70, nearDbm: -65, awayDbm: -85), Proximity.away);
      expect(classifyProximity(-90, nearDbm: -65, awayDbm: -85), Proximity.lost);
      expect(classifyProximity(-50, nearDbm: -65, awayDbm: -85, notSeen: true), Proximity.lost);
      expect(classifyProximity(null, nearDbm: -65, awayDbm: -85), Proximity.lost);
    });

    test('distance is 1 m at the calibrated power', () {
      expect(estimateDistance(-59, -59, 2.5), closeTo(1, 1e-9));
      expect(estimateDistance(-84, -59, 2.5), closeTo(10, 1e-9));
      expect(estimateDistance(null, -59, 2.5), isNull);
    });
  });

  group('scanner helpers', () {
    test('MAC normalised', () {
      expect(normaliseMac('aa:bb:cc:dd:ee:ff'), 'AA:BB:CC:DD:EE:FF');
      expect(normaliseMac('aabbccddeeff'), 'AA:BB:CC:DD:EE:FF');
      expect(normaliseMac('opaque-web-id'), 'OPAQUE-WEB-ID');
    });

    test('16-bit UUIDs from base UUIDs', () {
      expect(uuid16('0000feaa-0000-1000-8000-00805f9b34fb'), 0xFEAA);
      expect(uuid16('FEAA'), 0xFEAA);
      expect(uuid16('e61c0000-7df2-4d4e-8e6d-c611745b92e9'), isNull);
    });
  });

  test('a clock jump backwards starts a new reading without a negative gap', () {
    r.ingest(event('AA:00:00:00:00:01', beaconRsp, at: t0));
    r.ingest(event('AA:00:00:00:00:01', beaconRsp, at: t0.subtract(const Duration(seconds: 30))));
    final d = r.device('AA:00:00:00:00:01')!;
    expect(d.readings, 2);
    expect(d.intervalMs, isNull);
  });

  test('settings keep away at or below near', () {
    settings.update((s) {
      s.nearDbm = -70;
      s.awayDbm = -60;
    });
    expect(settings.awayDbm, -70);
  });

  test('without live scanning the source is demo', () {
    expect(AppSettings(null, false).scanSource, ScanSource.demo);
    expect(AppSettings(null, true).scanSource, ScanSource.live);
  });
}
