import 'dart:typed_data';

import 'package:eye_protocol/eye_protocol.dart';
import 'package:test/test.dart';

/// Full Codec 8 Extended packets from the BTSID1 wiki page (PDF, oldid=117310).
const lostPacket = '000000000000004b8e010000018368952793000f0e54fc209ab05800b300b40e0000'
    '2a4f0001000000000000000000012a4f001e011c0001a40110eb47706aa38255aa96f21a154e2d00550d01000e020bd6010000823f';

const visiblePacket = '00000000000000898e0100000183a1c8fbe3000f0e310b209ab02600e900760d00002a4c0001000000000000000000012a4c005c011c0001c00110eb577075868d55aa96021b20313800550d0100'
    '0e020c1c1c0001b60110ef3f3f74868d55aa9aeae91e313800550d01000e020bae200001a50114faffffff34b6f6aa38255aa9ef619154d0e200050d01000e020ad20100008811';

void main() {
  group('CRC-16/IBM', () {
    test('check value', () => expect(crc16Ibm('123456789'.codeUnits), 0xBB3D));
  });

  group('AVL 385', () {
    test('T-20 one Eddystone beacon', () {
      final v = decodeAvl385(parseHex('11 01 E39B606AA38255AA8E46 0B154E2D0055 CF'));
      expect(v.error, isNull);
      expect(v.part, 1);
      expect(v.totalParts, 1);
      expect(v.beacons.length, 1);
      final b = v.beacons.single;
      expect(b.id!.isEddystone, isTrue);
      expect(b.id!.namespaceHex, 'E39B606AA38255AA8E46');
      expect(b.id!.instanceHex, '0B154E2D0055');
      expect(b.rssi, -49);
    });

    test('T-21 two iBeacons', () {
      final v = decodeAvl385(parseHex(
          '11 21 6B817F8A274D4FBDB62D33E1842F8DF8 014D 022B BF 21 A579723675064DC396A7C3520129F619 0000 0000 BF'));
      expect(v.error, isNull);
      expect(v.beacons.length, 2);
      expect(v.beacons[0].id!.uuid, '6B817F8A-274D-4FBD-B62D-33E1842F8DF8');
      expect(v.beacons[0].id!.major, 333);
      expect(v.beacons[0].id!.minor, 555);
      expect(v.beacons[0].rssi, -65);
      expect(v.beacons[1].id!.uuid, 'A5797236-7506-4DC3-96A7-C3520129F619');
      expect(v.beacons[1].id!.major, 0);
      expect(v.beacons[1].rssi, -65);
    });

    test('advanced-mode flags stop parsing and keep the rest raw', () {
      final v = decodeAvl385(parseHex('11 01 E39B606AA38255AA8E46 0B154E2D0055 CF 07 AABB'));
      expect(v.beacons.length, 1);
      expect(v.error, contains('0x07'));
      expect(toHex(v.tail), '07AABB');
    });

    test('truncated beacon', () {
      final v = decodeAvl385(parseHex('11 01 E39B606AA3'));
      expect(v.beacons, isEmpty);
      expect(v.error, contains('Truncated'));
    });
  });

  group('AVL 10828 / 10829 / 10831', () {
    test('lost beacon value', () {
      final v = decodeEyeBeaconList(
          parseHex('011c0001a40110eb47706aa38255aa96f21a154e2d00550d01000e020bd6'));
      expect(v.error, isNull);
      final b = v.beacons.single;
      expect(b.rssi, -92);
      expect(b.id!.namespaceHex, 'EB47706AA38255AA96F2');
      expect(b.id!.instanceHex, '1A154E2D0055');
      expect(b.lowBattery, isFalse);
      expect(b.batteryMv, 3030);
    });

    test('MAC and unknown parameters', () {
      final v = decodeEyeBeaconList(parseHex('01 0E 00 01 C0 0F 06 112233445566 63 01 07'));
      final b = v.beacons.single;
      expect(b.rssi, -64);
      expect(b.macText, '11:22:33:44:55:66');
      expect(toHex(b.otherParams[0x63]!), '07');
      expect(b.id, isNull);
    });

    test('wrong constant is reported, beacons still read', () {
      final v = decodeEyeBeaconList(parseHex('02 03 00 01 C0'));
      expect(v.error, contains('expected 0x01'));
      expect(v.beacons.single.rssi, -64);
    });

    test('dispatch by AVL ID', () {
      expect(decodeBeaconAvl(385, parseHex('11 01 ${'00' * 16} CF'))!.beacons.length, 1);
      expect(decodeBeaconAvl(10831, parseHex('01 03 00 01 C0'))!.beacons.length, 1);
      expect(decodeBeaconAvl(16, Uint8List(1)), isNull);
      expect(BeaconAvlId.name(10829), 'EYE beacons · Found / Away');
    });
  });

  group('Codec 8 Extended packets', () {
    test('T-22 lost beacon record (AVL 10831)', () {
      final p = decodeAvlPacket(parseHex(lostPacket));
      expect(p.problems, isEmpty);
      expect(p.framed, isTrue);
      expect(p.codecId, 0x8E);
      expect(p.dataLength, 75);
      expect(p.crcOk, isTrue);
      expect(p.crcField, 0x823F);
      expect(p.records.length, 1);

      final r = p.records.single;
      expect(r.timestamp, DateTime.utc(2022, 9, 23, 4, 22, 29, 11));
      expect(r.longitude, closeTo(25.25975, 1e-9));
      expect(r.latitude, closeTo(54.70086, 1e-9));
      expect(r.altitude, 179);
      expect(r.angle, 180);
      expect(r.satellites, 14);
      expect(r.eventIoId, 10831);

      final io = r.element(10831)!;
      expect(io.variableLength, isTrue);
      expect(io.size, 30);
      final v = decodeBeaconAvl(io.id, io.value)!;
      expect(v.beacons.single.rssi, -92);
      expect(v.beacons.single.batteryMv, 3030);
    });

    test('T-23 visible list with three beacons (AVL 10828)', () {
      final p = decodeAvlPacket(parseHex(visiblePacket));
      expect(p.problems, isEmpty);
      expect(p.crcField, 0x8811);
      final io = p.records.single.element(10828)!;
      expect(io.size, 92);
      final beacons = decodeEyeBeaconList(io.value).beacons;
      expect(beacons.map((b) => b.rssi), [-64, -74, -91]);
      expect(beacons.map((b) => b.batteryMv), [3100, 2990, 2770]);
      expect(beacons[0].id!.isEddystone, isTrue);
      expect(beacons[2].id!.isIBeacon, isTrue);
      expect(beacons[2].id!.uuid, 'FAFFFFFF-34B6-F6AA-3825-5AA9EF619154');
      expect(beacons[2].id!.major, 53474);
      expect(beacons[2].id!.minor, 5);
    });

    test('T-24 one flipped byte → CRC mismatch, records still shown', () {
      final bytes = parseHex(lostPacket);
      bytes[60] ^= 0x01;
      final p = decodeAvlPacket(bytes);
      expect(p.crcOk, isFalse);
      expect(p.problems.single, contains('CRC mismatch'));
      expect(p.records.length, 1);
    });

    test('bare data field without framing', () {
      final full = parseHex(lostPacket);
      final p = decodeAvlPacket(Uint8List.fromList(full.sublist(8, full.length - 4)));
      expect(p.framed, isFalse);
      expect(p.problems, isEmpty);
      expect(p.records.single.eventIoId, 10831);
    });

    test('truncated packet', () {
      final full = parseHex(lostPacket);
      final p = decodeAvlPacket(Uint8List.fromList(full.sublist(0, 40)));
      expect(p.ok, isFalse);
      expect(p.problems.join(' '), contains('Truncated'));
    });

    test('not an AVL packet', () {
      final p = decodeAvlPacket(parseHex('FF FF'));
      expect(p.problems.single, contains('Not an AVL packet'));
      expect(looksLikeAvlPacket(parseHex('FF FF')), isFalse);
      expect(looksLikeAvlPacket(parseHex(lostPacket)), isTrue);
    });

    test('Codec 8 record with 1/2/4/8-byte IO', () {
      // Codec 8: 1-byte IO IDs and counts, no variable-length group.
      final data = parseHex('08 01 '
          '0000018368952793 00 0f0e54fc 209ab058 00b3 00b4 0e 0000 '
          '00 04 01 15 03 01 42 2EE0 01 F1 0000601A 01 4E 0000000000000001 '
          '01');
      final crc = crc16Ibm(data);
      final framed = Uint8List.fromList(
          [0, 0, 0, 0, 0, 0, 0, data.length, ...data, 0, 0, crc >> 8, crc & 0xFF]);
      final p = decodeAvlPacket(framed);
      expect(p.problems, isEmpty);
      expect(p.codecName, 'Codec 8');
      final r = p.records.single;
      expect(r.element(0x15)!.unsigned, BigInt.from(3));
      expect(r.element(0x42)!.unsigned, BigInt.from(12000));
      expect(r.element(0xF1)!.unsigned, BigInt.from(24602));
      expect(r.element(0x4E)!.unsigned, BigInt.one);
    });
  });
}
