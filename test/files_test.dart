import 'dart:io';

import 'package:bluepulse/app/controller.dart';
import 'package:bluepulse/app/paths.dart';
import 'package:bluepulse/app/settings.dart';
import 'package:bluepulse/core/error_log.dart';
import 'package:bluepulse/core/registry.dart';
import 'package:bluepulse/core/session_store.dart';
import 'package:bluepulse/core/sensor_log.dart';
import 'package:bluepulse/main.dart';
import 'package:bluepulse/ui/nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

/// The one BluePulse folder (Settings → Files): where everything goes, moving it, and the error log.
void main() {
  late Directory root;
  late Directory home;
  setUp(() {
    root = Directory.systemTemp.createTempSync('bluepulse_files_');
    home = Directory(p.join(root.path, 'BluePulse'))..createSync();
    resetAppHome(to: home);
  });
  tearDown(() async {
    await errorLog.close();
    resetAppHome();
    root.deleteSync(recursive: true);
  });

  AppController controller({AppSettings? settings}) {
    final s = settings ?? AppSettings(null, false);
    return AppController(
      settings: s,
      registry: DeviceRegistry(s),
      liveScanner: null,
      demoScanner: FakeScanner(),
      sessions: SessionStore(Directory(p.join(home.path, 'sessions'))..createSync()),
    );
  }

  void saved(String relative, String text) => File(p.join(home.path, relative))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  test('a folder name the person picks gets its own BluePulse folder inside, unless it is one', () {
    expect(bluePulseFolderIn(p.join('D:', 'Data')), p.join('D:', 'Data', 'BluePulse'));
    expect(bluePulseFolderIn(p.join('D:', 'BluePulse')), p.join('D:', 'BluePulse'));
    expect(folderLabel('/storage/emulated/0/Documents/BluePulse'), 'Internal storage › Documents › BluePulse');
  });

  test('changing the folder takes the saved files along, and everything carries on there', () async {
    await errorLog.open(home, header: 'BluePulse test');
    saved('sessions/BluePulse_session_20261111-100000.csv', 'session');
    saved('logs/BluePulse_log_2-devices_20261111-100000.csv', 'log');
    final settings = AppSettings(null, false);
    final c = controller(settings: settings);
    final to = Directory(p.join(root.path, 'Elsewhere', 'BluePulse'));

    final r = await c.changeFilesFolder(to, moveFiles: true);
    expect(r.moved, 3, reason: 'the session, the log and the error log');
    expect(r.stayed, 0);
    expect(File(p.join(to.path, 'sessions', 'BluePulse_session_20261111-100000.csv')).readAsStringSync(), 'session');
    expect(File(p.join(to.path, 'logs', 'BluePulse_log_2-devices_20261111-100000.csv')).existsSync(), isTrue);
    expect(home.existsSync(), isFalse, reason: 'the old folder held only BluePulse files, so it went');
    expect(appHomeNow!.path, to.path);
    expect(c.sessions!.dir.path, p.join(to.path, 'sessions'), reason: 'new sessions are saved there');
    expect(settings.filesFolder, to.path, reason: 'and the next start uses it too');
    expect(errorLog.file!.path, p.join(to.path, ErrorLog.fileName));
    await errorLog.flush();
    final log = errorLog.file!.readAsStringSync();
    expect(log, contains('BluePulse test · started'), reason: 'the log moved with its history');
    expect(log, contains('continued here'));
    expect(log, contains('Files folder changed from ${home.path} to ${to.path} · 3 moved'));
    c.dispose();
  });

  test('without moving, the files stay where they are and new ones go to the new folder', () async {
    saved('sessions/old.csv', 'old');
    final c = controller();
    final to = Directory(p.join(root.path, 'New'));
    await c.changeFilesFolder(to, moveFiles: false);
    expect(File(p.join(home.path, 'sessions', 'old.csv')).existsSync(), isTrue);
    expect(c.sessions!.dir.path, p.join(to.path, 'sessions'));
    c.dispose();
  });

  test('not while a log is writing, and not into the current folder itself; nothing changes then', () async {
    final c = controller();
    c.registry.sensorLog = await SensorLog.start(File(p.join(home.path, 'logs', 'running.csv')), macs: const []);
    expect(c.filesFolderBusy, 'Stop the running log first');
    await expectLater(c.changeFilesFolder(Directory(p.join(root.path, 'X')), moveFiles: true), throwsStateError);
    await c.stopSensorLog();
    expect(c.filesFolderBusy, isNull);

    await expectLater(
      c.changeFilesFolder(Directory(p.join(home.path, 'sessions', 'BluePulse')), moveFiles: true),
      throwsA(isA<FileSystemException>()),
    );
    expect(appHomeNow!.path, home.path, reason: 'unchanged');
    expect(c.sessions!.dir.path, p.join(home.path, 'sessions'));
    c.dispose();
  });

  testWidgets('Settings → Files shows the folder, and the error log in words, newest first', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = controller();
    await tester.pumpWidget(EyeApp(controller: c, initialPage: PageId.settings));
    await tester.pump();
    expect(find.text(home.path), findsOneWidget);
    expect(find.text('Default folder · sessions, logs and the error log'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Change…'), findsOneWidget);

    errorLog.warn('update', 'Update check failed', error: 'No connection to github.com');
    errorLog.info('update', 'Version 1.0.2 is available');
    await tester.pump();
    expect(find.textContaining('this run'), findsOneWidget);
    await tester.ensureVisible(find.text('View log'));
    await tester.tap(find.text('View log'));
    await tester.pumpAndSettle();
    final newest = tester.getTopLeft(find.text('Version 1.0.2 is available'));
    final older = tester.getTopLeft(find.text('Update check failed: No connection to github.com'));
    expect(newest.dy, lessThan(older.dy), reason: 'newest first');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
