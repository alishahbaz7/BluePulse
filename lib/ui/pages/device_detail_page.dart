import 'dart:async';

import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/device.dart';
import '../../core/device_book.dart';
import '../../core/ping_stats.dart';
import '../format.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/arrange_charts.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/device_name.dart';
import '../widgets/inspector.dart';
import '../widgets/rx_log_card.dart';
import 'devices_page.dart';
import 'overview_page.dart';

/// One device: a pinned bar (back, name, the time window every chart and figure follows, Arrange),
/// then its header, tiles, pings, the charts in the person's own arrangement, its received packets
/// and the last packet's bytes.
class DeviceDetailPage extends StatefulWidget {
  const DeviceDetailPage({super.key, required this.mac});

  final String mac;

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  DeviceBook? _book;

  // The open device is in focus for as long as its page is open. Changes are made just after the
  // current frame: notifying during a build or a teardown is not allowed.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_book == null) {
      final book = _book = AppScope.read(context).book;
      final mac = widget.mac;
      scheduleMicrotask(() => book.setTemporaryFocus(mac));
    }
  }

  @override
  void didUpdateWidget(covariant DeviceDetailPage old) {
    super.didUpdateWidget(old);
    if (old.mac != widget.mac) {
      final book = _book, mac = widget.mac;
      scheduleMicrotask(() => book?.setTemporaryFocus(mac));
    }
  }

  @override
  void dispose() {
    final book = _book, mac = widget.mac;
    scheduleMicrotask(() {
      if (book?.temporaryFocus == mac) book?.setTemporaryFocus(null);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final t = context.tokens;
    final go = Navigation.of(context).go;
    final d = c.registry.device(widget.mac);
    if (d == null) {
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => go(PageId.devices),
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('All devices'),
            ),
          ),
        ),
        const Expanded(child: EmptyState(text: 'This device is not in the current session.')),
      ]);
    }

    final book = c.book;
    final now = DateTime.now();
    final window = Duration(minutes: book.windowMinutes);
    final kind = d.model.name;
    final available = <String>{
      ChartSlot.signal,
      if (d.batteryHistory.isNotEmpty) ChartSlot.battery,
      if (d.temperatureHistory.isNotEmpty) ChartSlot.temperature,
      if (d.humidityHistory.isNotEmpty) ChartSlot.humidity,
      if (d.movementHistory.isNotEmpty) ChartSlot.movement,
      if (d.pitchHistory.isNotEmpty) ChartSlot.angles,
    };

    final bar = _Bar(
      label: deviceLabel(book, d),
      window: book.windowMinutes,
      onBack: () => go(PageId.devices),
      onWindow: book.setWindowMinutes,
      onArrange: () => showArrangeCharts(context, book: book, kind: kind, available: available),
    );

    return CustomScrollView(slivers: [
      SliverPersistentHeader(pinned: true, delegate: _BarDelegate(bar, t.bg, t.line)),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        sliver: SliverList.list(children: [
          _header(context, d, now),
          const SizedBox(height: 14),
          ..._tiles(context, d, now),
          const SizedBox(height: 14),
          _pings(context, d, now, window),
          const SizedBox(height: 14),
          _charts(context, d, now, window, book.chartLayout(kind), available),
          RxLogCard(device: d, window: window),
          const SizedBox(height: 14),
          PanelCard(
            title: 'Last packet',
            tip: 'Advertisement and scan response merged, rebuilt from the fields received',
            child: PacketInspector(packet: annotateStructures(d.merged.toStructures())),
          ),
        ]),
      ),
    ]);
  }

  Widget _header(BuildContext context, EyeDevice d, DateTime now) {
    final c = AppScope.of(context);
    final t = context.tokens;
    final r = c.registry;
    final book = c.book;
    final tag = book.tagOf(d.mac);
    final id = d.beaconId;
    final notSeen = d.isNotSeen(now, c.settings.notSeenMinSeconds);
    return PanelCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(tag ?? d.name ?? 'Unnamed device',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.text)),
              ModelPill(d.model),
              Pill(notSeen ? 'Not seen' : 'In view', tone: notSeen ? Tone.muted : Tone.ok),
              ProximityPill(r.proximityOf(d, now)),
              if (d.lowBattery) const Pill('Low battery', tone: Tone.warn),
              const HoldTip(
                message: 'This device gets every packet and the fastest refresh while its page is open',
                child: Pill('In focus', tone: Tone.accent),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => showRenameDialog(context, d),
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: Text(tag == null ? 'Name' : 'Rename'),
            ),
            OutlinedButton.icon(
              onPressed: () => book.toggleFocus(d.mac),
              icon: Icon(book.pinned(d.mac) ? Icons.check_box_outlined : Icons.check_box_outline_blank,
                  size: 17, color: book.pinned(d.mac) ? t.accent : null),
              label: const Text('Keep in focus'),
            ),
          ]),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 28, runSpacing: 12, children: [
          if (tag != null) Fact('Advertised name', d.name ?? '—'),
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
  }

  List<Widget> _tiles(BuildContext context, EyeDevice d, DateTime now) {
    final c = AppScope.of(context);
    final r = c.registry;
    final tel = d.teltonika;
    return [
      TileRow(minWidth: 150, tiles: [
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
        StatTile(
          label: 'Rate',
          value: d.packetsPerSecond(now).toStringAsFixed(1),
          secondary: '/s',
          tip: 'Packets per second over the last 10 seconds',
        ),
        StatTile(label: 'Readings', value: formatCount(d.readings), secondary: '${formatCount(d.packets)} packets'),
      ]),
      if (d.model == DeviceModel.eyeSensor && tel != null) ...[
        const SizedBox(height: 10),
        TileRow(minWidth: 150, tiles: [
          StatTile(label: 'Temperature', value: tel.temperatureC?.toStringAsFixed(2) ?? '—', secondary: '°C'),
          StatTile(label: 'Humidity', value: tel.humidity?.toString() ?? '—', secondary: '%'),
          StatTile(
            label: 'Movement',
            value: tel.moving == null ? '—' : (tel.moving! ? 'Moving' : 'Still'),
            secondary: tel.movementCount == null ? null : 'count ${tel.movementCount}',
            tone: tel.moving == true ? Tone.accent : Tone.neutral,
          ),
          StatTile(label: 'Pitch · Roll', value: tel.pitch == null ? '—' : '${tel.pitch}° · ${tel.roll}°'),
          StatTile(
            label: 'Magnet',
            value: switch (tel.magnetDetected) {
              true => 'Detected',
              false => 'None',
              null => '—',
            },
          ),
        ]),
      ],
      if (tel != null && !tel.ok) ...[const SizedBox(height: 10), Notice('Teltonika block: ${tel.error}', tone: Tone.bad)],
    ];
  }

  Widget _pings(BuildContext context, EyeDevice d, DateTime now, Duration window) {
    final t = context.tokens;
    final ps = PingStats.compute(
      times: d.pingTimes,
      allGapsMs: d.pingGapsMs,
      now: now,
      window: window,
      firstSeen: d.firstSeen,
    );
    final start = now.subtract(window);
    final times = d.pingTimes.where((x) => !x.isBefore(start)).toList();
    final gapPoints = <ChartPoint>[
      for (var i = 1; i < times.length; i++)
        ChartPoint(times[i], times[i].difference(times[i - 1]).inMilliseconds / 1000),
    ];
    final received = ps.receivedPercent;
    return PanelCard(
      title: 'Pings',
      count: '${ps.pings} in ${window.inMinutes} min',
      tip: 'A ping is one advertising event: an advertisement and its scan response count once',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TileRow(minWidth: 128, tiles: [
          StatTile(label: 'Pings', value: formatCount(ps.pings)),
          StatTile(label: 'Avg gap', value: formatGap(ps.avg), tone: Tone.accent),
          StatTile(label: 'Min gap', value: formatGap(ps.min)),
          StatTile(label: 'Max gap', value: formatGap(ps.max)),
          StatTile(label: 'Last gap', value: formatGap(ps.last)),
          StatTile(
            label: 'Jitter',
            value: formatGap(ps.jitter),
            tip: 'Standard deviation of the gaps: how regular the pings arrive',
          ),
          StatTile(
            label: 'Received',
            value: received == null ? '—' : '${received.round()} %',
            tone: received == null ? Tone.neutral : (received < 70 ? Tone.warn : Tone.ok),
            tip: ps.expected == null
                ? 'Shown once five gaps are known'
                : 'Pings heard against pings expected at the advertising interval, estimated as '
                    '${formatGap(ps.expected)} from the shortest common gap',
          ),
        ]),
        const SizedBox(height: 14),
        TimeChart(
          end: now,
          window: window,
          height: 130,
          yMin: 0,
          minSpan: 1,
          maxGap: const Duration(days: 1),
          series: [
            ChartSeries(label: 'Gap between pings', color: t.accent, dots: true, width: 1.2, unit: ' s', decimals: 2, points: gapPoints),
          ],
        ),
      ]),
    );
  }

  Widget _charts(BuildContext context, EyeDevice d, DateTime now, Duration window, List<ChartSlot> layout,
      Set<String> available) {
    final c = AppScope.of(context);
    final t = context.tokens;
    List<ChartPoint> pts(Iterable<Sample> s) => [for (final x in s) ChartPoint(x.time, x.value)];
    final maxGap = Duration(milliseconds: ((d.intervalMs ?? 5000) * 4).clamp(4000, 120000));

    Widget card(String id) {
      final (List<ChartSeries> series, double minSpan, double? yMin, String tip, List<ChartBand> bands) = switch (id) {
        ChartSlot.signal => (
            [
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
                showStats: false,
                points: [for (final s in d.rssiHistory) ChartPoint(s.time, s.smoothed)],
              ),
            ],
            20.0,
            null,
            'Raw RSSI per packet and the smoothed value; shaded bands are the proximity zones',
            [
              ChartBand(c.settings.nearDbm.toDouble(), -20, t.ok.withValues(alpha: 0.07), 'Near'),
              ChartBand(c.settings.awayDbm.toDouble(), c.settings.nearDbm.toDouble(), t.warn.withValues(alpha: 0.06), 'Away'),
            ],
          ),
        ChartSlot.battery => (
            [ChartSeries(label: 'Battery', color: t.ok, unit: ' mV', points: pts(d.batteryHistory))],
            100.0,
            null,
            '',
            const <ChartBand>[],
          ),
        ChartSlot.temperature => (
            [ChartSeries(label: 'Temperature', color: t.warn, unit: ' °C', decimals: 2, points: pts(d.temperatureHistory))],
            2.0,
            null,
            '',
            const <ChartBand>[],
          ),
        ChartSlot.humidity => (
            [ChartSeries(label: 'Humidity', color: t.accent, unit: ' %', points: pts(d.humidityHistory))],
            10.0,
            null,
            '',
            const <ChartBand>[],
          ),
        ChartSlot.movement => (
            [ChartSeries(label: 'Count', color: t.accent, points: pts(d.movementHistory))],
            10.0,
            0.0,
            'Movement events counted by the sensor',
            const <ChartBand>[],
          ),
        _ => (
            [
              ChartSeries(label: 'Pitch', color: t.ok, unit: '°', points: pts(d.pitchHistory)),
              ChartSeries(label: 'Roll', color: t.warn, unit: '°', points: pts(d.rollHistory)),
            ],
            20.0,
            null,
            '',
            const <ChartBand>[],
          ),
      };
      return PanelCard(
        title: ChartSlot.title(id),
        tip: tip,
        child: TimeChart(
          end: now,
          window: window,
          height: id == ChartSlot.signal ? 200 : 150,
          maxGap: maxGap,
          minSpan: minSpan,
          yMin: yMin,
          bands: bands,
          series: series,
        ),
      );
    }

    final shown = [for (final s in layout) if (s.visible && available.contains(s.id)) s];
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final rows = <Widget>[];
      for (var i = 0; i < shown.length; i++) {
        final s = shown[i];
        final pairable = wide && !s.full && i + 1 < shown.length && !shown[i + 1].full;
        if (pairable) {
          rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: card(s.id)),
            const SizedBox(width: 14),
            Expanded(child: card(shown[i + 1].id)),
          ]));
          i++;
        } else if (wide && !s.full) {
          rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: card(s.id)),
            const SizedBox(width: 14),
            const Expanded(child: SizedBox.shrink()),
          ]));
        } else {
          rows.add(card(s.id));
        }
      }
      return Column(children: [for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: 14), child: r)]);
    });
  }
}

