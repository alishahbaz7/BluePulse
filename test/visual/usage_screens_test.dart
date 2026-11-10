// Renders the usage screens — the first-start name dialog and Settings → Usage reporting — to PNG
// files for a visual check, with Segoe UI and the Material icons loaded. Skipped unless EYE_SHOTS
// names an output folder:
//
//   $env:EYE_SHOTS = "C:\temp\shots"; flutter test test/visual
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:bluepulse/app/settings.dart';
import 'package:bluepulse/main.dart';
import 'package:bluepulse/ui/nav.dart';
import 'package:bluepulse/usage/usage_service.dart';
import 'package:bluepulse/usage/usage_store.dart';
import 'package:bluepulse/usage/usage_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers.dart';
import '../usage/usage_service_test.dart' show FakeUsageTransport, facts;
import '../usage/usage_ui_test.dart' show feedDevices;
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

  Future<UsageService> started(WidgetTester tester, Map<String, String> stored, FakeUsageTransport t) async {
    final u = UsageService(
      store: MemoryUsageStore(stored),
      transport: t,
      endpoint: Uri.parse('https://bluepulse-usage.supabase.co/rest/v1/rpc/usage_report'),
      random: Random(5),
    );
    await tester.runAsync(() async {
      await u.start(app: 'BluePulse', appVersion: '1.0.0', build: 'release', facts: facts, listenToLifecycle: false, timers: false);
      await Future<void>.delayed(const Duration(milliseconds: 50)); // the first send finishes
    });
    return u;
  }

  testWidgets('first-start name dialog', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = testController(usage: await started(tester, {}, FakeUsageTransport()));
    await tester.pumpWidget(EyeApp(controller: c));
    await tester.pumpAndSettle();
    await shot(tester, 'usage-1-name-empty');
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Shahbaz Khan');
    await tester.pumpAndSettle();
    await shot(tester, 'usage-2-name-filled');
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await shot(tester, 'usage-7-greeting-not-scanning');
    await tester.runAsync(c.startScan);
    feedDevices(c);
    await tester.pump(const Duration(milliseconds: 300));
    await shot(tester, 'usage-8-greeting-overview');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }, skip: out == null);

  testWidgets('Settings → Usage reporting', (tester) async {
    // Tall enough for the whole Settings page, so the card is built and in the picture.
    tester.view.physicalSize = const Size(1280, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stored = {'installId': '3f9c0a1be47d4c2a9e8b5f61d0a7c3e2', 'name': 'Shahbaz Khan'};

    Future<void> settings(String name, UsageService u, {ThemeChoice theme = ThemeChoice.dark}) async {
      final c = testController(usage: u);
      c.settings.update((s) => s.themeChoice = theme);
      await tester.pumpWidget(EyeApp(controller: c, initialPage: PageId.settings));
      await tester.pumpAndSettle();
      expect(find.text('Usage reporting'), findsOneWidget);
      await shot(tester, name);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }

    await settings('usage-3-settings-dark', await started(tester, stored, FakeUsageTransport()));
    await settings('usage-4-settings-light', await started(tester, stored, FakeUsageTransport()), theme: ThemeChoice.light);
    final offline = FakeUsageTransport()..failWith = UsageSendException('No connection to bluepulse-usage.supabase.co');
    await settings('usage-5-settings-offline', await started(tester, stored, offline));
    await settings('usage-6-settings-off', UsageService.disabled(disabledReason: 'Usage reporting is not set in this build'));
  }, skip: out == null);
}
