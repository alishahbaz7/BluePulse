// Renders every page at a phone's size (moto g57 power: 411 × 914 dp) with a dozen EYE devices, to
// check the phone layout. Skipped unless EYE_SHOTS names an output folder:
//
//   $env:EYE_SHOTS = "C:\temp\shots"; flutter test test/visual/phone_screens_test.dart
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:bluepulse/app/controller.dart';
import 'package:bluepulse/app/settings.dart';
import 'package:bluepulse/core/registry.dart';
import 'package:bluepulse/main.dart';
import 'package:bluepulse/scanner/scanner.dart';
import 'package:bluepulse/simulator/sim_model.dart';
import 'package:bluepulse/simulator/sim_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers.dart';
import '../config_session_test.dart' show FakeSensor;
import '../simulator_test.dart' show FakeAdvertiser;
import 'update_screens_test.dart' show loadFont;

final out = Platform.environment['EYE_SHOTS'];

const phone = Size(411, 914);

/// A dozen devices like an office full of them: EYE SENSORs and EYE BEACONs, one simulated.
void fill(DeviceRegistry r) {
  final rng = Random(11);
  final start = DateTime.now().subtract(const Duration(minutes: 4));
  final sensors = [
    for (var i = 0; i < 7; i++)
      (
        'D4:7F:21:AA:10:${(i + 2).toRadixString(16).padLeft(2, '0').toUpperCase()}',
        SimSettings(
          name: 'MP1_7F21${(0xA0 + i).toRadixString(16).toUpperCase()}',
          simTag: false,
          temperatureC: 21 + i * 0.7,
          humidity: 40 + i * 3,
          batteryMv: i == 3 ? 2580 : 3010 - i * 20,
        ),
      ),
  ];
  final beacons = [
    for (var i = 0; i < 4; i++)
      (
        'E8:31:CD:5B:22:${(i + 10).toRadixString(16).padLeft(2, '0').toUpperCase()}',
        SimSettings(profile: SimProfile.eyeBeacon, name: 'ID1_C5B22${i + 1}', simTag: false, batteryMv: 2990 - i * 30),
      ),
  ];
  final sim = SimSettings(simIdHex: '647CA989');
  final values = {for (final (mac, s) in [...sensors, ...beacons]) mac: SimValues.from(s)};
  final simValues = SimValues.from(sim);
  for (var t = 0; t < 240; t += 2) {
    final at = start.add(Duration(seconds: t));
    for (final (mac, s) in [...sensors, ...beacons]) {
      if (rng.nextDouble() < 0.4) continue; // EYE devices every 5 s or so, some missed
      final v = values[mac]!..step(s, rng);
      final pay = buildPayload(s, v);
      final rssi = -55 - mac.hashCode % 30 - rng.nextInt(6);
      r.ingest(ScanEvent(deviceId: mac, time: at, rssi: rssi, data: pay.adv));
      if (pay.scanResponse != null) {
        r.ingest(ScanEvent(deviceId: mac, time: at.add(const Duration(milliseconds: 8)), rssi: rssi, data: pay.scanResponse!));
      }
    }
    simValues.step(sim, rng);
    final mac = [for (var b = 0; b < 6; b++) rng.nextInt(256).toRadixString(16).padLeft(2, '0')].join(':').toUpperCase();
    r.ingest(ScanEvent(
        deviceId: mac, time: at, rssi: -62 - rng.nextInt(8), data: buildPayload(sim, simValues, sendsName: false, reservedBytes: 3).adv));
  }
}

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
      File(p.join(out!, 'phone', '$name.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final (theme, size, tag) in [
    (ThemeChoice.dark, phone, ''),
    (ThemeChoice.light, phone, ''),
    (ThemeChoice.dark, const Size(914, 411), '-landscape'),
  ]) {
    testWidgets('phone pages, ${theme.name}$tag', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = AppSettings(null, false)..update((s) => s.themeChoice = theme);
      final registry = DeviceRegistry(settings);
      final c = AppController(
        settings: settings,
        registry: registry,
        liveScanner: null,
        demoScanner: FakeScanner(),
        simulator: SimulatorService(advertiser: FakeAdvertiser(), random: Random(7)),
      );
      await c.startScan();
      fill(registry);
      await tester.pumpWidget(EyeApp(controller: c));
      await tester.pump(const Duration(milliseconds: 500));

      // A scan keeps something moving, so the screen never settles: fixed steps instead.
      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
      }

      Future<void> open(String page) async {
        await tester.tap(find.byTooltip('Menu'));
        await settle();
        // Sideways, the menu scrolls: bring the item in first.
        final menu = find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)).first;
        await tester.dragUntilVisible(find.descendant(of: find.byType(Drawer), matching: find.text(page)), menu, const Offset(0, -80));
        await settle();
        await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text(page)).last);
        await settle();
      }

      final t = '${theme.name}$tag';
      await shot(tester, '01-overview-$t');
      await open('Devices');
      await shot(tester, '02-devices-$t');
      await tester.dragUntilVisible(find.text('MP1_7F21A0'), find.byType(ListView).last, const Offset(0, -150));
      await settle();
      await tester.tap(find.text('MP1_7F21A0').first);
      await settle();
      await shot(tester, '03-device-$t');
      await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -700));
      await settle();
      await shot(tester, '04-device-pings-$t');
      for (final (i, page) in ['Packets', 'Proximity', 'Simulator', 'Sessions', 'Decode', 'Settings'].indexed) {
        await open(page);
        await shot(tester, '${(i + 5).toString().padLeft(2, '0')}-${page.toLowerCase()}-$t');
      }
      // Settings is the last page opened: its end, where About is.
      await tester.drag(find.byType(ListView).last, const Offset(0, -3000));
      await settle();
      await shot(tester, '11-about-$t');
      await tester.runAsync(c.stopScan); // it closes the session file: real I/O
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }, skip: out == null);
  }

  for (final (label, size) in [('configure-phone-dark', phone), ('configure-wide-dark', const Size(1440, 1100))]) {
    testWidgets(label, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = AppSettings(null, false)..update((s) => s.themeChoice = ThemeChoice.dark);
      final registry = DeviceRegistry(settings);
      final c = AppController(
        settings: settings,
        registry: registry,
        liveScanner: null,
        demoScanner: FakeScanner(),
        gattLink: FakeSensor(),
      );
      registry.ingest(event('7C:D9:F4:15:2D:01', sensorRsp, rssi: -45));
      await tester.pumpWidget(EyeApp(controller: c));
      await tester.pump();
      if (size.width < 600) {
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Configure').last);
      } else {
        await tester.tap(find.text('Configure').first);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('SNS_TEST01').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '1'), '3'); // repeats
      await tester.enterText(find.widgetWithText(TextField, '2200'), '2100');
      await tester.pump();
      await shot(tester, label);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }, skip: out == null);
  }
}
