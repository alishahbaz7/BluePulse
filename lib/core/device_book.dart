import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the person knows about devices, kept on this computer: their own names for them (tags) and
/// which devices are in focus. Debug builds keep their own copy, like the settings.
///
/// Focus: devices in focus get every packet and the fastest screen refresh; the rest refresh slowly.
/// Opening a device's page focuses it for as long as the page is open ([temporaryFocus]).
class DeviceBook extends ChangeNotifier {
  DeviceBook(this._prefs) {
    _load();
  }

  final SharedPreferences? _prefs;
  static const _prefix = kDebugMode ? 'dev.' : '';
  static const maxTagLength = 40;

  final _tags = <String, String>{};
  final _focus = <String>{};
  String? _temporary;

  // Tags.
  String? tagOf(String mac) => _tags[mac];
  Map<String, String> get tags => Map.unmodifiable(_tags);

  void setTag(String mac, String? tag) {
    final t = (tag ?? '').trim();
    if (t.isEmpty) {
      if (_tags.remove(mac) == null) return;
    } else {
      final clipped = t.length > maxTagLength ? t.substring(0, maxTagLength) : t;
      if (_tags[mac] == clipped) return;
      _tags[mac] = clipped;
    }
    _save();
    notifyListeners();
  }

  // Focus.
  Set<String> get focus => Set.unmodifiable(_focus);
  String? get temporaryFocus => _temporary;
  bool get focusActive => _focus.isNotEmpty || _temporary != null;
  bool inFocus(String mac) => _focus.contains(mac) || _temporary == mac;
  bool pinned(String mac) => _focus.contains(mac);

  /// Full speed for this device: everything when nothing is in focus, otherwise focused devices only.
  bool fast(String mac) => !focusActive || inFocus(mac);

  void toggleFocus(String mac) {
    if (!_focus.remove(mac)) _focus.add(mac);
    _save();
    notifyListeners();
  }

  void setFocus(Iterable<String> macs) {
    _focus
      ..clear()
      ..addAll(macs);
    _save();
    notifyListeners();
  }

  void clearFocus() {
    if (_focus.isEmpty) return;
    _focus.clear();
    _save();
    notifyListeners();
  }

  void setTemporaryFocus(String? mac) {
    if (_temporary == mac) return;
    _temporary = mac;
    notifyListeners();
  }

  void _load() {
    final p = _prefs;
    if (p == null) return;
    try {
      final raw = p.getString('${_prefix}tags');
      if (raw != null) {
        final m = jsonDecode(raw);
        if (m is Map) {
          m.forEach((k, v) {
            if (k is String && v is String && v.trim().isNotEmpty) _tags[k] = v;
          });
        }
      }
    } catch (_) {
      // A damaged entry is dropped rather than stopping the app.
    }
    _focus.addAll(p.getStringList('${_prefix}focus') ?? const []);
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    p.setString('${_prefix}tags', jsonEncode(_tags));
    p.setStringList('${_prefix}focus', _focus.toList());
  }
}
