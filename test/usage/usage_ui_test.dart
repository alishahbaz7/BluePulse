import 'dart:math';

import 'package:bluepulse/app/controller.dart';
import 'package:bluepulse/main.dart';
import 'package:bluepulse/ui/nav.dart';
import 'package:bluepulse/ui/usage_ui.dart';
import 'package:bluepulse/usage/usage_service.dart';
import 'package:bluepulse/usage/usage_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'usage_service_test.dart' show FakeUsageTransport, facts;

Future<(AppController, FakeUsageTransport)> pumpWithUsage(
  WidgetTester tester, {
  Map<String, String>? stored,
  PageId? page,
  bool enabled = true,
}) async {
  tester.view.physicalSize = const Size(1440, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final transport = FakeUsageTransport();
  final usage = enabled
      ? UsageService(
          store: MemoryUsageStore(stored),
          transport: transport,
          endpoint: Uri.parse('https://example.supabase.co/rest/v1/rpc/usage_report'),
          random: Random(3),
        )
      : UsageService.disabled(disabledReason: 'Usage reporting is not set in this build');
  await tester.runAsync(
      () => usage.start(app: 'BluePulse', appVersion: '1.0.0', build: 'release', facts: facts, listenToLifecycle: false, timers: false));
  final c = testController(usage: usage);
  await tester.pumpWidget(EyeApp(controller: c, initialPage: page));
  await tester.pump();
  await tester.pump();
  return (c, transport);
}

Future<void> finish(WidgetTester tester, AppController c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}

/// Two EYE devices heard, so the Overview shows its tiles.
void feedDevices(AppController c) {
  final now = DateTime.now();
  c.registry
    ..ingest(event('AA:00:00:00:00:01', beaconAdv, rssi: -58, at: now))
    ..ingest(event('AA:00:00:00:00:01', beaconRsp, rssi: -59, at: now))
    ..ingest(event('AA:00:00:00:00:02', sensorRsp, rssi: -72, at: now));
}

void main() {
  testWidgets('first start asks for the name before anything else, and it cannot be skipped', (tester) async {
    final (c, transport) = await pumpWithUsage(tester);
    expect(find.text(welcomeTitle), findsOneWidget);
    final continueButton = find.widgetWithText(FilledButton, 'Continue');
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull, reason: 'no name yet');
    expect(find.text('Cancel'), findsNothing);

    await tester.tapAt(const Offset(5, 5)); // outside the dialog
    await tester.pump();
    expect(find.text(welcomeTitle), findsOneWidget);

    expect(find.byType(TextField), findsOneWidget, reason: 'the name is all that is asked');
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Shahbaz Khan');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(continueButton);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text(welcomeTitle), findsNothing);
    expect(c.usage.needsName, isFalse);
    final install = transport.reports.last['install']! as Map;
    expect(install['name'], 'Shahbaz Khan');
    expect(find.text('Hello, Shahbaz Khan'), findsOneWidget, reason: 'greeted on the home page at once');
    await finish(tester, c);
  });

  testWidgets('a known person is not asked again', (tester) async {
    final (c, _) = await pumpWithUsage(tester, stored: {'installId': 'a' * 32, 'name': 'Shahbaz Khan'});
    expect(find.text(welcomeTitle), findsNothing);
    await finish(tester, c);
  });

  testWidgets('Settings shows who this copy reports as, and where to', (tester) async {
    final (c, _) = await pumpWithUsage(tester,
        stored: {'installId': 'a' * 32, 'name': 'Shahbaz Khan'}, page: PageId.settings);
    expect(find.text('Shahbaz Khan'), findsOneWidget);
    expect(find.text('Edit name'), findsOneWidget);
    expect(find.text('Team'), findsNothing);
    expect(find.text('a' * 32), findsNothing, reason: 'the install ID waits under Details');
    await tester.ensureVisible(find.text('Details'));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('a' * 32), findsOneWidget, reason: 'the install ID, for support');
    expect(find.text('example.supabase.co'), findsNothing, reason: 'where reports go is not shown');
    expect(find.text('Send now'), findsNothing);
    await tester.ensureVisible(find.text('Edit name'));

    await tester.tap(find.text('Edit name'));
    await tester.pumpAndSettle();
    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Your name'), findsNothing);
    await finish(tester, c);
  });

  testWidgets('the home page greets the person by name, scanning or not', (tester) async {
    final (c, _) = await pumpWithUsage(tester, stored: {'installId': 'a' * 32, 'name': 'Shahbaz Khan'});
    expect(find.text('Not scanning.'), findsOneWidget);
    expect(find.text('Hello, Shahbaz Khan'), findsOneWidget);
    await tester.runAsync(c.startScan);
    feedDevices(c);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('IN VIEW'), findsOneWidget);
    expect(find.text('Hello, Shahbaz Khan'), findsOneWidget);
    await tester.tap(find.text('Settings').first);
    await tester.pump();
    expect(find.text('Hello, Shahbaz Khan'), findsNothing, reason: 'the home page only');
    await finish(tester, c);
  });

  testWidgets('a build without a usage channel says so and asks nothing', (tester) async {
    final (c, _) = await pumpWithUsage(tester, enabled: false, page: PageId.settings);
    expect(find.text(welcomeTitle), findsNothing);
    expect(find.textContaining('Hello'), findsNothing);
    expect(find.text('Edit name'), findsNothing, reason: 'no name to edit');
    await tester.ensureVisible(find.text('Details'));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Install ID'), findsNothing, reason: 'no reporting, no install ID to show');
    await finish(tester, c);
  });

  testWidgets('opening pages is counted', (tester) async {
    final (c, _) = await pumpWithUsage(tester, stored: {'installId': 'a' * 32, 'name': 'S'});
    await tester.tap(find.text('Decode').first);
    await tester.pump();
    await tester.tap(find.text('Settings').first);
    await tester.pump();
    expect(c.usage.session!.pages, {'overview': 1, 'decode': 1, 'settings': 1});
    await finish(tester, c);
  });
}
