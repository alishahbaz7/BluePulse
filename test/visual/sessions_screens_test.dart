// Renders the Sessions page to PNG files for a visual check: one session recording, one interrupted,
// two saved; wide and phone width, dark and light. Skipped unless EYE_SHOTS names an output folder:
//
//   $env:EYE_SHOTS = "C:\temp\shots"; flutter test test/visual
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bluepulse/app/settings.dart';
import 'package:bluepulse/core/rx_log.dart';
import 'package:bluepulse/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers.dart';
import '../sessions_test.dart' show entry, liveController, settle;
import 'update_screens_test.dart' show loadFont;

final out = Platform.environment['EYE_SHOTS'];

void main() {
  late Directory tmp;
  setUpAll(() async {
    if (out == null) return;
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'C:\Users\GT2575\develop\flutter';
    await loadFont('Roboto', [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\seguisb.ttf', r'C:\Windows\Fonts\segoeuib.ttf']);
    await loadFont('MaterialIcons', [
      p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts', 'materialicons-regular.otf'),
    ]);
    await loadFont('Consolas', [r'C:\Windows\Fonts\consola.ttf']);
  });
  setUp(() => tmp = Directory.systemTemp.createTempSync('bluepulse_shots_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final image = await captureImage(find.byType(MaterialApp).evaluate().single);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(p.join(out!, '$name.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final (label, size, theme) in [
    ('sessions-wide-dark', const Size(1440, 900), ThemeChoice.dark),
    ('sessions-wide-light', const Size(1440, 900), ThemeChoice.light),
    ('sessions-phone-dark', const Size(400, 820), ThemeChoice.dark),
  ]) {
    testWidgets(label, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = liveController(tmp)..settings.update((s) => s.themeChoice = theme);
      await tester.runAsync(() async {
        final store = c.sessions!;
        final day = DateTime.now();
        for (final (h, minutes, packets) in [(9, 47, 1840), (11, 125, 9312)]) {
          final w = await store.start(platform: 'windows', version: '1.0.1', at: DateTime(day.year, day.month, day.day, h, 5));
          for (var i = 0; i < packets; i++) {
            w.write(entry(i.isEven ? beaconRsp : sensorRsp), mac: 'AA:00:00:00:00:0${i % 7}');
          }
          await w.stop(at: DateTime(day.year, day.month, day.day, h, 5).add(Duration(minutes: minutes)));
        }
        // One the app never closed.
        final csv = File(p.join(tmp.path, 'BluePulse_session_${day.year}${day.month.toString().padLeft(2, '0')}'
            '${day.day.toString().padLeft(2, '0')}-073000.csv'))
          ..writeAsStringSync('${RxCsv.header}\n${'x' * 90000}');
        File(p.setExtension(csv.path, '.json')).writeAsStringSync(jsonEncode({
          'started': DateTime(day.year, day.month, day.day, 7, 30).toUtc().toIso8601String(),
          'updated': DateTime(day.year, day.month, day.day, 8, 2).toUtc().toIso8601String(),
          'ended': null,
          'packets': 512,
          'devices': 4,
        }));
        await c.startScan();
      });
      for (var i = 0; i < 40; i++) {
        c.registry.ingest(event('AA:00:00:00:00:0${i % 3}', i.isEven ? beaconRsp : sensorRsp));
      }
      await tester.pumpWidget(EyeApp(controller: c));
      await tester.pump();
      if (size.width < 600) {
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sessions').last);
      } else {
        await tester.tap(find.text('Sessions').first);
      }
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await shot(tester, label);
      if (size.width < 600) {
        await tester.tap(find.text('47 min'));
        await tester.pumpAndSettle();
        await shot(tester, '$label-row');
      }
      await tester.runAsync(c.stopScan);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }, skip: out == null);
  }
}
