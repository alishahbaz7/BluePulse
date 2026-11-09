import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'installer.dart';
import 'manifest.dart';
import 'semver.dart';
import 'transport.dart';
import 'update_config.dart';
import 'update_host.dart';

enum UpdateStage {
  /// Updating does not apply here (web, development run without a channel, no version known).
  disabled,
  idle,
  checking,
  upToDate,
  available,
  downloading,
  installing,

  /// Windows: installed, restart to use it. Android: the system installer is open.
  ready,
  failed,
}

/// Checks the release channel, downloads and verifies the package, installs it.
///
/// Windows installs into the launcher's `versions` folder and restarts through the launcher; Android
/// hands the APK to the system installer. Nothing is installed unless the SHA-256 matches
/// `latest.json`.
class UpdateService extends ChangeNotifier {
  UpdateService({
    required this.current,
    required this.host,
    required this.transport,
    Uri? manifestUrl,
  })  : manifestUrl = manifestUrl ?? UpdateConfig.manifestUrl,
        disabledReason = current == null
            ? 'The app version is unknown'
            : (host == null ? 'Updates apply to the Windows and Android apps' : null) {
    stage = disabledReason != null ? UpdateStage.disabled : UpdateStage.idle;
  }

  /// A service that never checks — for the web build, an unset channel, and tests.
  UpdateService.disabled({this.disabledReason, this.current})
      : host = null,
        transport = null,
        manifestUrl = Uri() {
    stage = UpdateStage.disabled;
  }

  /// Why updating does not apply here, in words; null when it does.
  final String? disabledReason;

  final SemVer? current;
  final UpdateHost? host;
  final UpdateTransport? transport;
  final Uri manifestUrl;

  late UpdateStage stage;
  UpdateManifest? manifest;
  String? error;
  DateTime? lastChecked;
  int received = 0;
  int? total;
  bool launcherUpdated = false;
  bool _cancel = false;

  /// The startup prompt is shown once per run.
  bool promptShown = false;

  UpdatePlatform? get platform => host?.platform;
  UpdateAsset? get asset => platform == null ? null : manifest?.assets[platform!];

  bool get updateAvailable => manifest != null && current != null && manifest!.isNewerThan(current!);
  bool get required => manifest != null && current != null && manifest!.requires(current!);

  /// Windows needs the launcher install to update in place; elsewhere the page opens instead.
  bool get canInstallHere => switch (platform) {
        UpdatePlatform.windows => host?.layout != null,
        UpdatePlatform.android => true,
        null => false,
      };

  bool get busy => stage == UpdateStage.checking || stage == UpdateStage.downloading || stage == UpdateStage.installing;

  double? get progress => total == null || total == 0 ? null : (received / total!).clamp(0.0, 1.0);

  void _set(UpdateStage s, {String? error}) {
    stage = s;
    this.error = error;
    notifyListeners();
  }

  Future<void> check() async {
    if (stage == UpdateStage.disabled || busy) return;
    _set(UpdateStage.checking);
    try {
      final text = await transport!.getText(manifestUrl);
      manifest = UpdateManifest.parse(text, base: manifestUrl, expectedApp: UpdateConfig.appName);
      lastChecked = DateTime.now();
      _set(updateAvailable ? UpdateStage.available : UpdateStage.upToDate);
    } on UpdateException catch (e) {
      lastChecked = DateTime.now();
      _set(UpdateStage.failed, error: e.message.contains('HTTP 404') ? 'No release published yet' : e.message);
    } on FormatException catch (e) {
      lastChecked = DateTime.now();
      _set(UpdateStage.failed, error: e.message);
    }
  }

  void cancel() => _cancel = true;

  /// Downloads, verifies and installs the release this device needs.
  Future<void> downloadAndInstall() async {
    final m = manifest;
    final a = asset;
    final h = host;
    if (m == null || h == null || busy) return;
    if (a == null) {
      _set(UpdateStage.failed, error: 'Release ${m.version} has no ${assetLabel(h.platform)}');
      return;
    }
    if (!canInstallHere) {
      await h.openUrl(UpdateConfig.releasesPage);
      return;
    }

    _cancel = false;
    received = 0;
    total = a.size;
    _set(UpdateStage.downloading);
    File? part;
    try {
      final staging = await h.stagingDir();
      part = File(p.join(staging.path, '${a.file}.part'));
      var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
      final sha = await transport!.download(
        a.url,
        part,
        cancelled: () => _cancel,
        onProgress: (r, t) {
          received = r;
          total = t ?? a.size;
          final now = DateTime.now();
          if (now.difference(lastNotify).inMilliseconds > 100) {
            lastNotify = now;
            notifyListeners();
          }
        },
      );
      if (sha != a.sha256) {
        throw UpdateException('The download does not match its checksum; nothing was installed');
      }
      final file = File(p.join(staging.path, a.file));
      if (file.existsSync()) file.deleteSync();
      part.renameSync(file.path);
      part = null;

      _set(UpdateStage.installing);
      switch (h.platform) {
        case UpdatePlatform.windows:
          final result = await h.install(file, '${m.version}');
          launcherUpdated = result.launcherUpdated;
          try {
            file.deleteSync();
          } catch (_) {}
        case UpdatePlatform.android:
          await h.openInstaller(file);
      }
      _set(UpdateStage.ready);
    } on UpdateException catch (e) {
      _set(UpdateStage.failed, error: e.message);
    } on FileSystemException catch (e) {
      _set(UpdateStage.failed, error: 'Could not write ${p.basename(e.path ?? 'the file')} (${e.osError?.message ?? e.message})');
    } finally {
      if (part != null && part.existsSync()) {
        try {
          part.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Windows: start the new version via the launcher. Android: reopen the installer.
  Future<void> finish() async {
    final h = host;
    final a = asset;
    if (h == null) return;
    if (h.platform == UpdatePlatform.windows) {
      await h.restart();
    } else if (a != null) {
      final staging = await h.stagingDir();
      try {
        await h.openInstaller(File(p.join(staging.path, a.file)));
      } on UpdateException catch (e) {
        _set(UpdateStage.failed, error: e.message);
      }
    }
  }

  /// Housekeeping on start: old version folders and leftovers.
  Future<void> cleanup() async {
    try {
      await host?.cleanup();
    } catch (_) {
      // Never let housekeeping stop the app.
    }
  }
}
