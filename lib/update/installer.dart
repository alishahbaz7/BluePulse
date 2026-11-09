import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'semver.dart';
import 'update_config.dart';

/// One complete version folder: `versions\BluePulse-v1.1.0\BluePulse-v1.1.0.exe`.
class InstalledVersion {
  InstalledVersion(this.version, this.dir);

  final SemVer version;
  final Directory dir;

  String get name => UpdateConfig.releaseName('$version');
  File get exe => File(p.join(dir.path, '$name.exe'));
}

/// The launcher install on Windows:
///
/// ```
/// <root>\BluePulse.exe                        launcher, pinned, never versioned
/// <root>\versions\BluePulse-v1.0.0\BluePulse-v1.0.0.exe
/// <root>\versions\BluePulse-v1.1.0\…
/// ```
class InstallLayout {
  InstallLayout(this.root, {this.current});

  final Directory root;

  /// The version folder the app is running from, when known.
  final Directory? current;

  Directory get versionsDir => Directory(p.join(root.path, UpdateConfig.versionsDir));
  File get launcher => File(p.join(root.path, UpdateConfig.launcherExe));

  /// Where downloads wait until they are verified.
  Directory get stagingDir => Directory(p.join(versionsDir.path, '.download'));

  /// Finds the layout from the running program's path, or null when the app is not running from a
  /// version folder (a development run, or a folder unzipped by hand).
  static InstallLayout? detect(String executable) {
    final exe = File(executable);
    final versionDir = exe.parent;
    final versions = versionDir.parent;
    final name = p.basename(versionDir.path);
    if (p.basename(versions.path).toLowerCase() != UpdateConfig.versionsDir) return null;
    if (_folder.firstMatch(name) == null) return null;
    if (p.basenameWithoutExtension(exe.path) != name) return null;
    return InstallLayout(versions.parent, current: versionDir);
  }

  SemVer? get currentVersion => current == null ? null : _versionOf(p.basename(current!.path));

  /// Complete versions (folder name right and its program present), newest first.
  List<InstalledVersion> installed() {
    if (!versionsDir.existsSync()) return const [];
    final out = <InstalledVersion>[];
    for (final d in versionsDir.listSync().whereType<Directory>()) {
      final v = _versionOf(p.basename(d.path));
      if (v == null) continue;
      final iv = InstalledVersion(v, d);
      if (iv.exe.existsSync()) out.add(iv);
    }
    out.sort((a, b) => b.version.compareTo(a.version));
    return out;
  }
}

final _folder = RegExp('^${RegExp.escape(UpdateConfig.appName)}-v(\\d+\\.\\d+\\.\\d+)\$');

SemVer? _versionOf(String folderName) {
  final m = _folder.firstMatch(folderName);
  return m == null ? null : SemVer.tryParse(m.group(1));
}

class InstallResult {
  InstallResult(this.installed, {required this.launcherUpdated});
  final InstalledVersion installed;
  final bool launcherUpdated;
}

/// A problem a person can act on, in their words.
class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Unpacks a release zip into `versions\<name>` and refreshes the launcher if the zip carries a newer
/// one. Accepts the release layout (`BluePulse\versions\<name>\…` plus the launcher at
/// the top) or a bare `<name>\…` folder. Writes to `<name>.partial` first and renames at the end, so
/// an interrupted install never leaves a half version that the launcher would start.
///
/// Pure function of its arguments, so it can run in a background isolate.
InstallResult installFromZip(String zipPath, String rootPath, String version) {
  final layout = InstallLayout(Directory(rootPath));
  final name = UpdateConfig.releaseName(version);
  final archive = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());

  final files = <String, List<int>>{};
  List<int>? launcher;
  for (final entry in archive.files) {
    if (!entry.isFile) continue;
    final path = entry.name.replaceAll(r'\', '/');
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.any((s) => s == '..') || path.startsWith('/') || path.contains(':')) {
      throw UpdateException('The package contains an unsafe path: ${entry.name}');
    }
    final i = parts.indexOf(name);
    if (i >= 0 && i < parts.length - 1) {
      files[parts.sublist(i + 1).join('/')] = entry.readBytes() ?? const [];
    } else if (parts.isNotEmpty && parts.last == UpdateConfig.launcherExe && !parts.contains(UpdateConfig.versionsDir)) {
      launcher = entry.readBytes();
    }
  }
  if (!files.containsKey('$name.exe')) {
    throw UpdateException('The package does not contain $name.exe');
  }

  layout.versionsDir.createSync(recursive: true);
  final partial = Directory(p.join(layout.versionsDir.path, '$name.partial'));
  if (partial.existsSync()) partial.deleteSync(recursive: true);
  for (final e in files.entries) {
    final f = File(p.joinAll([partial.path, ...e.key.split('/')]));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(e.value);
  }

  final target = Directory(p.join(layout.versionsDir.path, name));
  if (target.existsSync()) {
    final old = Directory('${target.path}.old-${DateTime.now().millisecondsSinceEpoch}');
    target.renameSync(old.path);
    try {
      old.deleteSync(recursive: true);
    } catch (_) {
      // Left for the next cleanup (a file may be in use).
    }
  }
  partial.renameSync(target.path);

  var launcherUpdated = false;
  if (launcher != null) {
    final current = layout.launcher;
    final same = current.existsSync() && _sameBytes(current.readAsBytesSync(), launcher);
    if (!same) {
      try {
        final fresh = File('${current.path}.new')..writeAsBytesSync(launcher);
        if (current.existsSync()) current.deleteSync();
        fresh.renameSync(current.path);
        launcherUpdated = true;
      } catch (_) {
        // The launcher is in use; the old one keeps working and the next update tries again.
      }
    }
  }

  return InstallResult(InstalledVersion(SemVer.parse(version), target), launcherUpdated: launcherUpdated);
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Keeps the running version, the newest one and the newest one below the running version (for
/// rollback); removes every other version folder, leftover `.partial` / `.old-…` folders and the
/// download staging folder. Folders in use are skipped. Returns what was removed.
List<String> cleanupVersions(InstallLayout layout) {
  final removed = <String>[];
  if (!layout.versionsDir.existsSync()) return removed;
  final installed = layout.installed();
  final current = layout.currentVersion;
  final keep = <SemVer>{
    ?current,
    if (installed.isNotEmpty) installed.first.version,
  };
  final below = installed.where((v) => current == null || v.version < current).toList();
  if (below.isNotEmpty) keep.add(below.first.version);

  for (final d in layout.versionsDir.listSync().whereType<Directory>()) {
    final name = p.basename(d.path);
    final v = _versionOf(name);
    final leftover = name.endsWith('.partial') || name.contains('.old-') || name == '.download';
    final stale = v != null && !keep.contains(v);
    if (!leftover && !stale) continue;
    try {
      d.deleteSync(recursive: true);
      removed.add(name);
    } catch (_) {
      // In use by another running copy; try again next start.
    }
  }
  return removed;
}
