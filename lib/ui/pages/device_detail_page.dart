import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/device.dart';
import '../format.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/inspector.dart';
import 'devices_page.dart';
import 'overview_page.dart';

class DeviceDetailPage extends StatefulWidget {
  const DeviceDetailPage({super.key, required this.mac});

  final String mac;

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  int _windowMinutes = 10;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final t = context.tokens;
    final go = Navigation.of(context).go;
    final d = c.registry.device(widget.mac);
    final back = Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => go(PageId.devices),
        icon: const Icon(Icons.chevron_left, size: 18),
        label: const Text('All devices'),
      ),
    );
    if (d == null) {
      return Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: back),
        const Expanded(child: EmptyState(text: 'This device is not in the current session.')),
      ]);
    }

    final now = DateTime.now();
    final r = c.registry;
    final notSeen = d.isNotSeen(now, c.settings.notSeenMinSeconds);
    final tel = d.teltonika;
    final id = d.beaconId;
    final window = Duration(minutes: _windowMinutes);
    final sessionSpan = now.difference(d.firstSeen);
    final longWindow = Duration(minutes: (sessionSpan.inMinutes + 1).clamp(10, 240));
    final isSensor = d.model == DeviceModel.eyeSensor;

    List<ChartPoint> pts(Iterable<Sample> s) => [for (final x in s) ChartPoint(x.time, x.value)];
    final maxGap = Duration(milliseconds: ((d.intervalMs ?? 5000) * 4).clamp(4000, 120000));

    final header = PanelCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(d.name ?? 'Unnamed device', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.text)),
          ModelPill(d.model),
          Pill(notSeen ? 'Not seen' : 'In view', tone: notSeen ? Tone.muted : Tone.ok),
          ProximityPill(r.proximityOf(d, now)),
          if (d.lowBattery) const Pill('Low battery', tone: Tone.warn),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 28, runSpacing: 12, children: [
          Fact('MAC', d.mac, mono: true),
          if (id != null && id.isEddystone) ...[
            Fact('Namespace', id.namespaceHex, mono: true),
            Fact('Instance', id.instanceHex, mono: true),
          ],
          if (id != null && id.isIBeacon) ...[
            Fact('UUID', id.uuid, mono: true),
            Fact('Major', '${id.major}'),
            Fact('Minor', '${id.minor}'),
          ],
          if (d.txPower1m != null)
            Fact('TX power at 1 m', '${d.txPower1m} dBm', tip: 'Calibrated power the beacon frame advertises'),
          Fact('First seen', formatClock(d.firstSeen)),
          Fact('Last seen', '${formatClock(d.lastSeen)} · ${formatAgo(d.lastSeen, now)}'),
        ]),
      ]),
    );

    final tiles = TileRow(minWidth: 150, tiles: [
      StatTile(label: 'RSSI', value: d.rssi?.toString() ?? '—', secondary: 'dBm', tip: 'Last packet'),
      StatTile(
        label: 'Smoothed',
        value: d.smoothed?.round().toString() ?? '—',
        secondary: 'dBm',
        tone: Tone.accent,
        tip: 'Averaged over ${c.settings.averagingSeconds} s',
      ),
      StatTile(label: 'Distance', value: formatDistance(r.distanceOf(d)), tip: 'Estimate — model in Settings'),
      StatTile(
        label: 'Battery',
        value: d.batteryMv?.toString() ?? '—',
        secondary: d.batteryMv == null ? null : 'mV',
        tone: d.lowBattery ? Tone.warn : Tone.neutral,
      ),
      StatTile(label: 'Interval', value: formatInterval(d.intervalMs), tip: 'Median gap between advertising events'),
      StatTile(label: 'Readings', value: formatCount(d.readings), secondary: '${formatCount(d.packets)} packets'),
    ]);

    final sensorTiles = !isSensor || tel == null
        ? null
        : TileRow(minWidth: 150, tiles: [
            StatTile(label: 'Temperature', value: tel.temperatureC?.toStringAsFixed(2) ?? '—', secondary: '°C'),
            StatTile(label: 'Humidity', value: tel.humidity?.toString() ?? '—', secondary: '%'),
            StatTile(
              label: 'Movement',
              value: tel.moving == null ? '—' : (tel.moving! ? 'Moving' : 'Still'),
              secondary: tel.movementCount == null ? null : 'count ${tel.movementCount}',
              tone: tel.moving == true ? Tone.accent : Tone.neutral,
            ),
            StatTile(
              label: 'Pitch · Roll',
              value: tel.pitch == null ? '—' : '${tel.pitch}° · ${tel.roll}°',
            ),
            StatTile(
              label: 'Magnet',
              value: switch (tel.magnetDetected) {
                true => 'Detected',
                false => 'None',
                null => '—',
              },
            ),
          ]);

    final rssiChart = PanelCard(
      title: 'Signal',
      tip: 'Raw RSSI per packet and the smoothed value; shaded bands are the proximity zones',
      actions: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 5, label: Text('5 min')),
            ButtonSegment(value: 10, label: Text('10 min')),
            ButtonSegment(value: 30, label: Text('30 min')),
          ],
          selected: {_windowMinutes},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _windowMinutes = s.first),
        ),
      ],
      child: TimeChart(
        end: now,
        window: window,
        height: 200,
        maxGap: maxGap,
        minSpan: 20,
        bands: [
          ChartBand(c.settings.nearDbm.toDouble(), -20, t.ok.withValues(alpha: 0.07), 'Near'),
          ChartBand(c.settings.awayDbm.toDouble(), c.settings.nearDbm.toDouble(), t.warn.withValues(alpha: 0.06), 'Away'),
        ],
        series: [
          ChartSeries(
            label: 'RSSI',
            color: t.muted,
            width: 1,
            dots: true,
            unit: ' dBm',
            points: [for (final s in d.rssiHistory) ChartPoint(s.time, s.raw.toDouble())],
          ),
          ChartSeries(
            label: 'Smoothed',
            color: t.accent,
            width: 2,
            unit: ' dBm',
            points: [for (final s in d.rssiHistory) ChartPoint(s.time, s.smoothed)],
          ),
        ],
      ),
    );

    Widget chartCard(String title, List<ChartSeries> series, {String tip = '', double minSpan = 0, double? yMin}) =>
        PanelCard(
          title: title,
          tip: tip,
          child: TimeChart(
            end: now,
            window: longWindow,
            height: 150,
            maxGap: maxGap,
            minSpan: minSpan,
            yMin: yMin,
            series: series,
          ),
        );

    final charts = <Widget>[
      if (d.batteryHistory.isNotEmpty)
        chartCard('Battery', [ChartSeries(label: 'Battery', color: t.ok, unit: ' mV', points: pts(d.batteryHistory))],
            minSpan: 100),
      if (d.temperatureHistory.isNotEmpty)
        chartCard('Temperature', [
          ChartSeries(label: 'Temperature', color: t.warn, unit: ' °C', decimals: 2, points: pts(d.temperatureHistory)),
        ], minSpan: 2),
      if (d.humidityHistory.isNotEmpty)
        chartCard('Humidity', [ChartSeries(label: 'Humidity', color: t.accent, unit: ' %', points: pts(d.humidityHistory))],
            minSpan: 10),
      if (d.movementHistory.isNotEmpty)
        chartCard('Movement count', [
          ChartSeries(label: 'Count', color: t.accent, points: pts(d.movementHistory)),
        ], tip: 'Movement events counted by the sensor', minSpan: 10, yMin: 0),
      if (d.pitchHistory.isNotEmpty)
        chartCard('Angles', [
          ChartSeries(label: 'Pitch', color: t.ok, unit: '°', points: pts(d.pitchHistory)),
          ChartSeries(label: 'Roll', color: t.warn, unit: '°', points: pts(d.rollHistory)),
        ], minSpan: 20),
    ];

    final packet = PanelCard(
      title: 'Last packet',
      tip: 'Advertisement and scan response merged, rebuilt from the fields the platform reported',
      child: PacketInspector(packet: annotateStructures(d.merged.toStructures())),
    );

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
      back,
      const SizedBox(height: 4),
      header,
      const SizedBox(height: 14),
      tiles,
      if (sensorTiles != null) ...[const SizedBox(height: 10), sensorTiles],
      if (tel != null && !tel.ok) ...[const SizedBox(height: 10), Notice('Teltonika block: ${tel.error}', tone: Tone.bad)],
      const SizedBox(height: 14),
      rssiChart,
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 900 || charts.length < 2) {
          return Column(children: [for (final w in charts) Padding(padding: const EdgeInsets.only(bottom: 14), child: w)]);
        }
        final rows = <Widget>[];
        for (var i = 0; i < charts.length; i += 2) {
          rows.add(Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: charts[i]),
              const SizedBox(width: 14),
              Expanded(child: i + 1 < charts.length ? charts[i + 1] : const SizedBox.shrink()),
            ]),
          ));
        }
        return Column(children: rows);
      }),
      packet,
    ]);
  }
}
