import 'dart:async';
import 'dart:io' show FileSystemException;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/device_book.dart';
import '../core/registry.dart';
import '../core/session_store.dart';
import '../scanner/demo_scanner.dart';
import '../scanner/scanner.dart';
import '../scanner/universal_ble_scanner.dart';
import '../scanner/windows_ble_scanner.dart';
import '../update/semver.dart';
import '../update/transport.dart';
import '../update/update_config.dart';
import '../update/update_host.dart';
import '../update/update_service.dart';
import '../usage/usage_config.dart';
import '../usage/usage_device.dart';
import '../usage/usage_service.dart';
import '../usage/usage_store.dart';
import '../usage/usage_transport.dart';
import 'paths.dart';
import 'scan_metrics.dart';
import 'settings.dart';

/// Live scanning exists on the platforms this app ships for. The web build is for demos and
/// screenshots only — browsers cannot scan advertisements in the background.
bool get liveScanSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.android);

/// Owns the settings, the registry and the scanners, and wires one scanner to the registry.
class AppController extends ChangeNotifier {
  AppController({
    required this.settings,
    required this.registry,
    required BeaconScanner? liveScanner,
    required this.demoScanner,
    this.version = '—',
    UpdateService? updates,
    UsageService? usage,
    this.sessions,
  })  : _live = liveScanner,
        updates = updates ?? UpdateService.disabled(),
        usage = usage ?? UsageService.disabled() {
    this.updates.addListener(notifyListeners);
    this.usage.addListener(notifyListeners);
    settings.addListener(_onSettings);
    // Pages depend on the controller alone, so registry and device-book updates reach them through it.
    registry.addListener(notifyListeners);
    registry.book.addListener(notifyListeners);
    _source = settings.scanSource;
    _recordSessions = settings.recordSessions;
    scanner.status.addListener(_onStatus);
  }

