import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/device.dart';
import '../../core/signal.dart';
import '../format.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'live_state.dart';

class ProximityPage extends StatelessWidget {
  const ProximityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final s = c.settings;
    final r = c.registry;
    final now = DateTime.now();
    final all = r.devices;

    final controls = PanelCard(
      title: 'Thresholds',
      tip: 'The same settings a Teltonika tracker uses for EYE beacon proximity events',
      child: Wrap(spacing: 28, runSpacing: 14, children: [
        SliderField(
          label: 'Near at or above',
          value: s.nearDbm.toDouble(),
          min: -100,
          max: -30,
          display: '${s.nearDbm} dBm',
          tip: 'Smoothed RSSI at or above this is Near',
          onChanged: (v) => s.update((x) => x.nearDbm = v.round()),
        ),
        SliderField(
          label: 'Away at or above',
          value: s.awayDbm.toDouble(),
          min: -100,
          max: -30,
          display: '${s.awayDbm} dBm',
          tip: 'Between this and Near is Away; below it, or not seen, is Lost',
          onChanged: (v) => s.update((x) {
            x.awayDbm = v.round();
            if (x.awayDbm > x.nearDbm) x.nearDbm = x.awayDbm;
          }),
        ),
        SliderField(
          label: 'Averaging timeout',
          value: s.averagingSeconds.toDouble(),
          min: 0,
          max: 60,
          display: s.averagingSeconds == 0 ? 'Off' : '${s.averagingSeconds} s',
          tip: 'How long the smoothed RSSI takes to reach a new level',
          onChanged: (v) => s.update((x) => x.averagingSeconds = v.round()),
        ),
      ]),
    );

    final empty = liveEmptyState(context, hasRows: all.isNotEmpty);
    final groups = {for (final p in Proximity.values) p: <EyeDevice>[]};
    for (final d in all) {
      groups[r.proximityOf(d, now)]!.add(d);
    }
    for (final g in groups.values) {
      g.sort((a, b) => (b.smoothed ?? -999).compareTo(a.smoothed ?? -999));
    }

    Widget column(Proximity p) => PanelCard(
          title: p.label,
          count: '${groups[p]!.length}',
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: groups[p]!.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text('None.', style: TextStyle(fontSize: 13, color: context.tokens.dim)),
                )
              : Column(children: [for (final d in groups[p]!) _DeviceSignal(device: d, proximity: p, now: now)]),
        );

    return ListView(padding: const EdgeInsets.all(16), children: [
      ?liveErrorNotice(context),
      controls,
      const SizedBox(height: 14),
      if (empty != null)
        SizedBox(height: 300, child: empty)
      else
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 900) {
            return Column(children: [
              for (final p in Proximity.values) Padding(padding: const EdgeInsets.only(bottom: 14), child: column(p)),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final p in Proximity.values) ...[
              Expanded(child: column(p)),
              if (p != Proximity.lost) const SizedBox(width: 14),
            ],
          ]);
        }),
    ]);
  }
}

class _DeviceSignal extends StatelessWidget {
  const _DeviceSignal({required this.device, required this.proximity, required this.now});

  final EyeDevice device;
  final Proximity proximity;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = device;
    final color = switch (proximity) {
      Proximity.near => t.ok,
      Proximity.away => t.warn,
      Proximity.lost => t.muted,
    };
    final strength = d.smoothed == null ? 0.0 : ((d.smoothed! + 100) / 70).clamp(0.0, 1.0);
    return InkWell(
      onTap: () => Navigation.of(context).go(PageId.deviceDetail, mac: d.mac),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(d.name ?? d.mac,
                  overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: t.text)),
            ),
            Text(
              d.smoothed == null ? '—' : '${d.smoothed!.round()} dBm',
              style: TextStyle(fontSize: 12.5, color: t.dim, fontFeatures: tabular),
            ),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: strength,
                  minHeight: 5,
                  color: color,
                  backgroundColor: t.line,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 70,
              child: Text(formatAgo(d.lastSeen, now),
                  textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: t.muted)),
            ),
          ]),
        ]),
      ),
    );
  }
}
