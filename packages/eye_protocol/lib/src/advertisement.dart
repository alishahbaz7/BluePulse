import 'dart:convert';
import 'dart:typed_data';

import 'ad_structures.dart';
import 'beacon_id.dart';
import 'eddystone.dart';
import 'ibeacon.dart';
import 'teltonika.dart';

/// What a scanner hands over, in platform-neutral form.
///
/// Built either from raw bytes ([AdvertisementData.parse]) or from the parsed fields a platform API
/// returns (manufacturer data keyed by company ID, service data keyed by 16-bit UUID).
class AdvertisementData {
  const AdvertisementData({
    this.name,
    this.flags,
    this.txPowerLevel,
    this.serviceUuids16 = const [],
    this.manufacturerData = const {},
    this.serviceData16 = const {},
    this.other = const [],
  });

  factory AdvertisementData.fromStructures(Iterable<AdStructure> structures) {
    String? name;
    int? flags;
    int? tx;
    final uuids = <int>[];
    final mfr = <int, Uint8List>{};
    final svc = <int, Uint8List>{};
    final other = <AdStructure>[];
    for (final s in structures) {
      final d = s.data;
      switch (s.type) {
        case AdType.completeName:
          name = utf8.decode(d, allowMalformed: true);
        case AdType.shortName:
          name ??= utf8.decode(d, allowMalformed: true);
        case AdType.flags when d.isNotEmpty:
          flags = d[0];
        case AdType.txPowerLevel when d.isNotEmpty:
          tx = d[0] >= 0x80 ? d[0] - 256 : d[0];
        case AdType.completeUuid16 || AdType.incompleteUuid16:
          for (var i = 0; i + 1 < d.length; i += 2) {
            uuids.add(d[i] | (d[i + 1] << 8));
          }
        case AdType.manufacturerData when d.length >= 2:
          mfr[d[0] | (d[1] << 8)] = Uint8List.fromList(d.sublist(2));
        case AdType.serviceData16 when d.length >= 2:
          svc[d[0] | (d[1] << 8)] = Uint8List.fromList(d.sublist(2));
        default:
          other.add(s);
      }
    }
    return AdvertisementData(
      name: name,
      flags: flags,
      txPowerLevel: tx,
      serviceUuids16: uuids,
      manufacturerData: mfr,
      serviceData16: svc,
      other: other,
    );
  }

  /// Parses a raw advertising or scan-response payload.
  factory AdvertisementData.parse(Uint8List raw) =>
      AdvertisementData.fromStructures(parseAdStructures(raw).structures);

  final String? name;
  final int? flags;
  final int? txPowerLevel;
  final List<int> serviceUuids16;

  /// Payload after the 2-byte company ID, keyed by company ID.
  final Map<int, Uint8List> manufacturerData;

  /// Payload after the 2-byte UUID, keyed by 16-bit service UUID.
  final Map<int, Uint8List> serviceData16;

  /// Structures not interpreted above, kept for the inspector.
  final List<AdStructure> other;

  bool get isEmpty =>
      name == null && manufacturerData.isEmpty && serviceData16.isEmpty && serviceUuids16.isEmpty;

  /// Combines an advertisement with its scan response; [newer] wins where both carry a field.
  AdvertisementData merge(AdvertisementData newer) => AdvertisementData(
        name: newer.name ?? name,
        flags: newer.flags ?? flags,
        txPowerLevel: newer.txPowerLevel ?? txPowerLevel,
        serviceUuids16: {...serviceUuids16, ...newer.serviceUuids16}.toList(),
        manufacturerData: {...manufacturerData, ...newer.manufacturerData},
        serviceData16: {...serviceData16, ...newer.serviceData16},
        other: newer.other.isNotEmpty ? newer.other : other,
      );

  /// Rebuilds AD structures in a fixed order — what the inspector shows when the platform API
  /// gave fields rather than raw bytes.
  List<AdStructure> toStructures() {
    final out = <AdStructure>[];
    var offset = 0;
    void add(int type, List<int> data) {
      final s = AdStructure(type, Uint8List.fromList(data), offset: offset);
      out.add(s);
      offset += s.size;
    }

    if (flags != null) add(AdType.flags, [flags!]);
    if (serviceUuids16.isNotEmpty) {
      add(AdType.completeUuid16, [for (final u in serviceUuids16) ...[u & 0xFF, u >> 8]]);
    }
    serviceData16.forEach((uuid, data) => add(AdType.serviceData16, [uuid & 0xFF, uuid >> 8, ...data]));
    manufacturerData.forEach((id, data) => add(AdType.manufacturerData, [id & 0xFF, id >> 8, ...data]));
    if (name != null) add(AdType.completeName, utf8.encode(name!));
    if (txPowerLevel != null) add(AdType.txPowerLevel, [txPowerLevel! & 0xFF]);
    for (final s in other) {
      add(s.type, s.data);
    }
    return out;
  }

  Uint8List toBytes() => Uint8List.fromList([for (final s in toStructures()) ...s.toBytes()]);
}

/// Everything the app reads out of one device's advertisement (+ scan response).
class DecodedAdvertisement {
  DecodedAdvertisement({this.name, this.iBeacon, this.eddystone, this.teltonika});

  final String? name;
  final IBeacon? iBeacon;
  final EddystoneFrame? eddystone;
  final TeltonikaData? teltonika;

  BeaconId? get beaconId {
    if (iBeacon != null) return iBeacon!.id;
    final e = eddystone;
    return e is EddystoneUid ? e.id : null;
  }

  /// Calibrated TX power at 1 m from whichever frame carries it.
  int? get txPower1m {
    if (iBeacon != null) return iBeacon!.measuredPower;
    final e = eddystone;
    return e is EddystoneUid ? e.txPower1m : null;
  }

  bool get isTeltonika => teltonika != null;
  bool get isBeacon => beaconId != null;
}

DecodedAdvertisement decodeAdvertisement(AdvertisementData ad) {
  final apple = ad.manufacturerData[appleCompanyId];
  final eddy = ad.serviceData16[eddystoneServiceUuid];
  final telt = ad.manufacturerData[teltonikaCompanyId];
  return DecodedAdvertisement(
    name: ad.name,
    iBeacon: apple == null ? null : decodeIBeacon(apple),
    eddystone: eddy == null ? null : decodeEddystone(eddy),
    teltonika: telt == null ? null : decodeTeltonika(telt),
  );
}
