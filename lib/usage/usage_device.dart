import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../update/installer.dart';

/// What the app can tell about the device it runs on, without asking the person.
class DeviceFacts {
  const DeviceFacts({required this.platform, this.os, this.login, this.computer, this.device, this.launcher, this.timeZone});

  final String platform;
  final String? os;
  final String? login;
  final String? computer;
  final String? device;
  final bool? launcher;
  final String? timeZone;
}

Future<DeviceFacts> readDeviceFacts() async {
  final zone = _timeZone(DateTime.now());
  if (kIsWeb) return DeviceFacts(platform: 'web', timeZone: zone);
  if (Platform.isWindows) {
    final env = Platform.environment;
    final user = env['USERNAME'];
    final domain = env['USERDOMAIN'];
    final computer = env['COMPUTERNAME'] ?? Platform.localHostname;
    return DeviceFacts(
      platform: 'windows',
      os: windowsName(Platform.operatingSystemVersion),
      // A domain account is named with its domain; a local one by the user name alone.
      login: user == null ? null : (domain != null && domain.toUpperCase() != computer.toUpperCase() ? '$domain\\$user' : user),
      computer: computer,
      launcher: InstallLayout.detect(Platform.resolvedExecutable) != null,
      timeZone: zone,
    );
  }
  if (Platform.isAndroid) {
    try {
      final a = await DeviceInfoPlugin().androidInfo;
      return DeviceFacts(
        platform: 'android',
        os: 'Android ${a.version.release} (SDK ${a.version.sdkInt})',
        device: '${a.manufacturer} ${a.model}',
        timeZone: zone,
      );
    } catch (_) {
      return DeviceFacts(platform: 'android', os: Platform.operatingSystemVersion, timeZone: zone);
    }
  }
  return DeviceFacts(
    platform: Platform.operatingSystem,
    os: Platform.operatingSystemVersion,
    computer: Platform.localHostname,
    timeZone: zone,
  );
}

/// `"Windows 10 Pro" 10.0 (Build 26300)` → `Windows 11 Pro (build 26300)`. Windows 11 still calls
/// itself 10 in the registry; the build number tells them apart (22000 and later is 11).
String windowsName(String raw) {
  final name = RegExp(r'"([^"]+)"').firstMatch(raw)?.group(1) ?? 'Windows';
  final build = int.tryParse(RegExp(r'Build (\d+)').firstMatch(raw)?.group(1) ?? '');
  final fixed = build != null && build >= 22000 ? name.replaceFirst('Windows 10', 'Windows 11') : name;
  return build == null ? fixed : '$fixed (build $build)';
}

String _timeZone(DateTime now) {
  final o = now.timeZoneOffset;
  final sign = o.isNegative ? '-' : '+';
  final m = o.inMinutes.abs();
  final hh = (m ~/ 60).toString().padLeft(2, '0');
  final mm = (m % 60).toString().padLeft(2, '0');
  return '${now.timeZoneName} (UTC$sign$hh:$mm)';
}
