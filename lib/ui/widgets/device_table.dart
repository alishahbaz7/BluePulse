import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/settings.dart';
import '../../core/device.dart';
import '../format.dart';
import '../theme.dart';
import 'common.dart';
import 'data_grid.dart';
import 'device_card.dart';
import 'device_name.dart';
import 'device_pills.dart';

/// The columns of every table of devices — the Devices page, choosing a device to configure — so
/// they read the same everywhere. Sensor columns appear when [rows] hold an EYE SENSOR; [pin] adds
/// the pin column first.
List<GridColumn<EyeDevice>> deviceColumns(
  BuildContext context, {
  required List<EyeDevice> rows,
  required DateTime now,
  bool pin = true,
}) {
  final c = AppScope.read(context);
  final r = c.registry;
  final book = c.book;
  final anySensor = rows.any((d) => d.model == DeviceModel.eyeSensor);
  bool notSeen(EyeDevice d) => d.isNotSeen(now, c.settings.notSeenMinSeconds);
  return <GridColumn<EyeDevice>>[
    if (pin)
      GridColumn(
        label: 'Pin',
        width: 56,
        tip: 'Pinned devices stay at the top, get every packet and the fastest refresh, and are what Log records',
        cell: (_, d) => SizedBox(height: 28, child: PinButton(mac: d.mac)),
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
      label: 'Proximity',
      width: 100,
      sortValue: (d) => r.proximityOf(d, now).index,
      cell: (_, d) => ProximityPill(r.proximityOf(d, now)),
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
}

/// Tiles or a table — one choice for every page that lists devices, kept between runs. Wide
/// screens only: a phone always shows tiles.
class DeviceViewToggle extends StatelessWidget {
  const DeviceViewToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    final t = context.tokens;
    Widget button(DeviceView v, IconData icon, String tip) {
      final on = s.deviceView == v;
      return Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: on ? null : () => s.update((x) => x.deviceView = v),
          child: Container(
            width: 32,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? t.accent.withValues(alpha: 0.16) : null,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(icon, size: 18, color: on ? t.accent : t.dim, semanticLabel: tip),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(border: Border.all(color: t.line), borderRadius: BorderRadius.circular(7)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        button(DeviceView.tiles, Icons.grid_view_rounded, 'Tile view'),
        button(DeviceView.list, Icons.view_list_rounded, 'List view'),
      ]),
    );
  }
}

/// Whether device lists show tiles here: always on a phone, else as chosen.
bool showTiles(BuildContext context) =>
    isPhone(context) || AppScope.of(context).settings.deviceView == DeviceView.tiles;
