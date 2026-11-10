import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the install ID, the name and unsent reports are kept on this device.
abstract class UsageStore {
  String? read(String key);

  /// Writes [value]; null removes the key.
  Future<void> write(String key, String? value);
}

/// The app's settings store. It lives in the user profile, so every installed version shares the
/// install ID. Debug builds keep their own (key prefix `dev.`), so a development run is a
/// different install from the release on the same computer.
class PrefsUsageStore implements UsageStore {
  PrefsUsageStore(this._prefs);

  final SharedPreferences _prefs;
  static const _prefix = kDebugMode ? 'dev.usage.' : 'usage.';

  @override
  String? read(String key) => _prefs.getString('$_prefix$key');

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      await _prefs.remove('$_prefix$key');
    } else {
      await _prefs.setString('$_prefix$key', value);
    }
  }
}

/// Kept for this run only — when the settings store is unavailable, and in tests.
class MemoryUsageStore implements UsageStore {
  MemoryUsageStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  String? read(String key) => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}
