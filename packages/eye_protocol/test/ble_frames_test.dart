import 'dart:typed_data';

import 'package:eye_protocol/eye_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('hex', () {
    test('accepts spaced, coloned, 0x-prefixed and multi-line input', () {
      expect(parseHex('0A FF 9a 08'), [0x0A, 0xFF, 0x9A, 0x08]);
      expect(parseHex('0a:ff:9a:08'), [0x0A, 0xFF, 0x9A, 0x08]);
      expect(parseHex('0x0A, 0xFF\n0x9A 0x08'), [0x0A, 0xFF, 0x9A, 0x08]);
      expect(parseHex('  '), isEmpty);
    });

    test('rejects odd length and non-hex', () {
      expect(() => parseHex('ABC'), throwsFormatException);
      expect(() => parseHex('ZZ'), throwsFormatException);
    });

    test('formats', () {
      expect(toHex([0x9A, 0x08]), '9A08');
      expect(toHex([0x9A, 0x08], separator: ' ', upper: false), '9a 08');
      expect(hexLabel(0x089A, digits: 4), '0x089A');
      expect(formatMac([0x11, 0x22, 0x33, 0x44, 0x55, 0x66]), '11:22:33:44:55:66');
    });
  });

  group('Eddystone', () {
    test('T-10 UID frame', () {
      final f = decodeEddystone(parseHex('00 EE E39B606AA38255AA8E46 0B154E2D0055 00 00'));
      expect(f, isA<EddystoneUid>());
      final uid = f! as EddystoneUid;
      expect(uid.txPower0m, -18);
      expect(uid.txPower1m, -59);
      expect(toHex(uid.namespace), 'E39B606AA38255AA8E46');
      expect(toHex(uid.instance), '0B154E2D0055');
      expect(uid.id.display, 'E39B606AA38255AA8E46 · 0B154E2D0055');
      expect(uid.fields.last.label, 'Reserved');
    });

    test('UID without reserved bytes', () {
      final f = decodeEddystone(parseHex('00 EE E39B606AA38255AA8E46 0B154E2D0055'));
      expect(f, isA<EddystoneUid>());
    });

    test('short UID frame', () {
      final f = decodeEddystone(parseHex('00 EE E39B'));
      expect(f, isA<EddystoneOther>());
      expect((f! as EddystoneOther).error, contains('needs 18'));
    });

    test('TLM recognised, not decoded', () {
      final f = decodeEddystone(parseHex('20 00 0BB8 1900 00000001 00000002'));
      expect(f!.kind, 'TLM');
    });

    test('empty → null', () => expect(decodeEddystone(Uint8List(0)), isNull));
  });

  group('iBeacon', () {
    test('T-11 frame', () {
      final b = decodeIBeacon(parseHex('02 15 6B817F8A274D4FBDB62D33E1842F8DF8 014D 022B C5'))!;
      expect(b.uuid, '6B817F8A-274D-4FBD-B62D-33E1842F8DF8');
      expect(b.major, 333);
      expect(b.minor, 555);
      expect(b.measuredPower, -59);
      expect(b.id.display, '6B817F8A-274D-4FBD-B62D-33E1842F8DF8 · 333 · 555');
    });

    test('not an iBeacon', () {
      expect(decodeIBeacon(parseHex('01 02 03')), isNull);
      expect(decodeIBeacon(parseHex('02 16 ${'00' * 21}')), isNull);
    });
  });

  group('AD structures', () {
    test('T-12 scan response: name + Teltonika block', () {
      final raw = parseHex('0C 09 4944315F41424344454647 06 FF 9A 08 01 80 63');
      final parsed = parseAdStructures(raw);
      expect(parsed.error, isNull);
      expect(parsed.structures.length, 2);
      expect(parsed.structures[1].offset, 13);

      final ad = AdvertisementData.parse(raw);
      expect(ad.name, 'ID1_ABCDEFG');
      final d = decodeAdvertisement(ad);
      expect(d.isTeltonika, isTrue);
      expect(d.teltonika!.batteryMv, 2990);
      expect(d.beaconId, isNull);
    });

    test('full Eddystone advertisement (31 bytes)', () {
      final raw = parseHex(
          '02 01 06 03 03 AA FE 17 16 AA FE 00 EE E39B606AA38255AA8E46 0B154E2D0055 00 00');
      expect(raw.length, 31);
      final ad = AdvertisementData.parse(raw);
      expect(ad.flags, 0x06);
      expect(ad.serviceUuids16, [0xFEAA]);
      final d = decodeAdvertisement(ad);
      expect(d.beaconId!.isEddystone, isTrue);
      expect(d.txPower1m, -59);
    });

    test('iBeacon advertisement', () {
      final raw = parseHex('02 01 06 1A FF 4C 00 02 15 6B817F8A274D4FBDB62D33E1842F8DF8 014D 022B C5');
      final d = decodeAdvertisement(AdvertisementData.parse(raw));
      expect(d.beaconId!.isIBeacon, isTrue);
      expect(d.beaconId!.major, 333);
      expect(d.txPower1m, -59);
    });

    test('zero length is padding', () {
      final parsed = parseAdStructures(parseHex('02 01 06 00 00 00'));
      expect(parsed.structures.length, 1);
      expect(parsed.error, isNull);
    });

    test('overrunning length is an error with the tail kept', () {
      final parsed = parseAdStructures(parseHex('02 01 06 09 FF 9A 08'));
      expect(parsed.structures.length, 1);
      expect(parsed.error, contains('declares 9 bytes'));
      expect(toHex(parsed.tail), '09FF9A08');
    });

    test('advertisement merged with its scan response', () {
      final adv = AdvertisementData.parse(
          parseHex('02 01 06 03 03 AA FE 15 16 AA FE 00 EE E39B606AA38255AA8E46 0B154E2D0055'));
      final rsp = AdvertisementData.parse(parseHex('0C 09 4944315F41424344454647 06 FF 9A 08 01 80 63'));
      final d = decodeAdvertisement(adv.merge(rsp));
      expect(d.name, 'ID1_ABCDEFG');
      expect(d.beaconId!.instanceHex, '0B154E2D0055');
      expect(d.teltonika!.batteryMv, 2990);
    });

    test('rebuilt bytes parse back to the same fields', () {
      final ad = AdvertisementData.parse(parseHex('0C 09 4944315F41424344454647 06 FF 9A 08 01 80 63'));
      final again = AdvertisementData.parse(ad.toBytes());
      expect(again.name, ad.name);
      expect(toHex(again.manufacturerData[teltonikaCompanyId]!), '018063');
    });
  });

  group('inspector', () {
    test('every byte of a scan response is labelled', () {
      final p = annotateRaw(parseHex('0C 09 4944315F41424344454647 06 FF 9A 08 01 80 63'));
      for (var i = 0; i < p.bytes.length; i++) {
        expect(p.fieldAt(i), isNotNull, reason: 'byte $i unlabelled');
      }
      expect(p.fieldAt(15)!.label, 'Company ID');
      expect(p.fieldAt(15)!.value, '0x089A Teltonika');
      expect(p.fieldAt(19)!.label, 'Battery voltage');
    });

    test('Eddystone service data is labelled to the instance', () {
      final p = annotateRaw(parseHex('15 16 AA FE 00 EE E39B606AA38255AA8E46 0B154E2D0055'));
      expect(p.fieldAt(2)!.value, '0xFEAA Eddystone');
      expect(p.fieldAt(5)!.label, 'TX power at 0 m');
      expect(p.fieldAt(16)!.label, 'Instance');
    });

    test('fields do not overlap', () {
      final p = annotateRaw(parseHex('02 01 06 1A FF 4C 00 02 15 6B817F8A274D4FBDB62D33E1842F8DF8 014D 022B C5'));
      for (var i = 1; i < p.fields.length; i++) {
        expect(p.fields[i].offset, greaterThanOrEqualTo(p.fields[i - 1].end));
      }
    });
  });

  group('BeaconId', () {
    test('equality by kind and bytes', () {
      final a = BeaconId.fromBytes(parseHex('E39B606AA38255AA8E460B154E2D0055'))!;
      final b = BeaconId.fromBytes(parseHex('E39B606AA38255AA8E460B154E2D0055'))!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(BeaconId.fromBytes(parseHex('0102')), isNull);
    });
  });
}
