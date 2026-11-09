import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/device.dart';
import '../../core/signal.dart';
import '../format.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import 'devices_page.dart';
import 'live_state.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final r = c.registry;
    final now = DateTime.now();
    final all = r.devices;
    final empty = liveEmptyState(context, hasRows: all.isNotEmpty);
    if (empty != null) return empty;

    final notSeen = all.where((d) => d.isNotSeen(now, c.settings.notSeenMinSeconds)).toList();
    final inView = all.where((d) => !notSeen.contains(d)).toList();
    final beacons = inView.where((d) => d.model == DeviceModel.eyeBeacon).length;
    final sensors = inView.where((d) => d.model == DeviceModel.eyeSensor).length;
    final low = all.where((d) => d.lowBattery).toList();
    final perMinute = r.readingsPerMinute(now, 30);
    final lastFull = perMinute.length >= 2 ? perMinute[perMinute.length - 2] : 0;
    final go = Navigation.of(context).go;

    Widget attention({bool expand = false}) => _Attention(low: low, notSeen: notSeen, now: now, expand: expand);
    Widget chart({bool expand = false}) => PanelCard(
          title: 'Readings per minute',
          count: '${formatCount(r.totalPackets)} packets',
          tip: 'Advertising events received each minute over the last 30 minutes; the current minute is lighter',
          expand: expand,
          child: BucketChart(values: perMinute, end: now),
        );
    final strongest = [...inView]..sort((a, b) => (b.smoothed ?? -999).compareTo(a.smoothed ?? -999));

    return ListView(padding: const EdgeInsets.all(16), children: [
      ?liveErrorNotice(context),
      TileRow(tiles: [
        StatTile(label: 'In view', value: '${inView.length}', tone: Tone.ok, onTap: () => go(PageId.devices)),
        StatTile(label: 'EYE beacons', value: '$beacons', tip: 'BTSID1 devices in view'),
        StatTile(label: 'EYE sensors', value: '$sensors', tip: 'BTSMP1 devices in view'),
        StatTile(
          label: 'Low battery',
          value: '${low.length}',
          tone: low.isEmpty ? Tone.neutral : Tone.warn,
          tip: 'Devices whose last packet set the low-battery flag',
        ),
        StatTile(
          label: 'Not seen',
          value: '${notSeen.length}',
          tone: Tone.muted,
          tip: 'Silent for three advertising intervals, or the minimum set in Settings',
        ),
        StatTile(label: 'Readings / min', value: '$lastFull', tip: 'Advertising events in the last full minute'),
      ]),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 900) {
          return Column(children: [attention(), const SizedBox(height: 14), chart()]);
        }
        return SizedBox(
          height: 228,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 2, child: attention(expand: true)),
            const SizedBox(width: 14),
            Expanded(flex: 3, child: chart(expand: true)),
          ]),
        );
      }),
      const SizedBox(height: 14),
      PanelCard(
        title: 'Strongest signals',
        count: '${strongest.length}',
        padding: EdgeInsets.zero,
        actions: [TextButton(onPressed: () => go(PageId.devices), child: const Text('All devices ›'))],
        child: DataGrid<EyeDevice>(
          rows: strongest.take(8).toList(),
          shrinkWrap: true,
          onTap: (d) => go(PageId.deviceDetail, mac: d.mac),
          columns: [
            GridColumn(label: 'Name', width: 150, cell: (_, d) => Text(d.name ?? '—')),
            GridColumn(label: 'MAC', width: 150, cell: (ctx, d) => Text(d.mac, style: monoStyle(ctx))),
            GridColumn(label: 'Model', width: 130, cell: (_, d) => ModelPill(d.model)),
            GridColumn(
              label: 'Smoothed',
              width: 96,
              numeric: true,
              cell: (_, d) => Text(d.smoothed == null ? '—' : '${d.smoothed!.round()} dBm'),
            ),
            GridColumn(label: 'Proximity', width: 100, cell: (_, d) => ProximityPill(r.proximityOf(d, now))),
            GridColumn(
              label: 'Battery',
              width: 96,
              numeric: true,
              cell: (_, d) => Text(d.batteryMv == null ? '—' : '${d.batteryMv} mV'),
            ),
            GridColumn(label: 'Last seen', width: 100, fill: true, cell: (_, d) => Text(formatAgo(d.lastSeen, now))),
          ],
        ),
      ),
    ]);
  }
}

class _Attention extends StatelessWidget {
  const _Attention({required this.low, required this.notSeen, required this.now, this.expand = false});

  final List<EyeDevice> low;
  final List<EyeDevice> notSeen;
  final DateTime now;

  /// Fill a fixed-height slot; the rows scroll inside it.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final go = Navigation.of(context).go;
    final rows = <Widget>[
      for (final d in low)
        _row(context, Icons.battery_alert_outlined, d.name ?? d.mac, '${d.batteryMv ?? '—'} mV', t.warn,
            () => go(PageId.deviceDetail, mac: d.mac)),
      for (final d in notSeen)
        _row(context, Icons.visibility_off_outlined, d.name ?? d.mac, formatAgo(d.lastSeen, now), t.muted,
            () => go(PageId.deviceDetail, mac: d.mac)),
    ];
    return PanelCard(
      title: 'Needs attention',
      count: '${low.length + notSeen.length}',
      padding: const EdgeInsets.symmetric(vertical: 6),
      expand: expand,
      child: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: Text('Nothing needs attention.', style: TextStyle(color: t.dim, fontSize: 13)),
            )
          : expand
              ? ListView(children: rows)
              : Column(children: rows),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String detail, Color c, VoidCallback onTap) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: c == t.warn ? t.warn.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          Icon(icon, size: 17, color: c),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: t.text), overflow: TextOverflow.ellipsis)),
          Text(detail, style: TextStyle(fontSize: 12.5, color: t.dim, fontFeatures: tabular)),
        ]),
      ),
    );
  }
}

/// Re-exported for pages that show a proximity state.
class ProximityPill extends StatelessWidget {
  const ProximityPill(this.p, {super.key});
  final Proximity p;

  @override
  Widget build(BuildContext context) => Pill(
        p.label,
        tone: switch (p) {
          Proximity.near => Tone.ok,
          Proximity.away => Tone.warn,
          Proximity.lost => Tone.muted,
        },
      );
}
