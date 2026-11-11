import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'advertiser.dart';
import 'sim_model.dart';
import '../core/error_log.dart';

enum SimState { stopped, starting, transmitting, failed }

/// Runs a simulation: builds the packets from the settings, transmits them, and changes the values
/// on their own schedule.
///
/// Android keeps the advertising interval in the radio and the data is updated in place. Windows
/// cannot set its advertising rate, so BluePulse sends a short burst every interval (one or two
/// advertisements at Windows' own rate); a profile with a scan response alternates the two packets
/// from burst to burst, since Windows sends no scan responses.
class SimulatorService extends ChangeNotifier {
  SimulatorService({required this.advertiser, this.prefs, Random? random}) : _rng = random ?? Random() {
    settings = _load();
    // Saved at once, so what a new version adds with a value made up on the spot (the simulator ID)
    // is the same at the next start, not only after the first change.
    unawaited(prefs?.setString(_key, jsonEncode(settings.toJson())));
    values = SimValues.from(settings);
    _errorSub = advertiser.errors.listen((e) {
      error = e;
      notifyListeners();
    });
  }

  final BleAdvertiser advertiser;
  final SharedPreferences? prefs;
  final Random _rng;
  static const _key = kDebugMode ? 'dev.simulator' : 'simulator';

  late SimSettings settings;
  late SimValues values;
  TxCapabilities? capabilities;

  SimState state = SimState.stopped;
  String? error;
  DateTime? startedAt;

  /// The name actually on air (Android reports it back after renaming).
  String? nameOnAir;

  /// Value changes sent since the start.
  int changes = 0;

  /// Windows: bursts sent since the start.
  int bursts = 0;

  /// The packets on air now.
  SimPayload? payload;

  Timer? _changeTimer;
  Timer? _burstTimer;
  Timer? _burstEnd;
  bool _burstScanResponse = false;
  StreamSubscription<String>? _errorSub;

  bool get running => state == SimState.transmitting || state == SimState.starting;
  bool get _bursts => !(capabilities?.exactInterval ?? false);

  /// The burst Windows sends every interval: half the interval, at most 500 ms. Windows is on air
  /// ~20 ms after Start (measured, 10-11-2026), but at 200 ms a burst held only one or two
  /// advertisements and a phone missed a third of them; a receiver still folds anything within
  /// 600 ms (readingGapMs, core/device.dart) into one ping, so 500 ms is as long as a burst can be.
  Duration get burstLength => Duration(milliseconds: min(500, max(60, settings.intervalMs ~/ 2)));

  /// The packets for the current settings and values, as this device's radio can send them.
  SimPayload build() => buildPayload(
        settings,
        values,
        sendsName: capabilities?.name ?? true,
        reservedBytes: capabilities?.reservedBytes ?? 0,
      );

