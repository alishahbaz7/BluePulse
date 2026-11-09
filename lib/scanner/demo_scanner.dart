import 'dart:async';
import 'dart:math';

import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/foundation.dart';

import 'scanner.dart';

enum _DemoKind { eddystone, iBeacon, sensor, foreign }

class _DemoDevice {
  _DemoDevice({
    required this.mac,
    required this.name,
    required this.kind,
    required this.idBytes,
    required this.intervalMs,
    required this.rssiBase,
    required this.batteryRaw,
    this.low = false,
    this.swing = false,
    this.vanishes = false,
  }) : rssi = rssiBase;

  final String mac;
  final String? name;
  final _DemoKind kind;
  final Uint8List idBytes;
  final int intervalMs;
  final double rssiBase;
  final int batteryRaw;
  final bool low;

  /// Walks in and out of range, through the proximity zones.
  final bool swing;

  /// Goes silent for a while every few minutes.
  final bool vanishes;

  double rssi;
  DateTime next = DateTime.now();
  double temp = 23.4;
  int humidity = 48;
  bool moving = false;
  int moveCount = 0;
  int pitch = 2;
  int roll = -4;
  bool magnet = false;
}

/// Generates EYE BEACON and EYE SENSOR traffic as real advertisement bytes, so everything after the
/// scanner — decoders, registry, pages — runs exactly as it would on air. The UI labels it *Demo*
/// everywhere it shows.
class DemoScanner implements BeaconScanner {
  DemoScanner({int? seed}) : _rng = Random(seed);

  final Random _rng;
  final _events = StreamController<ScanEvent>.broadcast();
  final _status = ValueNotifier(const ScannerStatus(radio: RadioState.on));
  Timer? _timer;
  final DateTime _epoch = DateTime.now();
  late final List<_DemoDevice> _devices = _build();

  @override
  bool get isDemo => true;

  @override
  ValueListenable<ScannerStatus> get status => _status;

  @override
  Stream<ScanEvent> get events => _events.stream;

  @override
  Future<void> init() async {}

  @override
  Future<void> start() async {
    _timer ??= Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    final now = DateTime.now();
    for (final d in _devices) {
      d.next = now.add(Duration(milliseconds: _rng.nextInt(d.intervalMs)));
    }
    _status.value = _status.value.copyWith(scanning: true);
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _status.value = _status.value.copyWith(scanning: false);
  }

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> enableRadio() async {}

  @override
  void dispose() {
    _timer?.cancel();
    _events.close();
    _status.dispose();
  }

  static Uint8List _hex(String s) => parseHex(s);

  List<_DemoDevice> _build() => [
        _DemoDevice(
          mac: 'DE:40:00:00:00:01',
          name: 'ID1_DEMO001',
          kind: _DemoKind.eddystone,
          idBytes: _hex('DE40DE40DE40DE40DE40 000000000001'),
          intervalMs: 5000,
          rssiBase: -58,
          batteryRaw: 103,
        ),
        _DemoDevice(
          mac: 'DE:40:00:00:00:02',
          name: 'ID1_DEMO002',
          kind: _DemoKind.eddystone,
          idBytes: _hex('DE40DE40DE40DE40DE40 000000000002'),
          intervalMs: 5000,
          rssiBase: -74,
          batteryRaw: 99,
          swing: true,
        ),
        _DemoDevice(
          mac: 'DE:40:00:00:00:03',
          name: 'ID1_DEMO003',
          kind: _DemoKind.iBeacon,
          idBytes: _hex('DE40DE4000004000800000000000000300010003'),
          intervalMs: 2000,
          rssiBase: -81,
          batteryRaw: 38,
          low: true,
        ),
        _DemoDevice(
          mac: 'DE:40:00:00:00:04',
          name: 'ID1_DEMO004',
          kind: _DemoKind.eddystone,
          idBytes: _hex('DE40DE40DE40DE40DE40 000000000004'),
          intervalMs: 5000,
          rssiBase: -88,
          batteryRaw: 101,
          vanishes: true,
        ),
        _DemoDevice(
          mac: 'DE:40:00:00:01:01',
          name: 'SNS_DEMO01',
          kind: _DemoKind.sensor,
          idBytes: _hex('DE40DE40DE40DE40DE40 000000000101'),
          intervalMs: 5000,
          rssiBase: -63,
          batteryRaw: 95,
        ),
        _DemoDevice(
          mac: 'DE:40:00:00:01:02',
          name: 'SNS_DEMO02',
          kind: _DemoKind.sensor,
          idBytes: _hex('DE40DE40DE40DE40DE40 000000000102'),
          intervalMs: 10000,
          rssiBase: -77,
          batteryRaw: 92,
        ),
        _DemoDevice(
          mac: 'DE:40:00:00:0F:01',
          name: null,
          kind: _DemoKind.foreign,
          idBytes: _hex('DE40DE4000004000800000000000F00100070001'),
          intervalMs: 1000,
          rssiBase: -70,
          batteryRaw: 0,
        ),
      ];

