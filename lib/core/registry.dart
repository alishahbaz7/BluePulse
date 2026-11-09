import 'dart:async';

import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/foundation.dart';

import '../app/settings.dart';
import '../scanner/scanner.dart';
import 'device.dart';
import 'device_book.dart';
import 'signal.dart';

/// One packet as received, for the Packets page.
class PacketEntry {
  PacketEntry(this.seq, this.time, this.mac, this.rssi, this.data, this.decoded, {this.raw, this.scanResponse});

  final int seq;
  final DateTime time;
  final String mac;
  final int? rssi;
  final AdvertisementData data;
  final DecodedAdvertisement decoded;

  /// The bytes exactly as received, when the scanner provides them.
  final Uint8List? raw;
  final bool? scanResponse;

  /// The inspector's view: the real bytes when known, otherwise rebuilt from the parsed fields.
  AnnotatedPacket get annotated => raw != null ? annotateRaw(raw!) : annotateStructures(data.toStructures());

  String get kind => switch (scanResponse) {
        true => 'Scan response',
        false => 'Advertisement',
        null => '—',
      };

  /// What the packet carried, in a few words.
  String get summary {
    final parts = <String>[];
    final id = decoded.beaconId;
    if (id != null) parts.add(id.kindLabel);
    final e = decoded.eddystone;
    if (e != null && e is! EddystoneUid) parts.add('Eddystone ${e.kind}');
    final t = decoded.teltonika;
    if (t != null) {
      if (!t.ok) {
        parts.add('Teltonika · ${t.error}');
      } else {
        final values = <String>[
          if (t.temperatureC != null) '${t.temperatureC!.toStringAsFixed(2)} °C',
          if (t.humidity != null) '${t.humidity} %',
          if (t.batteryMv != null) '${t.batteryMv} mV',
          if (t.lowBattery) 'low battery',
        ];
        parts.add(values.isEmpty ? 'Teltonika' : 'Teltonika · ${values.join(' · ')}');
      }
    }
    if (data.name != null) parts.add('"${data.name}"');
    return parts.isEmpty ? '—' : parts.join(' · ');
  }
}

