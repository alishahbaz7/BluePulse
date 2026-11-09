import 'dart:io';

import 'package:bluepulse/update/installer.dart';
import 'package:bluepulse/update/semver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'update_fixtures.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = tempDir('installer'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('layout', () {
    test('detected from a program inside a version folder', () {
      final exe = p.join(tmp.path, 'Tools', 'versions', 'BluePulse-v1.2.0', 'BluePulse-v1.2.0.exe');
      final l = InstallLayout.detect(exe)!;
      expect(l.root.path, p.join(tmp.path, 'Tools'));
      expect(l.currentVersion, const SemVer(1, 2, 0));
      expect(p.basename(l.launcher.path), 'BluePulse.exe');
    });

    test('not detected for a development run or a renamed program', () {
      expect(InstallLayout.detect(p.join(tmp.path, 'build', 'windows', 'x64', 'runner', 'Debug', 'bluepulse.exe')), isNull);
      expect(InstallLayout.detect(p.join(tmp.path, 'versions', 'BluePulse-v1.2.0', 'other.exe')), isNull);
      expect(InstallLayout.detect(p.join(tmp.path, 'old', 'BluePulse-v1.2.0', 'BluePulse-v1.2.0.exe')), isNull);
    });

    test('installed lists complete versions, newest first', () {
      final l = fakeInstall(tmp, ['1.0.0', '1.10.0', '1.9.0']);
      Directory(p.join(l.versionsDir.path, 'BluePulse-v2.0.0')).createSync(); // no program
      Directory(p.join(l.versionsDir.path, 'BluePulse-v3.0.0.partial')).createSync();
      expect(l.installed().map((v) => '${v.version}'), ['1.10.0', '1.9.0', '1.0.0']);
    });
  });

  group('installFromZip', () {
    test('release layout: version folder and a changed launcher', () {
      final l = fakeInstall(tmp, ['1.0.0'], current: '1.0.0');
      final zip = File(p.join(tmp.path, 'r.zip'))
        ..writeAsBytesSync(zipOf({
          'BluePulse/BluePulse.exe': 'launcher v2',
          'BluePulse/README.txt': 'hello',
          'BluePulse/versions/BluePulse-v1.1.0/BluePulse-v1.1.0.exe': 'app 1.1.0',
          'BluePulse/versions/BluePulse-v1.1.0/data/flutter_assets/a.json': '{}',
        }));
      final r = installFromZip(zip.path, l.root.path, '1.1.0');
      expect(r.installed.version, const SemVer(1, 1, 0));
      expect(r.installed.exe.readAsStringSync(), 'app 1.1.0');
      expect(File(p.join(r.installed.dir.path, 'data', 'flutter_assets', 'a.json')).existsSync(), isTrue);
      expect(r.launcherUpdated, isTrue);
      expect(l.launcher.readAsStringSync(), 'launcher v2');
      expect(l.installed().map((v) => '${v.version}'), ['1.1.0', '1.0.0']);
      expect(Directory(p.join(l.versionsDir.path, 'BluePulse-v1.1.0.partial')).existsSync(), isFalse);
    });

    test('same launcher is left alone; bare version folder accepted', () {
      final l = fakeInstall(tmp, ['1.0.0'], launcher: 'launcher v1');
      final zip = File(p.join(tmp.path, 'r.zip'))
        ..writeAsBytesSync(zipOf({
          'BluePulse-v1.1.0/BluePulse-v1.1.0.exe': 'app 1.1.0',
          'BluePulse.exe': 'launcher v1',
        }));
      final r = installFromZip(zip.path, l.root.path, '1.1.0');
      expect(r.launcherUpdated, isFalse);
      expect(r.installed.exe.existsSync(), isTrue);
    });

    test('reinstalling a version replaces its folder', () {
      final l = fakeInstall(tmp, ['1.1.0']);
      File(p.join(l.versionsDir.path, 'BluePulse-v1.1.0', 'stale.txt')).writeAsStringSync('x');
      final zip = File(p.join(tmp.path, 'r.zip'))
        ..writeAsBytesSync(zipOf({'BluePulse-v1.1.0/BluePulse-v1.1.0.exe': 'fresh'}));
      final r = installFromZip(zip.path, l.root.path, '1.1.0');
      expect(r.installed.exe.readAsStringSync(), 'fresh');
      expect(File(p.join(r.installed.dir.path, 'stale.txt')).existsSync(), isFalse);
    });

    test('refuses a zip without the program, and unsafe paths', () {
      final l = fakeInstall(tmp, ['1.0.0']);
      final noExe = File(p.join(tmp.path, 'a.zip'))
        ..writeAsBytesSync(zipOf({'BluePulse-v1.1.0/readme.txt': 'x'}));
      expect(() => installFromZip(noExe.path, l.root.path, '1.1.0'),
          throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains('BluePulse-v1.1.0.exe'))));
      final slip = File(p.join(tmp.path, 'b.zip'))
        ..writeAsBytesSync(zipOf({
          'BluePulse-v1.1.0/BluePulse-v1.1.0.exe': 'x',
          'BluePulse-v1.1.0/../../evil.txt': 'x',
        }));
      expect(() => installFromZip(slip.path, l.root.path, '1.1.0'), throwsA(isA<UpdateException>()));
      expect(File(p.join(tmp.path, 'evil.txt')).existsSync(), isFalse);
      expect(l.installed().map((v) => '${v.version}'), ['1.0.0'], reason: 'nothing installed from a refused zip');
    });
  });

  group('cleanup', () {
    test('keeps running, newest and the one below running; removes the rest and leftovers', () {
      final l = fakeInstall(tmp, ['1.0.0', '1.1.0', '1.2.0', '1.3.0'], current: '1.2.0');
      Directory(p.join(l.versionsDir.path, 'BluePulse-v1.4.0.partial')).createSync();
      Directory(p.join(l.versionsDir.path, 'BluePulse-v1.1.0.old-123')).createSync();
      l.stagingDir.createSync();
      final removed = cleanupVersions(l);
      expect(removed, containsAll(['BluePulse-v1.0.0', 'BluePulse-v1.4.0.partial', '.download']));
      expect(l.installed().map((v) => '${v.version}'), ['1.3.0', '1.2.0', '1.1.0']);
    });

    test('after an update: new version running, previous kept for rollback', () {
      final l = fakeInstall(tmp, ['1.0.0', '1.1.0', '1.2.0'], current: '1.2.0');
      cleanupVersions(l);
      expect(l.installed().map((v) => '${v.version}'), ['1.2.0', '1.1.0']);
    });
  });
}
