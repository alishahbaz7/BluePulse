import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:bluepulse/update/installer.dart';
import 'package:bluepulse/update/manifest.dart';
import 'package:bluepulse/update/semver.dart';
import 'package:bluepulse/update/transport.dart';
import 'package:bluepulse/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'update_fixtures.dart';

/// Serves a manifest and files from memory.
class FakeTransport implements UpdateTransport {
  FakeTransport(this.manifest, this.files, {this.fail});

  final String? manifest;
  final Map<String, List<int>> files;
  final UpdateException? fail;
  final requested = <Uri>[];

  @override
  Future<String> getText(Uri url) async {
    requested.add(url);
    if (fail != null) throw fail!;
    if (manifest == null) throw UpdateException('Not found on github.com (HTTP 404)');
    return manifest!;
  }

  @override
  Future<String> download(Uri url, File into, {void Function(int, int?)? onProgress, bool Function()? cancelled}) async {
    requested.add(url);
    final bytes = files[p.basename(url.path)];
    if (bytes == null) throw UpdateException('Not found on ${url.host} (HTTP 404)');
    into.parent.createSync(recursive: true);
    if (cancelled?.call() ?? false) throw UpdateException('Download cancelled');
    into.writeAsBytesSync(bytes);
    onProgress?.call(bytes.length, bytes.length);
    return sha256.convert(bytes).toString();
  }
}

String manifestFor(String version, Map<String, List<int>> files, {String? minimum, String? badSha}) => jsonEncode({
      'app': 'BluePulse',
      'version': version,
      'notes': 'Notes for $version',
      'minimumVersion': ?minimum,
      'assets': {
        for (final e in files.entries)
          (e.key.endsWith('.apk') ? 'android' : 'windows'): {
            'file': e.key,
            'sha256': badSha ?? sha256.convert(e.value).toString(),
            'size': e.value.length,
          },
      },
    });

