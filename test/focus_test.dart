import 'dart:typed_data';

import 'package:bluepulse/app/settings.dart';
import 'package:bluepulse/core/device_book.dart';
import 'package:bluepulse/core/registry.dart';
import 'package:bluepulse/scanner/windows_ble_scanner.dart';
import 'package:bluepulse_ble_windows/bluepulse_ble_windows.dart';
import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// EYE SENSOR advertisement carrying its data (the shape seen on air), temperature [t] × 0.01 °C.
String sensorAdv(int t) {
  final hex = (t & 0xFFFF).toRadixString(16).padLeft(4, '0');
  return '0B 09 4D50315F314645313337 0E FF 9A 08 01 BF $hex 2D 80 0C F6 00 5A 64';
}

void main() {
  late AppSettings settings;
  late DeviceBook book;
  late DeviceRegistry r;
  final t0 = DateTime(2026, 11, 9, 12);
  const a = 'AA:00:00:00:00:01', b = 'AA:00:00:00:00:02';

  setUp(() {
    settings = AppSettings(null, false);
    book = DeviceBook(null);
    r = DeviceRegistry(settings, book: book);
  });
  tearDown(() => r.dispose());

  /// Ten packets a second for [seconds] from each device, temperature rising one step per packet.
  void feed(int seconds) {
    for (var i = 0; i < seconds * 10; i++) {
      final at = t0.add(Duration(milliseconds: 100 * i));
      r.ingest(event(a, sensorAdv(2000 + i), at: at));
      r.ingest(event(b, sensorAdv(2000 + i), at: at.add(const Duration(milliseconds: 5))));
    }
  }

  test('nothing in focus: every packet applied for every device', () {
    feed(3);
    expect(r.device(a)!.temperatureHistory.length, 30);
    expect(r.device(b)!.temperatureHistory.length, 30);
    expect(r.totalPackets, 60);
  });

  test('a device in focus gets every packet; the rest are counted but applied every 2 s', () {
    book.toggleFocus(a);
    feed(6);
    final fa = r.device(a)!, fb = r.device(b)!;
    expect(fa.temperatureHistory.length, 60, reason: 'in focus: every packet charted');
    expect(fb.temperatureHistory.length, inInclusiveRange(3, 4), reason: 'out of focus: one every 2 s');
    expect(fb.packets, 60, reason: 'out-of-focus packets are still counted exactly');
    expect(fb.packetsPerSecond(t0.add(const Duration(seconds: 6))), closeTo(10, 0.5));
    expect(r.receivedPackets, 120);
    expect(r.totalPackets, lessThan(70), reason: 'only applied packets are logged');
  });

  test('out of focus, a scan response carrying the data is applied with its advertisement', () {
    // EYE BEACON in Eddystone mode: the advertisement has the ID, the scan response 12 ms later has
    // the name and the battery. Another device is in focus, so this one refreshes slowly.
    book.toggleFocus(b);
    for (var i = 0; i < 6; i++) {
      final at = t0.add(Duration(seconds: 5 * i));
      r.ingest(event(a, beaconAdv, at: at));
      r.ingest(event(a, beaconRsp, at: at.add(const Duration(milliseconds: 12))));
    }
    final d = r.device(a)!;
    expect(d.name, 'ID1_ABCDEFG');
    expect(d.batteryMv, 2990);
    expect(r.devices.map((x) => x.mac), contains(a), reason: 'recognised as an EYE device, so listed');
  });

  test('the newest values arrive for a device in focus (no stale repeats)', () {
    book.toggleFocus(a);
    feed(1);
    expect(r.device(a)!.teltonika!.temperatureC, closeTo(20.09, 1e-9));
  });

  test('an open device page focuses that device, and closing it lets go', () {
    book.setTemporaryFocus(b);
    expect(book.focusActive, isTrue);
    expect(book.fast(b), isTrue);
    expect(book.fast(a), isFalse);
    book.setTemporaryFocus(null);
    expect(book.focusActive, isFalse);
    expect(book.fast(a), isTrue);
  });

  test('a busy radio stretches the background interval', () {
    expect(r.backgroundInterval(t0), const Duration(seconds: 2));
    for (var i = 0; i < 2000; i++) {
      r.ingest(event(a, sensorAdv(2000), at: t0.add(Duration(milliseconds: 5 * i))));
    }
    expect(r.packetRate(t0.add(const Duration(seconds: 10))), greaterThan(150));
    expect(r.backgroundInterval(t0.add(const Duration(seconds: 10))), const Duration(seconds: 10));
  });

  group('tags', () {
    test('set, trim, clip, remove', () {
      book.setTag(a, '  Cold room 2  ');
      expect(book.tagOf(a), 'Cold room 2');
      book.setTag(a, 'x' * 60);
      expect(book.tagOf(a)!.length, DeviceBook.maxTagLength);
      book.setTag(a, '   ');
      expect(book.tagOf(a), isNull);
    });

    test('focus set survives clear only when asked', () {
      book.setFocus([a, b]);
      expect(book.focus, {a, b});
      book.clearFocus();
      expect(book.focus, isEmpty);
    });
  });

  test('a native Windows packet becomes a scan event with its exact bytes', () {
    final adv = RawAdvertisement.fromMessage({
      'a': 0x7CD9F4152CD4,
      'r': -61,
      't': WinAdvType.connectableUndirected,
      's': [
        [0x09, Uint8List.fromList('MP1_1FE137'.codeUnits)],
        [0xFF, parseHex('9A 08 01 80 63')],
      ],
    })!;
    expect(adv.mac, '7C:D9:F4:15:2C:D4');
    final e = scanEventFromRaw(adv, t0);
    expect(e.deviceId, '7C:D9:F4:15:2C:D4');
    expect(e.rssi, -61);
    expect(e.scanResponse, isFalse);
    expect(e.data.name, 'MP1_1FE137');
    expect(toHex(e.raw!), '0B094D50315F31464531333706FF9A08018063');
    expect(decodeTeltonika(e.data.manufacturerData[0x089A]!).batteryMv, 2990);
  });
}
