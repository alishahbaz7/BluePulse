import '../usage/usage_service.dart';

/// What BluePulse is doing right now, read once a tick.
class ScanSample {
  const ScanSample({
    required this.scanning,
    required this.demo,
    required this.bluetooth,
    required this.devices,
    required this.totalPackets,
  });

  final bool scanning;
  final bool demo;
  final String bluetooth;

  /// Addresses of the devices in the registry. Counted here; never sent.
  final Iterable<String> devices;

  /// The registry's packet counter (it restarts when the registry is cleared).
  final int totalPackets;
}

/// BluePulse's own counters for one session, sent as its usage `metrics`: time scanning real
/// Bluetooth and time on demo data, how many different devices and how many packets were heard over
/// real Bluetooth (counts only — no address leaves the device), and Bluetooth as last seen.
class ScanMetrics implements UsageMetrics {
  ScanMetrics(this.read);

  final ScanSample Function() read;

  Duration live = Duration.zero;
  Duration demo = Duration.zero;
  int packets = 0;
  String? bluetooth;
  final _macs = <String>{};
  int _lastPackets = 0;

  int get devices => _macs.length;

  @override
  void measure(Duration elapsed) {
    final s = read();
    if (s.scanning) {
      if (s.demo) {
        demo += elapsed;
      } else {
        live += elapsed;
      }
    }
    if (!s.demo) {
      _macs.addAll(s.devices);
      final total = s.totalPackets;
      packets += total >= _lastPackets ? total - _lastPackets : total;
      bluetooth = s.bluetooth;
    }
    _lastPackets = s.totalPackets;
  }

  @override
  Map<String, Object?> toJson() => {
        'liveSeconds': live.inSeconds,
        'demoSeconds': demo.inSeconds,
        'devices': devices,
        'packets': packets,
        'bluetooth': ?bluetooth,
      };
}