void main() {
  late Directory tmp;
  final manifestUrl = Uri.parse('https://github.com/acme/eye/releases/latest/download/latest.json');
  setUp(() => tmp = tempDir('service'));
  tearDown(() => tmp.deleteSync(recursive: true));

  List<int> releaseZip(String v) => zipOf({
        'BluePulse/BluePulse.exe': 'launcher v1',
        'BluePulse/versions/BluePulse-v$v/BluePulse-v$v.exe': 'app $v',
      });

  UpdateService service(TestHost host, FakeTransport t, {String current = '1.0.0'}) =>
      UpdateService(current: SemVer.parse(current), host: host, transport: t, manifestUrl: manifestUrl);

  test('up to date', () async {
    final files = {'BluePulse-v1.0.0.zip': releaseZip('1.0.0')};
    final s = service(TestHost(fakeInstall(tmp, ['1.0.0'], current: '1.0.0')), FakeTransport(manifestFor('1.0.0', files), files));
    await s.check();
    expect(s.stage, UpdateStage.upToDate);
    expect(s.updateAvailable, isFalse);
    expect(s.lastChecked, isNotNull);
  });

  test('available → download → verify → install → restart through the launcher (Windows)', () async {
    final files = {'BluePulse-v1.1.0.zip': releaseZip('1.1.0')};
    final layout = fakeInstall(tmp, ['1.0.0'], current: '1.0.0');
    final host = TestHost(layout);
    final t = FakeTransport(manifestFor('1.1.0', files), files);
    final s = service(host, t);
    final stages = <UpdateStage>[];
    s.addListener(() => stages.add(s.stage));

    await s.check();
    expect(s.stage, UpdateStage.available);
    expect(s.required, isFalse);
    expect(s.canInstallHere, isTrue);

    await s.downloadAndInstall();
    expect(s.stage, UpdateStage.ready, reason: s.error);
    expect(stages, containsAllInOrder([UpdateStage.checking, UpdateStage.available, UpdateStage.downloading, UpdateStage.installing, UpdateStage.ready]));
    expect(layout.installed().map((v) => '${v.version}'), ['1.1.0', '1.0.0']);
    expect(t.requested.last.toString(), 'https://github.com/acme/eye/releases/latest/download/BluePulse-v1.1.0.zip');
    expect(layout.stagingDir.listSync(), isEmpty, reason: 'the zip is removed once installed');

    await s.finish();
    expect(host.restarted, isTrue);
  });

  test('a checksum mismatch installs nothing', () async {
    final files = {'BluePulse-v1.1.0.zip': releaseZip('1.1.0')};
    final layout = fakeInstall(tmp, ['1.0.0'], current: '1.0.0');
    final s = service(TestHost(layout), FakeTransport(manifestFor('1.1.0', files, badSha: 'f' * 64), files));
    await s.check();
    await s.downloadAndInstall();
    expect(s.stage, UpdateStage.failed);
    expect(s.error, contains('checksum'));
    expect(layout.installed().map((v) => '${v.version}'), ['1.0.0']);
    expect(layout.stagingDir.existsSync() ? layout.stagingDir.listSync() : const [], isEmpty);
  });

  test('minimum version makes the update required', () async {
    final files = {'BluePulse-v1.2.0.zip': releaseZip('1.2.0')};
    final s = service(TestHost(fakeInstall(tmp, ['1.0.0'])), FakeTransport(manifestFor('1.2.0', files, minimum: '1.1.0'), files));
    await s.check();
    expect(s.required, isTrue);
  });

  test('no release yet, and offline, are reported in words', () async {
    final s1 = service(TestHost(fakeInstall(tmp, ['1.0.0'])), FakeTransport(null, const {}));
    await s1.check();
    expect(s1.stage, UpdateStage.failed);
    expect(s1.error, 'No release published yet');

    final s2 = service(TestHost(fakeInstall(tmp, ['1.0.0'])),
        FakeTransport(null, const {}, fail: UpdateException('No connection to github.com')));
    await s2.check();
    expect(s2.error, 'No connection to github.com');
  });

  test('a release without this platform\'s package says so', () async {
    final files = {'BluePulse-v1.1.0.apk': [1, 2, 3]};
    final s = service(TestHost(fakeInstall(tmp, ['1.0.0'])), FakeTransport(manifestFor('1.1.0', files), files));
    await s.check();
    await s.downloadAndInstall();
    expect(s.stage, UpdateStage.failed);
    expect(s.error, 'Release 1.1.0 has no Windows package');
  });

  test('Windows without the launcher install opens the releases page instead', () async {
    final files = {'BluePulse-v1.1.0.zip': releaseZip('1.1.0')};
    final host = TestHost(null);
    final s = service(host, FakeTransport(manifestFor('1.1.0', files), files));
    await s.check();
    expect(s.canInstallHere, isFalse);
    await s.downloadAndInstall();
    expect(host.opened, isNotNull);
    expect(s.stage, UpdateStage.available);
  });

  test('Android hands the verified APK to the system installer', () async {
    final apk = List<int>.generate(2048, (i) => i % 251);
    final files = {'BluePulse-v1.1.0.apk': apk};
    final host = TestHost(null, platform: UpdatePlatform.android);
    final s = service(host, FakeTransport(manifestFor('1.1.0', files), files));
    await s.check();
    await s.downloadAndInstall();
    expect(s.stage, UpdateStage.ready, reason: s.error);
    expect(p.basename(host.installerOpened!.path), 'BluePulse-v1.1.0.apk');
    expect(host.installerOpened!.readAsBytesSync(), apk);
    host.installerOpened!.parent.deleteSync(recursive: true);
  });

  test('disabled service never checks', () async {
    final s = UpdateService.disabled(disabledReason: 'Not here');
    await s.check();
    expect(s.stage, UpdateStage.disabled);
    expect(s.disabledReason, 'Not here');
  });
}
