import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'rx_log.dart';
import 'error_log.dart';

/// One recorded session: a scan from *Start scan* to *Stop scan*, every packet from every tracked
/// device in one CSV (the received-packets columns), with a small JSON beside it for the list.
class SessionInfo {
  SessionInfo({
    required this.csv,
    required this.started,
    this.ended,
    this.updated,
    this.packets,
    this.devices,
    this.bytes = 0,
    this.platform,
    this.version,
  });

  final File csv;
  final DateTime started;

  /// When the scan stopped; null while recording, or when the app closed without stopping it.
  final DateTime? ended;

  /// The last time the recording wrote its summary (every few seconds while it runs).
  final DateTime? updated;

  /// Unknown for a session whose summary is missing.
  final int? packets;
  final int? devices;
  final int bytes;
  final String? platform;
  final String? version;

  String get name => p.basename(csv.path);
  File get meta => File(p.setExtension(csv.path, '.json'));
  Duration get duration {
    final end = ended ?? updated;
    return end == null || end.isBefore(started) ? Duration.zero : end.difference(started);
  }
}

/// Writes a session as packets arrive. Rows are buffered and written once a second, so a crash
/// loses at most a second; the summary is rewritten every few seconds and when the scan stops.
class SessionWriter {
  SessionWriter._(this.csv, this._raf, this.started, {required this.platform, required this.version});

  static const _flushEvery = Duration(seconds: 1);
  static const _summaryEveryTicks = 5;

  static Future<SessionWriter> start(File csv, {required String platform, required String version, DateTime? at}) async {
    await csv.parent.create(recursive: true);
    final raf = await csv.open(mode: FileMode.write);
    raf.writeStringSync('${RxCsv.header}\n');
    final w = SessionWriter._(csv, raf, at ?? DateTime.now(), platform: platform, version: version);
    w._writeSummary();
    w._timer = Timer.periodic(_flushEvery, (_) => w.flush());
    return w;
  }

  final File csv;
  final RandomAccessFile _raf;
  final DateTime started;
  final String platform;
  final String version;
  final _buffer = StringBuffer();
  final _macs = <String>{};
  Timer? _timer;
  int _ticks = 0;
  bool _closed = false;
  int packets = 0;

  int get devices => _macs.length;
  bool get recording => !_closed;

  void write(RxEntry e, {required String mac, String? name, String? tag}) {
    if (_closed) return;
    _buffer.writeln(RxCsv.row(e, mac: mac, name: name, tag: tag));
    _macs.add(mac);
    packets++;
  }

  /// Writes the buffered rows to disk; called once a second.
  void flush() {
    if (_closed) return;
    if (_buffer.isNotEmpty) {
      _raf.writeStringSync(_buffer.toString());
      _buffer.clear();
    }
    if (++_ticks % _summaryEveryTicks == 0) _writeSummary();
  }

  Future<SessionInfo> stop({DateTime? at}) async {
    if (!_closed) {
      flush();
      _closed = true;
      _timer?.cancel();
      await _raf.close();
      _writeSummary(ended: at ?? DateTime.now());
    }
    return SessionStore.read(csv) ?? info;
  }

  /// What the list shows for this session while it records.
  SessionInfo get info => SessionInfo(
        csv: csv,
        started: started,
        updated: DateTime.now(),
        packets: packets,
        devices: devices,
        bytes: _closed ? csv.lengthSync() : _raf.positionSync() + _buffer.length,
        platform: platform,
        version: version,
      );

  void _writeSummary({DateTime? ended}) {
    final now = DateTime.now();
    File(p.setExtension(csv.path, '.json')).writeAsStringSync(jsonEncode({
      'app': 'BluePulse',
      'format': 1,
      'version': version,
      'platform': platform,
      'started': started.toUtc().toIso8601String(),
      'updated': (ended ?? now).toUtc().toIso8601String(),
      'ended': ended?.toUtc().toIso8601String(),
      'packets': packets,
      'devices': devices,
    }));
  }
}

/// The folder of recorded sessions.
class SessionStore {
  SessionStore(this.dir);

  /// Where sessions are saved; moves when the person changes the files folder.
  Directory dir;

  static const prefix = 'BluePulse_session_';

  /// `BluePulse_session_20261110-143005.csv`, local time.
  static String fileName(DateTime t, {int n = 1}) {
    String two(int v) => v.toString().padLeft(2, '0');
    final l = t.toLocal();
    final stamp = '${l.year}${two(l.month)}${two(l.day)}-${two(l.hour)}${two(l.minute)}${two(l.second)}';
    return '$prefix$stamp${n > 1 ? '-$n' : ''}.csv';
  }

  /// The start time a session's file name carries, for a session whose summary is missing.
  static DateTime? startFromName(String name) {
    final m = RegExp(r'(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})').firstMatch(name);
    if (m == null) return null;
    final v = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
    return DateTime(v[0], v[1], v[2], v[3], v[4], v[5]);
  }

  Future<SessionWriter> start({required String platform, required String version, DateTime? at}) async {
    final time = at ?? DateTime.now();
    await dir.create(recursive: true);
    var n = 1;
    var file = File(p.join(dir.path, fileName(time)));
    while (file.existsSync()) {
      file = File(p.join(dir.path, fileName(time, n: ++n)));
    }
    return SessionWriter.start(file, platform: platform, version: version, at: time);
  }

  /// Every session, newest first.
  Future<List<SessionInfo>> list() async {
    if (!await dir.exists()) return const [];
    final out = <SessionInfo>[];
    await for (final f in dir.list()) {
      if (f is! File) continue;
      final name = p.basename(f.path);
      if (!name.startsWith(prefix) || !name.toLowerCase().endsWith('.csv')) continue;
      final s = read(f);
      if (s != null) out.add(s);
    }
    out.sort((a, b) => b.started.compareTo(a.started));
    return out;
  }

  /// A session from its CSV and the summary beside it; the file alone when the summary is missing.
  static SessionInfo? read(File csv) {
    final int bytes;
    try {
      bytes = csv.lengthSync();
    } on FileSystemException {
      return null;
    }
    final meta = File(p.setExtension(csv.path, '.json'));
    Map<String, Object?>? m;
    try {
      if (meta.existsSync()) m = jsonDecode(meta.readAsStringSync()) as Map<String, Object?>;
    } catch (e) {
      m = null; // a damaged summary: list the file by its name
      errorLog.warn('sessions', 'Damaged session summary ${p.basename(meta.path)}', error: e);
    }
    DateTime? time(String key) => m?[key] is String ? DateTime.tryParse(m![key] as String)?.toLocal() : null;
    final started = time('started') ?? startFromName(p.basename(csv.path)) ?? csv.lastModifiedSync();
    return SessionInfo(
      csv: csv,
      started: started,
      ended: time('ended'),
      updated: time('updated') ?? (m == null ? csv.lastModifiedSync() : null),
      packets: m?['packets'] as int?,
      devices: m?['devices'] as int?,
      bytes: bytes,
      platform: m?['platform'] as String?,
      version: m?['version'] as String?,
    );
  }

  Future<void> delete(SessionInfo s) async {
    for (final f in [s.csv, s.meta]) {
      try {
        await f.delete();
      } on FileSystemException {
        // already gone
      }
    }
  }
}
