import 'dart:convert';
import 'dart:io';

import 'package:bluepulse/app/controller.dart';
import 'package:bluepulse/app/settings.dart';
import 'package:bluepulse/core/registry.dart';
import 'package:bluepulse/core/rx_log.dart';
import 'package:bluepulse/core/session_store.dart';
import 'package:bluepulse/main.dart';
import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

RxEntry entry(String hex, {DateTime? at, int rssi = -60}) => RxEntry(
      time: at ?? DateTime.now(),
      rssi: rssi,
      scanResponse: false,
      data: AdvertisementData.parse(parseHex(hex)),
      raw: null,
      gapMs: null,
    );

/// A controller whose scanner counts as live, recording into [dir].
AppController liveController(Directory dir, {FakeScanner? scanner}) {
  final settings = AppSettings(null, false);
  return AppController(
    settings: settings,
    registry: DeviceRegistry(settings),
    liveScanner: null,
    demoScanner: scanner ?? FakeScanner(demo: false),
    sessions: SessionStore(dir),
  );
}

/// Waits for real file work to finish (up to 2 s).
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

/// Lets real file work run between frames: each await on a file needs real time, then a frame.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bluepulse_sessions_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('session files', () {
    test('a session is one CSV of every packet, with a summary the list reads', () async {
      final store = SessionStore(tmp);
      final started = DateTime(2026, 11, 10, 14, 30, 5);
      final w = await store.start(platform: 'windows', version: '1.0.1', at: started);
      expect(p.basename(w.csv.path), 'BluePulse_session_20261110-143005.csv');
      w.write(entry(beaconRsp), mac: 'AA:00:00:00:00:01', name: 'ID1_ABCDEFG', tag: 'Cold room 2');
      w.write(entry(beaconRsp), mac: 'AA:00:00:00:00:01', name: 'ID1_ABCDEFG', tag: 'Cold room 2');
      w.write(entry(sensorRsp), mac: 'AA:00:00:00:00:02');
      expect(w.packets, 3);
      expect(w.devices, 2);
      await w.stop(at: started.add(const Duration(minutes: 12)));

      final lines = w.csv.readAsLinesSync();
      expect(lines.first, RxCsv.header);
      expect(lines, hasLength(4));
      expect(lines[1], contains('Cold room 2'));
      expect(lines[1], contains(',2990,'), reason: 'battery decoded into its column');

      final list = await store.list();
      expect(list, hasLength(1));
      final s = list.single;
      expect(s.started, started);
      expect(s.duration, const Duration(minutes: 12));
      expect(s.packets, 3);
      expect(s.devices, 2);
      expect(s.bytes, w.csv.lengthSync());
      expect(s.version, '1.0.1');
      expect(s.ended, isNotNull);
    });

    test('rows reach the disk once a second, before the session stops', () async {
      final store = SessionStore(tmp);
      final w = await store.start(platform: 'android', version: '1.0.1');
      w.write(entry(beaconRsp), mac: 'AA:00:00:00:00:01');
      expect(w.csv.readAsLinesSync(), hasLength(1), reason: 'only the header so far');
      w.flush();
      expect(w.csv.readAsLinesSync(), hasLength(2));
      expect(w.info.bytes, w.csv.lengthSync());
      await w.stop();
    });

    test('a session the app never closed lists as interrupted, with its figures so far', () async {
      final csv = File(p.join(tmp.path, 'BluePulse_session_20261110-090000.csv'))
        ..writeAsStringSync('${RxCsv.header}\nrow\n');
      File(p.setExtension(csv.path, '.json')).writeAsStringSync(jsonEncode({
        'started': DateTime(2026, 11, 10, 9).toUtc().toIso8601String(),
        'updated': DateTime(2026, 11, 10, 9, 45).toUtc().toIso8601String(),
        'ended': null,
        'packets': 4200,
        'devices': 17,
      }));
      final s = (await SessionStore(tmp).list()).single;
      expect(s.ended, isNull);
      expect(s.duration, const Duration(minutes: 45));
      expect(s.packets, 4200);
    });

    test('a CSV without its summary is still listed, by the time in its name', () async {
      File(p.join(tmp.path, 'BluePulse_session_20261109-161502.csv')).writeAsStringSync(RxCsv.header);
      File(p.join(tmp.path, 'notes.csv')).writeAsStringSync('not a session');
      final s = (await SessionStore(tmp).list()).single;
      expect(s.started, DateTime(2026, 11, 9, 16, 15, 2));
      expect(s.packets, isNull);
    });

    test('two sessions in the same second get their own files; the list is newest first', () async {
      final store = SessionStore(tmp);
      final at = DateTime(2026, 11, 10, 10);
      final a = await store.start(platform: 'windows', version: '1.0.1', at: at);
      final b = await store.start(platform: 'windows', version: '1.0.1', at: at);
      expect(a.csv.path, isNot(b.csv.path));
      expect(p.basename(b.csv.path), 'BluePulse_session_20261110-100000-2.csv');
      await a.stop();
      await b.stop();
      final c = await store.start(platform: 'windows', version: '1.0.1', at: at.add(const Duration(hours: 1)));
      await c.stop();
      expect((await store.list()).first.csv.path, c.csv.path);
    });

    test('delete removes the CSV and its summary', () async {
      final store = SessionStore(tmp);
      final w = await store.start(platform: 'windows', version: '1.0.1');
      final s = await w.stop();
      await store.delete(s);
      expect(tmp.listSync(), isEmpty);
    });
  });

  group('recording', () {
    test('every packet from a tracked device goes into the session, in focus or not', () async {
      final settings = AppSettings(null, false);
      final r = DeviceRegistry(settings);
      final w = await SessionStore(tmp).start(platform: 'windows', version: '1.0.1');
      r.session = w;
      final now = DateTime.now();
      r.ingest(event('AA:00:00:00:00:01', beaconAdv, at: now));
      r.ingest(event('AA:00:00:00:00:02', sensorRsp, at: now));
      r.book.setFocus(['AA:00:00:00:00:01']);
      // Out of focus and updated a moment ago: counted, not applied — but still recorded.
      for (var i = 1; i <= 5; i++) {
        r.ingest(event('AA:00:00:00:00:02', sensorRsp, at: now.add(Duration(milliseconds: 200 * i))));
      }
      r.ingest(event('11:22:33:44:55:66', phoneAdv, at: now)); // not tracked, not recorded
      expect(w.packets, 7);
      expect(w.devices, 2);
      r.session = null;
      await w.stop();
      r.dispose();
    });

    test('a live scan records from Start to Stop; an empty one is not kept', () async {
      final c = liveController(tmp);
      await c.startScan();
      expect(c.recording, isNotNull);
      final revision = c.sessionsRevision;
      c.registry.ingest(event('AA:00:00:00:00:01', beaconRsp));
      await c.stopScan();
      expect(c.recording, isNull);
      expect(c.sessionsRevision, greaterThan(revision));
      final kept = await c.sessions!.list();
      expect(kept, hasLength(1));
      expect(kept.single.packets, 1);
      expect(kept.single.ended, isNotNull);

      await c.startScan();
      await c.stopScan();
      expect(await c.sessions!.list(), hasLength(1), reason: 'a scan that heard nothing leaves no file');
      c.dispose();
    });

    test('nothing is recorded from demo data, or with recording switched off', () async {
      final demo = liveController(tmp, scanner: FakeScanner(demo: true));
      await demo.startScan();
      expect(demo.recording, isNull);
      await demo.stopScan();
      demo.dispose();

      final off = liveController(tmp)..settings.update((s) => s.recordSessions = false);
      await off.startScan();
      expect(off.recording, isNull);
      off.settings.update((s) => s.recordSessions = true);
      await until(() => off.recording != null); // switching it on mid-scan starts a session
      off.settings.update((s) => s.recordSessions = false);
      expect(off.recording, isNull);
      await off.stopScan();
      off.dispose();
    });

    test('the session ends when the radio stops on its own', () async {
      final scanner = FakeScanner(demo: false);
      final c = liveController(tmp, scanner: scanner);
      await c.startScan();
      c.registry.ingest(event('AA:00:00:00:00:01', beaconRsp));
      final revision = c.sessionsRevision;
      await scanner.stop(); // Bluetooth turned off
      expect(c.recording, isNull);
      await until(() => c.sessionsRevision > revision);
      expect((await c.sessions!.list()).single.ended, isNotNull);
      c.dispose();
    });
  });

  testWidgets('Sessions page lists the sessions on disk and deletes one after asking', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = liveController(tmp);
    await tester.runAsync(() async {
      final store = c.sessions!;
      for (final h in [9, 11]) {
        final w = await store.start(platform: 'windows', version: '1.0.1', at: DateTime(2026, 11, 10, h));
        w.write(entry(beaconRsp), mac: 'AA:00:00:00:00:01');
        await w.stop(at: DateTime(2026, 11, 10, h, 30));
      }
    });
    await tester.pumpWidget(EyeApp(controller: c));
    await tester.pump();
    await tester.tap(find.text('Sessions').first);
    await settle(tester);

    expect(find.text('10-11-2026 11:00:00'), findsOneWidget);
    expect(find.text('10-11-2026 09:00:00'), findsOneWidget);
    expect(find.text('30 min'), findsNWidgets(2));
    expect(find.text('Saved'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);
    expect(find.text('10-11-2026 11:00:00'), findsNothing, reason: 'newest first, so the first Delete was 11:00');
    expect(find.text('10-11-2026 09:00:00'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('on a phone a session row opens its actions', (tester) async {
    tester.view.physicalSize = const Size(400, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = liveController(tmp);
    await tester.runAsync(() async {
      final w = await c.sessions!.start(platform: 'android', version: '1.0.1', at: DateTime(2026, 11, 10, 9));
      w.write(entry(beaconRsp), mac: 'AA:00:00:00:00:01');
      await w.stop(at: DateTime(2026, 11, 10, 9, 30));
    });
    await tester.pumpWidget(EyeApp(controller: c));
    await tester.pump();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sessions').last);
    await tester.pumpAndSettle(); // the drawer closes
    await settle(tester);
    expect(find.byTooltip('Delete'), findsNothing, reason: 'no button column at phone width');
    await tester.tap(find.text('30 min'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(find.textContaining('1 packets'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
