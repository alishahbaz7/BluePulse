import 'dart:async';
import 'dart:io';

import 'package:eye_protocol/eye_protocol.dart';

import 'rx_log.dart';
import 'error_log.dart';

/// Several devices' packets in one CSV, a row for every packet as it arrives — the pinned devices on
/// the Devices page. Each row: when, from which MAC, how long after that device's previous packet,
/// its name, every value the packet carried, the signal, what kind of packet, and the raw bytes. A
/// gap on air is a longer interval, never a made-up row.
///
/// Made for runs of hours: rows reach the disk every [flushEvery] (a crash or a killed app loses at
/// most that much), and a file that reaches [maxRowsPerFile] is closed and the log carries on in the
/// next part (`…_part2.csv`), so each one opens in Excel (1,048,576 rows at most).
class SensorLog {
  SensorLog._(this._first, this.macs, this.started, this.maxRowsPerFile, Duration flushEvery) {
    files.add(_first);
    _timer = Timer.periodic(flushEvery, (_) => _flush());
  }

  /// The columns, in the order people read them: when and who first, the values, then the radio.
  static const header = 'time_local,time_utc,mac,gap_ms,name,temperature_c,humidity_pct,battery_mv,low_battery,'
      'moving,movement_count,pitch_deg,roll_deg,magnet,rssi_dbm,kind,beacon_id,protocol_version,flags_hex,raw_hex';

  static Future<SensorLog> start(
    File file, {
    required Iterable<String> macs,
    int maxRowsPerFile = 1000000,
    Duration flushEvery = const Duration(seconds: 2),
  }) async {
    await file.parent.create(recursive: true);
    await file.writeAsString('$header\n', flush: true);
    return SensorLog._(file, {...macs}, DateTime.now(), maxRowsPerFile, flushEvery);
  }

  final File _first;

  /// Every file of this log, the first one first.
  final List<File> files = [];

  /// The devices logged, by MAC (fixed when the log starts).
  final Set<String> macs;
  final DateTime started;
  final int maxRowsPerFile;

  /// Rows written, all parts together.
  int rows = 0;
  int _rowsInFile = 0;
  final _pending = StringBuffer();
  Future<void>? _writing;
  Timer? _timer;
  bool _closed = false;

  File get file => files.last;
  bool covers(String mac) => macs.contains(mac);

  /// One packet from one of [macs].
  void write(RxEntry e, {required String mac, String? name}) {
    if (_closed) return;
    if (_rowsInFile >= maxRowsPerFile) {
      _nextPart();
    }
    _pending.writeln(row(e, mac: mac, name: name));
    rows++;
    _rowsInFile++;
  }

  /// Closes this part with what is pending and starts the next with its own header.
  void _nextPart() {
    final rest = _pending.toString();
    _pending.clear();
    final full = file;
    final base = _first.path.replaceFirst(RegExp(r'\.csv$'), '');
    final next = File('${base}_part${files.length + 1}.csv');
    files.add(next);
    _rowsInFile = 0;
    _pending.write('$header\n');
    _writing = (_writing ?? Future<void>.value()).then((_) async {
      if (rest.isNotEmpty) await full.writeAsString(rest, mode: FileMode.append, flush: true);
    });
  }

  /// Appends what is waiting to the current file; one write at a time.
  Future<void> _flush() {
    if (_pending.isEmpty) return _writing ?? Future<void>.value();
    final text = _pending.toString();
    final target = file;
    _pending.clear();
    return _writing = (_writing ?? Future<void>.value())
        .then((_) => target.writeAsString(text, mode: FileMode.append, flush: true))
        .catchError((Object e) {
          // A full disk stops the file growing, not the app.
          errorLog.warn('log', 'Log rows not written to ${target.uri.pathSegments.last}', error: e);
          return target;
        });
  }

  static String row(RxEntry e, {required String mac, String? name}) {
    final t = e.teltonika;
    final id = decodeAdvertisement(e.data).beaconId;
    String flag(bool? b) => b == null ? '' : (b ? '1' : '0');
    return [
      localTime(e.time),
      e.time.toUtc().toIso8601String(),
      mac,
      e.gapMs?.toString() ?? '',
      _quote(name ?? e.data.name ?? ''),
      t?.temperatureC?.toStringAsFixed(2) ?? '',
      t?.humidity?.toString() ?? '',
      t?.batteryMv?.toString() ?? '',
      t == null ? '' : flag(t.lowBattery),
      flag(t?.moving),
      t?.movementCount?.toString() ?? '',
      t?.pitch?.toString() ?? '',
      t?.roll?.toString() ?? '',
      t != null && t.magnetPresent ? flag(t.magnetDetected) : '',
      e.rssi?.toString() ?? '',
      e.kind == '—' ? '' : e.kind,
      id == null ? '' : '${id.kindLabel} ${id.display}',
      t?.version?.toString() ?? '',
      t?.flags == null ? '' : t!.flags!.toRadixString(16).padLeft(2, '0').toUpperCase(),
      toHex(e.bytes),
    ].join(',');
  }

  /// Writes what is waiting and closes the log; its files, the first one first.
  Future<List<File>> stop() async {
    if (!_closed) {
      _closed = true;
      _timer?.cancel();
      await _flush();
      await _writing;
    }
    return files;
  }

  /// `BluePulse_log_3-devices_20261110-172000.csv`.
  static String fileName(int devices, DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    final l = time.toLocal();
    return 'BluePulse_log_$devices-device${devices == 1 ? '' : 's'}_'
        '${l.year}${two(l.month)}${two(l.day)}-${two(l.hour)}${two(l.minute)}${two(l.second)}.csv';
  }

  /// `2026-11-11 10:35:24.512` — local time to the millisecond, as Excel reads it.
  static String localTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final l = t.toLocal();
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}:${two(l.second)}.'
        '${l.millisecond.toString().padLeft(3, '0')}';
  }

  static String _quote(String s) => s.contains(RegExp('[,"\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
}
