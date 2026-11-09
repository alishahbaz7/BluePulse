import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/device.dart';
import '../format.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/device_name.dart';
import 'live_state.dart';
import 'overview_page.dart';

enum _Filter { all, beacons, sensors, low, notSeen }

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  _Filter _filter = _Filter.all;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final r = c.registry;
    final now = DateTime.now();
    final all = r.devices;
    final empty = liveEmptyState(context, hasRows: all.isNotEmpty);
    if (empty != null) return empty;

    bool notSeen(EyeDevice d) => d.isNotSeen(now, c.settings.notSeenMinSeconds);
    bool matches(EyeDevice d, _Filter f) => switch (f) {
          _Filter.all => true,
          _Filter.beacons => d.model == DeviceModel.eyeBeacon,
          _Filter.sensors => d.model == DeviceModel.eyeSensor,
          _Filter.low => d.lowBattery,
          _Filter.notSeen => notSeen(d),
        };
    final book = c.book;
    final q = _query.trim().toLowerCase();
    bool found(EyeDevice d) =>
        q.isEmpty || d.searchText.contains(q) || (book.tagOf(d.mac)?.toLowerCase().contains(q) ?? false);
    final rows = all.where((d) => matches(d, _filter) && found(d)).toList();
    final anySensor = rows.any((d) => d.model == DeviceModel.eyeSensor);
    final go = Navigation.of(context).go;
    final pinned = all.where((d) => book.pinned(d.mac)).length;

    final columns = <GridColumn<EyeDevice>>[
      GridColumn(
        label: 'Focus',
        width: 64,
        sortValue: (d) => book.pinned(d.mac) ? 0 : 1,
        tip: 'Devices in focus get every packet and the fastest refresh; the rest refresh every few seconds',
        cell: (_, d) => SizedBox(
          height: 24,
          child: Checkbox(
            value: book.pinned(d.mac),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (_) => book.toggleFocus(d.mac),
          ),
        ),
      ),
      GridColumn(
        label: 'Name',
        width: 190,
        sortValue: (d) => deviceLabel(book, d).toLowerCase(),
        tip: 'Your own name for the device first, then the name it advertises',
        cell: (_, d) => DeviceName(d),
      ),
      GridColumn(label: 'MAC', width: 146, sortValue: (d) => d.mac, cell: (ctx, d) => Text(d.mac, style: monoStyle(ctx))),
      GridColumn(label: 'Model', width: 120, sortValue: (d) => d.model.index, cell: (_, d) => ModelPill(d.model)),
      GridColumn(
        label: 'Smoothed',
        width: 104,
        numeric: true,
        sortValue: (d) => d.smoothed,
        tip: 'RSSI averaged over the averaging timeout in Settings, dBm',
        cell: (_, d) => Text(d.smoothed == null ? '—' : '${d.smoothed!.round()} dBm'),
      ),
      GridColumn(
        label: 'Proximity',
        width: 100,
        sortValue: (d) => r.proximityOf(d, now).index,
        cell: (_, d) => ProximityPill(r.proximityOf(d, now)),
      ),
      GridColumn(
        label: 'Rate',
        width: 78,
        numeric: true,
        sortValue: (d) => d.packetsPerSecond(now),
        tip: 'Packets per second received from the device over the last 10 seconds',
        cell: (_, d) => Text('${d.packetsPerSecond(now).toStringAsFixed(1)}/s'),
      ),
      GridColumn(
        label: 'Battery',
        width: 132,
        numeric: true,
        sortValue: (d) => d.batteryMv,
        tip: 'Millivolts as sent; Low when the device set its low-battery flag',
        cell: (_, d) => Row(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          if (d.lowBattery) ...[const Pill('Low', tone: Tone.warn, small: true), const SizedBox(width: 6)],
          Text(d.batteryMv == null ? '—' : '${d.batteryMv} mV'),
        ]),
      ),
      GridColumn(
        label: 'Last seen',
        width: 100,
        sortValue: (d) => -d.lastSeen.millisecondsSinceEpoch,
        cell: (ctx, d) => Text(
          formatAgo(d.lastSeen, now),
          style: TextStyle(color: notSeen(d) ? ctx.tokens.muted : null),
        ),
      ),
      if (anySensor) ...[
        GridColumn(
          label: 'Temp',
          width: 84,
          numeric: true,
          sortValue: (d) => d.teltonika?.temperatureC,
          cell: (_, d) => Text(d.teltonika?.temperatureC == null ? '—' : '${d.teltonika!.temperatureC!.toStringAsFixed(1)} °C'),
        ),
        GridColumn(
          label: 'Humidity',
          width: 90,
          numeric: true,
          sortValue: (d) => d.teltonika?.humidity,
          cell: (_, d) => Text(d.teltonika?.humidity == null ? '—' : '${d.teltonika!.humidity} %'),
        ),
        GridColumn(
          label: 'Movement',
          width: 116,
          sortValue: (d) => d.teltonika?.movementCount,
          cell: (_, d) {
            final t = d.teltonika;
            if (t?.moving == null) return const Text('—');
            return Text('${t!.moving! ? 'Moving' : 'Still'} · ${t.movementCount}');
          },
        ),
        GridColumn(
          label: 'Magnet',
          width: 90,
          sortValue: (d) => d.teltonika?.magnetDetected,
          cell: (_, d) => Text(switch (d.teltonika?.magnetDetected) {
            true => 'Detected',
            false => 'None',
            null => '—',
          }),
        ),
      ],
      GridColumn(
        label: 'RSSI',
        width: 70,
        numeric: true,
        sortValue: (d) => d.rssi,
        tip: 'Last packet, dBm',
        cell: (_, d) => Text(d.rssi?.toString() ?? '—'),
      ),
      GridColumn(
        label: 'Distance',
        width: 92,
        numeric: true,
        sortValue: r.distanceOf,
        tip: 'Estimate from smoothed RSSI and the TX power the beacon advertises',
        cell: (_, d) => Text(formatDistance(r.distanceOf(d))),
      ),
      GridColumn(
        label: 'Interval',
        width: 84,
        numeric: true,
        sortValue: (d) => d.intervalMs,
        tip: 'Median gap between advertising events',
        cell: (_, d) => Text(formatInterval(d.intervalMs)),
      ),
      GridColumn(
        label: 'Readings',
        width: 88,
        numeric: true,
        sortValue: (d) => d.readings,
        cell: (_, d) => Text(formatCount(d.readings)),
      ),
      GridColumn(
        label: 'ID',
        width: 300,
        fill: true,
        sortValue: (d) => d.beaconId?.display,
        tip: 'Eddystone namespace · instance, or iBeacon UUID · major · minor',
        cell: (ctx, d) => Text(d.beaconId?.display ?? '—', style: monoStyle(ctx, size: 12)),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ?liveErrorNotice(context),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final f in _Filter.values)
            _FilterChip(
              label: switch (f) {
                _Filter.all => 'All',
                _Filter.beacons => 'Beacons',
                _Filter.sensors => 'Sensors',
                _Filter.low => 'Low battery',
                _Filter.notSeen => 'Not seen',
              },
              count: all.where((d) => matches(d, f)).length,
              selected: _filter == f,
              onTap: () => setState(() => _filter = f),
            ),
          SizedBox(
            width: 260,
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Name, MAC or ID',
              ),
            ),
          ),
        ]),
        if (pinned > 0) ...[const SizedBox(height: 10), _FocusBar(count: pinned, interval: r.backgroundInterval(now))],
        const SizedBox(height: 12),
        Expanded(
          child: PanelCard(
            title: 'Devices',
            count: rows.length == all.length ? '${all.length}' : '${rows.length} of ${all.length}',
            padding: EdgeInsets.zero,
            expand: true,
            child: rows.isEmpty
                ? const EmptyState(text: 'No devices match.')
                : DataGrid<EyeDevice>(
                    rows: rows,
                    columns: columns,
                    // By name: a list that stays put. Click a header for signal, rate and the rest.
                    initialSort: 1,
                    initialAscending: true,
                    dimmed: (d) => book.focusActive && !book.inFocus(d.mac),
                    selected: (d) => book.pinned(d.mac),
                    onTap: (d) => go(PageId.deviceDetail, mac: d.mac),
                  ),
          ),
        ),
      ]),
    );
  }
}

