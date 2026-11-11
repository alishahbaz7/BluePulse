import 'package:bluepulse/app/settings.dart';
import 'package:bluepulse/main.dart';
import 'package:bluepulse/ui/widgets/data_grid.dart';
import 'package:bluepulse/ui/widgets/device_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Tile view (the cards Configure showed) or list view (the Devices table): one switch, the same on
/// Devices, Configure and the Overview, kept between runs. A phone always shows tiles.
void main() {
  Future<void> open(WidgetTester tester, String page) async {
    await tester.tap(find.text(page).first);
    await tester.pumpAndSettle();
  }

  testWidgets('one switch for every device list; Configure and Devices always look the same', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = testController();
    await c.startScan();
    c.registry.ingest(event('7C:D9:F4:15:2D:01', sensorRsp, rssi: -45));
    c.registry.ingest(event('7C:D9:F4:15:2C:FF', beaconRsp, rssi: -70));
    await tester.pumpWidget(EyeApp(controller: c));
    await tester.pump();

    expect(c.settings.deviceView, DeviceView.list, reason: 'the table, as the Devices page always was');
    await open(tester, 'Devices');
    expect(find.byWidgetPredicate((w) => w is DataGrid), findsOneWidget);
    expect(find.byType(DeviceCard), findsNothing);

    await open(tester, 'Configure');
    expect(find.byWidgetPredicate((w) => w is DataGrid), findsOneWidget, reason: 'Configure follows: the same table');
    expect(find.text('MAC'), findsOneWidget, reason: 'with the Devices columns');
    expect(find.text('Pin'), findsNothing, reason: 'except pinning, which belongs to Devices');

    await tester.tap(find.byTooltip('Tile view'));
    await tester.pumpAndSettle();
    expect(c.settings.deviceView, DeviceView.tiles, reason: 'kept for the next run');
    expect(find.byType(DeviceCard), findsNWidgets(2));
    expect(find.byWidgetPredicate((w) => w is DataGrid), findsNothing);

    await open(tester, 'Devices');
    expect(find.byType(DeviceCard), findsNWidgets(2), reason: 'Devices follows the same switch');
    expect(find.byTooltip('Sort'), findsOneWidget, reason: 'tiles sort by the menu, as on a phone');

    await open(tester, 'Overview');
    expect(find.byType(DeviceCard), findsWidgets, reason: 'and so do the strongest signals');

    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    expect(c.settings.deviceView, DeviceView.list);
    expect(find.byType(DeviceCard), findsNothing);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('As found: tiles keep the order they were first heard, a new one joins at the bottom, '
      'one out of range greys in place; pinned devices have their own section', (tester) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = testController();
    c.settings.update((s) => s.deviceView = DeviceView.tiles);
    expect(c.settings.deviceSort, DeviceSort.found, reason: 'the default order');
    await c.startScan();
    final t0 = DateTime.now().subtract(const Duration(minutes: 2));
    // Heard in the order Zulu, Alpha, Mike — so neither by name nor by signal.
    const zulu = '7C:D9:F4:00:00:03', alpha = '7C:D9:F4:00:00:01', mike = '7C:D9:F4:00:00:02';
    for (final (i, mac, tag, rssi) in [(0, zulu, 'Zulu', -80), (1, alpha, 'Alpha', -40), (2, mike, 'Mike', -60)]) {
      c.book.setTag(mac, tag);
      c.registry.ingest(event(mac, sensorRsp, rssi: rssi, at: t0.add(Duration(seconds: i))));
    }
    // Zulu and Mike still heard; Alpha went quiet two minutes ago.
    c.registry.ingest(event(zulu, sensorRsp, rssi: -80, at: DateTime.now()));
    c.registry.ingest(event(mike, sensorRsp, rssi: -60, at: DateTime.now()));
    await tester.pumpWidget(EyeApp(controller: c));
    await tester.pump();
    await open(tester, 'Devices');

    // A device's own name is drawn with its advertised name after it: "Zulu  SNS_TEST01".
    Finder name(String tag) => find.text('$tag  SNS_TEST01');

    List<String> order() {
      final names = ['Zulu', 'Alpha', 'Mike', 'Echo'].where((n) => name(n).evaluate().isNotEmpty).toList();
      names.sort((a, b) => tester.getTopLeft(name(a)).dy.compareTo(tester.getTopLeft(name(b)).dy));
      return names;
    }

    expect(order(), ['Zulu', 'Alpha', 'Mike']);
    double opacityOf(String n) =>
        tester.widget<Opacity>(find.ancestor(of: name(n), matching: find.byType(Opacity)).first).opacity;
    expect(opacityOf('Alpha'), greyedOut, reason: 'out of range: greyed, in the same place');
    expect(opacityOf('Zulu'), 1);

    const echo = '7C:D9:F4:00:00:04';
    c.book.setTag(echo, 'Echo');
    c.registry.ingest(event(echo, sensorRsp, rssi: -30));
    await tester.pump(const Duration(milliseconds: 300));
    expect(order(), ['Zulu', 'Alpha', 'Mike', 'Echo'], reason: 'a new device joins at the bottom, even the strongest');

    expect(find.text('Pinned'), findsNothing, reason: 'no sections while nothing is pinned');
    c.book.toggleFocus(mike);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Other devices'), findsOneWidget);
    expect(order(), ['Mike', 'Zulu', 'Alpha', 'Echo'], reason: 'pinned above, the rest in the order found');
    expect(tester.getTopLeft(find.text('Pinned')).dy, lessThan(tester.getTopLeft(name('Mike')).dy));
    expect(tester.getTopLeft(find.text('Other devices')).dy, greaterThan(tester.getTopLeft(name('Mike')).dy));
    expect(tester.getTopLeft(find.text('Other devices')).dy, lessThan(tester.getTopLeft(name('Zulu')).dy));

    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name').last);
    await tester.pumpAndSettle();
    expect(c.settings.deviceSort, DeviceSort.name, reason: 'kept, and the same on Configure');
    expect(order(), ['Mike', 'Alpha', 'Echo', 'Zulu']);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('a phone shows tiles and no switch, whatever is chosen on the laptop', (tester) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = testController();
    c.settings.update((s) => s.deviceView = DeviceView.list);
    await c.startScan();
    c.registry.ingest(event('7C:D9:F4:15:2D:01', sensorRsp, rssi: -45));
    await tester.pumpWidget(EyeApp(controller: c));
    await tester.pump();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devices').last);
    await tester.pumpAndSettle();
    expect(find.byType(DeviceCard), findsOneWidget);
    expect(find.byTooltip('Tile view'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
