import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'advertiser.dart';
import 'sim_model.dart';

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

  /// The burst Windows sends every interval: long enough for one or two advertisements.
  Duration get burstLength => Duration(milliseconds: min(200, max(60, settings.intervalMs ~/ 2)));

  SimSettings _load() {
    try {
      final raw = prefs?.getString(_key);
      if (raw != null) return SimSettings.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      // damaged: start from the defaults
    }
    return SimSettings();
  }

  Future<void> refreshCapabilities() async {
    capabilities = await advertiser.capabilities();
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
      payload = buildPayload(settings, values);
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
      };

  Future<void> start() async {
    await _halt();
    error = null;
    state = SimState.starting;
    notifyListeners();
    try {
      final caps = capabilities = await advertiser.capabilities();
      if (!caps.supported) throw StateError(caps.reason ?? 'Transmitting is not supported here');
      if (!caps.permitted && !await advertiser.requestPermissions()) {
        throw StateError('Bluetooth advertise permission was refused');
      }
      final p = payload = buildPayload(settings, values);
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
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _halt();
    state = SimState.stopped;
    notifyListeners();
  }

  Future<void> _halt() async {
    _changeTimer?.cancel();
    _burstTimer?.cancel();
    _burstEnd?.cancel();
    _changeTimer = _burstTimer = _burstEnd = null;
    if (state != SimState.stopped) {
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
    final p = payload = buildPayload(settings, values);
    notifyListeners();
    if (_bursts || state != SimState.transmitting) return; // the next burst carries them
    try {
      await advertiser.update(adv: p.adv, scanResponse: p.scanResponse);
    } catch (e) {
      error = txFailure(e);
      notifyListeners();
    }
  }

  /// Windows: advertise for [burstLength], then fall silent until the next interval.
  Future<void> _burst() async {
    final p = payload ?? buildPayload(settings, values);
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
