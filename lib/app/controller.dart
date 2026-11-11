import 'dart:async';
import 'dart:io' show Directory, File, FileSystemException;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/gatt_link.dart';
import '../core/device.dart';
import '../core/device_book.dart';
import '../core/error_log.dart';
import '../core/registry.dart';
import '../core/sensor_log.dart';
import '../core/session_store.dart';
import '../scanner/demo_scanner.dart';
import '../scanner/scanner.dart';
import '../scanner/universal_ble_scanner.dart';
import '../scanner/windows_ble_scanner.dart';
import '../simulator/advertiser.dart';
import '../simulator/sim_service.dart';
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
    SimulatorService? simulator,
    GattLink? gattLink,
  })  : _live = liveScanner,
        gattLink = gattLink ?? UniversalBleLink(),
        updates = updates ?? UpdateService.disabled(),
        usage = usage ?? UsageService.disabled(),
        simulator = simulator ??
            SimulatorService(advertiser: UnsupportedAdvertiser('Transmitting works in the Windows and Android apps')) {
    this.updates.addListener(notifyListeners);
    this.usage.addListener(notifyListeners);
    // The background services stay silent; what goes wrong in them is written to the error log.
    this.updates.addListener(_logUpdates);
    this.usage.addListener(_logUsage);
    this.simulator.addListener(notifyListeners);
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
    } catch (e) {
      prefs = null; // settings then last for this run only
      errorLog.warn('settings', 'Settings could not be read; this run starts from the defaults', error: e);
    }
    final settings = AppSettings(prefs, liveScanSupported);
    var version = '—';
    try {
      version = (await PackageInfo.fromPlatform()).version; // from pubspec.yaml, via the build
    } catch (e) {
      errorLog.warn('app', 'The app version could not be read', error: e); // unknown rather than wrong
    }
    final build = kDebugMode ? 'debug' : (kProfileMode ? 'profile' : 'release');
    preferAppHome(settings.filesFolder);
    if (!kIsWeb) {
      try {
        await errorLog.open(await appHome(), header: 'BluePulse $version · $build · ${defaultTargetPlatform.name}');
      } catch (_) {
        // No documents folder: the log lasts for this run, in memory.
      }
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
      simulator: SimulatorService(advertiser: BleAdvertiser.forThisDevice(), prefs: prefs),
    );
    // Closing the window stops the scan first, so the session is saved whole rather than interrupted,
    // and stops transmitting (on Android that also gives the phone its Bluetooth name back).
    c._exitListener = AppLifecycleListener(onExitRequested: () async {
      await c.simulator.stop();
      await c.stopSensorLog();
      await c.stopScan();
      await errorLog.flush();
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
          build: build,
          facts: await readDeviceFacts(),
        );
      } catch (e) {
        // Reporting never stops the app from starting.
        errorLog.warn('usage', 'Usage reporting did not start', error: e);
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
    _paused = false;
    if (scanning) return;
    registry.startSession();
    _sub ??= scanner.events.listen(registry.ingest);
    await _startRecording();
    await scanner.start();
    if (!scanning) await _stopRecording(); // the radio refused: nothing to record
  }

  /// The multi-device log while one runs (Devices page → Log): every packet from the ticked devices.
  SensorLog? get sensorLog => registry.sensorLog;

  /// Logs every packet from [devices] to a CSV in the logs folder. One log at a time: a running one
  /// is saved first.
  Future<SensorLog> startSensorLog(List<EyeDevice> devices) async {
    await stopSensorLog();
    final dir = await appFilesDir('logs');
    final file = File(p.join(dir.path, SensorLog.fileName(devices.length, DateTime.now())));
    final log = registry.sensorLog = await SensorLog.start(file, macs: devices.map((d) => d.mac));
    notifyListeners();
    return log;
  }

  /// Saves and closes the running log; its files (one, or a part per million rows), empty when none
  /// was running.
  Future<List<File>> stopSensorLog() async {
    final log = registry.sensorLog;
    if (log == null) return const [];
    registry.sensorLog = null;
    final files = await log.stop();
    notifyListeners();
    return files;
  }

  /// Why the files folder cannot change right now (a log or a recording is writing to it); null
  /// when it can.
  String? get filesFolderBusy => sensorLog != null
      ? 'Stop the running log first'
      : (registry.recordings > 0 ? 'Stop the device recording first' : null);

  /// Saves BluePulse's files in [to] from now on — the default folder when null — and with
  /// [moveFiles] takes the files already saved along. A scan being recorded is closed and goes too;
  /// recording carries on in the new folder. Throws a [FileSystemException] when [to] cannot be
  /// used; nothing changes then.
  Future<FolderMove> changeFilesFolder(Directory? to, {required bool moveFiles}) async {
    final busy = filesFolderBusy;
    if (busy != null) throw StateError(busy);
    final target = to ?? await defaultAppHome();
    final wasRecording = registry.session != null;
    if (wasRecording) await _stopRecording();
    await errorLog.close();
    try {
      final result = await moveAppHome(target, moveFiles: moveFiles);
      appHomeIsDefault = to == null;
      sessions?.dir = await appFilesDir('sessions');
      settings.update((s) => s.filesFolder = to == null ? null : target.path);
      errorLog.info(
        'files',
        'Files folder changed from ${result.from.path} to ${target.path}'
            '${moveFiles ? ' · ${result.moved} moved${result.stayed > 0 ? ', ${result.stayed} stayed' : ''}' : ''}',
      );
      return result;
    } finally {
      await errorLog.open(appHomeNow ?? target);
      if (wasRecording && scanning) await _startRecording();
      sessionsRevision++;
      notifyListeners();
    }
  }

  /// Empties the device list and the packet list. A scan keeps running and what is still in range
  /// comes back as it is heard; the session being recorded and device recordings are not touched.
  void clearDevices() {
    registry.clear();
    if (scanning) registry.startSession();
    notifyListeners();
  }

  /// Configure pauses the radio while it is connected to a device: the scan stops, the session
  /// being recorded stays open, and [resumeScan] carries on into it.
  bool get paused => _paused;
  bool _paused = false;

  Future<void> pauseScan() async {
    if (!scanning) return;
    _paused = true;
    await scanner.stop();
    notifyListeners();
  }

  Future<void> resumeScan() async {
    if (!_paused) return;
    _paused = false;
    await scanner.start();
    notifyListeners();
  }

  Future<void> stopScan() async {
    _paused = false;
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
    } catch (e) {
      errorLog.warn('sessions', 'No folder for sessions: scans are not recorded this run', error: e);
      return null; // scanning still works, nothing is recorded
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
      errorLog.warn('sessions', sessionProblem!);
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
      } catch (e) {
        // the file stays as far as it was written
        errorLog.warn('sessions', 'The session did not close cleanly', error: e);
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
    final problem = status.error;
    if (problem != null && problem != _loggedScan) errorLog.warn('scanner', problem);
    _loggedScan = problem;
    if (!scanning && !_paused && registry.session != null) unawaited(_stopRecording());
    notifyListeners();
  }

  String? _loggedScan;
  UpdateStage? _loggedUpdate;
  String? _loggedUsage;

  /// Update failures and arrivals, once each.
  void _logUpdates() {
    final u = updates;
    if (u.stage == _loggedUpdate) return;
    _loggedUpdate = u.stage;
    final v = u.manifest?.version;
    switch (u.stage) {
      case UpdateStage.failed:
        errorLog.warn('update', u.updateAvailable ? 'Update to $v did not complete' : 'Update check failed', error: u.error);
      case UpdateStage.available:
        errorLog.info('update', 'Version $v is available');
      case UpdateStage.ready:
        errorLog.info('update', 'Version $v installed');
      default:
        break;
    }
  }

  /// A usage report that did not go out, once per reason (it waits on the device and goes later).
  void _logUsage() {
    final e = usage.error;
    if (e != null && e != _loggedUsage) errorLog.warn('usage', 'Usage report waiting for the next try', error: e);
    _loggedUsage = e;
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

  /// Transmits a simulated EYE device or beacon, to test receivers.
  final SimulatorService simulator;

  /// Connections to devices being configured (Configure page).
  final GattLink gattLink;

  @override
  void dispose() {
    _exitListener?.dispose();
    unawaited(sensorLog?.stop());
    simulator.removeListener(notifyListeners);
    simulator.dispose();
    settings.removeListener(_onSettings);
    registry.removeListener(notifyListeners);
    registry.book.removeListener(notifyListeners);
    // Usage first: it listens to the update service.
    usage.removeListener(notifyListeners);
    usage.removeListener(_logUsage);
    usage.dispose();
    updates.removeListener(notifyListeners);
    updates.removeListener(_logUpdates);
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
