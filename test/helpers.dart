import 'dart:async';

import 'package:bluepulse/app/controller.dart';
import 'package:bluepulse/app/settings.dart';
import 'package:bluepulse/core/registry.dart';
import 'package:bluepulse/scanner/scanner.dart';
import 'package:bluepulse/update/update_service.dart';
import 'package:bluepulse/usage/usage_service.dart';
import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/foundation.dart';

/// A scanner the test drives by hand.
class FakeScanner implements BeaconScanner {
  FakeScanner({this.radio = RadioState.on, this.demo = true});

  final RadioState radio;
  final bool demo;
  final controller = StreamController<ScanEvent>.broadcast();
  late final _status = ValueNotifier(ScannerStatus(radio: radio));

  @override
  bool get isDemo => demo;
  @override
  ValueListenable<ScannerStatus> get status => _status;
  @override
  Stream<ScanEvent> get events => controller.stream;
  @override
  Future<void> init() async {}
  @override
  Future<void> start() async => _status.value = _status.value.copyWith(scanning: true);
  @override
  Future<void> stop() async => _status.value = _status.value.copyWith(scanning: false);
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> enableRadio() async {}
  @override
  void dispose() {
    controller.close();
    _status.dispose();
  }
}

AppController testController({FakeScanner? scanner, UpdateService? updates, UsageService? usage, String version = '1.0.0'}) {
  final settings = AppSettings(null, false);
  return AppController(
    settings: settings,
    registry: DeviceRegistry(settings),
    liveScanner: null,
    demoScanner: scanner ?? FakeScanner(),
    version: version,
    updates: updates,
    usage: usage,
  );
}

ScanEvent event(String mac, String hex, {int rssi = -60, DateTime? at}) => ScanEvent(
      deviceId: mac,
      time: at ?? DateTime.now(),
      rssi: rssi,
      data: AdvertisementData.parse(parseHex(hex)),
    );

/// EYE BEACON advertisement (Eddystone-UID) and its scan response.
const beaconAdv = '02 01 06 03 03 AA FE 17 16 AA FE 00 EE E39B606AA38255AA8E46 0B154E2D0055 00 00';
const beaconRsp = '0C 09 4944315F41424344454647 06 FF 9A 08 01 80 63';

/// EYE SENSOR scan response with every value.
const sensorRsp = '0B 09 534E535F544553543031 0E FF 9A 08 01 BF 08 B4 2D 80 0C F6 00 5A 64';

/// A third-party iBeacon.
const foreignAdv = '02 01 06 1A FF 4C 00 02 15 6B817F8A274D4FBDB62D33E1842F8DF8 014D 022B C5';

/// A phone advertising nothing beacon-like.
const phoneAdv = '02 01 1A 05 FF 06 00 01 09';
