import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/error_log.dart';

/// BluePulse's one folder on this device. Everything it saves goes here, and nowhere else:
///
/// ```
/// BluePulse/
///   sessions/              every live scan, Start to Stop
///   logs/                  device recordings and multi-device logs
///   BluePulse_errors.log   what went wrong, one line per event (.1.log: the one before)
///   README.txt             this list
/// ```
///
/// The person can choose another folder (Settings → Files); by default:
/// - **Windows:** `C:\Users\<you>\BluePulse` — beside Documents, not inside it: Documents is often
///   synced by OneDrive, which would upload a growing log every few seconds.
/// - **Android:** Internal storage › Documents › BluePulse, which the Files app shows and a laptop
///   sees over USB. A development copy keeps `BluePulse DEV`: Android lets each app open only the
///   files it made itself. Where that cannot be written (older Android), the app's own folder.
///
/// A chosen folder that cannot be written at a later start (a USB drive unplugged) gives way to the
/// default for that run, and the error log says so. Update downloads are not kept here: Windows
/// stages them beside the installed versions (so they can be renamed into place) and Android in the
/// app's cache (where the system installer reads them).
Future<Directory> appHome() => _home ??= _findHome();
Future<Directory>? _home;
String? _preferred;

/// The folder the person chose ([AppSettings.filesFolder]); call before the first [appHome].
void preferAppHome(String? path) => _preferred = path;

/// The home folder once known (for showing it); null before the first [appHome].
Directory? appHomeNow;

/// True while the files go to the default folder rather than a chosen one.
bool appHomeIsDefault = true;

/// A folder inside [appHome], made if missing.
Future<Directory> appFilesDir(String name) async {
  final dir = Directory(p.join((await appHome()).path, name));
  await dir.create(recursive: true);
  return dir;
}

/// [appHomeNow] as people know it: `C:\Users\you\BluePulse`, or `Internal storage › Documents ›
/// BluePulse` on a phone.
String? appHomeLabel() => appHomeNow == null ? null : folderLabel(appHomeNow!.path);

String folderLabel(String path) {
  final shared = RegExp(r'^/storage/emulated/\d+/(.*)$').firstMatch(path);
  return shared == null ? path : 'Internal storage › ${shared.group(1)!.split('/').join(' › ')}';
}

/// The BluePulse folder inside a folder the person picked — `D:\Data` → `D:\Data\BluePulse` — or the
/// picked folder itself when it is already called BluePulse.
String bluePulseFolderIn(String picked) {
  final name = p.basename(picked).toLowerCase();
  return name == 'bluepulse' || name == 'bluepulse dev' ? picked : p.join(picked, _name);
}

String get _name => !kIsWeb && Platform.isAndroid && kDebugMode ? 'BluePulse DEV' : 'BluePulse';

Future<Directory> _findHome() async {
  final home = await _pick();
  appHomeNow = home;
  _readme(home);
  return home;
}

Future<Directory> _pick() async {
  final chosen = _preferred;
  if (chosen != null && chosen.isNotEmpty) {
    final dir = Directory(chosen);
    if (await writable(dir)) {
      appHomeIsDefault = false;
      return dir;
    }
    errorLog.warn('files', 'The chosen folder $chosen cannot be written now; this run uses the default folder');
  }
  appHomeIsDefault = true;
  return _defaultHome(bringOver: true);
}

/// The default folder (see [appHome]), made if missing.
Future<Directory> defaultAppHome() => _defaultHome(bringOver: false);

Future<Directory> _defaultHome({required bool bringOver}) async {
  final docs = await getApplicationDocumentsDirectory();
  if (Platform.isWindows) {
    final profile = Platform.environment['USERPROFILE'];
    final home = Directory(profile == null || profile.isEmpty ? p.join(docs.path, 'BluePulse') : p.join(profile, 'BluePulse'));
    await home.create(recursive: true);
    // Earlier versions saved under Documents\BluePulse: copied over once, the originals left alone.
    if (bringOver) await _bringOver(Directory(p.join(docs.path, 'BluePulse')), home, keepOriginals: true);
    return home;
  }
  if (Platform.isAndroid) {
    final home = await androidFolder('Documents');
    if (home != null) {
      // Earlier versions kept files inside the app, where nobody could reach them: moved out once.
      if (bringOver) await _bringOver(docs, home, keepOriginals: false);
      return home;
    }
    return docs;
  }
  return Directory(p.join(docs.path, 'BluePulse'));
}

/// `Internal storage › <collection> › BluePulse` on Android, when it can be written; null if not.
/// Android lets an app write its own files into the shared Documents and Download folders only.
Future<Directory?> androidFolder(String collection) async {
  try {
    // /storage/emulated/0/Android/data/<app>/files → /storage/emulated/0
    final ext = (await getExternalStorageDirectory())?.path;
    final cut = ext?.indexOf('/Android/') ?? -1;
    if (ext == null || cut <= 0) return null;
    final dir = Directory(p.join(ext.substring(0, cut), collection, _name));
    if (await writable(dir)) return dir;
    errorLog.warn('files', '$collection › $_name cannot be written on this phone');
  } catch (e) {
    errorLog.warn('files', '$collection › $_name cannot be used on this phone', error: e);
  }
  return null;
}

