import 'package:bluepulse/app/scan_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BluePulse counts scanning time, devices and packets heard over real Bluetooth only', () {
    var sample = const ScanSample(scanning: true, demo: false, bluetooth: 'on', devices: ['A', 'B'], totalPackets: 40);
    final m = ScanMetrics(() => sample);
    const minute = Duration(minutes: 1);

    m.measure(minute);
    sample = const ScanSample(scanning: true, demo: false, bluetooth: 'on', devices: ['B', 'C'], totalPackets: 100);
    m.measure(minute);
    // The registry was cleared (its packet count restarts) and the source switched to demo data.
    sample = const ScanSample(scanning: true, demo: true, bluetooth: 'on', devices: ['D1', 'D2'], totalPackets: 5);
    m.measure(minute);
    sample = const ScanSample(scanning: false, demo: false, bluetooth: 'off', devices: [], totalPackets: 0);
    m.measure(minute);

    expect(m.toJson(), {
      'liveSeconds': 120,
      'demoSeconds': 60,
      'devices': 3, // A, B, C — demo devices are not counted
      'packets': 100,
      'bluetooth': 'off',
    });
  });

  test('before any real Bluetooth reading, its state is left out', () {
    final m = ScanMetrics(() => const ScanSample(scanning: true, demo: true, bluetooth: 'on', devices: ['D'], totalPackets: 9));
    m.measure(const Duration(seconds: 30));
    expect(m.toJson(), {'liveSeconds': 0, 'demoSeconds': 30, 'devices': 0, 'packets': 0});
  });
}
