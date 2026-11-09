import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'installer.dart';
import 'manifest.dart';
import 'update_config.dart';

/// What the update service needs from the platform — real on Windows and Android, faked in tests.
abstract class UpdateHost {
  UpdatePlatform get platform;

  /// Windows only: the launcher install, or null when not running from one.
  InstallLayout? get layout;

  /// Where a download waits until verified.
  Future<Directory> stagingDir();

  /// Windows: unpack a verified zip into the versions folder.
  Future<InstallResult> install(File zip, String version);

  /// Windows: start the newest version through the launcher and quit this one.
  Future<void> restart();

  /// Android: hand the verified APK to the system installer.
  Future<void> openInstaller(File apk);

  /// Opens the releases page in the browser (no install possible here).
  Future<void> openUrl(Uri url);

  /// Removes old version folders on start; returns their names.
  Future<List<String>> cleanup();
}

class IoUpdateHost implements UpdateHost {
  IoUpdateHost._(this.platform, this.layout);

  /// The host for this device, or null where updating does not apply (web, other platforms).
  static IoUpdateHost? forThisDevice() {
    if (kIsWeb) return null;
    if (Platform.isWindows) return IoUpdateHost._(UpdatePlatform.windows, InstallLayout.detect(Platform.resolvedExecutable));
    if (Platform.isAndroid) return IoUpdateHost._(UpdatePlatform.android, null);
    return null;
  }

  @override
  final UpdatePlatform platform;

  @override
  final InstallLayout? layout;

  @override
  Future<Directory> stagingDir() async {
    final l = layout;
    if (l != null) return l.stagingDir;
    final tmp = await getTemporaryDirectory();
    return Directory(p.join(tmp.path, 'updates'));
  }

  @override
  Future<InstallResult> install(File zip, String version) {
    final root = layout!.root.path;
    final zipPath = zip.path;
    // Unpacking tens of MB takes a moment; keep it off the UI thread.
    return compute((_) => installFromZip(zipPath, root, version), null);
  }

  @override
  Future<void> restart() async {
    final l = layout!;
    final newest = l.installed().firstOrNull;
    if (l.launcher.existsSync()) {
      await Process.start(l.launcher.path, ['--after-update'],
          mode: ProcessStartMode.detached, workingDirectory: l.root.path);
    } else if (newest != null) {
      await Process.start(newest.exe.path, const [], mode: ProcessStartMode.detached, workingDirectory: newest.dir.path);
    }
    exit(0);
  }

  @override
  Future<void> openInstaller(File apk) async {
    final r = await OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
    if (r.type != ResultType.done) throw UpdateException('The Android installer did not open (${r.type.name})');
  }

  @override
  Future<void> openUrl(Uri url) async {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [url.toString()], mode: ProcessStartMode.detached);
    }
  }

  @override
  Future<List<String>> cleanup() async {
    final l = layout;
    if (l == null) return const [];
    return compute((_) => cleanupVersions(InstallLayout(l.root, current: l.current)), null);
  }
}

/// Release file name for a platform.
String assetLabel(UpdatePlatform p) => switch (p) {
      UpdatePlatform.windows => 'Windows package',
      UpdatePlatform.android => 'Android package',
    };

/// Kept here so the UI does not import dart:io.
String releasePageLabel() => UpdateConfig.releasesPage.toString();
