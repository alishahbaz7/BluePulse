import 'dart:async';

import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/foundation.dart';

import '../app/settings.dart';
import '../scanner/scanner.dart';
import 'device.dart';
import 'signal.dart';

/// One packet as received, for the Packets page.
class PacketEntry {
  PacketEntry(this.seq, this.time, this.mac, this.rssi, this.data, this.decoded);

  final int seq;
  final DateTime time;
  final String mac;
  final int? rssi;
  final AdvertisementData data;
  final DecodedAdvertisement decoded;

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

/// Every device heard this session, merged by MAC. Notifies at most four times a second, and once
/// a second while devices exist so *last seen* and *not seen* stay current.
class DeviceRegistry extends ChangeNotifier {
  DeviceRegistry(this.settings) {
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_devices.isNotEmpty) notifyListeners();
    });
  }

  final AppSettings settings;
  final _devices = <String, EyeDevice>{};
  final _smoothers = <String, RssiSmoother>{};
  final packets = Ring<PacketEntry>(500);
  final _perMinute = <int, int>{};
  int _seq = 0;
  Timer? _tick;
  Timer? _pending;
  bool _disposed = false;

  DateTime? sessionStart;

  /// Devices that pass the current filter (EYE only unless *all beacons* is on).
  List<EyeDevice> get devices => _devices.values
      .where((d) => settings.showAllBeacons || d.model.isEye)
      .toList(growable: false);

  EyeDevice? device(String mac) => _devices[mac];

  int get totalPackets => _seq;

  void startSession() {
    sessionStart ??= DateTime.now();
  }

  void clear() {
    _devices.clear();
    _smoothers.clear();
    packets.clear();
    _perMinute.clear();
    _seq = 0;
    sessionStart = null;
    notifyListeners();
  }

  void ingest(ScanEvent e) {
    final decoded = decodeAdvertisement(e.data);
    var d = _devices[e.deviceId];
    if (d == null) {
      final eyeName = e.data.name?.startsWith('ID1_') ?? false;
      // Only beacons and EYE devices are tracked; phones, earbuds and the rest are ignored.
      if (!decoded.isTeltonika && !decoded.isBeacon && !eyeName) return;
      d = _devices[e.deviceId] = EyeDevice(e.deviceId, firstSeen: e.time);
    }
    final smoother = _smoothers.putIfAbsent(e.deviceId, () => RssiSmoother(settings.averagingSeconds))
      ..timeoutSeconds = settings.averagingSeconds;
    final readingsBefore = d.readings;
    d.apply(time: e.time, rssi: e.rssi, data: e.data, decoded: decoded, smoother: smoother);
    if (d.readings != readingsBefore) {
      final minute = e.time.millisecondsSinceEpoch ~/ 60000;
      _perMinute[minute] = (_perMinute[minute] ?? 0) + 1;
      _perMinute.removeWhere((k, _) => k < minute - 120);
    }
    packets.add(PacketEntry(++_seq, e.time, e.deviceId, e.rssi, e.data, decoded));
    _schedule();
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

  void _schedule() {
    if (_pending != null || _disposed) return;
    _pending = Timer(const Duration(milliseconds: 250), () {
      _pending = null;
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
