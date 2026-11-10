import 'dart:async';

import 'package:bluepulse_ble_android/bluepulse_ble_android.dart';
import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What this device's transmitter can do.
@immutable
class TxCapabilities {
  const TxCapabilities({
    required this.supported,
    this.reason,
    this.exactInterval = false,
    this.name = false,
    this.scanResponse = false,
    this.txPower = false,
    this.permitted = true,
    this.bluetoothOn = true,
  });

  const TxCapabilities.unsupported(String this.reason)
      : supported = false,
        exactInterval = false,
        name = false,
        scanResponse = false,
        txPower = false,
        permitted = true,
        bluetoothOn = true;

  final bool supported;

  /// Why not, when [supported] is false.
  final String? reason;

  /// The radio keeps the interval itself (Android); otherwise BluePulse sends a short burst every
  /// interval (Windows, whose advertising rate apps cannot set).
  final bool exactInterval;

  /// Can advertise a name (Android, by renaming the phone's Bluetooth while it transmits).
  final bool name;
  final bool scanResponse;
  final bool txPower;
  final bool permitted;
  final bool bluetoothOn;
}

/// Sends advertisements. One implementation per platform; tests use a fake.
abstract class BleAdvertiser {
  Future<TxCapabilities> capabilities();

  /// Asks for the permissions transmitting needs; true when granted.
  Future<bool> requestPermissions() async => true;

  /// Starts transmitting; returns the name actually advertised, when there is one.
  Future<String?> start({
    required AdvertisementData adv,
    AdvertisementData? scanResponse,
    required int intervalMs,
    int? txPowerDbm,
    String? name,
  });

  /// New data for the packets already on air.
  Future<void> update({required AdvertisementData adv, AdvertisementData? scanResponse});
  Future<void> stop();

  /// Failures reported while transmitting.
  Stream<String> get errors => const Stream.empty();

  static BleAdvertiser forThisDevice() {
    if (kIsWeb) return UnsupportedAdvertiser('Transmitting works in the Windows and Android apps');
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidAdvertiser(),
      TargetPlatform.windows => WindowsAdvertiser(),
      _ => UnsupportedAdvertiser('Transmitting works in the Windows and Android apps'),
    };
  }
}

/// The fields of one packet, for the native side.
Map<String, Object?> packetFields(AdvertisementData d, {bool includeName = true}) => {
      'includeName': includeName && d.name != null,
      'uuids16': d.serviceUuids16,
      'serviceData16': [
        for (final e in d.serviceData16.entries) [e.key, e.value],
      ],
      'manufacturer': [
        for (final e in d.manufacturerData.entries) [e.key, e.value],
      ],
    };

/// A readable message from a platform failure.
String txFailure(Object e) => switch (e) {
      PlatformException(:final message?) => message,
      PlatformException(:final code) => code,
      _ => '$e',
    };

class UnsupportedAdvertiser extends BleAdvertiser {
  UnsupportedAdvertiser(this.reason);
  final String reason;

  @override
  Future<TxCapabilities> capabilities() async => TxCapabilities.unsupported(reason);
  @override
  Future<String?> start({required adv, scanResponse, required intervalMs, txPowerDbm, name}) =>
      Future.error(StateError(reason));
  @override
  Future<void> update({required adv, scanResponse}) async {}
  @override
  Future<void> stop() async {}
}

/// Android: AdvertisingSet with the exact interval and power; the name by renaming the phone's
/// Bluetooth while transmitting (restored on stop).
class AndroidAdvertiser extends BleAdvertiser {
  AndroidAdvertiser() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'error') _errors.add('${call.arguments}');
    });
  }

  static const _channel = MethodChannel(bluepulseBleAndroidChannel);
  final _errors = StreamController<String>.broadcast();

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<TxCapabilities> capabilities() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('capabilities') ?? const {};
      return TxCapabilities(
        supported: m['supported'] == true,
        reason: m['reason'] as String?,
        exactInterval: true,
        name: true,
        scanResponse: true,
        txPower: true,
        permitted: m['permitted'] != false,
        bluetoothOn: m['bluetoothOn'] != false,
      );
    } catch (e) {
      return TxCapabilities.unsupported(txFailure(e));
    }
  }

  @override
  Future<bool> requestPermissions() async => await _channel.invokeMethod<bool>('requestPermissions') ?? false;

  @override
  Future<String?> start({required adv, scanResponse, required intervalMs, txPowerDbm, name}) async {
    final r = await _channel.invokeMapMethod<String, Object?>('start', {
      'adv': packetFields(adv),
      'scanResponse': scanResponse == null ? null : packetFields(scanResponse),
      'intervalMs': intervalMs,
      'txPowerDbm': txPowerDbm,
      'name': name,
    });
    return r?['name'] as String?;
  }

  @override
  Future<void> update({required adv, scanResponse}) => _channel.invokeMethod<void>('update', {
        'adv': packetFields(adv),
        'scanResponse': scanResponse == null ? null : packetFields(scanResponse),
      });

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}

/// Windows: a publisher per transmission. Windows sets the advertising rate itself and cannot send
/// a name or a scan response, so the simulator sends a short burst every interval (see
/// SimulatorService) and puts the scan response's data in its own advertisement.
class WindowsAdvertiser extends BleAdvertiser {
  static const _channel = MethodChannel('bluepulse_ble_windows');

  @override
  Future<TxCapabilities> capabilities() async => const TxCapabilities(supported: true, txPower: true);

  @override
  Future<String?> start({required adv, scanResponse, required intervalMs, txPowerDbm, name}) async {
    final r = await _channel.invokeMapMethod<String, Object?>('advertiseStart', {
      ...packetFields(adv, includeName: false),
      'txPowerDbm': txPowerDbm,
    });
    final status = r?['status'] as int? ?? -1;
    if (status == 5) throw StateError(windowsTxError(r?['error'] as int? ?? 0));
    return null;
  }

  @override
  Future<void> update({required adv, scanResponse}) async {
    await start(adv: adv, intervalMs: 0);
  }

  @override
  Future<void> stop() => _channel.invokeMethod<void>('advertiseStop');

  /// The publisher's state: aborted publishers carry the reason.
  Future<String?> problem() async {
    final r = await _channel.invokeMapMethod<String, Object?>('advertiseStatus');
    if ((r?['status'] as int?) == 5) return windowsTxError(r?['error'] as int? ?? 0);
    return null;
  }
}

/// WinRT BluetoothError, in words.
String windowsTxError(int code) => switch (code) {
      1 => 'The Bluetooth radio is off or missing',
      2 => 'Bluetooth is busy with another advertiser',
      4 => 'Advertising is disabled by policy on this PC',
      6 => "This PC's Bluetooth cannot advertise",
      8 => 'Bluetooth is turned off',
      _ => 'Windows stopped advertising (error $code)',
    };
