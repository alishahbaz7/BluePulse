import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The version rules, enforced: one declaration (pubspec.yaml), a changelog section for it, no second
/// literal anywhere in the code, and a version branch named for it.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(\+[0-9]+)?\s*$', multiLine: true).firstMatch(pubspec);
  final version = match?.group(1);

  test('pubspec.yaml declares a semantic version', () {
    expect(version, isNotNull);
  });

  test('the changelog has a section for the current version, and it is the newest', () {
    final changelog = File('CHANGELOG.md').readAsStringSync();
    final first = RegExp(r'^## ([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true).firstMatch(changelog);
    expect(first?.group(1), version);
  });

  test('no second version literal in the code or the protocol package', () {
    final offenders = <String>[];
    for (final dir in ['lib', 'packages/eye_protocol/lib']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (f.readAsStringSync().contains("'$version'") || f.readAsStringSync().contains('"$version"')) {
          offenders.add(f.path);
        }
      }
    }
    expect(offenders, isEmpty, reason: 'read the version from AppController.version instead');
    expect(File('packages/eye_protocol/pubspec.yaml').readAsStringSync(), isNot(contains(RegExp(r'^version:', multiLine: true))),
        reason: 'the internal package carries no number of its own');
  });

  test('a version branch is named for the version', () {
    final ProcessResult r;
    try {
      r = Process.runSync('git', ['symbolic-ref', '--short', 'HEAD']);
    } on ProcessException {
      markTestSkipped('git not available');
      return;
    }
    if (r.exitCode != 0) {
      markTestSkipped('not on a branch');
      return;
    }
    final branch = (r.stdout as String).trim();
    if (RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(branch)) {
      expect(branch, version, reason: 'the version in pubspec.yaml must match the branch it sits on');
    }
  });
}
