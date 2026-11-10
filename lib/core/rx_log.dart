import 'dart:io';
import 'dart:typed_data';

import 'package:eye_protocol/eye_protocol.dart';

/// One packet received from a device, kept for its received-packets log.
class RxEntry {
  RxEntry({
    required this.time,
    required this.rssi,
    required this.scanResponse,
    required this.data,
    required this.raw,
    required this.gapMs,
  });

  final DateTime time;
  final int? rssi;

  /// True for a scan response, false for an advertisement, null when the scanner cannot tell.
  final bool? scanResponse;
  final AdvertisementData data;

  /// The bytes as received, when the scanner provides them.
  final Uint8List? raw;

  /// Time since the previous packet from the same device.
  final int? gapMs;

  TeltonikaData? _tel;
  bool _decoded = false;

  /// Decoded on first use: the log holds thousands of entries, most never displayed.
  TeltonikaData? get teltonika {
    if (!_decoded) {
      _decoded = true;
      final p = data.manufacturerData[teltonikaCompanyId];
      _tel = p == null ? null : decodeTeltonika(p);
    }
    return _tel;
  }

  Uint8List get bytes => raw ?? data.toBytes();

  String get kind => switch (scanResponse) {
        true => 'Scan response',
        false => 'Advertisement',
        null => 'Packet',
      };

  /// The decoded values in a few words, for the log table.
  String get summary {
    final t = teltonika;
    final parts = <String>[
      if (t != null && t.temperatureC != null) '${t.temperatureC!.toStringAsFixed(2)} °C',
      if (t != null && t.humidity != null) '${t.humidity} %',
      if (t != null && t.batteryMv != null) '${t.batteryMv} mV',
      if (t != null && t.lowBattery) 'low battery',
      if (t != null && t.moving != null) '${t.moving! ? 'moving' : 'still'} ${t.movementCount}',
      if (t != null && t.pitch != null) '${t.pitch}°/${t.roll}°',
      if (t != null && t.magnetDetected == true) 'magnet',
      if (data.name != null && t == null) '"${data.name}"',
    ];
    if (t != null && !t.ok) parts.add(t.error!);
    return parts.isEmpty ? (data.isEmpty ? 'empty' : '—') : parts.join(' · ');
  }
}

/// CSV for received-packet logs: ASCII headers, one row per packet, opens straight in Excel.
abstract final class RxCsv {
  static const header = 'time_utc,time_local,mac,name,tag,kind,rssi_dbm,gap_ms,protocol_version,flags_hex,'
      'battery_mv,low_battery,temperature_c,humidity_pct,moving,movement_count,pitch_deg,roll_deg,magnet,raw_hex';

  static String row(RxEntry e, {required String mac, String? name, String? tag}) {
    final t = e.teltonika;
    final l = e.time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final local = '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}:${two(l.second)}.'
        '${l.millisecond.toString().padLeft(3, '0')}';
    return [
      e.time.toUtc().toIso8601String(),
      local,
      mac,
      _q(name),
      _q(tag),
      e.kind,
      e.rssi?.toString() ?? '',
      e.gapMs?.toString() ?? '',
      t?.version?.toString() ?? '',
      t?.flags == null ? '' : t!.flags!.toRadixString(16).padLeft(2, '0').toUpperCase(),
      t?.batteryMv?.toString() ?? '',
      t == null ? '' : (t.lowBattery ? '1' : '0'),
      t?.temperatureC?.toStringAsFixed(2) ?? '',
      t?.humidity?.toString() ?? '',
      t?.moving == null ? '' : (t!.moving! ? '1' : '0'),
      t?.movementCount?.toString() ?? '',
      t?.pitch?.toString() ?? '',
      t?.roll?.toString() ?? '',
      t?.magnetDetected == null ? '' : (t!.magnetDetected! ? '1' : '0'),
      toHex(e.bytes),
    ].join(',');
  }

  static String document(Iterable<RxEntry> entries, {required String mac, String? name, String? tag}) {
    final b = StringBuffer()..writeln(header);
    for (final e in entries) {
      b.writeln(row(e, mac: mac, name: name, tag: tag));
    }
    return b.toString();
  }

  /// Quotes a text field when it holds a comma, a quote or a line break.
  static String _q(String? s) {
    if (s == null || s.isEmpty) return '';
    if (!s.contains(RegExp('[,"\n\r]'))) return s;
    return '"${s.replaceAll('"', '""')}"';
  }

  /// `BluePulse_Cold-room-2_7CD9F4152CD4_20261109-161502.csv`
  static String fileName({required String label, required String mac, required DateTime time}) {
    final safe = label.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-').replaceAll(RegExp('-+'), '-');
    String two(int v) => v.toString().padLeft(2, '0');
    final l = time.toLocal();
    final stamp = '${l.year}${two(l.month)}${two(l.day)}-${two(l.hour)}${two(l.minute)}${two(l.second)}';
    return 'BluePulse_${safe}_${mac.replaceAll(':', '')}_$stamp.csv';
  }
}

/// Writes one device's packets to a CSV file as they arrive, for long tests.
class RxRecorder {
  RxRecorder._(this.file, this._sink, this.started, {required this.mac, this.name, this.tag});

  static Future<RxRecorder> start(File file, {required String mac, String? name, String? tag}) async {
    await file.parent.create(recursive: true);
    final sink = file.openWrite()..writeln(RxCsv.header);
    return RxRecorder._(file, sink, DateTime.now(), mac: mac, name: name, tag: tag);
  }

  final File file;
  final IOSink _sink;
  final DateTime started;
  final String mac;
  final String? name;
  final String? tag;
  int rows = 0;
  bool _closed = false;

  void write(RxEntry e) {
    if (_closed) return;
    _sink.writeln(RxCsv.row(e, mac: mac, name: name, tag: tag));
    rows++;
  }

  Future<File> stop() async {
    if (!_closed) {
      _closed = true;
      await _sink.flush();
      await _sink.close();
    }
    return file;
  }
}
