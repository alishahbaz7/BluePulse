// Renders the update dialog in each state to PNG files for a visual check, with Segoe UI and the
// Material icons loaded so text and icons look as they will on Windows. Skipped unless EYE_SHOTS
// names an output folder:
//
//   $env:EYE_SHOTS = "C:\temp\shots"; flutter test test/visual
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bluepulse/main.dart';
import 'package:bluepulse/ui/nav.dart';
import 'package:bluepulse/update/installer.dart';
import 'package:bluepulse/update/semver.dart';
import 'package:bluepulse/update/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers.dart';
import '../update/update_fixtures.dart';
import '../update/update_service_test.dart' show FakeTransport;
import '../update/update_ui_test.dart' show manifest;

final out = Platform.environment['EYE_SHOTS'];

Future<void> loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    if (File(f).existsSync()) loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
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
      File(p.join(out!, '$name.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('update dialog states', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final u = UpdateService(
      current: SemVer.parse('1.0.0'),
      host: TestHost(InstallLayout(Directory.systemTemp)),
      transport: FakeTransport(manifest(), const {}),
      manifestUrl: Uri.parse('https://github.com/acme/eye/releases/latest/download/latest.json'),
    );
    final c = testController(updates: u);
    await tester.pumpWidget(EyeApp(controller: c, initialPage: PageId.decode));
    await u.check();
    await tester.pumpAndSettle();
    await shot(tester, 'update-1-available');

    void set(void Function() f) {
      f();
      // ignore: invalid_use_of_protected_member
      u.notifyListeners();
    }

    set(() => u
      ..stage = UpdateStage.downloading
      ..received = 12 * 1048576
      ..total = 30 * 1048576);
    await tester.pump();
    await shot(tester, 'update-2-downloading');

    set(() => u.stage = UpdateStage.ready);
    await tester.pump();
    await shot(tester, 'update-3-ready');

    set(() => u
      ..stage = UpdateStage.failed
      ..error = 'The download does not match its checksum; nothing was installed');
    await tester.pump();
    await shot(tester, 'update-4-failed');

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }, skip: out == null);
}
