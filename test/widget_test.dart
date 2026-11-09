import 'package:bluepulse/app/controller.dart';
import 'package:bluepulse/main.dart';
import 'package:bluepulse/ui/nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<AppController> pumpApp(WidgetTester tester, {Size size = const Size(1440, 900), bool scanning = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = testController();
  if (scanning) await c.startScan();
  await tester.pumpWidget(EyeApp(controller: c));
  await tester.pump();
  return c;
}

Future<void> finish(WidgetTester tester, AppController c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}

void feed(AppController c) {
  final now = DateTime.now();
  c.registry
    ..ingest(event('AA:00:00:00:00:01', beaconAdv, rssi: -58, at: now))
    ..ingest(event('AA:00:00:00:00:01', beaconRsp, rssi: -59, at: now))
    ..ingest(event('AA:00:00:00:00:02', sensorRsp, rssi: -72, at: now));
}

void main() {
  group('navigation definition', () {
    test('every page has a title, a tip and a module', () {
      for (final n in navItems) {
        expect(n.title, isNotEmpty);
        expect(n.tip, isNotEmpty);
        expect(n.module, isNotEmpty);
        expect(n.tip.endsWith('.'), isFalse, reason: 'tips are phrases, not sentences of help');
      }
      expect(navItems.map((n) => n.id).toSet().length, PageId.values.length);
    });

    test('the legend explains every pill the rail can show', () {
      expect(pillLegend.keys, containsAll(['Soon', 'BT']));
    });

    test('pages outside the rail name the rail item they belong to', () {
      for (final n in navItems.where((n) => !n.inRail)) {
        expect(n.railParent, isNotNull);
      }
    });
  });

  testWidgets('empty state when not scanning', (tester) async {
    final c = await pumpApp(tester, scanning: false);
    expect(find.text('Not scanning.'), findsOneWidget);
    expect(find.text('Start scan'), findsWidgets);
    await finish(tester, c);
  });

  testWidgets('empty state while scanning with nothing in range', (tester) async {
    final c = await pumpApp(tester);
    expect(find.text('No EYE devices in range.'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('every page renders with devices', (tester) async {
    final c = await pumpApp(tester);
    feed(c);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('IN VIEW'), findsOneWidget);
    expect(find.text('Demo data'), findsOneWidget);
    expect(find.text('Scanning · 2'), findsOneWidget);

    for (final title in ['Devices', 'Packets', 'Proximity', 'Decode', 'Settings', 'Overview']) {
      await tester.tap(find.text(title).first); // the rail comes first in the tree
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: title);
    }
    await finish(tester, c);
  });

  testWidgets('a device row opens its detail page and comes back', (tester) async {
    final c = await pumpApp(tester);
    feed(c);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Devices').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ID1_ABCDEFG'), findsOneWidget);
    expect(find.text('2990 mV'), findsOneWidget);

    await tester.tap(find.text('ID1_ABCDEFG'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('All devices'), findsOneWidget);
    expect(find.text('E39B606AA38255AA8E46'), findsOneWidget);
    expect(find.text('Signal'), findsOneWidget);

    await tester.tap(find.text('All devices'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ID1_ABCDEFG'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('decode page reads the wiki lost-beacon packet', (tester) async {
    final c = await pumpApp(tester);
    await tester.tap(find.text('Decode').first);
    await tester.pump();
    await tester.enterText(
      find.byType(TextField),
      '000000000000004b8e010000018368952793000f0e54fc209ab05800b300b40e00002a4f0001000000000000000000012a4f001e'
      '011c0001a40110eb47706aa38255aa96f21a154e2d00550d01000e020bd6010000823f',
    );
    await tester.pump();
    expect(find.text('Codec 8 Extended'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('AVL 10831 · EYE beacons · Lost'), findsOneWidget);
    expect(find.text('3030 mV'), findsOneWidget);
    expect(find.text('-92 dBm'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('decode page names a hex error', (tester) async {
    final c = await pumpApp(tester);
    await tester.tap(find.text('Decode').first);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'ABC');
    await tester.pump();
    expect(find.textContaining('Odd number of hex digits'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('phone width uses a drawer with the same items', (tester) async {
    final c = await pumpApp(tester, size: const Size(400, 820));
    feed(c);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    for (final n in navItems.where((n) => n.inRail)) {
      expect(find.text(n.title), findsWidgets, reason: n.title);
    }
    await tester.tap(find.text('Devices').last);
    await tester.pumpAndSettle();
    expect(find.text('ID1_ABCDEFG'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('Soon items do not navigate', (tester) async {
    final c = await pumpApp(tester);
    await tester.tap(find.text('Sessions'));
    await tester.pump();
    expect(find.text('Overview'), findsWidgets);
    await finish(tester, c);
  });
}
