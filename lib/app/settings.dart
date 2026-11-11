import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeChoice { auto, light, dark }

enum ScanSource { live, demo }

/// How lists of devices are shown on a wide screen: tiles (as on a phone) or a table.
enum DeviceView { tiles, list }

/// The order of device tiles (a table sorts by its headers). [found]: the order the app first heard
/// them — a new device joins at the bottom and nothing moves.
enum DeviceSort { found, name, signal, battery, lastSeen }

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

  /// Save every live scan as a session, from Start scan to Stop scan.
  bool recordSessions = true;

  /// Time for the smoothed RSSI to reach a new level, as the tracker's *averaging timeout*.
  int averagingSeconds = 10;

  /// Proximity thresholds, dBm: at or above [nearDbm] is Near, at or above [awayDbm] is Away.
  int nearDbm = -65;
  int awayDbm = -85;

  /// Log-distance path-loss exponent for the distance estimate.
  double pathLossExponent = 2.5;

  /// Shortest silence before a device counts as not seen.
  int notSeenMinSeconds = 15;

  /// The folder the person chose for BluePulse's files; null for the default (`lib/app/paths.dart`).
  String? filesFolder;

  /// Tiles or a table, the same on every page that lists devices (a phone always shows tiles).
  DeviceView deviceView = DeviceView.list;

  /// The order of device tiles, the same on every page that shows them.
  DeviceSort deviceSort = DeviceSort.found;

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
    recordSessions = p.getBool('${_prefix}recordSessions') ?? true;
    averagingSeconds = p.getInt('${_prefix}averagingSeconds') ?? 10;
    nearDbm = p.getInt('${_prefix}nearDbm') ?? -65;
    awayDbm = p.getInt('${_prefix}awayDbm') ?? -85;
    pathLossExponent = p.getDouble('${_prefix}pathLossExponent') ?? 2.5;
    notSeenMinSeconds = p.getInt('${_prefix}notSeenMinSeconds') ?? 15;
    filesFolder = p.getString('${_prefix}filesFolder');
    deviceView = DeviceView.values.elementAtOrNull(p.getInt('${_prefix}deviceView') ?? 1) ?? DeviceView.list;
    deviceSort = DeviceSort.values.elementAtOrNull(p.getInt('${_prefix}deviceSort') ?? 0) ?? DeviceSort.found;
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
    p.setBool('${_prefix}recordSessions', recordSessions);
    p.setInt('${_prefix}averagingSeconds', averagingSeconds);
    p.setInt('${_prefix}nearDbm', nearDbm);
    p.setInt('${_prefix}awayDbm', awayDbm);
    p.setDouble('${_prefix}pathLossExponent', pathLossExponent);
    p.setInt('${_prefix}notSeenMinSeconds', notSeenMinSeconds);
    p.setInt('${_prefix}deviceView', deviceView.index);
    p.setInt('${_prefix}deviceSort', deviceSort.index);
    final folder = filesFolder;
    folder == null ? p.remove('${_prefix}filesFolder') : p.setString('${_prefix}filesFolder', folder);
  }
}
