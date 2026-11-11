import 'dart:async';

import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/foundation.dart';

import 'gatt_link.dart';
import '../core/error_log.dart';

enum ConfigState { idle, connecting, unlocking, reading, ready, saving, saved, failed }

/// Who the device says it is, read once connected.
@immutable
class EyeDeviceInfo {
  const EyeDeviceInfo({this.model, this.firmware, this.hardware, this.manufacturer, this.mac});

  final String? model;
  final String? firmware;
  final String? hardware;
  final String? manufacturer;
  final String? mac;
}

/// One configuration session with one EYE device: connect, unlock with the PIN, read every setting,
/// let the person change them, write only what changed, read each back to make sure it took, and
/// save to flash — the way Teltonika's EYE App does it, without its extra writes. While connected
/// the live values are read every few seconds (the EYE App does the same), which also keeps the
/// device from dropping the connection.
class ConfigSession extends ChangeNotifier {
  ConfigSession({required this.link, required this.mac, this.livePeriod = const Duration(seconds: 5)});

  final GattLink link;
  final String mac;
  final Duration livePeriod;

  ConfigState state = ConfigState.idle;

  /// What went wrong, in a sentence; set with [ConfigState.failed].
  String? error;

  /// The PIN was refused: nothing was read, and trying again costs another attempt.
  bool wrongPin = false;

  /// Wrong PINs counted by the device before this session (its password counter).
  int? failedAttempts;

  EyeDeviceInfo info = const EyeDeviceInfo();

  /// The values as read from the device.
  final Map<EyeSetting, Object> original = {};

  /// The values as the person has set them.
  final Map<EyeSetting, Object> edited = {};

  /// Settings this device does not have (no such characteristic, or refused even when unlocked).
  final Set<EyeSetting> unsupported = {};

  /// The device's own reading, refreshed while connected.
  TeltonikaData? live;
  DateTime? liveAt;

  /// What the last save did: settings written and confirmed, and those that did not take.
  List<EyeSetting> savedSettings = const [];
  Map<EyeSetting, String> saveErrors = const {};

  Timer? _liveTimer;
  StreamSubscription<bool>? _connSub;
  bool _closed = false;

  bool get busy => switch (state) {
        ConfigState.connecting || ConfigState.unlocking || ConfigState.reading || ConfigState.saving => true,
        _ => false,
      };
  bool get connected => state == ConfigState.ready || state == ConfigState.saving || state == ConfigState.saved;

  /// Settings whose edited value differs from the device's.
  List<EyeSetting> get changes => [
        for (final s in EyeSetting.values)
          if (edited.containsKey(s) && !_same(edited[s], original[s])) s,
      ];

  /// Why the edited values cannot be saved, per setting.
  Map<EyeSetting, String> get problems {
    final out = <EyeSetting, String>{};
    for (final s in changes) {
      final p = s.problem(edited[s]!);
      if (p != null) out[s] = p;
    }
    return out;
  }

  static bool _same(Object? a, Object? b) {
    if (a is List<int> && b is List<int>) return listEquals(a, b);
    return a == b;
  }

  void _set(ConfigState s, {String? fail}) {
    state = s;
    error = fail;
    if (!_closed) notifyListeners();
  }

