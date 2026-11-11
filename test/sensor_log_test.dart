import 'dart:io';

import 'package:bluepulse/app/settings.dart';
import 'package:bluepulse/core/registry.dart';
import 'package:bluepulse/core/sensor_log.dart';
import 'package:bluepulse/scanner/scanner.dart';
import 'package:bluepulse/simulator/sim_model.dart';
import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late DeviceRegistry r;
  final t0 = DateTime(2026, 11, 11, 10, 40);
  setUp(() {
    dir = Directory.systemTemp.createTempSync('bluepulse_log_');
    r = DeviceRegistry(AppSettings(null, false));
  });
  tearDown(() {
    r.dispose();
    dir.deleteSync(recursive: true);
  });

  void hear(String mac, SimSettings s, DateTime at, {int rssi = -60}) {
    final p = buildPayload(s, SimValues.from(s));
    r.ingest(ScanEvent(deviceId: mac, time: at, rssi: rssi, data: p.adv));
    if (p.scanResponse != null) r.ingest(ScanEvent(deviceId: mac, time: at, rssi: rssi, data: p.scanResponse!));
  }

  test('a row for every packet from the logged devices, in the order they arrive, nothing from the others', () async {
    final a = SimSettings(name: 'MP1_A', simTag: false, temperatureC: 22.5, humidity: 45, movementCount: 7);
    final b = SimSettings(name: 'MP1_B', simTag: false, temperatureC: 19.25, humidity: 60, batteryMv: 2900);
    final other = SimSettings(name: 'MP1_C', simTag: false);
    final log = r.sensorLog = await SensorLog.start(File('${dir.path}/log.csv'), macs: ['AA:00:00:00:00:0A', 'AA:00:00:00:00:0B']);

    hear('AA:00:00:00:00:0A', a, t0, rssi: -51);
    hear('AA:00:00:00:00:0C', other, t0.add(const Duration(milliseconds: 300)));
    hear('AA:00:00:00:00:0B', b, t0.add(const Duration(seconds: 1)), rssi: -72);
    hear('AA:00:00:00:00:0A', a, t0.add(const Duration(milliseconds: 2200)), rssi: -52);
    expect(log.rows, 3);
    final lines = (await log.stop()).single.readAsStringSync().trim().split(RegExp(r'\r?\n'));

    final header = lines.first.split(',');
    expect(header.take(5), ['time_local', 'time_utc', 'mac', 'gap_ms', 'name'], reason: 'when, who, how long since its last');
    expect(header.last, 'raw_hex');
    expect(lines, hasLength(4));
    Map<String, String> row(int i) => Map.fromIterables(header, lines[i].split(','));

    expect(row(1)['mac'], 'AA:00:00:00:00:0A');
    expect(row(1)['name'], 'MP1_A');
    expect(row(1)['gap_ms'], '', reason: "the device's first packet");
    expect([row(1)['temperature_c'], row(1)['humidity_pct'], row(1)['movement_count'], row(1)['rssi_dbm']], ['22.50', '45', '7', '-51']);
    expect(row(1)['time_local'], '2026-11-11 10:40:00.000');
    expect(row(2)['mac'], 'AA:00:00:00:00:0B', reason: 'MP1_C is not logged');
    expect([row(2)['temperature_c'], row(2)['battery_mv']], ['19.25', '2900']);
    expect(row(3)['mac'], 'AA:00:00:00:00:0A');
    expect(row(3)['gap_ms'], '2200', reason: 'interval since the same device\'s previous packet');
    expect(row(3)['raw_hex'], toHex(buildPayload(a, SimValues.from(a)).adv.toBytes()));
  });

  test('a beacon frame carries its ID; a name with a comma stays one column', () async {
    final beacon = SimSettings(profile: SimProfile.eyeBeacon, name: 'ID1, lobby', simTag: false);
    final log = r.sensorLog = await SensorLog.start(File('${dir.path}/log.csv'), macs: ['BB:00:00:00:00:01']);
    hear('BB:00:00:00:00:01', beacon, t0);
    final lines = (await log.stop()).single.readAsStringSync().trim().split(RegExp(r'\r?\n'));
    expect(lines.length, 3, reason: 'the advertisement and the scan response');
    expect(lines.any((l) => l.contains('Eddystone ')), isTrue);
    expect(lines.any((l) => l.contains('"ID1, lobby"')), isTrue);
    expect(SensorLog.fileName(2, t0), 'BluePulse_log_2-devices_20261111-104000.csv');
  });

  test('a long run: rows reach the disk while it runs, and a full file carries on in the next part', () async {
    final a = SimSettings(name: 'MP1_A', simTag: false);
    final log = r.sensorLog = await SensorLog.start(
      File('${dir.path}/log.csv'),
      macs: ['AA:00:00:00:00:0A'],
      maxRowsPerFile: 3,
      flushEvery: const Duration(milliseconds: 20),
    );
    hear('AA:00:00:00:00:0A', a, t0);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(log.file.readAsLinesSync(), hasLength(2), reason: 'on disk before Stop: a crash loses seconds, not hours');

    for (var i = 1; i < 7; i++) {
      hear('AA:00:00:00:00:0A', a, t0.add(Duration(seconds: 2 * i)));
    }
    final files = await log.stop();
    expect(files.map((f) => f.uri.pathSegments.last), ['log.csv', 'log_part2.csv', 'log_part3.csv']);
    expect(files.map((f) => f.readAsLinesSync().length), [4, 4, 2], reason: 'each part: its header and up to 3 rows');
    expect(files.every((f) => f.readAsLinesSync().first == SensorLog.header), isTrue);
    expect(log.rows, 7);
  });
}