/// Whether BluePulse can make [dir] and write a file in it.
Future<bool> writable(Directory dir) async {
  try {
    await dir.create(recursive: true);
    final probe = File(p.join(dir.path, '.write-test'));
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
}

/// What BluePulse saved in [home]: sessions, logs and the error log.
List<File> savedFiles(Directory home) {
  final files = <File>[];
  for (final name in const ['sessions', 'logs']) {
    final d = Directory(p.join(home.path, name));
    if (d.existsSync()) files.addAll(d.listSync().whereType<File>());
  }
  for (final name in [ErrorLog.fileName, ErrorLog.fileName.replaceFirst('.log', '.1.log')]) {
    final f = File(p.join(home.path, name));
    if (f.existsSync()) files.add(f);
  }
  return files;
}

/// The outcome of [moveAppHome]: how many files went along, and how many stayed (in use, or a file
/// of the same name already there).
class FolderMove {
  const FolderMove(this.from, this.to, {this.moved = 0, this.stayed = 0});
  final Directory from;
  final Directory to;
  final int moved;
  final int stayed;
}

/// Makes [to] the home folder from now on; with [moveFiles], BluePulse's files go along (a rename
/// on the same drive, a copy then delete across drives). The caller closes open files first.
/// Throws a [FileSystemException] when [to] cannot be written or lies inside the current folder.
Future<FolderMove> moveAppHome(Directory to, {required bool moveFiles}) async {
  final from = await appHome();
  if (p.isWithin(from.path, to.path)) {
    throw FileSystemException('Choose a folder outside the current BluePulse folder', to.path);
  }
  if (!await writable(to)) throw FileSystemException('BluePulse cannot write to this folder', to.path);
  var moved = 0;
  var stayed = 0;
  if (moveFiles && !p.equals(from.path, to.path)) {
    for (final f in savedFiles(from)) {
      final target = File(p.join(to.path, p.relative(f.path, from: from.path)));
      if (target.existsSync()) {
        stayed++;
        continue;
      }
      try {
        target.parent.createSync(recursive: true);
        try {
          await f.rename(target.path);
        } on FileSystemException {
          await f.copy(target.path); // another drive
          await f.delete();
        }
        moved++;
      } catch (e) {
        stayed++;
        errorLog.warn('files', 'Not moved: ${p.basename(f.path)}', error: e);
      }
    }
    // Tidy what was BluePulse's and is now empty; nothing else is touched.
    for (final name in const ['sessions', 'logs']) {
      _deleteIfEmpty(Directory(p.join(from.path, name)));
    }
    if (stayed == 0) {
      for (final name in const ['README.txt', '.earlier-files-brought-over']) {
        try {
          final f = File(p.join(from.path, name));
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      _deleteIfEmpty(from);
    }
  }
  // Earlier versions' files belong to the default folder only: never copied into this one later.
  _mark(to);
  _home = Future.value(to);
  appHomeNow = to;
  _readme(to);
  return FolderMove(from, to, moved: moved, stayed: stayed);
}

void _deleteIfEmpty(Directory d) {
  try {
    if (d.existsSync() && d.listSync().isEmpty) d.deleteSync();
  } catch (_) {}
}

File _marker(Directory home) => File(p.join(home.path, '.earlier-files-brought-over'));

void _mark(Directory home, [String? from]) {
  try {
    final f = _marker(home);
    if (!f.existsSync()) f.writeAsStringSync('${DateTime.now().toIso8601String()}${from == null ? '' : ' from $from'}\n');
  } catch (_) {}
}

/// Copies (or moves) the sessions and logs an earlier version saved in [from] into [home], once.
/// Never in the way of the start: a few seconds at most, the rest carries on in the background.
Future<void> _bringOver(Directory from, Directory home, {required bool keepOriginals}) async {
  if (_marker(home).existsSync() || p.equals(from.path, home.path)) return;
  Future<void> work() async {
    var count = 0;
    for (final name in const ['sessions', 'logs']) {
      final src = Directory(p.join(from.path, name));
      if (!src.existsSync()) continue;
      final dst = Directory(p.join(home.path, name))..createSync(recursive: true);
      for (final f in src.listSync().whereType<File>()) {
        final target = File(p.join(dst.path, p.basename(f.path)));
        if (target.existsSync()) continue;
        try {
          await f.copy(target.path);
          if (!keepOriginals) await f.delete();
          count++;
        } catch (e) {
          errorLog.warn('files', 'An earlier file was not brought over: ${p.basename(f.path)}', error: e);
        }
      }
    }
    _mark(home, from.path);
    if (count > 0) {
      errorLog.info('files', '$count earlier file${count == 1 ? '' : 's'} ${keepOriginals ? 'copied' : 'moved'} from ${from.path}');
    }
  }

  try {
    await work().timeout(const Duration(seconds: 5));
  } on TimeoutException {
    // Large or cloud-only files: they keep arriving in the background.
  } catch (e) {
    errorLog.warn('files', 'Earlier files were not brought over', error: e);
  }
}

void _readme(Directory home) {
  try {
    final f = File(p.join(home.path, 'README.txt'));
    if (f.existsSync()) return;
    f.writeAsStringSync('''
BluePulse - files on this device

sessions              every live scan, Start to Stop (CSV, with a .json summary)
logs                  device recordings (Record, Save log) and multi-device logs (Devices > Log)
BluePulse_errors.log  what went wrong, one line per event, newest at the bottom
                      (BluePulse_errors.1.log is the one before; each stops at about 1 MB)

Everything here can be copied, shared or deleted; BluePulse makes new files as it needs them.
The folder can be changed in BluePulse: Settings > Files > Change.
''');
  } catch (_) {
    // Only a convenience.
  }
}

/// For tests: forget the home folder so the next [appHome] looks again.
@visibleForTesting
void resetAppHome({Directory? to}) {
  _home = to == null ? null : Future.value(to);
  appHomeNow = to;
  _preferred = null;
  appHomeIsDefault = true;
}