  /// Connects, unlocks with [pin] and reads everything.
  Future<void> open(String pin) async {
    final pinBytes = encodePin(pin); // throws before anything is sent
    wrongPin = false;
    _set(ConfigState.connecting);
    try {
      // Android often loses a first connection before the services are known; trying once more
      // then costs nothing — the PIN has not been sent.
      for (var attempt = 1;; attempt++) {
        try {
          await link.connect(mac);
          await link.discover(mac);
          break;
        } catch (e) {
          await link.disconnect(mac);
          if (attempt >= 2) rethrow;
          errorLog.warn('config', 'Connecting to $mac failed; trying once more', error: e);
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
      }
      await link.negotiateMtu(mac);
      if (link.settle > Duration.zero) await Future<void>.delayed(link.settle);
      _connSub ??= link.connection(mac).listen((up) {
        if (!up && connected) {
          _stopLive();
          _set(ConfigState.failed, fail: 'The device closed the connection');
        }
      });
      try {
        final c = await link.read(mac, EyeGatt.service, EyeGatt.passwordCounter);
        failedAttempts = c.isEmpty ? null : c[0];
      } catch (_) {
        failedAttempts = null;
      }

      _set(ConfigState.unlocking);
      await link.write(mac, EyeGatt.service, EyeGatt.password, pinBytes);
      // A wrong PIN is accepted as a write and shows only when the settings stay unreadable.
      try {
        original[EyeSetting.protocolType] = EyeSetting.protocolType.decode(
          await link.read(mac, EyeSetting.protocolType.service, EyeSetting.protocolType.characteristic),
        );
      } catch (_) {
        wrongPin = true;
        errorLog.info('config', 'Wrong PIN for $mac');
        await link.disconnect(mac);
        _set(ConfigState.failed, fail: 'Wrong PIN: the device refused to show its settings');
        return;
      }

      _set(ConfigState.reading);
      info = EyeDeviceInfo(
        model: await _text(EyeGatt.deviceInfo, EyeGatt.model),
        firmware: await _text(EyeGatt.deviceInfo, EyeGatt.firmware),
        hardware: await _text(EyeGatt.deviceInfo, EyeGatt.hardware),
        manufacturer: await _text(EyeGatt.deviceInfo, EyeGatt.manufacturer),
        mac: await _macText(),
      );
      for (final s in EyeSetting.values) {
        if (s == EyeSetting.protocolType) continue;
        if (s == EyeSetting.sensors && info.firmware != null && !hasSensorSwitches(info.firmware!)) {
          unsupported.add(s);
          continue;
        }
        try {
          original[s] = s.decode(await link.read(mac, s.service, s.characteristic));
        } catch (_) {
          unsupported.add(s);
        }
      }
      edited
        ..clear()
        ..addAll(original);
      await _readLive();
      _liveTimer = Timer.periodic(livePeriod, (_) => _readLive());
      _set(ConfigState.ready);
    } catch (e) {
      _stopLive();
      await link.disconnect(mac);
      errorLog.warn('config', 'Could not connect to $mac', error: e);
      _set(ConfigState.failed, fail: 'Could not connect: ${_short(e)}');
    }
  }

  /// Sets one value (nothing is sent until [save]).
  void edit(EyeSetting s, Object value) {
    edited[s] = value;
    if (state == ConfigState.saved) state = ConfigState.ready;
    notifyListeners();
  }

  void discard() {
    edited
      ..clear()
      ..addAll(original);
    notifyListeners();
  }

  /// Writes what changed, reads each back, and saves to flash when all took. Returns true when
  /// everything changed was confirmed and saved.
  Future<bool> save() async {
    final todo = changes;
    if (todo.isEmpty || problems.isNotEmpty || !connected) return false;
    _set(ConfigState.saving);
    final done = <EyeSetting>[];
    final errors = <EyeSetting, String>{};
    for (final s in todo) {
      try {
        await link.write(mac, s.service, s.characteristic, s.encode(edited[s]!));
        final back = s.decode(await link.read(mac, s.service, s.characteristic));
        if (_same(back, edited[s])) {
          done.add(s);
          original[s] = back;
        } else {
          errors[s] = 'the device kept ${s.show(back)}';
        }
      } catch (e) {
        errors[s] = _short(e);
        errorLog.warn('config', '${s.name} not saved on $mac', error: e);
      }
    }
    if (done.isNotEmpty) {
      try {
        await link.write(mac, EyeGatt.service, EyeGatt.command, EyeCommand.writeToFlash.bytes);
      } catch (e) {
        errors[EyeSetting.values.first] = 'not saved to flash: ${_short(e)}';
        errorLog.warn('config', 'Settings not written to flash on $mac', error: e);
      }
    }
    savedSettings = done;
    saveErrors = errors;
    _set(errors.isEmpty ? ConfigState.saved : ConfigState.ready);
    return errors.isEmpty;
  }

  /// Sends a command: reset, restore defaults.
  Future<void> command(EyeCommand c) => link.write(mac, EyeGatt.service, EyeGatt.command, c.bytes);

  Future<void> _readLive() async {
    try {
      final t = decodeTeltonika(await link.read(mac, EyeGatt.liveService, EyeGatt.live));
      if (t.ok) {
        live = t;
        liveAt = DateTime.now();
        if (!_closed) notifyListeners();
      }
    } catch (_) {
      // A beacon has no live block; a missed read is not worth a message.
    }
  }

  Future<String?> _text(String service, String characteristic) async {
    try {
      final raw = await link.read(mac, service, characteristic);
      final s = String.fromCharCodes(raw.takeWhile((b) => b != 0)).trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _macText() async {
    try {
      final raw = await link.read(mac, EyeGatt.deviceInfo, EyeGatt.mac);
      if (raw.length != 6) return null;
      return [for (final b in raw) b.toRadixString(16).padLeft(2, '0')].join(':').toUpperCase();
    } catch (_) {
      return null;
    }
  }

  void _stopLive() {
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  /// Disconnects; the session cannot be used again.
  Future<void> close() async {
    _stopLive();
    await _connSub?.cancel();
    _connSub = null;
    if (state != ConfigState.idle) await link.disconnect(mac);
    _closed = true;
  }

  @override
  void dispose() {
    _stopLive();
    _connSub?.cancel();
    _closed = true;
    super.dispose();
  }

  static String _short(Object e) {
    final s = e.toString().split('\n').first;
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}

/// Hex text to bytes, for the ID fields; null when it is not whole bytes of hex.
Uint8List? hexOrNull(String text) {
  final clean = text.replaceAll(RegExp(r'[\s:-]'), '');
  if (clean.isEmpty || clean.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean)) return null;
  return parseHex(clean);
}