/// Every device heard this session, merged by MAC.
///
/// Focus ([book]): with nothing in focus every packet is applied and the screen refreshes four times
/// a second. With devices in focus, those get every packet and up to ten refreshes a second, while
/// the rest are counted exactly but applied only every [backgroundInterval] — 2 s on a quiet radio,
/// up to 10 s on a busy one — and refresh the screen once a second.
class DeviceRegistry extends ChangeNotifier {
  DeviceRegistry(this.settings, {DeviceBook? book}) : book = book ?? DeviceBook(null) {
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_devices.isNotEmpty) notifyListeners();
    });
  }

  final AppSettings settings;
  final DeviceBook book;
  final _devices = <String, EyeDevice>{};
  final _smoothers = <String, RssiSmoother>{};
  final packets = Ring<PacketEntry>(500);
  final _perMinute = <int, int>{};
  final _perSecond = <int, int>{};
  int _seq = 0;
  int _received = 0;
  Timer? _tick;
  Timer? _pending;
  DateTime? _pendingDue;
  bool _disposed = false;

  DateTime? sessionStart;

  /// Devices that pass the current filter (EYE only unless *all beacons* is on).
  List<EyeDevice> get devices => _devices.values
      .where((d) => settings.showAllBeacons || d.model.isEye)
      .toList(growable: false);

  EyeDevice? device(String mac) => _devices[mac];

  /// Packets fully applied (and logged).
  int get totalPackets => _seq;

  /// Every packet from a tracked device, applied or only counted.
  int get receivedPackets => _received;

  /// Packets per second from tracked devices over the last 10 s.
  double packetRate(DateTime now) {
    final s = now.millisecondsSinceEpoch ~/ 1000;
    var n = 0;
    for (var i = s - 9; i <= s; i++) {
      n += _perSecond[i] ?? 0;
    }
    return n / 10;
  }

  /// How often a device out of focus is fully updated: longer when the radio is busy.
  Duration backgroundInterval(DateTime now) {
    final rate = packetRate(now);
    if (rate < 30) return const Duration(seconds: 2);
    if (rate < 150) return const Duration(seconds: 5);
    return const Duration(seconds: 10);
  }

  void startSession() {
    sessionStart ??= DateTime.now();
  }

  void clear() {
    _devices.clear();
    _smoothers.clear();
    packets.clear();
    _perMinute.clear();
    _perSecond.clear();
    _seq = 0;
    _received = 0;
    sessionStart = null;
    notifyListeners();
  }

  void ingest(ScanEvent e) {
    var d = _devices[e.deviceId];
    final fast = book.fast(e.deviceId);
    if (d != null) {
      _received++;
      final second = e.time.millisecondsSinceEpoch ~/ 1000;
      _perSecond[second] = (_perSecond[second] ?? 0) + 1;
      if (_perSecond.length > 30) _perSecond.removeWhere((k, _) => k < second - 15);
      // Out of focus and updated recently: count it, skip the decoding and the charts.
      if (!fast && e.time.difference(d.lastApplied) < backgroundInterval(e.time)) {
        final readingsBefore = d.readings;
        d.touch(e.time);
        _countReading(d, readingsBefore, e.time);
        _schedule(fast: false);
        return;
      }
    }
    final decoded = decodeAdvertisement(e.data);
    if (d == null) {
      final eyeName = e.data.name?.startsWith('ID1_') ?? false;
      // Only beacons and EYE devices are tracked; phones, earbuds and the rest are ignored.
      if (!decoded.isTeltonika && !decoded.isBeacon && !eyeName) return;
      d = _devices[e.deviceId] = EyeDevice(e.deviceId, firstSeen: e.time);
      _received++;
      final second = e.time.millisecondsSinceEpoch ~/ 1000;
      _perSecond[second] = (_perSecond[second] ?? 0) + 1;
    }
    final smoother = _smoothers.putIfAbsent(e.deviceId, () => RssiSmoother(settings.averagingSeconds))
      ..timeoutSeconds = settings.averagingSeconds;
    final readingsBefore = d.readings;
    d.apply(time: e.time, rssi: e.rssi, data: e.data, decoded: decoded, smoother: smoother);
    _countReading(d, readingsBefore, e.time);
    packets.add(PacketEntry(++_seq, e.time, e.deviceId, e.rssi, e.data, decoded,
        raw: e.raw, scanResponse: e.scanResponse));
    _schedule(fast: fast);
  }

  void _countReading(EyeDevice d, int readingsBefore, DateTime time) {
    if (d.readings == readingsBefore) return;
    final minute = time.millisecondsSinceEpoch ~/ 60000;
    _perMinute[minute] = (_perMinute[minute] ?? 0) + 1;
    _perMinute.removeWhere((k, _) => k < minute - 120);
  }

  /// Readings (advertising events) per minute for the last [minutes] minutes, oldest first; the
  /// last bucket is the current, unfinished minute.
  List<int> readingsPerMinute(DateTime now, int minutes) {
    final current = now.millisecondsSinceEpoch ~/ 60000;
    return [for (var m = current - minutes + 1; m <= current; m++) _perMinute[m] ?? 0];
  }

  Proximity proximityOf(EyeDevice d, DateTime now) => classifyProximity(
        d.smoothed,
        nearDbm: settings.nearDbm,
        awayDbm: settings.awayDbm,
        notSeen: d.isNotSeen(now, settings.notSeenMinSeconds),
      );

  double? distanceOf(EyeDevice d) => estimateDistance(d.smoothed, d.txPower1m, settings.pathLossExponent);

  /// Refresh the screen soon: 100 ms for a device in focus, 250 ms with nothing in focus, 1 s for a
  /// device out of focus. A sooner refresh replaces a later one already waiting.
  void _schedule({required bool fast}) {
    if (_disposed) return;
    final delay = !book.focusActive
        ? const Duration(milliseconds: 250)
        : (fast ? const Duration(milliseconds: 100) : const Duration(seconds: 1));
    final due = DateTime.now().add(delay);
    if (_pending != null && _pendingDue != null && !due.isBefore(_pendingDue!)) return;
    _pending?.cancel();
    _pendingDue = due;
    _pending = Timer(delay, () {
      _pending = null;
      _pendingDue = null;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    _pending?.cancel();
    super.dispose();
  }
}
