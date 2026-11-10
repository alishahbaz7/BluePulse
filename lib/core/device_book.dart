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
  final _layouts = <String, List<ChartSlot>>{};
  int _windowMinutes = 10;

  // The device page: one time window for every chart and the ping figures, and the chart layout
  // per device kind.
  static const windowChoices = [5, 10, 15];
  int get windowMinutes => _windowMinutes;

  void setWindowMinutes(int m) {
    if (!windowChoices.contains(m) || m == _windowMinutes) return;
    _windowMinutes = m;
    _save();
    notifyListeners();
  }

  /// The charts in the order chosen for [kind], with any chart added since appended.
  List<ChartSlot> chartLayout(String kind) {
    final saved = _layouts[kind];
    if (saved == null) return ChartSlot.defaults;
    final ids = saved.map((s) => s.id).toSet();
    return [
      ...saved.where((s) => ChartSlot.known.contains(s.id)),
      ...ChartSlot.defaults.where((s) => !ids.contains(s.id)),
    ];
  }

  void setChartLayout(String kind, List<ChartSlot> slots) {
    _layouts[kind] = List.unmodifiable(slots);
    _save();
    notifyListeners();
  }

  void resetChartLayout(String kind) {
    if (_layouts.remove(kind) == null) return;
    _save();
    notifyListeners();
  }

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
    final w = p.getInt('${_prefix}detailWindow');
    if (w != null && windowChoices.contains(w)) _windowMinutes = w;
    try {
      final raw = p.getString('${_prefix}chartLayouts');
      if (raw != null) {
        final m = jsonDecode(raw);
        if (m is Map) {
          m.forEach((kind, list) {
            if (kind is String && list is List) {
              _layouts[kind] = [for (final e in list) ?ChartSlot.fromJson(e)];
            }
          });
        }
      }
    } catch (_) {
      // A damaged layout falls back to the default.
    }
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    p.setString('${_prefix}tags', jsonEncode(_tags));
    p.setStringList('${_prefix}focus', _focus.toList());
    p.setInt('${_prefix}detailWindow', _windowMinutes);
    p.setString('${_prefix}chartLayouts',
        jsonEncode({for (final e in _layouts.entries) e.key: [for (final s in e.value) s.toJson()]}));
  }
}

/// One chart on the device page: shown or hidden, half or full width.
class ChartSlot {
  const ChartSlot(this.id, {this.visible = true, this.full = false});

  final String id;
  final bool visible;
  final bool full;

  static const signal = 'signal';
  static const battery = 'battery';
  static const temperature = 'temperature';
  static const humidity = 'humidity';
  static const movement = 'movement';
  static const angles = 'angles';
  static const known = {signal, battery, temperature, humidity, movement, angles};

  static const defaults = [
    ChartSlot(signal, full: true),
    ChartSlot(battery),
    ChartSlot(temperature),
    ChartSlot(humidity),
    ChartSlot(movement),
    ChartSlot(angles),
  ];

  static String title(String id) => switch (id) {
        signal => 'Signal',
        battery => 'Battery',
        temperature => 'Temperature',
        humidity => 'Humidity',
        movement => 'Movement count',
        angles => 'Angles',
        _ => id,
      };

  ChartSlot copyWith({bool? visible, bool? full}) =>
      ChartSlot(id, visible: visible ?? this.visible, full: full ?? this.full);

  Map<String, Object> toJson() => {'id': id, 'visible': visible, 'full': full};

  static ChartSlot? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return ChartSlot(j['id'] as String, visible: j['visible'] != false, full: j['full'] == true);
  }
}
