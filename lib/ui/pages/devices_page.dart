import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../app/controller.dart';
import '../../core/device.dart';
import '../format.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/device_card.dart';
import '../widgets/device_name.dart';
import '../widgets/device_table.dart';
import 'live_state.dart';
import '../../core/error_log.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final r = c.registry;
    final now = DateTime.now();
    final all = r.devices;
    final empty = liveEmptyState(context, hasRows: all.isNotEmpty);
    if (empty != null) return empty;

    final book = c.book;
    final q = _query.trim().toLowerCase();
    bool found(EyeDevice d) =>
        q.isEmpty || d.searchText.contains(q) || (book.tagOf(d.mac)?.toLowerCase().contains(q) ?? false);
    final rows = all.where(found).toList();
    final go = Navigation.of(context).go;
    final pinned = all.where((d) => book.pinned(d.mac)).length;

    final phone = isPhone(context);
    // Tiles (as on Configure and on a phone) or the table, as chosen with the switch beside Search.
    final tiles = showTiles(context);
    final sort = c.settings.deviceSort;
    if (tiles) sortDevices(rows, sort, (d) => deviceLabel(book, d));
    // Tiles: the pinned devices in their own section above the rest, each in the chosen order.
    final top = [for (final d in rows) if (book.pinned(d.mac)) d];
    final rest = [for (final d in rows) if (!book.pinned(d.mac)) d];
    Widget card(EyeDevice d, bool stripe) => DeviceCard(
          device: d,
          now: now,
          focus: true,
          stripe: stripe,
          onTap: () => go(PageId.deviceDetail, mac: d.mac),
        );

    return Padding(
      padding: EdgeInsets.all(phone ? 12 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ?liveErrorNotice(context),
        if (pinned > 0 || c.sensorLog != null) ...[
          _FocusBar(ticked: all.where((d) => book.pinned(d.mac)).toList(), interval: r.backgroundInterval(now)),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: PanelCard(
            title: 'Devices',
            // How many, once on the page; "3 of 16" while a search narrows the list.
            count: rows.length == all.length ? '${all.length}' : '${rows.length} of ${all.length}',
            padding: EdgeInsets.zero,
            expand: true,
            actions: [
              SearchButton(query: _query, hint: 'Name, MAC or ID', onChanged: (q) => setState(() => _query = q)),
              if (tiles) DeviceSortMenu(value: sort, onChanged: (v) => c.settings.update((s) => s.deviceSort = v)),
              if (!phone) const DeviceViewToggle(),
            ],
            child: rows.isEmpty
                ? const EmptyState(text: 'No devices match.')
                : tiles
                    ? CardRows.sections(sections: [
                        if (top.isNotEmpty)
                          CardSection(
                            title: 'Pinned',
                            icon: Icons.push_pin,
                            count: top.length,
                            card: (i, stripe) => card(top[i], stripe),
                          ),
                        CardSection(
                          title: top.isEmpty ? null : 'Other devices',
                          icon: Icons.sensors,
                          count: rest.length,
                          card: (i, stripe) => card(rest[i], stripe),
                        ),
                      ])
                    : DataGrid<EyeDevice>(
                    rows: rows,
                    columns: deviceColumns(context, rows: rows, now: now),
                    // By name: a list that stays put. Click a header for signal, rate and the rest.
                    initialSort: 1,
                    initialAscending: true,
                    pinned: (d) => book.pinned(d.mac),
                    selected: (d) => book.pinned(d.mac),
                    // Out of range: greyed in place, as a tile is.
                    dimmed: (d) => d.isNotSeen(now, c.settings.notSeenMinSeconds),
                    onTap: (d) => go(PageId.deviceDetail, mac: d.mac),
                  ),
          ),
        ),
      ]),
    );
  }
}

