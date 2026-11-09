import 'dart:collection';

import 'package:eye_protocol/eye_protocol.dart';

import 'signal.dart';

enum DeviceModel { eyeBeacon, eyeSensor, eyeDevice, otherBeacon }

extension DeviceModelLabel on DeviceModel {
  String get label => switch (this) {
        DeviceModel.eyeBeacon => 'EYE BEACON',
        DeviceModel.eyeSensor => 'EYE SENSOR',
        DeviceModel.eyeDevice => 'EYE device',
        DeviceModel.otherBeacon => 'Other beacon',
      };

  bool get isEye => this != DeviceModel.otherBeacon;
}

/// A value at a time, for charts.
class Sample {
  const Sample(this.time, this.value);
  final DateTime time;
  final double value;
}

class RssiSample {
  const RssiSample(this.time, this.raw, this.smoothed);
  final DateTime time;
  final int raw;
  final double smoothed;
}

/// A fixed-size history: the oldest entry drops when a new one arrives over [capacity].
class Ring<T> extends IterableBase<T> {
  Ring(this.capacity);
  final int capacity;
  final _q = ListQueue<T>();

  void add(T v) {
    _q.addLast(v);
    while (_q.length > capacity) {
      _q.removeFirst();
    }
  }

  T? get lastOrNull => _q.isEmpty ? null : _q.last;

  void clear() => _q.clear();

  @override
  Iterator<T> get iterator => _q.iterator;

  @override
  int get length => _q.length;
}

/// Readings closer together than this belong to one advertising event (an advertisement and its
/// scan response, or a burst of repeats).
const readingGapMs = 600;

/// Everything known about one device in this session.
class EyeDevice {
  EyeDevice(this.mac, {required this.firstSeen}) : lastSeen = firstSeen;

  final String mac;
  final DateTime firstSeen;
  DateTime lastSeen;

  String? name;
  AdvertisementData merged = const AdvertisementData();
  BeaconId? beaconId;
  int? txPower1m;

  TeltonikaData? teltonika;
  DateTime? teltonikaAt;
  bool teltonikaSeen = false;

  /// OR of every flags byte seen, so a sensor stays a sensor when one packet drops a value.
  int flagsSeen = 0;

  int? rssi;
  double? smoothed;
  int packets = 0;
  int readings = 0;

  DateTime? _lastReadingAt;
  final _gaps = Ring<int>(24);

  /// When the last packet was fully applied (decoded, charted). Devices out of focus are applied
  /// only every few seconds; their counters stay exact through [touch].
  DateTime lastApplied = DateTime.fromMillisecondsSinceEpoch(0);

  /// Arrival times (ms) of the packets in the last [rateWindow], for [packetsPerSecond].
  final _recent = ListQueue<int>();
  static const rateWindow = Duration(seconds: 10);

  final rssiHistory = Ring<RssiSample>(3000);
  final batteryHistory = Ring<Sample>(1500);
  final temperatureHistory = Ring<Sample>(1500);
  final humidityHistory = Ring<Sample>(1500);
  final movementHistory = Ring<Sample>(1500);
  final pitchHistory = Ring<Sample>(1500);
  final rollHistory = Ring<Sample>(1500);

  DeviceModel get model {
    if (flagsSeen & EyeFlag.sensorBits != 0) return DeviceModel.eyeSensor;
    if (name?.startsWith('ID1_') ?? false) return DeviceModel.eyeBeacon;
    if (teltonikaSeen) return DeviceModel.eyeBeacon;
    return DeviceModel.otherBeacon;
  }

  /// Median gap between advertising events, ms.
  int? get intervalMs => median(_gaps.toList());

  int? get batteryMv => teltonika?.batteryMv;
  bool get lowBattery => teltonika?.lowBattery ?? false;

  /// Silence longer than this means *not seen*.
  Duration notSeenAfter(int minSeconds) {
    final i = intervalMs;
    final ms = i == null ? minSeconds * 1000 : (i * 3).clamp(minSeconds * 1000, 1 << 31);
    return Duration(milliseconds: ms);
  }

  bool isNotSeen(DateTime now, int minSeconds) => now.difference(lastSeen) > notSeenAfter(minSeconds);

  /// Packets per second over the last [rateWindow] (or since first seen, if sooner).
  double packetsPerSecond(DateTime now) {
    final cutoff = now.millisecondsSinceEpoch - rateWindow.inMilliseconds;
    while (_recent.isNotEmpty && _recent.first < cutoff) {
      _recent.removeFirst();
    }
    final span = now.difference(firstSeen).inMilliseconds.clamp(1000, rateWindow.inMilliseconds);
    return _recent.length * 1000 / span;
  }

  /// Counts a packet without decoding it — for devices out of focus between full updates.
  void touch(DateTime time) => _count(time);

  void _count(DateTime time) {
    packets++;
    lastSeen = time;
    final ms = time.millisecondsSinceEpoch;
    _recent.addLast(ms);
    while (_recent.isNotEmpty && _recent.first < ms - rateWindow.inMilliseconds) {
      _recent.removeFirst();
    }
    final last = _lastReadingAt;
    final gap = last == null ? null : time.difference(last).inMilliseconds;
    // A negative gap is a clock jump: a new reading, but not a gap worth measuring.
    if (gap == null || gap > readingGapMs || gap < 0) {
      if (gap != null && gap > 0) _gaps.add(gap);
      _lastReadingAt = time;
      readings++;
    }
  }

  /// Applies one advertisement or scan response in full.
  void apply({
    required DateTime time,
    required int? rssi,
    required AdvertisementData data,
    required DecodedAdvertisement decoded,
    required RssiSmoother smoother,
  }) {
    _count(time);
    lastApplied = time;
    merged = merged.merge(data);
    if (decoded.name != null) name = decoded.name;
    if (decoded.beaconId != null) beaconId = decoded.beaconId;
    if (decoded.txPower1m != null) txPower1m = decoded.txPower1m;

    if (rssi != null && rssi < 0) {
      this.rssi = rssi;
      smoothed = smoother.add(rssi, time);
      rssiHistory.add(RssiSample(time, rssi, smoothed!));
    }

    final t = decoded.teltonika;
    if (t != null) {
      teltonika = t;
      teltonikaAt = time;
      teltonikaSeen = true;
      if (t.flags != null) flagsSeen |= t.flags!;
      if (t.batteryMv != null) batteryHistory.add(Sample(time, t.batteryMv!.toDouble()));
      if (t.temperatureC != null) temperatureHistory.add(Sample(time, t.temperatureC!));
      if (t.humidity != null) humidityHistory.add(Sample(time, t.humidity!.toDouble()));
      if (t.movementCount != null) movementHistory.add(Sample(time, t.movementCount!.toDouble()));
      if (t.pitch != null) pitchHistory.add(Sample(time, t.pitch!.toDouble()));
      if (t.roll != null) rollHistory.add(Sample(time, t.roll!.toDouble()));
    }
  }

  /// Text the device list searches.
  String get searchText => [mac, name ?? '', beaconId?.display ?? '', model.label].join(' ').toLowerCase();
}