/// Shown while devices are in focus: how many, how often the rest refresh, and the way out.
class _FocusBar extends StatelessWidget {
  const _FocusBar({required this.count, required this.interval});

  final int count;
  final Duration interval;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.accentSoft, t.panel),
        border: Border.all(color: t.accent.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Icon(Icons.center_focus_strong_outlined, size: 18, color: t.accent),
        const SizedBox(width: 10),
        Text('$count in focus', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
        const SizedBox(width: 12),
        HoldTip(
          message: 'Devices out of focus are counted in full but redrawn less often; busier radios mean longer gaps',
          child: Text('others every ${formatDuration(interval)}', style: TextStyle(fontSize: 12.5, color: t.dim)),
        ),
        const Spacer(),
        TextButton(onPressed: AppScope.read(context).book.clearFocus, child: const Text('Clear focus')),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.count, required this.selected, required this.onTap});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: selected ? t.accentSoft : t.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: selected ? t.accent : t.frame),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(fontSize: 13, color: selected ? t.text : t.dim)),
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(fontSize: 12.5, color: t.muted, fontFeatures: tabular)),
          ]),
        ),
      ),
    );
  }
}

class ModelPill extends StatelessWidget {
  const ModelPill(this.model, {super.key});
  final DeviceModel model;

  @override
  Widget build(BuildContext context) => Pill(
        model.label,
        tone: switch (model) {
          DeviceModel.eyeBeacon => Tone.accent,
          DeviceModel.eyeSensor => Tone.ok,
          DeviceModel.eyeDevice => Tone.neutral,
          DeviceModel.otherBeacon => Tone.muted,
        },
      );
}
