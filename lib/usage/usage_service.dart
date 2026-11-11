import 'dart:async';
import 'dart:math';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';

import '../update/update_service.dart';
import 'usage_config.dart';
import 'usage_device.dart';
import 'usage_model.dart';
import 'usage_store.dart';
import 'usage_transport.dart';

/// An app's own counters for one session — whatever that app wants to know about how it is used.
/// Measured each tick and sent as the session's `metrics`, under the app's own names, so the server
/// needs no change when an app counts something new.
abstract class UsageMetrics {
  /// Called each tick with the time since the last one (a long sleep already cut to one tick).
  void measure(Duration elapsed);

  /// The counters so far: JSON values only, small (the server keeps up to 4,000 characters).
  Map<String, Object?> toJson();
}

/// Reports who uses this copy and how: the install, each start of the app (a session), and events
/// such as updates and errors. Reports wait on the device until the server has them, so starts made
/// offline still count.
class UsageService extends ChangeNotifier {
  UsageService({
    required this.store,
    required UsageTransport this.transport,
    required this.endpoint,
    DateTime Function()? clock,
    Random? random,
  })  : enabled = true,
        disabledReason = null,
        _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  /// A service that never reports — for the web build, a build without a usage channel, and tests.
  UsageService.disabled({this.disabledReason})
      : enabled = false,
        endpoint = null,
        store = MemoryUsageStore(),
        transport = null,
        _clock = DateTime.now,
        _random = Random();

  final bool enabled;

  /// Why nothing is reported, in words; null when reporting is on.
  final String? disabledReason;

  /// Where reports go (shown in Settings).
  final Uri? endpoint;

  /// Where the install ID, name and unsent reports are kept.
  final UsageStore store;
  final UsageTransport? transport;
  final DateTime Function() _clock;
  final Random _random;

  InstallInfo? install;
  SessionRecord? session;
  Outbox _outbox = Outbox();
  DateTime? lastSent;
  DateTime? _lastAttempt;

  /// Why the last send failed; null after a success.
  String? error;
  bool sending = false;

  /// Sends that failed in a row; each one doubles the wait before the next try.
  int failures = 0;
  bool _again = false;

  /// The app's own counters; set by the app before [start].
  UsageMetrics? metrics;

  Timer? _timer;
  DateTime? _lastTick;
  bool _onScreen = true;
  bool _recording = false;
  bool _disposed = false;
  AppLifecycleListener? _lifecycle;
  UpdateService? _updates;
  UpdateStage? _lastUpdateStage;

  /// The person has not given a name yet: the app asks before anything else.
  bool get needsName => enabled && install != null && install!.name.trim().isEmpty;

  /// Reports on this device not yet sent, apart from the session that is open now.
  int get waiting => _outbox.events.length + _outbox.sessions.keys.where((id) => id != session?.id).length;

  DateTime _now() => _clock();

