import 'package:bluepulse/scanner/universal_ble_scanner.dart';
import 'package:bluepulse/simulator/sim_model.dart';
import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Whether one packet passes Android's filter the way the radio applies it: any one filter matching
/// (a service UUID in the advertised list, or manufacturer data starting with the given bytes).
bool passes(AdvertisementData d) {
  final f = UniversalBleScanner.androidFilter;
  final uuids = {for (final u in d.serviceUuids16) u.toRadixString(16).padLeft(4, '0')};
  if (f.withServices.any((s) => uuids.contains(s.substring(4, 8)))) return true;
  for (final m in f.withManufacturerData) {
    final data = d.manufacturerData[m.companyIdentifier];
    if (data == null) continue;
    final prefix = m.payloadPrefix ?? const <int>[];
    if (data.length >= prefix.length && [for (var i = 0; i < prefix.length; i++) data[i] == prefix[i]].every((x) => x)) {
      return true;
    }
  }
  return false;
}

void main() {
  test('every packet layout BluePulse lists passes the radio filter, so filtering hides no device', () {
    for (final s in [
      for (final packet in SensorPacket.values) SimSettings(sensorPacket: packet, simTag: false),
      for (final frame in BeaconFrame.values) SimSettings(profile: SimProfile.eyeBeacon, beaconFrame: frame, simTag: false),
      SimSettings(profile: SimProfile.iBeacon, simTag: false),
    ]) {
      final p = buildPayload(s, SimValues.from(s));
      expect(passes(p.adv), isTrue, reason: '${s.profile.name}/${s.sensorPacket.name}/${s.beaconFrame.name}: advertisement');
    }
    expect(passes(AdvertisementData.parse(parseHex(beaconAdv))), isTrue, reason: 'a real EYE BEACON (wiki bytes)');
    expect(passes(AdvertisementData.parse(parseHex(sensorRsp))), isTrue, reason: 'a real EYE SENSOR block');
    expect(passes(AdvertisementData.parse(parseHex(foreignAdv))), isTrue, reason: 'another make of iBeacon (Show all beacons)');
    final tagOnly = AdvertisementData(manufacturerData: {simulatorCompanyId: encodeSimulatorTag(1)});
    expect(passes(tagOnly), isTrue, reason: "a Windows simulator's tag burst");
  });

  test('what BluePulse never lists stays out at the radio', () {
    expect(passes(AdvertisementData.parse(parseHex(phoneAdv))), isFalse, reason: 'a phone');
    final appleNotIBeacon = AdvertisementData(manufacturerData: {appleCompanyId: parseHex('10 05 01 1C')});
    expect(passes(appleNotIBeacon), isFalse, reason: 'AirPods and the like: Apple data that is not an iBeacon');
    final otherTest = AdvertisementData(manufacturerData: {simulatorCompanyId: parseHex('00 11 22')});
    expect(passes(otherTest), isFalse, reason: "someone else's 0xFFFF test data");
  });
}
