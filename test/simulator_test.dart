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
import 'package:shared_preferences/shared_preferences.dart';

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
      final sensor = SimSettings();
      final beacon = SimSettings(profile: SimProfile.eyeBeacon);
      for (final (mac, s) in [('5A:00:00:00:00:01', sensor), ('5A:00:00:00:00:02', beacon)]) {
        final p = buildPayload(s, SimValues.from(s));
        r.ingest(ScanEvent(deviceId: mac, time: now, rssi: -60, data: p.adv));
        if (p.scanResponse != null) r.ingest(ScanEvent(deviceId: mac, time: now, rssi: -60, data: p.scanResponse!));
      }
      expect(r.device('5A:00:00:00:00:01')!.model, DeviceModel.eyeSensor, reason: 'its name leaves no room for the tag');
      final b = r.device(simulatorKey(simulatorIdOf(beacon)))!;
      expect(b.model, DeviceModel.eyeBeacon, reason: 'the tag in the scan response names it');
      expect(b.name, 'ID1_SIM0001');
      expect(b.beaconId, isNotNull, reason: 'the advertisement joined it');
      expect(b.lastAddress, '5A:00:00:00:00:02');
      expect(r.device('5A:00:00:00:00:02'), isNull);
      r.dispose();
    });
  });

  group('simulator tag', () {
    List<SimSettings> everyLayout({bool simTag = true}) => [
          for (final packet in SensorPacket.values) SimSettings(sensorPacket: packet, simTag: simTag),
          for (final frame in BeaconFrame.values) SimSettings(profile: SimProfile.eyeBeacon, beaconFrame: frame, simTag: simTag),
          SimSettings(profile: SimProfile.iBeacon, simTag: simTag),
        ];
    bool hasTag(AdvertisementData? d) => d?.manufacturerData.containsKey(simulatorCompanyId) ?? false;

    test('Windows: no name, the tag wherever it fits, and no packet past 31 bytes with the Flags Windows adds', () {
      for (final s in everyLayout()) {
        final p = buildPayload(s, SimValues.from(s), sendsName: false, reservedBytes: 3);
        final what = '${s.profile.name}/${s.sensorPacket.name}/${s.beaconFrame.name}';
        expect(p.problem, isNull, reason: what);
        expect(p.advBytes + 3, lessThanOrEqualTo(31), reason: what);
        if (p.scanResponse != null) expect(p.scanResponseBytes! + 3, lessThanOrEqualTo(31), reason: what);
        expect([p.adv.name, p.scanResponse?.name], [null, null], reason: '$what: Windows sends no name');
        expect(p.simulatorId, simulatorIdOf(s), reason: what);
        expect(hasTag(p.adv) || hasTag(p.scanResponse), isTrue, reason: what);
        expect(decoded(p).simulatorId, simulatorIdOf(s), reason: what);
      }
      final sensor = SimSettings();
      expect(hasTag(buildPayload(sensor, SimValues.from(sensor), sendsName: false, reservedBytes: 3).adv), isTrue,
          reason: 'an EYE SENSOR alone carries the tag in its one packet');
      final ib = SimSettings(profile: SimProfile.iBeacon);
      final p = buildPayload(ib, SimValues.from(ib), sendsName: false, reservedBytes: 3);
      expect(hasTag(p.adv), isFalse, reason: 'an iBeacon frame has no room');
      expect(p.scanResponse!.manufacturerData.keys, [simulatorCompanyId], reason: 'so the tag has a burst of its own');
    });

    test('tag off: exactly what a real device sends', () {
      for (final s in everyLayout(simTag: false)) {
        for (final sendsName in [true, false]) {
          final p = buildPayload(s, SimValues.from(s), sendsName: sendsName, reservedBytes: sendsName ? 0 : 3);
          expect([hasTag(p.adv), hasTag(p.scanResponse), p.simulatorId], [false, false, null]);
        }
      }
      final ib = SimSettings(profile: SimProfile.iBeacon, simTag: false);
      expect(buildPayload(ib, SimValues.from(ib), sendsName: false).scanResponse, isNull);
    });

    test('Android: the tag never pushes the name out; it goes where there is room', () {
      final sensor = SimSettings();
      final p = buildPayload(sensor, SimValues.from(sensor));
      expect([p.adv.name, hasTag(p.adv), p.problem], ['MP1_SIM001', false, null]);
      final shortName = SimSettings(name: 'S1');
      expect(hasTag(buildPayload(shortName, SimValues.from(shortName)).adv), isTrue);
      final beacon = SimSettings(profile: SimProfile.eyeBeacon);
      final b = buildPayload(beacon, SimValues.from(beacon));
      expect([b.scanResponse!.name, hasTag(b.scanResponse)], ['ID1_SIM0001', true]);
      expect(b.scanResponseBytes, lessThanOrEqualTo(31));
    });

    test('settings saved by the version before the tag keep one simulator ID from the first start on', () async {
      final old = SimSettings().toJson()
        ..remove('simIdHex')
        ..remove('simTag');
      SharedPreferences.setMockInitialValues({'dev.simulator': jsonEncode(old)});
      final prefs = await SharedPreferences.getInstance();
      final first = SimulatorService(advertiser: FakeAdvertiser(), prefs: prefs);
      await Future<void>.delayed(Duration.zero);
      final second = SimulatorService(advertiser: FakeAdvertiser(), prefs: prefs);
      expect(second.settings.simIdHex, first.settings.simIdHex, reason: 'the next start lists the same SIM device');
      expect(second.settings.simTag, isTrue);
      first.dispose();
      second.dispose();
    });

    test('a simulated beacon gets its ID from its beacon ID; a sensor alone keeps the one made for this install', () {
      final sensor = SimSettings();
      expect(simulatorIdOf(sensor), int.parse(sensor.simIdHex, radix: 16));
      final again = SimSettings.fromJson(jsonDecode(jsonEncode(sensor.toJson())) as Map<String, Object?>);
      expect(simulatorIdOf(again), simulatorIdOf(sensor), reason: 'kept between runs');
      expect(SimSettings().simIdHex, isNot(sensor.simIdHex), reason: 'each install its own');
      for (final s in everyLayout().where((s) => simBeaconId(s) != null)) {
        final p = buildPayload(s, SimValues.from(s));
        expect(simulatorIdOf(s), simulatorIdForBeacon(decoded(p).beaconId!), reason: 'what a receiver works out');
      }
    });
  });

  group('receiving a simulator whose address keeps changing', () {
    late DeviceRegistry r;
    late DateTime t;
    var n = 0;
    setUp(() {
      r = DeviceRegistry(AppSettings(null, false)..showAllBeacons = true); // the iBeacon one is an "Other beacon"
      t = DateTime(2026, 11, 10, 15);
    });
    tearDown(() => r.dispose());

    String newMac() {
      n++;
      return 'C0:FF:EE:00:${(n ~/ 256).toRadixString(16).padLeft(2, '0')}:${(n % 256).toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();
    }

    void hear(AdvertisementData d) {
      t = t.add(const Duration(seconds: 2));
      r.ingest(ScanEvent(deviceId: newMac(), time: t, rssi: -55, data: d));
    }

    test('Windows EYE SENSOR: a new address every burst, still one device', () {
      final s = SimSettings();
      final p = buildPayload(s, SimValues.from(s), sendsName: false, reservedBytes: 3);
      for (var i = 0; i < 10; i++) {
        hear(p.adv);
      }
      expect(r.devices, hasLength(1));
      final d = r.devices.single;
      expect(d.mac, simulatorKey(simulatorIdOf(s)));
      expect(d.isSimulated, isTrue);
      expect(d.model, DeviceModel.eyeSensor);
      expect(d.readings, 10);
      expect(d.lastAddress, startsWith('C0:FF:EE'));
      expect(d.searchText, contains('sim-'), reason: 'the Devices search finds it by SIM');
    });

    test('Windows EYE BEACON: the beacon frames, sent without the tag, join it, even ones heard before the first tag', () {
      final s = SimSettings(profile: SimProfile.eyeBeacon);
      final p = buildPayload(s, SimValues.from(s), sendsName: false, reservedBytes: 3);
      for (var i = 0; i < 4; i++) {
        hear(p.adv); // Eddystone, untagged; the first arrives before anything tagged
        hear(p.scanResponse!); // battery and the tag
      }
      expect(r.devices, hasLength(1));
      final d = r.devices.single;
      expect(d.mac, simulatorKey(simulatorIdOf(s)));
      expect(d.model, DeviceModel.eyeBeacon);
      expect(d.beaconId, simBeaconId(s));
      expect(d.readings, 7, reason: 'every burst but the first, which came in under its own address and was folded in');
    });

    test('Windows iBeacon: frames and tag bursts are one device', () {
      final s = SimSettings(profile: SimProfile.iBeacon);
      final p = buildPayload(s, SimValues.from(s), sendsName: false, reservedBytes: 3);
      for (var i = 0; i < 3; i++) {
        hear(p.scanResponse!);
        hear(p.adv);
      }
      expect(r.devices, hasLength(1));
      expect(r.devices.single.beaconId, simBeaconId(s));
    });

    test('real beacons nearby are not taken in', () {
      final s = SimSettings(profile: SimProfile.eyeBeacon);
      final p = buildPayload(s, SimValues.from(s), sendsName: false, reservedBytes: 3);
      hear(p.scanResponse!);
      final real = SimSettings(profile: SimProfile.eyeBeacon, simTag: false); // another instance ID
      final rp = buildPayload(real, SimValues.from(real));
      r.ingest(ScanEvent(deviceId: 'AA:BB:CC:00:00:01', time: t, rssi: -70, data: rp.adv));
      r.ingest(ScanEvent(deviceId: 'AA:BB:CC:00:00:01', time: t, rssi: -70, data: rp.scanResponse!));
      expect(r.devices.map((d) => d.mac), unorderedEquals([simulatorKey(simulatorIdOf(s)), 'AA:BB:CC:00:00:01']));
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
      expect(second.manufacturerData.containsKey(simulatorCompanyId), isTrue, reason: 'with the simulator tag');
      expect([first.name, second.name], [null, null], reason: 'and no name in the packets either');
      await sim.stop();
      sim.dispose();
    });

    testWidgets('Android: a restart replaces the transmission without stopping it, so the phone does not get its '
        'own name back and lose it again in between', (tester) async {
      final radio = FakeAdvertiser();
      final sim = SimulatorService(advertiser: radio, random: Random(1));
      await sim.start();
      await sim.update((s) => s.intervalMs = 5000);
      await sim.update((s) => s.simTag = false);
      expect(radio.calls, ['start', 'start', 'start']);
      await sim.stop();
      expect(radio.calls.last, 'stop');
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

  testWidgets('Simulator page on Windows: the receiver finds it by its simulator ID; the name is explained', (tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings(null, false);
    final sim = SimulatorService(
      advertiser: FakeAdvertiser(caps: const TxCapabilities(supported: true, txPower: true, reservedBytes: 3)),
      random: Random(3),
    );
    final c = AppController(
      settings: settings,
      registry: DeviceRegistry(settings),
      liveScanner: null,
      demoScanner: FakeScanner(),
      simulator: sim,
    );
    await tester.pumpWidget(EyeApp(controller: c));
    await tester.pump();
    await tester.tap(find.text('Simulator').first);
    await tester.pumpAndSettle();
    final key = simulatorKey(simulatorIdOf(sim.settings));
    expect(find.text(key), findsWidgets, reason: 'the Receiver tile and the decoded packet');
    expect(find.textContaining('each from a new random address'), findsOneWidget);
    expect(find.text('MP1_SIM001'), findsOneWidget, reason: 'in the greyed name field only, not on air');

    await tester.tap(find.byType(Switch).first); // the BluePulse tag, off
    await tester.pumpAndSettle();
    expect(sim.settings.simTag, isFalse);
    expect(find.text(key), findsNothing);
    expect(find.textContaining('turn the BluePulse tag on'), findsOneWidget, reason: 'nothing identifies it now');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
