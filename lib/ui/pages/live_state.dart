import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/settings.dart';
import '../../scanner/scanner.dart';
import '../widgets/common.dart';

/// What a live page shows instead of its content when there is nothing to show — one line and the
/// action that fixes it. Null when the page should render.
Widget? liveEmptyState(BuildContext context, {required bool hasRows}) {
  final c = AppScope.of(context);
  if (hasRows) return null;
  final s = c.status;
  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  final useDemo = OutlinedButton(
    onPressed: () => c.settings.update((x) => x.scanSource = ScanSource.demo),
    child: const Text('Use demo data'),
  );

  if (!c.isDemo) {
    switch (s.radio) {
      case RadioState.unsupported:
        return EmptyState(icon: Icons.bluetooth_disabled, text: 'No Bluetooth LE adapter found.', secondary: useDemo);
      case RadioState.off:
        return EmptyState(
          icon: Icons.bluetooth_disabled,
          text: 'Bluetooth is off.',
          action: isAndroid ? c.scanner.enableRadio : null,
          actionLabel: 'Turn on Bluetooth',
          secondary: useDemo,
        );
      case RadioState.unauthorized:
        return EmptyState(
          icon: Icons.lock_outline,
          text: 'Bluetooth permission not granted.',
          action: c.scanner.requestPermission,
          actionLabel: 'Grant permission',
        );
      case RadioState.on || RadioState.unknown:
        break;
    }
  }
  if (!s.scanning) {
    return EmptyState(icon: Icons.play_circle_outline, text: 'Not scanning.', action: c.startScan, actionLabel: 'Start scan');
  }
  return EmptyState(
    icon: Icons.bluetooth_searching,
    text: c.settings.showAllBeacons ? 'No beacons in range.' : 'No EYE devices in range.',
    secondary: c.settings.showAllBeacons
        ? null
        : OutlinedButton(
            onPressed: () => c.settings.update((x) => x.showAllBeacons = true),
            child: const Text('Show all beacons'),
          ),
  );
}

/// The scanner's last failure, as a notice above the page.
Widget? liveErrorNotice(BuildContext context) {
  final c = AppScope.of(context);
  final e = c.status.error;
  if (e == null || c.isDemo) return null;
  return Padding(padding: const EdgeInsets.only(bottom: 12), child: Notice(e, tone: Tone.bad));
}