  SimSettings _load() {
    try {
      final raw = prefs?.getString(_key);
      if (raw != null) return SimSettings.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (e) {
      // damaged: start from the defaults
      errorLog.warn('simulator', 'Saved simulator settings were damaged; starting from the defaults', error: e);
    }
    return SimSettings();
  }

  Future<void> refreshCapabilities() async {
    capabilities = await advertiser.capabilities();
    if (!running) payload = build();
    notifyListeners();
  }

  /// Changes settings; a running simulation picks them up (restarting when the radio must).
  Future<void> update(void Function(SimSettings s) change) async {
    final before = jsonEncode(_radioPart(settings));
    change(settings);
    unawaited(prefs?.setString(_key, jsonEncode(settings.toJson())));
    // Fixed values apply at once.
    final fresh = SimValues.from(settings)..seq = values.seq;
    if (!settings.autoTemperature) values.temperatureC = fresh.temperatureC;
    if (!settings.autoHumidity) values.humidity = fresh.humidity;
    if (!settings.autoBattery) values.batteryMv = fresh.batteryMv;
    if (!settings.autoMovement) {
      values.moving = fresh.moving;
      values.movementCount = fresh.movementCount;
    }
    if (!settings.autoAngles) {
      values.pitch = fresh.pitch;
      values.roll = fresh.roll;
    }
    if (!settings.autoMagnet) values.magnetDetected = fresh.magnetDetected;
    notifyListeners();
    if (!running) {
      payload = build();
      return;
    }
    if (jsonEncode(_radioPart(settings)) != before) {
      await start(); // interval, power, name or packet layout changed
    } else {
      _scheduleChanges();
      await _send();
    }
  }

  /// Settings the radio is started with; changing one means starting again.
  Map<String, Object?> _radioPart(SimSettings s) => {
        'profile': s.profile.name,
        'name': s.name,
        'intervalMs': s.intervalMs,
        'txPower': s.txPower.name,
        'sensorPacket': s.sensorPacket.name,
        'beaconFrame': s.beaconFrame.name,
        'simTag': s.simTag,
      };

  Future<void> start() async {
    // Android's start replaces a running set itself and keeps the simulated name; stopping first
    // would give the phone its own name back only to rename it again at once (which raced).
    await _halt(radio: !(capabilities?.exactInterval ?? false));
    error = null;
    state = SimState.starting;
    notifyListeners();
    try {
      final caps = capabilities = await advertiser.capabilities();
      if (!caps.supported) throw StateError(caps.reason ?? 'Transmitting is not supported here');
      if (!caps.permitted && !await advertiser.requestPermissions()) {
        throw StateError('Bluetooth advertise permission was refused');
      }
      final p = payload = build();
      final problem = p.problem;
      if (problem != null) throw StateError(problem);
      startedAt = DateTime.now();
      changes = 0;
      bursts = 0;
      if (_bursts) {
        await _burst();
        _burstTimer = Timer.periodic(Duration(milliseconds: settings.intervalMs), (_) => _burst());
      } else {
        nameOnAir = await advertiser.start(
          adv: p.adv,
          scanResponse: p.scanResponse,
          intervalMs: settings.intervalMs,
          txPowerDbm: caps.txPower ? settings.txPower.dbm : null,
          name: caps.name && settings.name.trim().isNotEmpty ? settings.name.trim() : null,
        );
      }
      state = SimState.transmitting;
      _scheduleChanges();
    } catch (e) {
      await _halt();
      state = SimState.failed;
      error = txFailure(e is StateError ? e.message : e);
      errorLog.warn('simulator', 'Transmitting did not start', error: error);
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _halt();
    state = SimState.stopped;
    notifyListeners();
  }

  /// Stops the timers and, unless a start replaces it at once ([radio] false), the transmission.
  Future<void> _halt({bool radio = true}) async {
    _changeTimer?.cancel();
    _burstTimer?.cancel();
    _burstEnd?.cancel();
    _changeTimer = _burstTimer = _burstEnd = null;
    if (radio && state != SimState.stopped) {
      try {
        await advertiser.stop();
      } catch (_) {
        // already stopped
      }
    }
    nameOnAir = null;
  }

  void _scheduleChanges() {
    _changeTimer?.cancel();
    final every = settings.changeEvery;
    if (every == null) return;
    _changeTimer = Timer.periodic(every, (_) {
      values.step(settings, _rng);
      changes++;
      unawaited(_send());
    });
  }

  /// Puts the current values on air.
  Future<void> _send() async {
    final p = payload = build();
    notifyListeners();
    if (_bursts || state != SimState.transmitting) return; // the next burst carries them
    try {
      await advertiser.update(adv: p.adv, scanResponse: p.scanResponse);
    } catch (e) {
      error = txFailure(e);
      errorLog.warn('simulator', 'New values were not put on air', error: error);
      notifyListeners();
    }
  }

  /// Windows: advertise for [burstLength], then fall silent until the next interval.
  Future<void> _burst() async {
    final p = payload ?? build();
    final packet = _burstScanResponse && p.scanResponse != null ? p.scanResponse! : p.adv;
    _burstScanResponse = !_burstScanResponse;
    try {
      await advertiser.start(
        adv: packet,
        intervalMs: settings.intervalMs,
        txPowerDbm: capabilities?.txPower ?? false ? settings.txPower.dbm : null,
      );
      bursts++;
      _burstEnd?.cancel();
      _burstEnd = Timer(burstLength, () => unawaited(advertiser.stop()));
    } catch (e) {
      error = txFailure(e is StateError ? e.message : e);
      errorLog.warn('simulator', 'A burst was not sent', error: error);
    }
    notifyListeners();
  }

  /// Advertising events expected on air since the start, at the set interval.
  int expectedEvents(DateTime now) =>
      startedAt == null ? 0 : now.difference(startedAt!).inMilliseconds ~/ settings.intervalMs + 1;

  @override
  void dispose() {
    _errorSub?.cancel();
    _changeTimer?.cancel();
    _burstTimer?.cancel();
    _burstEnd?.cancel();
    if (state != SimState.stopped) unawaited(advertiser.stop());
    super.dispose();
  }
}
