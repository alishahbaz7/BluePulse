import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bluepulse/app/controller.dart';
import 'package:bluepulse/app/settings.dart';
import 'package:bluepulse/core/device.dart';
import 'package:bluepulse/core/registry.dart';
import 'package:bluepulse/main.dart';
import 'package:bluepulse/scanner/scanner.dart';
import 'package:bluepulse/simulator/advertiser.dart';
import 'package:bluepulse/simulator/sim_model.dart';
import 'package:bluepulse/simulator/sim_service.dart';
import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Records what the simulator asks of the radio.
class FakeAdvertiser extends BleAdvertiser {
  FakeAdvertiser({this.caps = const TxCapabilities(supported: true, exactInterval: true, name: true, scanResponse: true, txPower: true)});

  TxCapabilities caps;
  final calls = <String>[];
  final started = <Map<String, Object?>>[];
  final updated = <AdvertisementData>[];
  bool permissionGranted = true;
  final errorsCtl = StreamController<String>.broadcast();

  @override
  Stream<String> get errors => errorsCtl.stream;

  @override
  Future<TxCapabilities> capabilities() async => caps;

  @override
  Future<bool> requestPermissions() async {
    calls.add('permissions');
    return permissionGranted;
  }

  @override
  Future<String?> start({required adv, scanResponse, required intervalMs, txPowerDbm, name}) async {
    calls.add('start');
    started.add({'adv': adv, 'sr': scanResponse, 'interval': intervalMs, 'power': txPowerDbm, 'name': name});
    return name;
  }

  @override
  Future<void> update({required adv, scanResponse}) async {
    calls.add('update');
    updated.add(adv);
  }

  @override
  Future<void> stop() async => calls.add('stop');
}

DecodedAdvertisement decoded(SimPayload p) =>
    decodeAdvertisement(p.scanResponse == null ? p.adv : p.adv.merge(p.scanResponse!));