  double _noise(double spread) => (_rng.nextDouble() * 2 - 1) * spread;

  void _tick() {
    final now = DateTime.now();
    final t = now.difference(_epoch).inMilliseconds / 1000.0;
    for (final d in _devices) {
      if (now.isBefore(d.next)) continue;
      d.next = now.add(Duration(milliseconds: d.intervalMs + _rng.nextInt(40) - 20));
      if (d.vanishes && (t % 150) > 110) continue; // silent 40 s of every 150 s

      final base = d.swing ? -73 + 19 * sin(t * 2 * pi / 180) : d.rssiBase;
      d.rssi += (base - d.rssi) * 0.25 + _noise(1.5);
      final rssi = (d.rssi + _noise(3)).round().clamp(-100, -30);

      if (d.kind == _DemoKind.sensor) _stepSensor(d);

      _emit(d, now, rssi, _advertisement(d));
      final rsp = _scanResponse(d);
      if (rsp != null) {
        final later = now.add(const Duration(milliseconds: 12));
        _emit(d, later, rssi + _rng.nextInt(3) - 1, rsp, scanResponse: true);
      }
    }
  }

  void _stepSensor(_DemoDevice d) {
    d.temp = (d.temp + _noise(0.08)).clamp(18.0, 30.0);
    d.humidity = (d.humidity + _rng.nextInt(3) - 1).clamp(25, 75);
    if (_rng.nextDouble() < 0.06) d.moving = !d.moving;
    if (d.moving) {
      d.moveCount = (d.moveCount + 1) & 0x7FFF;
      d.pitch = (d.pitch + _rng.nextInt(11) - 5).clamp(-90, 90);
      d.roll = (d.roll + _rng.nextInt(21) - 10).clamp(-180, 180);
    }
    if (_rng.nextDouble() < 0.03) d.magnet = !d.magnet;
  }

  void _emit(_DemoDevice d, DateTime time, int rssi, Uint8List raw, {bool scanResponse = false}) {
    if (_events.isClosed) return;
    _events.add(ScanEvent(
      deviceId: d.mac,
      time: time,
      rssi: rssi,
      data: AdvertisementData.parse(raw),
      raw: raw,
      scanResponse: scanResponse,
    ));
  }

  static List<int> _ad(int type, List<int> data) => AdStructure(type, Uint8List.fromList(data)).toBytes();

  Uint8List _advertisement(_DemoDevice d) {
    final out = <int>[..._ad(AdType.flags, [0x06])];
    if (d.kind == _DemoKind.iBeacon || d.kind == _DemoKind.foreign) {
      out.addAll(_ad(AdType.manufacturerData, [0x4C, 0x00, 0x02, 0x15, ...d.idBytes, 0xC5]));
    } else {
      out.addAll(_ad(AdType.completeUuid16, [0xAA, 0xFE]));
      out.addAll(_ad(AdType.serviceData16, [0xAA, 0xFE, 0x00, 0xEE, ...d.idBytes, 0x00, 0x00]));
    }
    return Uint8List.fromList(out);
  }

  Uint8List? _scanResponse(_DemoDevice d) {
    if (d.kind == _DemoKind.foreign) return null;
    final values = <int>[];
    var flags = EyeFlag.batteryVoltage;
    if (d.low) flags |= EyeFlag.lowBattery;
    if (d.kind == _DemoKind.sensor) {
      flags |= EyeFlag.temperature |
          EyeFlag.humidity |
          EyeFlag.magnetPresent |
          EyeFlag.movementCounter |
          EyeFlag.movementAngle;
      if (d.magnet) flags |= EyeFlag.magnetDetected;
      final t = (d.temp * 100).round() & 0xFFFF;
      final move = (d.moving ? 0x8000 : 0) | d.moveCount;
      final roll = d.roll & 0xFFFF;
      values.addAll([
        t >> 8, t & 0xFF,
        d.humidity,
        move >> 8, move & 0xFF,
        d.pitch & 0xFF, roll >> 8, roll & 0xFF,
      ]);
    }
    final battery = (d.batteryRaw + (_rng.nextDouble() < 0.1 ? _rng.nextInt(3) - 1 : 0)).clamp(0, 255);
    values.add(battery);
    return Uint8List.fromList([
      ..._ad(AdType.completeName, d.name!.codeUnits),
      ..._ad(AdType.manufacturerData, [0x9A, 0x08, 0x01, flags, ...values]),
    ]);
  }
}
