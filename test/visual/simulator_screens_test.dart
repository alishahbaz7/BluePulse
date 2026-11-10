// Renders the Simulator page to PNG files for a visual check: wide while transmitting, light, and phone
// width. Skipped unless EYE_SHOTS names an output folder:
//
//   $env:EYE_SHOTS = "C:\temp\shots"; flutter test test/visual
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:bluepulse/app/controller.dart';
import 'package:bluepulse/app/settings.dart';
import 'package:bluepulse/core/registry.dart';
import 'package:bluepulse/main.dart';
import 'package:bluepulse/simulator/sim_model.dart';
import 'package:bluepulse/simulator/sim_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers.dart';
import '../simulator_test.dart' show FakeAdvertiser;
import 'update_screens_test.dart' show loadFont;

final out = Platform.environment['EYE_SHOTS'];

void main() {
  setUpAll(() async {
    if (out == null) return;
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'C:\Users\GT2575\develop\flutter';
    await loadFont('Roboto', [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\seguisb.ttf', r'C:\Windows\Fonts\segoeuib.ttf']);
    await loadFont('MaterialIcons', [
      p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts', 'materialicons-regular.otf'),
    ]);
    await loadFont('Consolas', [r'C:\Windows\Fonts\consola.ttf']);
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

  for (final (label, size, theme, profile, transmit) in [
    ('simulator-wide-dark', const Size(1440, 1300), ThemeChoice.dark, SimProfile.eyeSensor, true),
    ('simulator-beacon-light', const Size(1440, 1100), ThemeChoice.light, SimProfile.eyeBeacon, false),
    ('simulator-phone-dark', const Size(400, 1500), ThemeChoice.dark, SimProfile.eyeSensor, false),
  ]) {
    testWidgets(label, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = AppSettings(null, false)..update((s) => s.themeChoice = theme);
      final sim = SimulatorService(advertiser: FakeAdvertiser(), random: Random(7));
      final c = AppController(
        settings: settings,
        registry: DeviceRegistry(settings),
        liveScanner: null,
        demoScanner: FakeScanner(),
        simulator: sim,
      );
      await sim.update((s) => s
        ..profile = profile
        ..name = profile.defaultName
        ..countPackets = true);
      await tester.pumpWidget(EyeApp(controller: c));
      await tester.pump();
      if (size.width < 600) {
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Simulator').last);
      } else {
        await tester.tap(find.text('Simulator').first);
      }
      await tester.pumpAndSettle();
      if (transmit) {
        await tester.tap(find.text('Start transmitting'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 9));
      }
      await shot(tester, label);
      await sim.stop();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }, skip: out == null);
  }
}
