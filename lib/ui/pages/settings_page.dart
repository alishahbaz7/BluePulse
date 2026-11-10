import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/settings.dart';
import '../../version.dart';
import '../format.dart';
import '../theme.dart';
import '../update_ui.dart';
import '../usage_ui.dart';
import '../widgets/common.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final s = c.settings;
    final r = c.registry;
    final t = context.tokens;

    Widget row(String label, Widget control, {String tip = ''}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(
              width: 200,
              child: HoldTip(message: tip, child: Text(label, style: TextStyle(fontSize: 13.5, color: t.text))),
            ),
            Flexible(child: Align(alignment: Alignment.centerLeft, child: control)),
          ]),
        );

    final liveSegment = ButtonSegment(
      value: ScanSource.live,
      enabled: s.liveSupported,
      label: s.liveSupported
          ? const Text('Bluetooth')
          : const Tooltip(message: 'Live scanning runs on Windows and Android', child: Text('Bluetooth')),
    );

    return ListView(padding: const EdgeInsets.all(16), children: [
      PanelCard(
        title: 'Appearance',
        child: row(
          'Theme',
          SegmentedButton<ThemeChoice>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeChoice.auto, label: Text('Auto')),
              ButtonSegment(value: ThemeChoice.light, label: Text('Light')),
              ButtonSegment(value: ThemeChoice.dark, label: Text('Dark')),
            ],
            selected: {s.themeChoice},
            onSelectionChanged: (v) => s.update((x) => x.themeChoice = v.first),
          ),
        ),
      ),
      const SizedBox(height: 14),
      PanelCard(
        title: 'Scanning',
        child: Column(children: [
          row(
            'Source',
            SegmentedButton<ScanSource>(
              showSelectedIcon: false,
              segments: [liveSegment, const ButtonSegment(value: ScanSource.demo, label: Text('Demo data'))],
              selected: {s.scanSource},
              onSelectionChanged: (v) => s.update((x) => x.scanSource = v.first),
            ),
            tip: 'Demo data is simulated EYE traffic, decoded exactly like real packets',
          ),
          row(
            'Show all beacons',
            Switch(value: s.showAllBeacons, onChanged: (v) => s.update((x) => x.showAllBeacons = v)),
            tip: 'Also list iBeacon and Eddystone devices from other makers',
          ),
        ]),
      ),
      const SizedBox(height: 14),
      PanelCard(
        title: 'Signal',
        child: Wrap(spacing: 28, runSpacing: 14, children: [
          SliderField(
            label: 'Averaging timeout',
            value: s.averagingSeconds.toDouble(),
            min: 0,
            max: 60,
            display: s.averagingSeconds == 0 ? 'Off' : '${s.averagingSeconds} s',
            tip: 'How long the smoothed RSSI takes to reach a new level, as on the tracker',
            onChanged: (v) => s.update((x) => x.averagingSeconds = v.round()),
          ),
          SliderField(
            label: 'Not seen after at least',
            value: s.notSeenMinSeconds.toDouble(),
            min: 5,
            max: 120,
            display: '${s.notSeenMinSeconds} s',
            tip: 'A device is not seen after three advertising intervals of silence, or this, whichever is longer',
            onChanged: (v) => s.update((x) => x.notSeenMinSeconds = v.round()),
          ),
          SliderField(
            label: 'Path-loss exponent',
            value: s.pathLossExponent,
            min: 1.6,
            max: 4.0,
            divisions: 24,
            display: s.pathLossExponent.toStringAsFixed(1),
            tip: 'Distance ≈ 10 ^ ((TX power at 1 m − RSSI) / (10 × n)). About 2 in open space, 3–4 indoors',
            onChanged: (v) => s.update((x) => x.pathLossExponent = (v * 10).round() / 10),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      PanelCard(
        title: 'Session',
        actions: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: t.bad, side: BorderSide(color: t.bad.withValues(alpha: 0.7))),
            onPressed: r.totalPackets == 0
                ? null
                : () async {
                    final ok = await confirmDestructive(
                      context,
                      title: 'Clear the session?',
                      sentence: 'Every device and packet heard so far is removed from the app.',
                      action: 'Clear',
                    );
                    if (ok) r.clear();
                  },
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Clear session'),
          ),
        ],
        child: Wrap(spacing: 28, runSpacing: 12, children: [
          Fact('Started', r.sessionStart == null ? '—' : formatDateTime(r.sessionStart!)),
          Fact('Devices', '${r.devices.length}'),
          Fact('Packets', formatCount(r.totalPackets)),
        ]),
      ),
      const SizedBox(height: 14),
      const UpdatesCard(),
      const SizedBox(height: 14),
      const UsageCard(),
      const SizedBox(height: 14),
      PanelCard(
        title: 'About',
        child: Wrap(spacing: 28, runSpacing: 12, children: [
          Fact('Version', c.version),
          const Fact('Protocol', protocolSource),
          Fact('Platform', kIsWeb ? 'Web' : defaultTargetPlatform.name),
          const Fact('Build', kDebugMode ? 'Debug' : (kProfileMode ? 'Profile' : 'Release')),
        ]),
      ),
    ]);
  }
}
