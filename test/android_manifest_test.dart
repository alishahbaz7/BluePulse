import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The release manifest is the only one a shipped APK has: debug and profile manifests add their own
/// permissions, so something missing here passes every development run and fails only for users.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  bool declares(String permission) => RegExp(
        r'<uses-permission[^>]*android:name="android\.permission\.' + permission + r'"(?![^>]*tools:node="remove")',
      ).hasMatch(manifest);

  test('release builds may use the internet: updates (GitHub) and usage reports (Supabase)', () {
    expect(declares('INTERNET'), isTrue, reason: '1.0.0 shipped without it and could reach nothing');
  });

  test('release builds keep the permissions their features need', () {
    for (final p in ['BLUETOOTH_SCAN', 'BLUETOOTH_CONNECT', 'ACCESS_FINE_LOCATION', 'REQUEST_INSTALL_PACKAGES']) {
      expect(declares(p), isTrue, reason: p);
    }
  });
}
