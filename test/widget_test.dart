import 'dart:io';

import 'package:bluepulse/app/controller.dart';
import 'package:bluepulse/core/sensor_log.dart';
import 'package:bluepulse/main.dart';
import 'package:bluepulse/core/device.dart';
import 'package:bluepulse/scanner/scanner.dart';
import 'package:bluepulse/ui/nav.dart';
import 'package:bluepulse/ui/widgets/data_grid.dart';
import 'package:bluepulse/ui/widgets/device_card.dart';
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
  testWidgets('a pinned device goes to the top, gets the bar and the top-bar chip; nothing else fades', (tester) async {
    final c = await pumpApp(tester);
    feed(c);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Devices').first);
    await tester.pump(const Duration(milliseconds: 300));
    double top(String name) => tester.getTopLeft(find.text(name).first).dy;
    expect(top('ID1_ABCDEFG'), lessThan(top('SNS_TEST01')), reason: 'by name');

    await tester.tap(find.byTooltip('Pin to the top').last); // the sensor, second by name
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.book.focus.length, 1);
    expect(top('SNS_TEST01'), lessThan(top('ID1_ABCDEFG')), reason: 'pinned on top whatever the sort');
    expect(find.text('1 pinned'), findsOneWidget);
    expect(find.text('Pinned · 1'), findsOneWidget);
    expect(find.byTooltip('Unpin'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1), findsNothing, reason: 'the rest stay readable');

    await tester.tap(find.text('Unpin all'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.book.focus, isEmpty);
    expect(find.text('1 pinned'), findsNothing);
    expect(top('ID1_ABCDEFG'), lessThan(top('SNS_TEST01')));
    await finish(tester, c);
  });

  testWidgets('on a phone a pinned card goes to the top too', (tester) async {
    final c = await pumpApp(tester, size: const Size(411, 914));
    feed(c);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devices').last);
    await tester.pumpAndSettle();
    double top(String name) => tester.getTopLeft(find.text(name).first).dy;
    expect(top('ID1_ABCDEFG'), lessThan(top('SNS_TEST01')));
    await tester.tap(find.byTooltip('Pin to the top').last);
    await tester.pumpAndSettle();
    expect(top('SNS_TEST01'), lessThan(top('ID1_ABCDEFG')));
    await finish(tester, c);
  });

  testWidgets('Clear empties the list on Overview and Devices, after asking; the scan keeps running', (tester) async {
    final c = await pumpApp(tester);
    expect(find.text('Clear'), findsNothing, reason: 'nothing to clear yet');
    feed(c);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Clear'), findsOneWidget, reason: 'on the Overview');

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Clear the list?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.registry.devices, hasLength(2), reason: 'Cancel keeps everything');

    await tester.tap(find.text('Devices').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(c.registry.devices, isEmpty);
    expect(c.registry.totalPackets, 0);
    expect(c.scanning, isTrue);
    expect(c.registry.sessionStart, isNotNull, reason: 'the scan carries on, from now');
    expect(find.text('Clear'), findsNothing);

    feed(c);
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.registry.devices, hasLength(2), reason: 'what is in range comes back');
    await tester.tap(find.text('Settings').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.widgetWithText(OutlinedButton, 'Clear'), findsNothing, reason: 'only on Overview and Devices');
    await finish(tester, c);
  });

  testWidgets('Clear on a phone is an icon in the top bar', (tester) async {
    final c = await pumpApp(tester, size: const Size(360, 900));
    feed(c);
    c.book.toggleFocus('AA:00:00:00:00:01'); // a device in focus: the most crowded the bar would get
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Focus · 1'), findsNothing, reason: 'no room on a phone; the Devices page shows it');
    expect(find.byTooltip('Theme: Dark'), findsNothing, reason: 'Settings has it; the bar needs the room');
    await tester.tap(find.byTooltip('Clear the list'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(c.registry.devices, isEmpty);
    await finish(tester, c);
  });

  testWidgets('on a phone, devices and packets are cards with every figure, sorted from a menu', (tester) async {
    final c = await pumpApp(tester, size: const Size(411, 914));
    feed(c);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DataGrid<EyeDevice>), findsNothing, reason: 'no table on a phone');
    expect(find.byType(DeviceCard), findsWidgets, reason: 'Strongest signals on the Overview');

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devices').last);
    await tester.pumpAndSettle();
    expect(find.byType(DeviceCard), findsNWidgets(2));
    expect(find.textContaining('2.99 V', findRichText: true), findsOneWidget, reason: "the beacon's battery, in its card");
    expect(find.textContaining('dBm', findRichText: true), findsNWidgets(2), reason: 'and each signal');
    List<String> names() => tester.widgetList<DeviceCard>(find.byType(DeviceCard)).map((w) => w.device.mac).toList();
    expect(names(), ['AA:00:00:00:00:01', 'AA:00:00:00:00:02'], reason: 'by name: ID1_… before SNS_…');

    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lowest battery').last);
    await tester.pumpAndSettle();
    expect(names(), ['AA:00:00:00:00:01', 'AA:00:00:00:00:02'], reason: '2990 mV before 3000 mV');
    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Strongest').last);
    await tester.pumpAndSettle();
    expect(names().first, 'AA:00:00:00:00:01', reason: '-59 dBm before -72 dBm');

    await tester.tap(find.byType(DeviceCard).first);
    await tester.pumpAndSettle();
    expect(find.text('ID1_ABCDEFG'), findsWidgets, reason: 'the card opens the device page');
    await finish(tester, c);
  });

  testWidgets('ticked devices can be logged packet by packet; a running log stays in view until stopped', (tester) async {
    final c = await pumpApp(tester);
    feed(c);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Devices').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Log'), findsNothing, reason: 'nothing pinned');
    await tester.tap(find.byTooltip('Pin to the top').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Log'), findsOneWidget);

    final dir = Directory.systemTemp.createTempSync('bluepulse_log_');
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.runAsync(() async {
      c.registry.sensorLog = await SensorLog.start(File('${dir.path}/log.csv'), macs: [c.registry.devices.first.mac]);
    });
    c.book.clearFocus();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Logging 1'), findsOneWidget, reason: 'still shown with nothing pinned');
    expect(find.text('Stop log'), findsOneWidget);
    await tester.runAsync(c.stopSensorLog);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Stop log'), findsNothing);
    await finish(tester, c);
  });

  testWidgets('one Bluetooth button: glowing while scanning, plain when idle, grey when Bluetooth is off', (tester) async {
    final c = await pumpApp(tester, size: const Size(411, 914));
    expect(find.byTooltip('Scanning · tap to stop'), findsOneWidget);
    expect(find.byTooltip('Stop scan'), findsNothing, reason: 'no separate scan button any more');
    await tester.tap(find.byTooltip('Scanning · tap to stop'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.scanning, isFalse);
    expect(find.byTooltip('Bluetooth on · tap to scan'), findsOneWidget);
    await tester.tap(find.byTooltip('Bluetooth on · tap to scan'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.scanning, isTrue);
    await finish(tester, c);

    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1;
    final off = testController(scanner: FakeScanner(radio: RadioState.off, demo: false));
    await tester.pumpWidget(EyeApp(controller: off));
    await tester.pump();
    expect(find.byTooltip('Bluetooth is off · tap to turn it on'), findsOneWidget);
    await finish(tester, off);
  });

  testWidgets('Devices says how many once, in the list title; no filter chips', (tester) async {
    final c = await pumpApp(tester);
    feed(c);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Devices').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Low battery'), findsNothing);
    expect(find.text('Not seen'), findsNothing);
    expect(find.text('2'), findsOneWidget, reason: 'the count beside the title, and nowhere else');
    await finish(tester, c);
  });

  testWidgets('naming a device shows the name everywhere; its page focuses it while open', (tester) async {
    final c = await pumpApp(tester);
    feed(c);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Devices').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('ID1_ABCDEFG'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.book.temporaryFocus, 'AA:00:00:00:00:01');
    expect(find.text('In focus'), findsOneWidget);

    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Cold room 2');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.book.tagOf('AA:00:00:00:00:01'), 'Cold room 2');
    expect(find.text('Cold room 2'), findsNWidgets(2), reason: 'the page title and the pinned bar show the tag');
    expect(find.text('ADVERTISED NAME'), findsOneWidget);

    await tester.tap(find.text('All devices'));
    await tester.pumpAndSettle();
    expect(c.book.temporaryFocus, isNull, reason: 'leaving the page lets go of the focus');
    expect(find.textContaining('Cold room 2', findRichText: true), findsOneWidget,
        reason: 'the list shows the tag, then the advertised name');
    await finish(tester, c);
  });

  testWidgets('device page: one window for everything, pings, chart stats, arrange, received packets', (tester) async {
    final c = await pumpApp(tester, size: const Size(1440, 1400));
    final now = DateTime.now();
    for (var i = 0; i < 8; i++) {
      final at = now.subtract(Duration(seconds: 5 * (8 - i)));
      c.registry
        ..ingest(event('AA:00:00:00:00:01', beaconAdv, rssi: -58 - i, at: at))
        ..ingest(event('AA:00:00:00:00:01', beaconRsp, rssi: -59 - i, at: at.add(const Duration(milliseconds: 12))));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Devices').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('ID1_ABCDEFG'));
    await tester.pump(const Duration(milliseconds: 300));

    // The window.
    expect(find.text('10 min'), findsOneWidget);
    await tester.tap(find.text('5 min'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.book.windowMinutes, 5);

    // Pings: 8 advertising events, 5 s apart.
    expect(find.text('PINGS'), findsOneWidget);
    expect(find.text('8 in 5 min'), findsOneWidget);
    expect(find.text('5.00 s'), findsWidgets, reason: 'avg / min / max gap');

    // Every chart: Now · Avg · Min · Max.
    expect(find.text('AVG'), findsWidgets);
    expect(find.text('MIN'), findsWidgets);
    expect(find.text('MAX'), findsWidgets);

    // Arrange.
    await tester.tap(find.text('Arrange'));
    await tester.pumpAndSettle();
    expect(find.text('Arrange charts'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(c.book.chartLayout('eyeBeacon').first.visible, isFalse, reason: 'Signal hidden');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Received packets.
    final scrollable = find.byType(Scrollable).evaluate().map((e) => e.widget).whereType<Scrollable>().length;
    expect(scrollable, greaterThan(0));
    await tester.scrollUntilVisible(find.text('Received packets'), 400,
        scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first);
    expect(find.text('Received packets'), findsOneWidget);
    expect(find.text('16 in 5 min'), findsOneWidget, reason: '8 advertisements + 8 scan responses');
    expect(find.text('Save log'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
    await finish(tester, c);
  });

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
    for (final gone in ['EYE BEACONS', 'EYE SENSORS', 'LOW BATTERY']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.text('NOT SEEN'), findsOneWidget);
    expect(find.textContaining('Scanning ·'), findsNothing, reason: 'the count is on the page, once, not in the bar');

    for (final title in ['Devices', 'Packets', 'Proximity', 'Decode', 'Sessions', 'Settings', 'Overview']) {
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
    expect(find.text('OK  0x823F'), findsOneWidget, reason: 'CRC tile: the result with the checksum beside it');
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

  testWidgets('the rail says who it is plainly: the name, the version, and marks that explain themselves', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = testController(scanner: FakeScanner(radio: RadioState.off, demo: false));
    await tester.pumpWidget(EyeApp(controller: c));
    await tester.pump();
    expect(find.text('Version 1.0.0'), findsOneWidget);
    expect(find.text('Bluetooth workbench'), findsNothing, reason: 'no tagline');
    expect(find.textContaining('Needs Bluetooth'), findsNothing, reason: 'no legend under the menu');
    expect(find.text('BT'), findsNothing, reason: 'no letters to decode');
    // A menu mark explains itself when hovered or held.
    final railMarks = find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').contains('Turn Bluetooth on'));
    expect(railMarks, findsWidgets, reason: 'Bluetooth is off: the live pages carry the crossed-out mark');
    expect(find.descendant(of: railMarks.first, matching: find.byIcon(Icons.bluetooth_disabled)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();

    final on = testController(scanner: FakeScanner(demo: false));
    await tester.pumpWidget(EyeApp(controller: on));
    await tester.pump();
    expect(railMarks, findsNothing, reason: 'with Bluetooth on, no marks');
    await tester.pumpWidget(const SizedBox());
    on.dispose();
  });

  testWidgets("a phone's side menu stays clear of the status bar and the gesture bar", (tester) async {
    tester.view.padding = const FakeViewPadding(top: 40, bottom: 24); // dpr 1: logical pixels
    addTearDown(tester.view.resetPadding);
    final c = await pumpApp(tester, size: const Size(411, 914));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    final brand = tester.getRect(find.text('Version 1.0.0'));
    expect(brand.top, greaterThanOrEqualTo(40), reason: 'below the notification bar');
    final drawer = tester.getRect(find.byType(Drawer));
    final lastItem = navItems.where((n) => n.inRail).last.title;
    final last = tester.getRect(find.descendant(of: find.byType(Drawer), matching: find.text(lastItem)));
    expect(drawer.top, 0, reason: "the menu's colour still fills the strip behind the status bar");
    expect(last.bottom, lessThanOrEqualTo(914 - 24), reason: 'its last line above the gesture bar');
    await finish(tester, c);
  });

  testWidgets('Soon items do not navigate', (tester) async {
    final c = await pumpApp(tester);
    await tester.tap(find.text('Configure'));
    await tester.pump();
    expect(find.text('Overview'), findsWidgets);
    await finish(tester, c);
  });
}
