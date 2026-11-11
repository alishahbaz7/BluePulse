import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// A GATT connection to one device, as the configuration session needs it. One implementation over
/// `universal_ble`; tests use a fake sensor.
abstract class GattLink {
  Future<void> connect(String id);

  /// Learns the device's services; reads and writes need it first.
  Future<void> discover(String id);

  /// Asks for a larger packet size (the EYE App asks for 517; an EYE device keeps 23).
  Future<void> negotiateMtu(String id);

  /// The pause after the services are known, before the first read. Right after discovery the
  /// sensor asks for a slower connection; a read sent while that change took effect left a BTSMP1
  /// silent until the link timed out (twice, logcat 11-11-2026). The EYE App asks for the MTU and
  /// starts reading about a second later — so does this.
  Duration get settle;

  Future<Uint8List> read(String id, String service, String characteristic);

  /// A write with response: it returns once the device has accepted it.
  Future<void> write(String id, String service, String characteristic, Uint8List value);

  Future<void> disconnect(String id);

  /// False when the device drops the connection.
  Stream<bool> connection(String id);
}

class UniversalBleLink implements GattLink {
  static const _timeout = Duration(seconds: 15);

  @override
  Duration get settle => const Duration(milliseconds: 1200);

  @override
  Future<void> connect(String id) => UniversalBle.connect(id, timeout: const Duration(seconds: 20));

  @override
  Future<void> discover(String id) async {
    await UniversalBle.discoverServices(id, timeout: _timeout);
  }

  @override
  Future<void> negotiateMtu(String id) async {
    try {
      await UniversalBle.requestMtu(id, 517, timeout: const Duration(seconds: 5));
    } catch (_) {
      // Not offered (Windows negotiates by itself) or refused: the default 23 does.
    }
  }

  @override
  Future<Uint8List> read(String id, String service, String characteristic) =>
      UniversalBle.read(id, service, characteristic, timeout: _timeout);

  @override
  Future<void> write(String id, String service, String characteristic, Uint8List value) =>
      UniversalBle.write(id, service, characteristic, value, timeout: _timeout);

  @override
  Future<void> disconnect(String id) async {
    try {
      await UniversalBle.disconnect(id, timeout: const Duration(seconds: 5));
    } catch (_) {
      // Already gone.
    }
  }

  @override
  Stream<bool> connection(String id) => UniversalBle.connectionStream(id);
}
