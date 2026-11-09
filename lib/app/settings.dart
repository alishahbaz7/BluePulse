import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeChoice { auto, light, dark }

enum ScanSource { live, demo }

/// User settings, persisted. Debug builds keep their own copy (key prefix `dev.`) so a development
/// run never changes the release app's settings.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs, this._liveSupported) {
    _load();
  }

  final SharedPreferences? _prefs;
  final bool _liveSupported;
  static const _prefix = kDebugMode ? 'dev.' : '';

  ThemeChoice themeChoice = ThemeChoice.dark;
  bool railFolded = false;
  ScanSource scanSource = ScanSource.live;

  /// Show every iBeacon / Eddystone device, not only Teltonika EYE devices.
  bool showAllBeacons = false;

  /// Time for the smoothed RSSI to reach a new level, as the tracker's *averaging timeout*.
  int averagingSeconds = 10;

  /// Proximity thresholds, dBm: at or above [nearDbm] is Near, at or above [awayDbm] is Away.
  int nearDbm = -65;
  int awayDbm = -85;

  /// Log-distance path-loss exponent for the distance estimate.
  double pathLossExponent = 2.5;

  /// Shortest silence before a device counts as not seen.
  int notSeenMinSeconds = 15;

  void _load() {
    final p = _prefs;
    if (p == null) {
      if (!_liveSupported) scanSource = ScanSource.demo;
      return;
    }
    themeChoice = ThemeChoice.values.elementAtOrNull(p.getInt('${_prefix}theme') ?? 2) ?? ThemeChoice.dark;
    railFolded = p.getBool('${_prefix}railFolded') ?? false;
    scanSource = ScanSource.values.elementAtOrNull(p.getInt('${_prefix}scanSource') ?? 0) ?? ScanSource.live;
    if (!_liveSupported) scanSource = ScanSource.demo;
    showAllBeacons = p.getBool('${_prefix}showAllBeacons') ?? false;
    averagingSeconds = p.getInt('${_prefix}averagingSeconds') ?? 10;
    nearDbm = p.getInt('${_prefix}nearDbm') ?? -65;
    awayDbm = p.getInt('${_prefix}awayDbm') ?? -85;
    pathLossExponent = p.getDouble('${_prefix}pathLossExponent') ?? 2.5;
    notSeenMinSeconds = p.getInt('${_prefix}notSeenMinSeconds') ?? 15;
  }

  bool get liveSupported => _liveSupported;

  void update(void Function(AppSettings s) change) {
    change(this);
    if (awayDbm > nearDbm) awayDbm = nearDbm;
    if (!_liveSupported) scanSource = ScanSource.demo;
    _save();
    notifyListeners();
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    p.setInt('${_prefix}theme', themeChoice.index);
    p.setBool('${_prefix}railFolded', railFolded);
    p.setInt('${_prefix}scanSource', scanSource.index);
    p.setBool('${_prefix}showAllBeacons', showAllBeacons);
    p.setInt('${_prefix}averagingSeconds', averagingSeconds);
    p.setInt('${_prefix}nearDbm', nearDbm);
    p.setInt('${_prefix}awayDbm', awayDbm);
    p.setDouble('${_prefix}pathLossExponent', pathLossExponent);
    p.setInt('${_prefix}notSeenMinSeconds', notSeenMinSeconds);
  }
}