/// Shown while devices are ticked or a log runs: how many are in focus and how often the rest
/// refresh, the multi-device log (every packet from the ticked devices, as it arrives), and the way
/// out of focus.
class _FocusBar extends StatefulWidget {
  const _FocusBar({required this.ticked, required this.interval});

  /// The devices ticked now, in list order.
  final List<EyeDevice> ticked;
  final Duration interval;

  @override
  State<_FocusBar> createState() => _FocusBarState();
}

class _FocusBarState extends State<_FocusBar> {
  bool _busy = false;

  Future<void> _start() async {
    final c = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final log = await c.startSensorLog(widget.ticked);
      messenger.showSnackBar(SnackBar(content: Text('Logging to ${p.basename(log.file.path)}')));
    } catch (e) {
      errorLog.warn('log', 'The multi-device log did not start', error: e);
      messenger.showSnackBar(SnackBar(content: Text('The log did not start: ${e.runtimeType}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final c = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final rows = c.sensorLog?.rows ?? 0;
    setState(() => _busy = true);
    try {
      final files = await c.stopSensorLog();
      if (files.isEmpty) return;
      final file = files.first;
      final parts = files.length == 1 ? '' : ' (${files.length} parts)';
      if (Platform.isWindows) {
        messenger.showSnackBar(SnackBar(
          content: Text('Saved ${formatCount(rows)} packets · ${p.basename(file.path)}$parts'),
          action: SnackBarAction(label: 'Open folder', onPressed: () => Process.start('explorer.exe', ['/select,${file.path}'])),
        ));
      } else {
        await SharePlus.instance.share(ShareParams(
          files: [for (final f in files) XFile(f.path, mimeType: 'text/csv')],
          subject: p.basename(file.path),
        ));
      }
    } catch (e) {
      errorLog.warn('log', 'The multi-device log did not close or share cleanly', error: e);
      messenger.showSnackBar(SnackBar(content: Text('The log was not shared: ${e.runtimeType}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = AppScope.of(context);
    final log = c.sensorLog;
    final count = widget.ticked.length;

    final info = log != null
        ? HoldTip(
            message: 'A row for every packet from these devices: time, MAC, interval since its last packet, name, '
                'values, signal and the raw bytes',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.fiber_manual_record, size: 14, color: t.bad),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Logging ${log.macs.length} · ${formatDuration(DateTime.now().difference(log.started))} · '
                  '${formatCount(log.rows)} packets',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text, fontFeatures: tabular),
                ),
              ),
            ]),
          )
        : Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.push_pin, size: 18, color: t.accent),
            const SizedBox(width: 10),
            Text('$count pinned', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(width: 12),
            Flexible(
              child: HoldTip(
                message: 'Pinned devices are redrawn with every packet; the rest are counted in full but redrawn less '
                    'often — busier radios mean longer gaps',
                child: Text('others every ${formatDuration(widget.interval)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: t.dim)),
              ),
            ),
          ]);

    final actions = Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (log != null)
        TextButton.icon(
          onPressed: _busy ? null : _stop,
          icon: const Icon(Icons.stop, size: 18),
          label: const Text('Stop log'),
        )
      else if (count > 0)
        Tooltip(
          message: 'Every packet from the ticked devices, as it arrives, to one CSV',
          child: TextButton.icon(
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.fiber_manual_record, size: 16),
            label: const Text('Log'),
          ),
        ),
      if (count > 0) TextButton(onPressed: c.book.clearFocus, child: const Text('Unpin all')),
    ]);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(log != null ? t.bad.withValues(alpha: 0.08) : t.accentSoft, t.panel),
        border: Border.all(color: (log != null ? t.bad : t.accent).withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: LayoutBuilder(builder: (context, box) {
        // On a phone the buttons go under the line: beside it they squeezed it to nothing.
        if (box.maxWidth < 560) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: info),
            actions,
          ]);
        }
        return Row(children: [Expanded(child: Align(alignment: Alignment.centerLeft, child: info)), actions]);
      }),
    );
  }
}
