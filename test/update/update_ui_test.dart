import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:bluepulse/app/controller.dart';
import 'package:bluepulse/main.dart';
import 'package:bluepulse/ui/nav.dart';
import 'package:bluepulse/ui/pages/settings_page.dart';
import 'package:bluepulse/update/installer.dart';
import 'package:bluepulse/update/semver.dart';
import 'package:bluepulse/update/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'update_fixtures.dart';
import 'update_service_test.dart' show FakeTransport;

String manifest({String version = '1.1.0', String? minimum}) => jsonEncode({
      'app': 'BluePulse',
      'version': version,
      'published': '2026-11-20T10:00:00Z',
      'notes': '- Sessions with CSV export\n- Faster scanning on Android',
      'minimumVersion': ?minimum,
      'assets': {
        'windows': {'file': 'BluePulse-v$version.zip', 'sha256': sha256.convert([1]).toString(), 'size': 31457280},
      },
    });

UpdateService serviceWith(String json) => UpdateService(
      current: SemVer.parse('1.0.0'),
      host: TestHost(InstallLayout(Directory.systemTemp)),
      transport: FakeTransport(json, const {}),
      manifestUrl: Uri.parse('https://github.com/acme/eye/releases/latest/download/latest.json'),
    );

Future<AppController> pump(WidgetTester tester, UpdateService updates, {PageId? page}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = testController(updates: updates);
  await tester.pumpWidget(EyeApp(controller: c, initialPage: page));
  await tester.pump();
  return c;
}

Future<void> finish(WidgetTester tester, AppController c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}

void main() {
  testWidgets('a newer release is offered once at start; Later leaves a chip', (tester) async {
    final u = serviceWith(manifest());
    final c = await pump(tester, u);
    await u.check();
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Version 1.1.0 is available. This copy is 1.0.0.'), findsOneWidget);
    expect(find.text('30.0 MB'), findsOneWidget);
    expect(find.textContaining('Sessions with CSV export'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Update ›'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    expect(find.text('Update 1.1.0'), findsOneWidget, reason: 'the chip carries the offer after Later');

    // A second check does not prompt again in the same run.
    await u.check();
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);

    await tester.tap(find.text('Update 1.1.0'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('a required update offers no Later', (tester) async {
    final u = serviceWith(manifest(version: '1.2.0', minimum: '1.1.0'));
    final c = await pump(tester, u);
    await u.check();
    await tester.pumpAndSettle();
    expect(find.text('Version 1.0.0 must be updated to keep working.'), findsOneWidget);
    expect(find.text('Later'), findsNothing);
    await finish(tester, c);
  });

  testWidgets('no prompt and no chip when up to date', (tester) async {
    final u = serviceWith(manifest(version: '1.0.0'));
    final c = await pump(tester, u);
    await u.check();
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    expect(find.textContaining('Update 1.'), findsNothing);
    await finish(tester, c);
  });

  testWidgets('progress, ready and failure read in words', (tester) async {
    final u = serviceWith(manifest());
    final c = await pump(tester, u);
    await u.check();
    await tester.pumpAndSettle();

    u
      ..stage = UpdateStage.downloading
      ..received = 12 * 1048576
      ..total = 30 * 1048576;
    // ignore: invalid_use_of_protected_member
    u.notifyListeners();
    await tester.pump();
    expect(find.text('Downloading 1.1.0'), findsOneWidget);
    expect(find.text('12.0 MB of 30.0 MB · 40 %'), findsOneWidget);
    expect(find.text('Updating · 40 %'), findsOneWidget);

    u.stage = UpdateStage.ready;
    // ignore: invalid_use_of_protected_member
    u.notifyListeners();
    await tester.pump();
    expect(find.text('Restart to finish'), findsOneWidget);
    expect(find.text('Restart now'), findsOneWidget);
    expect(find.text('Restart to update'), findsOneWidget);

    u
      ..stage = UpdateStage.failed
      ..error = 'No connection to github.com';
    // ignore: invalid_use_of_protected_member
    u.notifyListeners();
    await tester.pump();
    expect(find.text('Update failed'), findsWidgets);
    expect(find.text('No connection to github.com'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('Settings shows the update state', (tester) async {
    final c = await pump(tester, UpdateService.disabled(current: SemVer.parse('1.0.0'), disabledReason: 'The releases repository is not set in this build'), page: PageId.settings);
    await tester.scrollUntilVisible(find.text('Check for updates'), 300,
        scrollable: find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable)).first);
    expect(find.text('About'), findsOneWidget);
    expect(find.descendant(of: find.byType(SettingsPage), matching: find.textContaining('Version ')), findsOneWidget,
        reason: 'in the About card (the rail names the version too)');
    expect(find.text('The releases repository is not set in this build'), findsOneWidget);
    await finish(tester, c);
  });
}
