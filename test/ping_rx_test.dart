import 'dart:io';

import 'package:bluepulse/app/settings.dart';
import 'package:bluepulse/core/device_book.dart';
import 'package:bluepulse/core/ping_stats.dart';
import 'package:bluepulse/core/registry.dart';
import 'package:bluepulse/core/rx_log.dart';
import 'package:bluepulse/ui/widgets/charts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

void main() {
  final t0 = DateTime(2026, 11, 9, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  group('ping stats', () {
    test('count, avg / min / max / last gap and jitter over the window', () {
      final times = [at(0), at(5000), at(10000), at(20000), at(25000)]; // one missed ping at 15 s
      final s = PingStats.compute(
        times: times,
        allGapsMs: const [5000, 5000, 10000, 5000, 5000, 5000],
        now: at(26000),
        window: const Duration(minutes: 5),
        firstSeen: at(0),
      );
      expect(s.pings, 5);
      expect(s.avg, const Duration(milliseconds: 6250));
      expect(s.min, const Duration(seconds: 5));
      expect(s.max, const Duration(seconds: 10));
      expect(s.last, const Duration(seconds: 5));
      expect(s.jitter, const Duration(milliseconds: 2165)); // sd of 5,5,10,5 s
      expect(s.expected, const Duration(seconds: 5));
      expect(s.receivedPercent, closeTo(5 / (26 / 5) * 100, 0.1));
    });

    test('pings outside the window are left out', () {
      final s = PingStats.compute(
        times: [at(0), at(60000), at(65000)],
        allGapsMs: const [],
        now: at(66000),
        window: const Duration(seconds: 30),
        firstSeen: at(0),
      );
      expect(s.pings, 2);
      expect(s.avg, const Duration(seconds: 5));
      expect(s.receivedPercent, isNull, reason: 'no interval estimate from fewer than five gaps');
    });

    test('the interval estimate ignores missed pings', () {
      expect(PingStats.estimateInterval(const [5000, 10000, 5010, 15000, 4990, 5000, 10000, 5000, 5000, 4995]),
          const Duration(milliseconds: 4995));
      expect(PingStats.estimateInterval(const [5000, 5000]), isNull);
    });

    test('no pings', () {
      final s = PingStats.compute(
          times: const [], allGapsMs: const [], now: t0, window: const Duration(minutes: 5), firstSeen: t0);
      expect(s.pings, 0);
      expect(s.avg, isNull);
    });
  });

  group('device log', () {
    late DeviceRegistry r;
    setUp(() => r = DeviceRegistry(AppSettings(null, false), book: DeviceBook(null)));
    tearDown(() => r.dispose());

    test('every packet is kept with its gap, and a ping is an advertising event', () {
      r.ingest(event('AA:00:00:00:00:01', beaconAdv, at: at(0)));
      r.ingest(event('AA:00:00:00:00:01', beaconRsp, at: at(12)));
      r.ingest(event('AA:00:00:00:00:01', beaconAdv, at: at(5000)));
      r.ingest(event('AA:00:00:00:00:01', beaconRsp, at: at(5012)));
      final d = r.device('AA:00:00:00:00:01')!;
      expect(d.rx.length, 4);
      expect(d.rx.map((e) => e.gapMs), [null, 12, 4988, 12]);
      expect(d.pingTimes.length, 2, reason: 'advertisement + scan response = one ping');
      expect(d.rx.last.teltonika!.batteryMv, 2990);
    });

    test('devices out of focus are still logged in full', () {
      r.book.toggleFocus('AA:00:00:00:00:99');
      for (var i = 0; i < 20; i++) {
        r.ingest(event('AA:00:00:00:00:01', beaconRsp, at: at(100 * i)));
      }
      expect(r.device('AA:00:00:00:00:01')!.rx.length, 20);
    });

    test('recording writes each packet to the CSV file as it arrives', () async {
      final dir = Directory.systemTemp.createTempSync('eye-rec-');
      addTearDown(() => dir.deleteSync(recursive: true));
      r.ingest(event('AA:00:00:00:00:01', beaconRsp, at: at(0)));
      final d = r.device('AA:00:00:00:00:01')!;
      final file = File(p.join(dir.path, 'log.csv'));
      await r.startRecording(d, file);
      r.ingest(event('AA:00:00:00:00:01', beaconRsp, at: at(5000)));
      r.ingest(event('AA:00:00:00:00:01', beaconRsp, at: at(10000)));
      expect(r.recorder(d.mac)!.rows, 2);
      await r.stopRecording(d.mac);
      final lines = file.readAsLinesSync();
      expect(lines.first, RxCsv.header);
      expect(lines.length, 3);
      expect(lines[1], contains('AA:00:00:00:00:01'));
      expect(lines[1], contains(',2990,'));
      // No raw bytes in this test event, so the row carries the bytes rebuilt from its fields.
      expect(lines[1], contains('06FF9A08018063'));
      expect(lines[1], contains('0C094944315F41424344454647'));
    });
  });

  group('CSV', () {
    test('a row carries the decoded values and the raw bytes; names with commas are quoted', () {
      final r = DeviceRegistry(AppSettings(null, false));
      addTearDown(r.dispose);
      r.ingest(event('AA:00:00:00:00:02', sensorRsp, rssi: -70, at: at(0)));
      final e = r.device('AA:00:00:00:00:02')!.rx.single;
      final row = RxCsv.row(e, mac: 'AA:00:00:00:00:02', name: 'SNS_TEST01', tag: 'Cold room, 2');
      final cells = row.split(',');
      expect(row, contains('"Cold room, 2"'));
      expect(cells[6 + 1], '-70', reason: 'rssi (shifted one by the quoted comma)');
      expect(row, contains(',22.28,45,1,12,-10,90,1,'));
      expect(RxCsv.header.split(',').length, 20);
    });

    test('file name is safe and names the device', () {
      final n = RxCsv.fileName(label: 'Cold room / 2', mac: '7C:D9:F4:15:2C:D4', time: DateTime(2026, 11, 9, 16, 15, 2));
      expect(n, 'BluePulse_Cold-room-2_7CD9F4152CD4_20261109-161502.csv');
    });
  });

  group('chart stats', () {
    test('now / avg / min / max over the window only', () {
      final points = [
        ChartPoint(at(0), -90),
        ChartPoint(at(60000), -60),
        ChartPoint(at(70000), -70),
        ChartPoint(at(80000), -50),
      ];
      final s = SeriesStats.of(points, at(30000), at(90000))!;
      expect(s.now, -50);
      expect(s.min, -70);
      expect(s.max, -50);
      expect(s.avg, -60);
      expect(s.count, 3);
      expect(SeriesStats.of(points, at(100000), at(110000)), isNull);
    });
  });

  group('chart layout', () {
    test('saved order and visibility; charts added later are appended; reset', () {
      final book = DeviceBook(null);
      expect(book.chartLayout('eyeSensor').first.id, ChartSlot.signal);
      book.setChartLayout('eyeSensor', const [
        ChartSlot(ChartSlot.temperature, full: true),
        ChartSlot(ChartSlot.signal, visible: false),
      ]);
      final l = book.chartLayout('eyeSensor');
      expect(l.take(2).map((s) => s.id), [ChartSlot.temperature, ChartSlot.signal]);
      expect(l[1].visible, isFalse);
      expect(l.length, ChartSlot.defaults.length, reason: 'unlisted charts are appended');
      expect(book.chartLayout('eyeBeacon').first.id, ChartSlot.signal, reason: 'layouts are per device kind');
      book.resetChartLayout('eyeSensor');
      expect(book.chartLayout('eyeSensor').first.id, ChartSlot.signal);
    });

    test('window choices', () {
      final book = DeviceBook(null);
      expect(book.windowMinutes, 10);
      book.setWindowMinutes(5);
      expect(book.windowMinutes, 5);
      book.setWindowMinutes(7);
      expect(book.windowMinutes, 5, reason: 'only 5 / 10 / 15');
    });
  });
}
