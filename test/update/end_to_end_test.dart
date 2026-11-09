import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bluepulse/update/semver.dart';
import 'package:bluepulse/update/transport.dart';
import 'package:bluepulse/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/package_release.dart' as release;
import 'update_fixtures.dart';

/// The whole path on real sockets: package a release with the release tool, serve it the way GitHub
/// does (the `latest/download` address redirects to the release's own), then check, download, verify,
/// install and clean up with the real HTTP transport.
void main() {
  late Directory tmp;
  late HttpServer server;
  late Map<String, List<int>> served;

  setUp(() async {
    tmp = tempDir('e2e');
    served = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path;
      if (path.startsWith('/acme/eye/releases/latest/download/')) {
        // GitHub answers the stable address with a redirect to the newest release's file.
        final file = p.basename(path);
        req.response.redirect(Uri.parse('/acme/eye/releases/download/v1.1.0/$file'), status: HttpStatus.found);
        return;
      }
      final bytes = served[p.basename(path)];
      if (bytes == null) {
        req.response.statusCode = HttpStatus.notFound;
      } else {
        req.response.contentLength = bytes.length;
        req.response.add(bytes);
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  test('package → serve → check → download → verify → install → cleanup', () async {
    // Package 1.1.0 with the release tool.
    final build = fakeFlutterBuild(tmp, '1.1.0');
    final launcher = File(p.join(tmp.path, 'launcher.exe'))..writeAsStringSync('launcher v2');
    final zip = release.buildWindowsZip(flutterBuild: build, launcher: launcher, version: '1.1.0');
    served['BluePulse-v1.1.0.zip'] = zip;
    served['latest.json'] = utf8.encode(release.buildManifest(
      version: '1.1.0',
      notes: 'Test release',
      assets: {'windows': release.asset('BluePulse-v1.1.0.zip', zip, null, '1.1.0')},
    ));

    // A 1.0.0 install (plus an older 0.9.0 that cleanup should remove later).
    final layout = fakeInstall(tmp, ['0.9.0', '1.0.0'], current: '1.0.0');
    final host = TestHost(layout);
    final base = 'http://127.0.0.1:${server.port}/acme/eye/releases/latest/download';
    final s = UpdateService(
      current: SemVer.parse('1.0.0'),
      host: host,
      transport: HttpUpdateTransport(userAgent: 'BluePulse/1.0.0'),
      manifestUrl: Uri.parse('$base/latest.json'),
    );

    await s.check();
    expect(s.stage, UpdateStage.available, reason: s.error);
    expect(s.manifest!.notes, 'Test release');

    await s.downloadAndInstall();
    expect(s.stage, UpdateStage.ready, reason: s.error);
    expect(s.received, zip.length);
    expect(s.launcherUpdated, isTrue);
    expect(layout.launcher.readAsStringSync(), 'launcher v2');

    final installed = layout.installed();
    expect(installed.first.version, const SemVer(1, 1, 0));
    expect(installed.first.exe.readAsStringSync(), 'app 1.1.0',
        reason: 'the Flutter program is renamed to the release name inside the version folder');
    expect(File(p.join(installed.first.dir.path, 'data', 'flutter_assets', 'AssetManifest.json')).existsSync(), isTrue);

    // Next start runs 1.1.0: keep it and 1.0.0 (rollback), drop 0.9.0.
    final after = fakeInstall(tmp, const [], current: '1.1.0'); // same root, now running 1.1.0
    final removed = await TestHost(after).cleanup();
    expect(removed, contains('BluePulse-v0.9.0'));
    expect(after.installed().map((v) => '${v.version}'), ['1.1.0', '1.0.0']);
  });

  test('a damaged download is caught by the checksum', () async {
    final build = fakeFlutterBuild(tmp, '1.1.0');
    final launcher = File(p.join(tmp.path, 'launcher.exe'))..writeAsStringSync('launcher v1');
    final zip = release.buildWindowsZip(flutterBuild: build, launcher: launcher, version: '1.1.0');
    served['latest.json'] = utf8.encode(release.buildManifest(
      version: '1.1.0',
      notes: '',
      assets: {'windows': release.asset('BluePulse-v1.1.0.zip', zip, null, '1.1.0')},
    ));
    served['BluePulse-v1.1.0.zip'] = [...zip]..[100] ^= 0xFF;

    final layout = fakeInstall(tmp, ['1.0.0'], current: '1.0.0');
    final s = UpdateService(
      current: SemVer.parse('1.0.0'),
      host: TestHost(layout),
      transport: HttpUpdateTransport(userAgent: 'test'),
      manifestUrl: Uri.parse('http://127.0.0.1:${server.port}/acme/eye/releases/latest/download/latest.json'),
    );
    await s.check();
    await s.downloadAndInstall();
    expect(s.stage, UpdateStage.failed);
    expect(s.error, contains('checksum'));
    expect(layout.installed().map((v) => '${v.version}'), ['1.0.0']);
  });

  test('the C++ runtime goes beside the program, once', () {
    final build = fakeFlutterBuild(tmp, '1.1.0');
    File(p.join(build.path, 'vcruntime140.dll')).writeAsStringSync('from build');
    final rt = Directory(p.join(tmp.path, 'crt'))..createSync();
    final runtime = [
      for (final n in release.vcRuntime) File(p.join(rt.path, n))..writeAsStringSync('crt $n'),
    ];
    final launcher = File(p.join(tmp.path, 'launcher.exe'))..writeAsStringSync('launcher');
    final zip = release.buildWindowsZip(flutterBuild: build, launcher: launcher, version: '1.1.0', runtime: runtime);
    final names = ZipDecoder().decodeBytes(zip).files.map((f) => f.name).toList();
    const dir = 'BluePulse/versions/BluePulse-v1.1.0';
    expect(names, containsAll(['$dir/msvcp140.dll', '$dir/vcruntime140.dll', '$dir/vcruntime140_1.dll']));
    expect(names.where((n) => n.endsWith('/vcruntime140.dll')).length, 1, reason: 'the build’s own copy wins');
  });

  test('this machine can supply the runtime', () {
    expect(release.findVcRuntime().map((f) => p.basename(f.path).toLowerCase()), release.vcRuntime);
  }, skip: Platform.isWindows ? false : 'Windows only');

  test('release tool reads the version and the changelog section', () {
    expect(release.readVersion('name: x\nversion: 1.2.3+4\n'), '1.2.3');
    const log = '# Changelog\n\n## 1.2.3\n\nFixed things.\n- a\n\n## 1.2.2\n\nOlder.\n';
    expect(release.changelogSection(log, '1.2.3'), 'Fixed things.\n- a');
    expect(() => release.changelogSection(log, '9.9.9'), throwsFormatException);
  });
}
