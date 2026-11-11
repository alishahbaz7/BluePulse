import 'package:bluepulse/app/controller.dart';
import 'package:bluepulse/app/settings.dart';
import 'package:bluepulse/core/registry.dart';
import 'package:bluepulse/main.dart';
import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'config_session_test.dart' show FakeSensor;
import 'helpers.dart';

void main() {
  Future<(AppController, FakeSensor)> pump(WidgetTester tester, {Size size = const Size(1440, 1000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sensor = FakeSensor();
    final settings = AppSettings(null, false);
    final c = AppController(
      settings: settings,
      registry: DeviceRegistry(settings),
      liveScanner: null,
      demoScanner: FakeScanner(),
      gattLink: sensor,
    );
    await c.startScan();
    c.registry.ingest(event('7C:D9:F4:15:2D:01', sensorRsp, rssi: -45));
    await tester.pumpWidget(EyeApp(controller: c));
    await tester.pump();
    return (c, sensor);
  }

  testWidgets('from a device to its settings: connect with the PIN, change the interval, save and read back', (tester) async {
    final (c, sensor) = await pump(tester);
    await tester.tap(find.text('Devices').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SNS_TEST01').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Configure'));
    await tester.pumpAndSettle();
    expect(find.text('7C:D9:F4:15:2D:01'), findsWidgets);
    expect(find.widgetWithText(TextField, '123456'), findsOneWidget, reason: 'the factory PIN, ready to change');

    expect(c.scanning, isTrue);
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    expect(c.scanning, isFalse, reason: 'the radio belongs to the connection while configuring');
    expect(find.text('BTSMP1'), findsOneWidget);
    expect(find.text('1.2.10'), findsOneWidget);
    expect(find.widgetWithText(TextField, '2200'), findsOneWidget, reason: 'the interval as the device keeps it');
    expect(find.text('No changes'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '2200'), '2100');
    await tester.pump();
    expect(find.text('1 change'), findsOneWidget);
    expect(find.textContaining('was 2200 ms'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '2100'), '900');
    await tester.pump();
    expect(find.textContaining('1000–10000'), findsOneWidget, reason: 'out of range is marked, not sent');
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, '900'), '2100');
    await tester.pump();

    sensor.writes.clear();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(sensor.writes, [(EyeSetting.interval.characteristic, '3408'), (EyeGatt.command, '0010')]);
    expect(find.textContaining('Saved to the device and read back: Advertising interval'), findsOneWidget);
    expect(find.text('No changes'), findsOneWidget);

    await tester.tap(find.byTooltip('Disconnect'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
    expect(c.scanning, isTrue, reason: 'scanning starts again when configuring ends');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('a wrong PIN is said plainly and nothing is shown', (tester) async {
    final (c, sensor) = await pump(tester, size: const Size(411, 914));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configure').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SNS_TEST01').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '123456'), '000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Wrong PIN'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    expect(sensor.wrongPins, 1);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