  /// Opens this run's session and sends the first report. Call once, before the UI starts. [app] names
  /// the application (`BluePulse`), as every report to the shared usage server must.
  Future<void> start({
    required String app,
    required String appVersion,
    required String build,
    required DeviceFacts facts,
    bool listenToLifecycle = true,
    bool timers = true,
  }) async {
    if (!enabled || session != null) return;
    final now = _now();
    var id = store.read('installId');
    final firstStart = !isUsageId(id);
    if (firstStart) {
      id = newUsageId(_random);
      await store.write('installId', id);
    }
    install = InstallInfo(
      id: id!,
      app: app,
      name: store.read('name') ?? '',
      login: facts.login,
      computer: facts.computer,
      platform: facts.platform,
      os: facts.os,
      device: facts.device,
      appVersion: appVersion,
      build: build,
      launcher: facts.launcher,
      timeZone: facts.timeZone,
    );
    _outbox = Outbox.decode(store.read('outbox'));
    lastSent = DateTime.tryParse(store.read('lastSent') ?? '');
    session = SessionRecord(id: newUsageId(_random), startedAt: now, appVersion: appVersion);
    _lastTick = now;

    if (firstStart) record('first_start');
    final previous = store.read('lastVersion');
    if (previous != null && previous != appVersion) record('version_changed', {'from': previous, 'to': appVersion});
    await store.write('lastVersion', appVersion);

    _outbox.putSession(session!);
    await _save();
    if (timers) _timer = Timer.periodic(UsageConfig.tick, (_) => tick());
    if (listenToLifecycle) {
      _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested, onStateChange: _onLifecycle);
    }
    _notify();
    unawaited(flush());
  }

  /// Measures the time since the last tick into the open session, saves it, and sends when due.
  void tick() {
    final s = session;
    if (!enabled || s == null || s.endedAt != null) return;
    _measure(s);
    _outbox.putSession(s);
    unawaited(_save());
    final last = _lastAttempt;
    if (last == null || _now().difference(last) >= retryEvery) unawaited(flush());
  }

  /// The gap before the next send: [UsageConfig.sendEvery], doubled for each failure in a row, at
  /// most [UsageConfig.retryAtMost].
  Duration get retryEvery {
    final d = UsageConfig.sendEvery * (1 << min(failures, 4));
    return d > UsageConfig.retryAtMost ? UsageConfig.retryAtMost : d;
  }

  void _measure(SessionRecord s) {
    final now = _now();
    var elapsed = now.difference(_lastTick ?? now);
    _lastTick = now;
    if (elapsed.isNegative) elapsed = Duration.zero;
    // A gap far longer than a tick is the computer asleep, not the app in use.
    if (elapsed > UsageConfig.tick * 2) elapsed = UsageConfig.tick;
    if (_onScreen) s.open += elapsed;
    final m = metrics;
    if (m != null) {
      m.measure(elapsed);
      s.metrics = m.toJson();
    }
    s.lastActiveAt = now;
  }

  /// A page was opened.
  void pageOpened(String page) {
    final s = session;
    if (!enabled || s == null) return;
    s.pages[page] = (s.pages[page] ?? 0) + 1;
  }

  /// Something happened. Kept on the device until sent. Never notifies listeners: it may be
  /// called while the UI is building (an error report).
  void record(String kind, [Map<String, Object?> data = const {}]) {
    final s = session;
    if (!enabled || s == null || _recording) return;
    _recording = true;
    try {
      _outbox.addEvent(UsageEvent(id: newUsageId(_random), sessionId: s.id, at: _now(), kind: kind, data: data));
      unawaited(_save());
    } finally {
      _recording = false;
    }
  }

  /// An error the app did not handle: counted always, reported in full for the first few.
  void recordError(Object error, StackTrace? stack) {
    final s = session;
    if (!enabled || s == null) return;
    s.errors++;
    if (s.errors > UsageConfig.maxErrorsPerSession) return;
    var message = '${error.runtimeType}: $error';
    if (message.length > 300) message = '${message.substring(0, 300)}…';
    final top = stack?.toString().split('\n').where((l) => l.trim().isNotEmpty).take(8).join('\n');
    record('error', {'message': message, if (top != null && top.isNotEmpty) 'stack': top});
  }

  /// Saves the person's name; it goes to the server in the background, so nobody waits for it.
  Future<void> setName(String name) async {
    final i = install;
    if (!enabled || i == null) return;
    final n = name.trim();
    install = i.withName(n);
    await _write('name', n);
    _notify();
    unawaited(flush());
  }

  /// Follows the release channel and records offers, downloads, installs and failures.
  void watchUpdates(UpdateService updates) {
    _updates?.removeListener(_onUpdate);
    _updates = updates..addListener(_onUpdate);
    _lastUpdateStage = updates.stage;
  }

  void _onUpdate() {
    final u = _updates!;
    if (u.stage == _lastUpdateStage) return;
    _lastUpdateStage = u.stage;
    final v = u.manifest?.version.toString();
    switch (u.stage) {
      case UpdateStage.available:
        record('update_offered', {'version': v, 'required': u.required});
      case UpdateStage.downloading:
        record('update_started', {'version': v});
      case UpdateStage.ready:
        record('update_installed', {'version': v});
      case UpdateStage.failed when u.manifest == null:
        record('update_check_failed', {'error': u.error});
      case UpdateStage.failed:
        record('update_failed', {'version': v, 'error': u.error});
      default:
        break;
    }
  }

  /// Sends everything waiting, in batches. Silent and never in the way: it runs in the background,
  /// gives up after [UsageConfig.sendTimeout] (or [timeout]), and whatever goes wrong — no network,
  /// the server down, an answer that makes no sense — the reports stay on this device for the next
  /// try. Only a report the server refuses outright is dropped, so it cannot block the rest. The
  /// server ignores a report it already has, so sending one twice is harmless.
  Future<void> flush({Duration? timeout}) async {
    final i = install;
    final t = transport;
    if (!enabled || i == null || t == null) return;
    if (sending) {
      _again = true; // e.g. a name typed while the start's report is on its way: send once more after
      return;
    }
    sending = true;
    _again = false;
    _lastAttempt = _now();
    var more = false;
    final sessions = Map.of(_outbox.sessions);
    final events = _outbox.events.take(UsageConfig.maxEventsPerSend).toList();
    try {
      final report = {'install': i.toJson(), 'sessions': sessions.values.toList(), 'events': events};
      await t.send(report).timeout(timeout ?? UsageConfig.sendTimeout);
      _outbox.acknowledge(sessions, events);
      lastSent = _now();
      error = null;
      failures = 0;
      more = _outbox.events.isNotEmpty && events.length == UsageConfig.maxEventsPerSend;
      await _write('lastSent', lastSent!.toUtc().toIso8601String());
    } on UsageSendException catch (e) {
      if (e.rejected) {
        _outbox.acknowledge(sessions, events);
        error = '${e.message} (report dropped)';
        failures = 0; // the server answered
      } else {
        error = e.message;
        failures++;
      }
    } on TimeoutException {
      error = 'Not sent in time; kept for the next try';
      failures++;
    } catch (e) {
      error = 'Not sent (${e.runtimeType}); kept for the next try';
      failures++;
    } finally {
      sending = false;
      await _save();
      _notify();
    }
    if (more || (_again && failures == 0)) await flush(timeout: timeout);
  }

  /// Closes the session (the app is exiting) and sends it, waiting a few seconds at most.
  Future<void> end() async {
    final s = session;
    if (!enabled || s == null || s.endedAt != null) return;
    _measure(s);
    s.endedAt = _now();
    _outbox.putSession(s);
    await _save();
    await flush(timeout: const Duration(seconds: 3));
  }

  Future<AppExitResponse> _onExitRequested() async {
    try {
      await end();
    } catch (_) {
      // Reporting never stops the app from closing.
    }
    return AppExitResponse.exit;
  }

  void _onLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        // Minimised, or in the background on a phone — which may be the last we hear of it.
        if (_onScreen) {
          tick();
          _onScreen = false;
          unawaited(flush());
        }
      case AppLifecycleState.resumed || AppLifecycleState.inactive:
        if (!_onScreen) {
          _lastTick = _now(); // time in the background is not time on screen
          _onScreen = true;
        }
      case AppLifecycleState.detached:
        unawaited(end());
    }
  }

  Future<void> _save() => _write('outbox', _outbox.encode());

  Future<void> _write(String key, String value) async {
    try {
      await store.write(key, value);
    } catch (_) {
      // The settings store failing must never take the app down; reports then last for this run.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _lifecycle?.dispose();
    _updates?.removeListener(_onUpdate);
    super.dispose();
  }
}
