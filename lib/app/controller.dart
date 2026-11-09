import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/registry.dart';
import '../scanner/demo_scanner.dart';
import '../scanner/scanner.dart';
import '../scanner/universal_ble_scanner.dart';
import '../update/semver.dart';
import '../update/transport.dart';
import '../update/update_config.dart';
import '../update/update_host.dart';
import '../update/update_service.dart';
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
  })  : _live = liveScanner,
        updates = updates ?? UpdateService.disabled() {
    this.updates.addListener(notifyListeners);
    settings.addListener(_onSettings);
    // Pages depend on the controller alone, so registry updates reach them through it.
    registry.addListener(notifyListeners);
    _source = settings.scanSource;
    scanner.status.addListener(notifyListeners);
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
      registry: DeviceRegistry(settings),
      liveScanner: liveScanSupported ? UniversalBleScanner() : null,
      demoScanner: DemoScanner(),
    );
    unawaited(c.scanner.init());
    unawaited(c.updates.cleanup());
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

  final AppSettings settings;
  final DeviceRegistry registry;

  /// The app version, as the build reports it — pubspec.yaml is its only declaration.
  final String version;

  /// Release channel: check, download, install, restart.
  final UpdateService updates;
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
    await scanner.start();
  }

  Future<void> stopScan() async {
    await scanner.stop();
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> toggleScan() => scanning ? stopScan() : startScan();

  void _onSettings() {
    if (settings.scanSource != _source) unawaited(_switchSource(settings.scanSource));
    notifyListeners();
  }

  Future<void> _switchSource(ScanSource next) async {
    final wasScanning = scanning;
    await stopScan();
    scanner.status.removeListener(notifyListeners);
    _source = next;
    scanner.status.addListener(notifyListeners);
    registry.clear();
    await scanner.init();
    notifyListeners();
    if (wasScanning) await startScan();
  }

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    registry.removeListener(notifyListeners);
    updates.removeListener(notifyListeners);
    updates.dispose();
    scanner.status.removeListener(notifyListeners);
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