void main() {
  group('packets', () {
    test('EYE SENSOR: name and every value in one advertisement, as a real BTSMP1 with protocol "EYE Sensors"', () {
      final s = SimSettings(temperatureC: 22.28, humidity: 18, batteryMv: 3030, pitch: 11, roll: -57, movementCount: 3275);
      final p = buildPayload(s, SimValues.from(s));
      expect(p.scanResponse, isNull);
      expect(p.problem, isNull);
      expect(p.advBytes, lessThanOrEqualTo(31));
      final d = decoded(p);
      expect(d.name, 'MP1_SIM001');
      final t = d.teltonika!;
      expect(t.temperatureC, 22.28);
      expect(t.humidity, 18);
      expect(t.movementCount, 3275);
      expect(t.pitch, 11);
      expect(t.roll, -57);
      expect(t.batteryMv, 3030);
      expect(t.magnetPresent, isTrue);
    });

    test('EYE SENSOR with a beacon frame puts the sensor data in the scan response', () {
      for (final packet in [SensorPacket.eddystoneAndSensor, SensorPacket.iBeaconAndSensor]) {
        final s = SimSettings(sensorPacket: packet);
        final p = buildPayload(s, SimValues.from(s));
        expect(p.adv.manufacturerData.containsKey(teltonikaCompanyId), isFalse, reason: packet.name);
        expect(p.scanResponse!.manufacturerData.containsKey(teltonikaCompanyId), isTrue);
        expect(decoded(p).beaconId, isNotNull);
        expect(p.problem, isNull);
      }
    });

    test('EYE BEACON: Eddystone-UID advertisement, name and battery in the scan response, like a BTSID1', () {
      final s = SimSettings(profile: SimProfile.eyeBeacon, namespaceHex: 'E39B606AA38255AA8E46', instanceHex: '0B154E2D0055');
      final p = buildPayload(s, SimValues.from(s));
      final d = decoded(p);
      expect(d.name, 'ID1_SIM0001');
      expect(d.beaconId!.display, contains('E39B606AA38255AA8E46'));
      expect(d.teltonika!.batteryMv, 3030);
      expect(d.teltonika!.hasSensorBits, isFalse);
      expect(p.problem, isNull);
    });

    test('iBeacon: UUID, major, minor, power; no name unless one is set', () {
      final s = SimSettings(profile: SimProfile.iBeacon, major: 7, minor: 9, measuredPower: -61);
      final p = buildPayload(s, SimValues.from(s));
      expect(p.scanResponse, isNull);
      final b = decoded(p).iBeacon!;
      expect([b.major, b.minor, b.measuredPower], [7, 9, -61]);
    });

    test('a name too long for 31 bytes is refused with the reason', () {
      final s = SimSettings(name: 'A_VERY_LONG_SIMULATED_NAME');
      expect(buildPayload(s, SimValues.from(s)).problem, contains('shorten the name'));
    });

    test('the receiver recognises the simulated devices as an EYE SENSOR and an EYE BEACON', () {
      final r = DeviceRegistry(AppSettings(null, false));
      final now = DateTime.now();
      for (final (mac, profile) in [('5A:00:00:00:00:01', SimProfile.eyeSensor), ('5A:00:00:00:00:02', SimProfile.eyeBeacon)]) {
        final s = SimSettings(profile: profile);
        final p = buildPayload(s, SimValues.from(s));
        r.ingest(ScanEvent(deviceId: mac, time: now, rssi: -60, data: p.adv));
        if (p.scanResponse != null) r.ingest(ScanEvent(deviceId: mac, time: now, rssi: -60, data: p.scanResponse!));
      }
      expect(r.device('5A:00:00:00:00:01')!.model, DeviceModel.eyeSensor);
      expect(r.device('5A:00:00:00:00:02')!.model, DeviceModel.eyeBeacon);
      r.dispose();
    });
  });

  group('values', () {
    test('with Auto off a value is exactly what was set', () {
      final s = SimSettings(autoTemperature: false, autoHumidity: false, autoBattery: false, autoMovement: false,
          autoAngles: false, autoMagnet: false, temperatureC: -5.5, humidity: 80, moving: true, movementCount: 12);
      final v = SimValues.from(s);
      for (var i = 0; i < 50; i++) {
        v.step(s, Random(i));
      }
      expect([v.temperatureC, v.humidity, v.batteryMv, v.moving, v.movementCount], [-5.5, 80, 3030, true, 12]);
    });

    test('Auto values wander like a real sensor and stay within what the fields allow', () {
      final s = SimSettings();
      final v = SimValues.from(s);
      final rng = Random(42);
      final temps = <double>{};
      var starts = 0;
      var wasMoving = v.moving;
      for (var i = 0; i < 20000; i++) {
        v.step(s, rng);
        temps.add(v.temperatureC);
        if (v.moving && !wasMoving) starts++;
        wasMoving = v.moving;
        expect(v.temperatureC, inInclusiveRange(-40, 125));
        expect(v.humidity, inInclusiveRange(0, 100));
        expect(v.pitch, inInclusiveRange(-90, 90));
        expect(v.roll, inInclusiveRange(-180, 180));
        expect(v.batteryMv, greaterThanOrEqualTo(2000));
      }
      expect(temps.length, greaterThan(20), reason: 'the temperature moves');
      expect((v.temperatureC - s.temperatureC).abs(), lessThan(3), reason: 'and stays near the set value');
      expect(v.movementCount, starts & 0x7FFF, reason: 'each start of movement is one movement event');
    });

    test('"Count updates" makes the movement count a packet counter', () {
      final s = SimSettings(countPackets: true);
      final v = SimValues.from(s);
      for (var i = 1; i <= 5; i++) {
        v.step(s, Random(i));
        expect(v.movementCount, i);
      }
    });

    test('settings survive a round trip; damaged settings fall back to defaults', () {
      final s = SimSettings(profile: SimProfile.eyeBeacon, name: 'ID1_X', intervalMs: 5000, txPower: SimTxPower.high);
      final back = SimSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>);
      expect(back.toJson(), s.toJson());
      final damaged = SimSettings.fromJson({'profile': 'toaster', 'intervalMs': 'fast'});
      expect(damaged.profile, SimProfile.eyeSensor);
      expect(damaged.intervalMs, 2000);
    });
  });

  group('service', () {
    testWidgets('Android: starts with the interval, power and name, updates the data in place, stops', (tester) async {
      final radio = FakeAdvertiser();
      final sim = SimulatorService(advertiser: radio, random: Random(1));
      await sim.update((s) => s
        ..intervalMs = 1000
        ..txPower = SimTxPower.high
        ..name = 'MP1_TEST01');
      await sim.start();
      expect(sim.state, SimState.transmitting);
      expect(radio.started.single['interval'], 1000);
      expect(radio.started.single['power'], 1);
      expect(radio.started.single['name'], 'MP1_TEST01');
      expect(sim.nameOnAir, 'MP1_TEST01');

      await tester.pump(const Duration(milliseconds: 3100));
      expect(radio.calls.where((c) => c == 'update'), hasLength(3), reason: 'values change with every advertisement');
      expect(sim.changes, 3);

      await sim.update((s) => s.temperatureC = 30); // a value: updated in place
      expect(radio.calls.where((c) => c == 'start'), hasLength(1));
      await sim.update((s) => s.intervalMs = 5000); // the interval: started again
      expect(radio.calls.where((c) => c == 'start'), hasLength(2));
      expect(radio.started.last['interval'], 5000);

      expect(sim.changes, 0, reason: 'a restart counts afresh');
      await tester.pump(const Duration(milliseconds: 5100));
      expect(sim.changes, 1);

      await sim.stop();
      expect(radio.calls.last, 'stop');
      expect(sim.state, SimState.stopped);
      await tester.pump(const Duration(seconds: 20));
      expect(sim.changes, 1, reason: 'nothing changes once stopped');
      sim.dispose();
    });

    testWidgets('Windows: a short burst every interval, alternating advertisement and scan response', (tester) async {
      final radio = FakeAdvertiser(caps: const TxCapabilities(supported: true, txPower: true));
      final sim = SimulatorService(advertiser: radio, random: Random(1));
      await sim.update((s) => s
        ..profile = SimProfile.eyeBeacon
        ..intervalMs = 2000
        ..changeEverySec = -1);
      await sim.start();
      expect(sim.bursts, 1);
      await tester.pump(sim.burstLength);
      expect(radio.calls, ['start', 'stop'], reason: 'silent between bursts');
      await tester.pump(const Duration(milliseconds: 2000) - sim.burstLength);
      await tester.pump(const Duration(milliseconds: 10));
      expect(sim.bursts, 2);
      final first = radio.started[0]['adv']! as AdvertisementData;
      final second = radio.started[1]['adv']! as AdvertisementData;
      expect(first.serviceData16.containsKey(eddystoneServiceUuid), isTrue);
      expect(second.manufacturerData.containsKey(teltonikaCompanyId), isTrue, reason: 'the scan response in its own burst');
      expect(radio.started.every((m) => m['name'] == null), isTrue, reason: 'Windows sends no name');
      await sim.stop();
      sim.dispose();
    });

    testWidgets('it says why it cannot transmit', (tester) async {
      final radio = FakeAdvertiser(caps: const TxCapabilities.unsupported("This phone's Bluetooth cannot advertise"));
      final sim = SimulatorService(advertiser: radio);
      await sim.start();
      expect(sim.state, SimState.failed);
      expect(sim.error, "This phone's Bluetooth cannot advertise");

      radio
        ..caps = const TxCapabilities(supported: true, exactInterval: true, permitted: false)
        ..permissionGranted = false;
      await sim.start();
      expect(radio.calls, contains('permissions'));
      expect(sim.error, contains('permission'));

      radio.caps = const TxCapabilities(supported: true, exactInterval: true, name: true);
      await sim.update((s) => s.name = 'A_VERY_LONG_SIMULATED_NAME');
      await sim.start();
      expect(sim.error, contains('shorten the name'));
      expect(radio.calls.where((c) => c == 'start'), isEmpty);
      sim.dispose();
    });
  });

  testWidgets('Simulator page: start, see it on air, stop', (tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final radio = FakeAdvertiser();
    final settings = AppSettings(null, false);
    final c = AppController(
      settings: settings,
      registry: DeviceRegistry(settings),
      liveScanner: null,
      demoScanner: FakeScanner(),
      simulator: SimulatorService(advertiser: radio, random: Random(3)),
    );
    await tester.pumpWidget(EyeApp(controller: c));
    await tester.pump();
    await tester.tap(find.text('Simulator').first);
    await tester.pumpAndSettle();
    expect(find.text('Stopped'), findsOneWidget);
    expect(find.text('MP1_SIM001'), findsWidgets, reason: 'the name field and the decoded packet');

    await tester.tap(find.text('Start transmitting'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Transmitting'), findsOneWidget);
    expect(radio.started, hasLength(1));
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('/ 31 bytes'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Stopped'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
