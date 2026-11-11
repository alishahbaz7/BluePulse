import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum LogLevel { info, warning, error }

/// One line of the error log; [repeats] counts the same line again right after it.
class LogEntry {
  LogEntry(this.time, this.level, this.source, this.message, {this.stack});

  final DateTime time;
  final LogLevel level;

  /// Which part of the app: `app`, `scanner`, `update`, `usage`, `config`, `sessions`, …
  final String source;
  final String message;
  final String? stack;
  int repeats = 0;

  bool sameAs(LogEntry o) => level == o.level && source == o.source && message == o.message;

  /// `2026-11-11 15:42:10.123  ERROR  update     Could not check for updates: …`
  String format() {
    final head = '${stamp(time)}  ${level.name.toUpperCase().padRight(7)}  ${source.padRight(9)}  $message';
    if (stack == null || stack!.isEmpty) return head;
    return '$head\n${stack!.split('\n').map((l) => '    $l').join('\n')}';
  }

  static String stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final l = t.toLocal();
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}:${two(l.second)}.'
        '${l.millisecond.toString().padLeft(3, '0')}';
  }
}

/// Everything that went wrong, on this device, in a plain text file — for tracking down a fault
/// after the fact. Silent: nothing is shown to the person; Settings → About → Details opens it.
///
/// Errors nobody handled arrive with their stack; failures the app handles quietly (an update check
/// that could not reach GitHub, a usage report that waits, a scan the radio refused, a file that
/// could not be written) are written as warnings by the part that handled them. Each run starts with
/// a line naming the version, so a fault can be matched to a release.
///
/// Never in the way: writing it never throws, the same line again is counted rather than repeated,
/// a run writes [maxPerRun] entries at most, and past [maxBytes] the file moves to `….1.log` (the one
/// before is dropped) — two files, a couple of MB, at most.
class ErrorLog extends ChangeNotifier {
  ErrorLog({this.maxBytes = 1024 * 1024, this.maxPerRun = 2000, this.repeatWindow = const Duration(minutes: 10)});

  /// The app's log. Entries recorded before [open] (the earliest start-up) are kept and written then.
  static final ErrorLog instance = ErrorLog();

  static const fileName = 'BluePulse_errors.log';

  final int maxBytes;
  final int maxPerRun;
  final Duration repeatWindow;

  File? _file;
  int _bytes = 0;
  int _written = 0;
  Future<void> _writing = Future<void>.value();
  final _recent = ListQueue<LogEntry>();
  final _unwritten = <String>[];

  /// The file, once [open]; null before.
  File? get file => _file;

  /// Warnings and errors since this run started (repeats included).
  int problems = 0;

  /// The latest entries, newest last (the last 200).
  List<LogEntry> get recent => List.unmodifiable(_recent);

  String _header = 'BluePulse';

  /// Starts writing to [dir]; [header] (version, build, platform) opens this run's section. Opened
  /// again elsewhere (the files folder changed), the same header says where it carries on.
  Future<void> open(Directory dir, {String? header}) async {
    final again = header == null;
    _header = header ?? _header;
    try {
      await dir.create(recursive: true);
      final f = File(p.join(dir.path, fileName));
      _bytes = f.existsSync() ? f.lengthSync() : 0;
      _file = f;
      _rotateIfFull();
      _append('\n==== $_header · ${again ? 'continued here' : 'started'} ${LogEntry.stamp(DateTime.now())}');
      final early = List.of(_unwritten);
      _unwritten.clear();
      early.forEach(_append);
    } catch (_) {
      _file = null; // no folder to write to: the entries stay in memory for this run
    }
    notifyListeners();
  }

  void info(String source, String message) => _add(LogLevel.info, source, message);

  /// Something failed and the app carried on (no network, a refused scan, a damaged file).
  void warn(String source, String message, {Object? error}) =>
      _add(LogLevel.warning, source, error == null ? message : '$message: ${describe(error)}');

  /// Something failed that should not have: an error nobody handled, with where it happened.
  void error(String source, Object error, {StackTrace? stack, String? context}) => _add(
        LogLevel.error,
        source,
        context == null ? describe(error) : '$context: ${describe(error)}',
        stack: _top(stack),
      );

  /// An error in words: its type and message, on one line, not too long.
  static String describe(Object e) {
    final text = '$e';
    // Most errors name their type already ("FileSystemException: locked"); others get it in front.
    var s = e is String || text.startsWith('${e.runtimeType}') ? text : '${e.runtimeType}: $text';
    s = s.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
    return s.length > 500 ? '${s.substring(0, 500)}…' : s;
  }

  static String? _top(StackTrace? stack) {
    if (stack == null) return null;
    final lines = stack.toString().split('\n').where((l) => l.trim().isNotEmpty).take(12).toList();
    return lines.isEmpty ? null : lines.join('\n');
  }

  void _add(LogLevel level, String source, String message, {String? stack}) {
    try {
      final now = DateTime.now();
      if (level != LogLevel.info) problems++;
      final entry = LogEntry(now, level, source, message, stack: stack);
      final last = _recent.isEmpty ? null : _recent.last;
      if (last != null && last.sameAs(entry) && now.difference(last.time) < repeatWindow) {
        // The same thing again (a fault in a loop): counted, not written again.
        last.repeats++;
        notifyListeners();
        return;
      }
      _closeRepeats(last);
      _recent.addLast(entry);
      while (_recent.length > 200) {
        _recent.removeFirst();
      }
      if (kDebugMode) debugPrint('[BluePulse ${level.name}] $source: $message');
      if (_written < maxPerRun) {
        _written++;
        _line(_written == maxPerRun ? '${entry.format()}\n(more this run are not written)' : entry.format());
      }
      notifyListeners();
    } catch (_) {
      // The log itself must never become a fault.
    }
  }

  /// Writes how often the previous line repeated, if it did.
  void _closeRepeats(LogEntry? last) {
    if (last == null || last.repeats == 0) return;
    _line('    … ${last.repeats} more time${last.repeats == 1 ? '' : 's'}');
    last.repeats = 0;
  }

  /// Writes what is pending, including a repeat count (on closing the app, and for tests).
  Future<void> flush() {
    _closeRepeats(_recent.isEmpty ? null : _recent.last);
    return _writing;
  }

  /// Writes what is pending and lets go of the file (it is about to move); events wait in memory
  /// until [open] again.
  Future<void> close() async {
    await flush();
    _file = null;
  }

  void _line(String text) => _file == null ? _unwritten.add(text) : _append(text);

  void _append(String text) {
    final f = _file;
    if (f == null) return;
    final line = '$text\n';
    _bytes += line.length;
    _writing = _writing
        .then((_) => f.writeAsString(line, mode: FileMode.append, flush: true))
        .then<void>((_) {}, onError: (Object _) {}); // a full disk loses a line, nothing else
    _rotateIfFull();
  }

  void _rotateIfFull() {
    final f = _file;
    if (f == null || _bytes < maxBytes) return;
    _bytes = 0;
    _writing = _writing.then((_) async {
      try {
        final older = File(p.join(f.parent.path, fileName.replaceFirst('.log', '.1.log')));
        if (older.existsSync()) older.deleteSync();
        if (f.existsSync()) f.renameSync(older.path);
      } catch (_) {
        // In use elsewhere: the file grows a little more and the next line tries again.
      }
    });
  }
}

/// The app's error log ([ErrorLog.instance]).
ErrorLog get errorLog => ErrorLog.instance;