/// The pinned bar: back to the list, the device's name, the window, Arrange.
class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.window, required this.onBack, required this.onWindow, required this.onArrange});

  final String label;
  final int window;
  final VoidCallback onBack;
  final ValueChanged<int> onWindow;
  final VoidCallback onArrange;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 640;
      return Row(children: [
        TextButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.chevron_left, size: 18),
          label: Text(narrow ? 'Back' : 'All devices'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: narrow
              ? const SizedBox.shrink()
              : Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
        ),
        HoldTip(
          message: 'Every chart and the ping figures cover this window',
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [for (final m in DeviceBook.windowChoices) ButtonSegment(value: m, label: Text('$m min'))],
            selected: {window},
            onSelectionChanged: (s) => onWindow(s.first),
          ),
        ),
        const SizedBox(width: 8),
        if (narrow)
          IconButton(onPressed: onArrange, tooltip: 'Arrange charts', icon: const Icon(Icons.dashboard_customize_outlined, size: 20))
        else
          OutlinedButton.icon(
            onPressed: onArrange,
            icon: const Icon(Icons.dashboard_customize_outlined, size: 17),
            label: const Text('Arrange'),
          ),
      ]);
    });
  }
}

class _BarDelegate extends SliverPersistentHeaderDelegate {
  _BarDelegate(this.child, this.background, this.line);

  final Widget child;
  final Color background;
  final Color line;

  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: background, border: Border(bottom: BorderSide(color: line))),
        child: child,
      );

  @override
  bool shouldRebuild(covariant _BarDelegate old) => true;
}
