import 'package:bluepulse/update/manifest.dart';
import 'package:bluepulse/update/semver.dart';
import 'package:flutter_test/flutter_test.dart';

const sha = 'a3f1c2d4e5b6a7980a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f6071';
final base = Uri.parse('https://github.com/acme/eye-releases/releases/latest/download/latest.json');

String manifestJson({String version = '1.1.0', String? minimum, String app = 'BluePulse', String? url}) => '''
{
  "app": "$app",
  "version": "$version",
  "published": "2026-11-20T10:00:00Z",
  "notes": "  Faster scanning  ",
  ${minimum == null ? '' : '"minimumVersion": "$minimum",'}
  "assets": {
    "windows": {"file": "BluePulse-v$version.zip", ${url == null ? '' : '"url": "$url",'} "sha256": "${sha.toUpperCase()}", "size": 1234},
    "android": {"file": "BluePulse-v$version.apk", "sha256": "$sha"}
  }
}''';

UpdateManifest parse(String json) => UpdateManifest.parse(json, base: base, expectedApp: 'BluePulse');

void main() {
  group('SemVer', () {
    test('parses with or without v and build suffix', () {
      expect(SemVer.parse('1.2.3'), const SemVer(1, 2, 3));
      expect(SemVer.parse('v1.2.3'), const SemVer(1, 2, 3));
      expect(SemVer.parse('1.2.3+7'), const SemVer(1, 2, 3));
      expect(SemVer.tryParse('1.2'), isNull);
      expect(SemVer.tryParse('—'), isNull);
    });

    test('compares numerically', () {
      expect(SemVer.parse('1.10.0') > SemVer.parse('1.9.9'), isTrue);
      expect(SemVer.parse('2.0.0') > SemVer.parse('1.99.99'), isTrue);
      expect(SemVer.parse('1.0.1') < SemVer.parse('1.0.10'), isTrue);
      expect(SemVer.parse('1.0.0'), SemVer.parse('v1.0.0+3'));
    });
  });

  group('latest.json', () {
    test('parses a release', () {
      final m = parse(manifestJson());
      expect(m.version, const SemVer(1, 1, 0));
      expect(m.notes, 'Faster scanning');
      expect(m.published, DateTime.utc(2026, 11, 20, 10));
      expect(m.minimumVersion, isNull);
      final w = m.assets[UpdatePlatform.windows]!;
      expect(w.sha256, sha, reason: 'checksums are compared lower-case');
      expect(w.size, 1234);
      expect(w.url.toString(), 'https://github.com/acme/eye-releases/releases/latest/download/BluePulse-v1.1.0.zip');
    });

    test('an absolute url is kept', () {
      final m = parse(manifestJson(url: 'https://github.com/acme/eye-releases/releases/download/v1.1.0/BluePulse-v1.1.0.zip'));
      expect(m.assets[UpdatePlatform.windows]!.url.path, '/acme/eye-releases/releases/download/v1.1.0/BluePulse-v1.1.0.zip');
    });

    test('newer and required', () {
      final m = parse(manifestJson(minimum: '1.0.2'));
      expect(m.isNewerThan(const SemVer(1, 0, 0)), isTrue);
      expect(m.isNewerThan(const SemVer(1, 1, 0)), isFalse);
      expect(m.isNewerThan(const SemVer(1, 2, 0)), isFalse);
      expect(m.requires(const SemVer(1, 0, 1)), isTrue);
      expect(m.requires(const SemVer(1, 0, 2)), isFalse);
    });

    test('rejects what it cannot trust', () {
      expect(() => parse('not json'), throwsFormatException);
      expect(() => parse('[]'), throwsFormatException);
      expect(() => parse(manifestJson(app: 'Other-App')), throwsFormatException);
      expect(() => parse(manifestJson(version: '1.1')), throwsFormatException);
      expect(() => parse(manifestJson(minimum: 'soon')), throwsFormatException);
      expect(() => parse(manifestJson().replaceFirst(sha.toUpperCase(), 'abc')), throwsFormatException);
      expect(() => parse(manifestJson().replaceFirst('"BluePulse-v1.1.0.zip"', '"../evil.zip"')),
          throwsFormatException);
      expect(() => parse(manifestJson(url: 'file:///C:/evil.zip')), throwsFormatException);
    });
  });
}
