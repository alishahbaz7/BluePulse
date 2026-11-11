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
import 'package:bluepulse/scanner/scanner.dart';
import 'package:bluepulse/simulator/advertiser.dart';
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

  const windows = TxCapabilities(supported: true, txPower: true, reservedBytes: 3);
  for (final (label, size, theme, profile, transmit, caps) in [
    ('simulator-wide-dark', const Size(1440, 1300), ThemeChoice.dark, SimProfile.eyeSensor, true, null),
    ('simulator-beacon-light', const Size(1440, 1100), ThemeChoice.light, SimProfile.eyeBeacon, false, null),
    ('simulator-phone-dark', const Size(400, 1500), ThemeChoice.dark, SimProfile.eyeSensor, false, null),
    ('simulator-windows-dark', const Size(1440, 1300), ThemeChoice.dark, SimProfile.eyeSensor, true, windows),
    ('simulator-windows-light', const Size(1440, 1300), ThemeChoice.light, SimProfile.eyeSensor, false, windows),
    ('simulator-windows-phone-light', const Size(400, 1700), ThemeChoice.light, SimProfile.eyeSensor, false, windows),
  ]) {
    testWidgets(label, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = AppSettings(null, false)..update((s) => s.themeChoice = theme);
      final sim = SimulatorService(advertiser: caps == null ? FakeAdvertiser() : FakeAdvertiser(caps: caps), random: Random(7));
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

  // The receiving phone: a Windows simulation (a new address every burst) next to a real EYE SENSOR.
  testWidgets('receiver-phone-dark', (tester) async {
    tester.view.physicalSize = const Size(400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings(null, false)..update((s) => s.themeChoice = ThemeChoice.dark);
    final registry = DeviceRegistry(settings);
    final c = AppController(
      settings: settings,
      registry: registry,
      liveScanner: null,
      demoScanner: FakeScanner(),
      simulator: SimulatorService(advertiser: FakeAdvertiser(), random: Random(7)),
    );
    await tester.pumpWidget(EyeApp(controller: c));
    await tester.pump();

    final sim = SimSettings(simIdHex: 'AD236581');
    final real = SimSettings(name: 'MP1_7F21AA', simTag: false, temperatureC: 24.1, humidity: 52);
    final sv = SimValues.from(sim);
    final rv = SimValues.from(real);
    final rng = Random(5);
    var t = DateTime.now().subtract(const Duration(seconds: 40));
    for (var i = 0; i < 20; i++) {
      sv.step(sim, rng);
      rv.step(real, rng);
      final mac = [for (var b = 0; b < 6; b++) rng.nextInt(256).toRadixString(16).padLeft(2, '0')].join(':').toUpperCase();
      registry.ingest(ScanEvent(
          deviceId: mac, time: t, rssi: -56 - rng.nextInt(6), data: buildPayload(sim, sv, sendsName: false, reservedBytes: 3).adv));
      registry.ingest(ScanEvent(
          deviceId: 'D4:7F:21:AA:10:02', time: t.add(const Duration(milliseconds: 700)), rssi: -71 - rng.nextInt(5),
          data: buildPayload(real, rv).adv));
      t = t.add(const Duration(seconds: 2));
    }

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devices').last);
    await tester.pumpAndSettle();
    await shot(tester, 'receiver-devices-phone-dark');
    await tester.tap(find.text('SIM-AD236581').first);
    await tester.pumpAndSettle();
    await shot(tester, 'receiver-detail-phone-dark');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }, skip: out == null);
}
