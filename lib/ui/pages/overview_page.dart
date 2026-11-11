import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/device.dart';
import '../../core/registry.dart';
import '../format.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/device_card.dart';
import '../widgets/device_name.dart';
import '../widgets/device_table.dart';
import '../usage_ui.dart';
import 'live_state.dart';
import '../widgets/device_pills.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final r = c.registry;
    final now = DateTime.now();
    final all = r.devices;
    final name = greetingName(context);
    final empty = liveEmptyState(context, hasRows: all.isNotEmpty);
    if (empty != null) {
      if (name == null) return empty;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: Greeting(name)),
        Expanded(child: empty),
      ]);
    }

    final notSeen = all.where((d) => d.isNotSeen(now, c.settings.notSeenMinSeconds)).toList();
    final inView = all.where((d) => !notSeen.contains(d)).toList();
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
    final strongest = [...inView]..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));

    // A phone shows what is there and what is wrong with it: no throughput figures, and the
    // attention list after the devices.
    final phone = isPhone(context);
    final tiles = TileRow(tiles: [
      StatTile(
        label: 'In view',
        value: '${inView.length}',
        tone: Tone.ok,
        icon: Icons.sensors,
        onTap: () => go(PageId.devices),
      ),
      StatTile(
        label: 'Not seen',
        value: '${notSeen.length}',
        tone: Tone.muted,
        icon: Icons.visibility_off_outlined,
        tip: 'Silent for three advertising intervals, or the minimum set in Settings',
      ),
      if (!phone)
        StatTile(
          label: 'Readings / min',
          value: '$lastFull',
          icon: Icons.speed,
          tip: 'Advertising events in the last full minute',
        ),
    ]);
    final strongestCard = PanelCard(
      title: 'Strongest signals',
      padding: EdgeInsets.zero,
      actions: [
        if (!phone) const DeviceViewToggle(),
        TextButton(onPressed: () => go(PageId.devices), child: const Text('All devices ›')),
      ],
      child: showTiles(context)
          ? CardRows(
              shrinkWrap: true,
              count: strongest.take(8).length,
              card: (i, stripe) =>
                  DeviceCard(device: strongest[i], now: now, stripe: stripe, onTap: () => go(PageId.deviceDetail, mac: strongest[i].mac)),
            )
          : _strongestGrid(strongest, r, now, go),
    );
    if (phone) {
      return ListView(padding: const EdgeInsets.all(12), children: [
        if (name != null) Greeting(name),
        ?liveErrorNotice(context),
        tiles,
        const SizedBox(height: 14),
        strongestCard,
        const SizedBox(height: 14),
        attention(),
      ]);
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (name != null) Greeting(name),
      ?liveErrorNotice(context),
      tiles,
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
      strongestCard,
    ]);
  }

  Widget _strongestGrid(List<EyeDevice> strongest, DeviceRegistry r, DateTime now, void Function(PageId, {String? mac}) go) {
    return DataGrid<EyeDevice>(
          rows: strongest.take(8).toList(),
          shrinkWrap: true,
          onTap: (d) => go(PageId.deviceDetail, mac: d.mac),
          columns: [
            GridColumn(label: 'Name', width: 190, cell: (_, d) => DeviceName(d)),
            GridColumn(label: 'MAC', width: 150, cell: (ctx, d) => Text(d.mac, style: monoStyle(ctx))),
            GridColumn(label: 'Model', width: 130, cell: (_, d) => ModelPill(d.model)),
            GridColumn(
              label: 'RSSI',
              width: 96,
              numeric: true,
              cell: (_, d) => Text(d.rssi == null ? '—' : '${d.rssi} dBm'),
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
        );
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
    final book = AppScope.of(context).book;
    final rows = <Widget>[
      for (final d in low)
        _row(context, Icons.battery_alert_outlined, deviceLabel(book, d), '${d.batteryMv ?? '—'} mV', t.warn,
            () => go(PageId.deviceDetail, mac: d.mac)),
      for (final d in notSeen)
        _row(context, Icons.visibility_off_outlined, deviceLabel(book, d), formatAgo(d.lastSeen, now), t.muted,
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