  static Future<AppController> create() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null; // settings then last for this run only
    }
    final settings = AppSettings(prefs, liveScanSupported);
    var version = '—';
    try {
      version = (await PackageInfo.fromPlatform()).version; // from pubspec.yaml, via the build
    } catch (_) {
      // Unknown rather than wrong.
    }
    final c = AppController(
      version: version,
      updates: _updateService(version),
      settings: settings,
      registry: DeviceRegistry(settings, book: DeviceBook(prefs)),
      liveScanner: !liveScanSupported
          ? null
          : (defaultTargetPlatform == TargetPlatform.windows ? WindowsBleScanner() : UniversalBleScanner()),
      demoScanner: DemoScanner(),
      usage: _usageService(prefs, version),
      sessions: await _sessionStore(),
    );
    // Closing the window stops the scan first, so the session is saved whole rather than interrupted.
    c._exitListener = AppLifecycleListener(onExitRequested: () async {
      await c.stopScan();
      return AppExitResponse.exit;
    });
    unawaited(c.scanner.init());
    unawaited(c.updates.cleanup());
    // Usage first, so the update check below is recorded in this start's session.
    if (c.usage.enabled) {
      c.usage.metrics = ScanMetrics(() => ScanSample(
            scanning: c.scanning,
            demo: c.isDemo,
            bluetooth: c.status.radio.name,
            devices: c.registry.devices.map((d) => d.mac),
            totalPackets: c.registry.totalPackets,
          ));
      c.usage.watchUpdates(c.updates);
      try {
        await c.usage.start(
          app: UpdateConfig.appName,
          appVersion: version,
          build: kDebugMode ? 'debug' : (kProfileMode ? 'profile' : 'release'),
          facts: await readDeviceFacts(),
        );
      } catch (_) {
        // Reporting never stops the app from starting.
      }
    }
    // Every start checks the release channel; development runs only when pointed at a test channel.
    if (!kDebugMode || UpdateConfig.manifestOverride.isNotEmpty) unawaited(c.updates.check());
    return c;
  }

  static UpdateService _updateService(String version) {
    final current = SemVer.tryParse(version);
    if (kIsWeb) return UpdateService.disabled(current: current, disabledReason: 'Updates apply to the Windows and Android apps');
    if (!UpdateConfig.configured) {
      return UpdateService.disabled(current: current, disabledReason: 'The releases repository is not set in this build');
    }
    return UpdateService(
      current: current,
      host: IoUpdateHost.forThisDevice(),
      transport: HttpUpdateTransport(userAgent: '${UpdateConfig.appName}/$version'),
    );
  }

  static UsageService _usageService(SharedPreferences? prefs, String version) {
    if (kIsWeb) return UsageService.disabled(disabledReason: 'Usage reporting applies to the Windows and Android apps');
    if (!UsageConfig.configured) return UsageService.disabled(disabledReason: 'Usage reporting is not set in this build');
    if (kDebugMode && !UsageConfig.passedAtBuild) {
      return UsageService.disabled(disabledReason: 'Development runs do not report usage (pass USAGE_URL to test it)');
    }
    final url = Uri.parse(UsageConfig.url);
    return UsageService(
      store: prefs == null ? MemoryUsageStore() : PrefsUsageStore(prefs),
      transport: HttpUsageTransport(url: url, key: UsageConfig.key, userAgent: '${UpdateConfig.appName}/$version'),
      endpoint: url,
    );
  }

  final AppSettings settings;
  final DeviceRegistry registry;

  /// Tags and focus, kept on this computer.
  DeviceBook get book => registry.book;

  /// The app version, as the build reports it — pubspec.yaml is its only declaration.
  final String version;

  /// Release channel: check, download, install, restart.
  final UpdateService updates;

  /// Who uses this copy and how: reported to the usage channel.
  final UsageService usage;
  final BeaconScanner? _live;
  final BeaconScanner demoScanner;
  late ScanSource _source;
  StreamSubscription<ScanEvent>? _sub;

  BeaconScanner get scanner => _source == ScanSource.live && _live != null ? _live : demoScanner;
  ScannerStatus get status => scanner.status.value;
  bool get scanning => status.scanning;
  bool get isDemo => scanner.isDemo;

  Future<void> startScan() async {
    if (scanning) return;
    registry.startSession();
    _sub ??= scanner.events.listen(registry.ingest);
    await _startRecording();
    await scanner.start();
    if (!scanning) await _stopRecording(); // the radio refused: nothing to record
  }

  Future<void> stopScan() async {
    await scanner.stop();
    await _sub?.cancel();
    _sub = null;
    await _stopRecording();
  }

  Future<void> toggleScan() => scanning ? stopScan() : startScan();

  // Sessions: every live scan saved from Start to Stop.

  /// Recorded sessions; null where nothing is recorded (the web build, tests without a folder).
  final SessionStore? sessions;

  /// Bumped when a session starts, stops or is deleted, so the Sessions page reloads its list.
  int sessionsRevision = 0;

  /// Why the last scan was not recorded, when it failed.
  String? sessionProblem;

  /// The session being recorded now.
  SessionWriter? get recording => registry.session;

  late bool _recordSessions;

  static Future<SessionStore?> _sessionStore() async {
    if (!liveScanSupported) return null;
    try {
      return SessionStore(await appFilesDir('sessions'));
    } catch (_) {
      return null; // no documents folder: scanning still works, nothing is recorded
    }
  }

  Future<void> _startRecording() async {
    final store = sessions;
    if (store == null || !settings.recordSessions || isDemo || registry.session != null) return;
    try {
      registry.session = await store.start(platform: defaultTargetPlatform.name, version: version);
      sessionProblem = null;
    } catch (e) {
      sessionProblem = 'This scan is not being recorded: ${e is FileSystemException ? e.osError?.message ?? e.message : e}';
    }
    sessionsRevision++;
    notifyListeners();
  }

  /// Closes the session; one that caught nothing is not kept. Stopping the radio also ends it (via
  /// [_onStatus]), so a second caller waits for the close already under way.
  Future<void> _stopRecording() {
    final s = registry.session;
    if (s == null) return _closing ?? Future<void>.value();
    registry.session = null;
    return _closing = () async {
      try {
        final info = await s.stop();
        if (s.packets == 0) await sessions?.delete(info);
      } catch (_) {
        // the file stays as far as it was written
      } finally {
        _closing = null;
        sessionsRevision++;
        notifyListeners();
      }
    }();
  }

  Future<void>? _closing;
  AppLifecycleListener? _exitListener;

  Future<void> deleteSession(SessionInfo s) async {
    if (registry.session?.csv.path == s.csv.path) return;
    await sessions?.delete(s);
    sessionsRevision++;
    notifyListeners();
  }

  /// The radio stopped on its own (Bluetooth turned off): the session ends with it.
  void _onStatus() {
    if (!scanning && registry.session != null) unawaited(_stopRecording());
    notifyListeners();
  }

  void _onSettings() {
    if (settings.scanSource != _source) unawaited(_switchSource(settings.scanSource));
    if (settings.recordSessions != _recordSessions) {
      _recordSessions = settings.recordSessions;
      unawaited(_recordSessions ? (scanning ? _startRecording() : Future<void>.value()) : _stopRecording());
    }
    notifyListeners();
  }

  Future<void> _switchSource(ScanSource next) async {
    final wasScanning = scanning;
    await stopScan();
    scanner.status.removeListener(_onStatus);
    _source = next;
    scanner.status.addListener(_onStatus);
    registry.clear();
    await scanner.init();
    notifyListeners();
    if (wasScanning) await startScan();
  }

  @override
  void dispose() {
    _exitListener?.dispose();
    settings.removeListener(_onSettings);
    registry.removeListener(notifyListeners);
    registry.book.removeListener(notifyListeners);
    // Usage first: it listens to the update service.
    usage.removeListener(notifyListeners);
    usage.dispose();
    updates.removeListener(notifyListeners);
    updates.dispose();
    scanner.status.removeListener(_onStatus);
    _sub?.cancel();
    _live?.dispose();
    demoScanner.dispose();
    registry.dispose();
    super.dispose();
  }
}

/// Makes the controller reachable from any widget and rebuilds dependents when it notifies.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Without subscribing to rebuilds — for event handlers.
  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
