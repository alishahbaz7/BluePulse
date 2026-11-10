import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../app/controller.dart';
import '../../app/paths.dart';
import '../../core/device.dart';
import '../../core/rx_log.dart';
import '../format.dart';
import '../theme.dart';
import 'common.dart';
import 'data_grid.dart';
import 'device_name.dart';

/// Where logs go: Documents\BluePulse\logs on Windows, the app's own documents folder on Android.
Future<Directory> rxLogsDir() => appFilesDir('logs');

/// A device's received packets, live: newest first, every packet in the time window, with Pause,
/// Record (writes each packet to a CSV file as it arrives) and Save log (a CSV of what is kept).
class RxLogCard extends StatefulWidget {
  const RxLogCard({super.key, required this.device, required this.window});

  final EyeDevice device;
  final Duration window;

  @override
  State<RxLogCard> createState() => _RxLogCardState();
}

class _RxLogCardState extends State<RxLogCard> {
  List<RxEntry>? _frozen;
  bool _busy = false;

  static const _shownMax = 1000;

  List<RxEntry> _inWindow(DateTime now) {
    final start = now.subtract(widget.window);
    return widget.device.rx.where((e) => !e.time.isBefore(start)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final t = context.tokens;
    final now = DateTime.now();
    final live = _inWindow(now).reversed.toList();
    final rows = (_frozen ?? live).take(_shownMax).toList();
    final recorder = c.registry.recorder(widget.device.mac);
    final canSave = !kIsWeb && (Platform.isWindows || Platform.isAndroid);

    return PanelCard(
      title: 'Received packets',
      count: '${live.length} in ${widget.window.inMinutes} min',
      tip: 'Every packet from this device, newest first; the last ${widget.device.rx.capacity} are kept',
      padding: EdgeInsets.zero,
      actions: [
        if (recorder != null)
          Pill('Recording · ${formatCount(recorder.rows)} · ${formatDuration(now.difference(recorder.started))}',
              tone: Tone.bad),
        OutlinedButton.icon(
          onPressed: () => setState(() => _frozen = _frozen == null ? live : null),
          icon: Icon(_frozen == null ? Icons.pause : Icons.play_arrow, size: 17),
          label: Text(_frozen == null ? 'Pause' : 'Resume'),
        ),
        Tooltip(
          message: canSave ? '' : 'Recording works in the Windows and Android apps',
          child: OutlinedButton.icon(
            onPressed: !canSave || _busy ? null : () => recorder == null ? _startRecording(context) : _stopRecording(context),
            icon: Icon(recorder == null ? Icons.fiber_manual_record : Icons.stop, size: 17, color: recorder == null ? t.bad : null),
            label: Text(recorder == null ? 'Record' : 'Stop'),
          ),
        ),
        PopupMenuButton<bool>(
          enabled: canSave && !_busy,
          tooltip: canSave ? 'Save log' : 'Saving logs works in the Windows and Android apps',
          onSelected: (everything) => _save(context, everything ? widget.device.rx.toList() : _inWindow(DateTime.now())),
          itemBuilder: (_) => [
            PopupMenuItem(value: false, child: Text('This window · ${formatCount(live.length)} packets')),
            PopupMenuItem(value: true, child: Text('Everything kept · ${formatCount(widget.device.rx.length)} packets')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(border: Border.all(color: t.frame), borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.save_alt, size: 17, color: canSave ? t.text : t.muted),
              const SizedBox(width: 6),
              Text('Save log', style: TextStyle(fontSize: 13, color: canSave ? t.text : t.muted)),
              Icon(Icons.arrow_drop_down, size: 18, color: t.dim),
            ]),
          ),
        ),
      ],
      child: SizedBox(
        height: 360,
        child: rows.isEmpty
            ? const EmptyState(text: 'No packets in this window.')
            : DataGrid<RxEntry>(
                rows: rows,
                rowHeight: 30,
                columns: [
                  GridColumn(label: 'Time', width: 112, cell: (ctx, e) => Text(formatClockMs(e.time), style: monoStyle(ctx, size: 12))),
                  GridColumn(label: 'Kind', width: 118, cell: (_, e) => Text(e.kind)),
                  GridColumn(label: 'RSSI', width: 62, numeric: true, cell: (_, e) => Text(e.rssi?.toString() ?? '—')),
                  GridColumn(
                    label: 'Gap',
                    width: 84,
                    numeric: true,
                    tip: 'Time since the previous packet from this device',
                    cell: (_, e) => Text(formatGap(e.gapMs == null ? null : Duration(milliseconds: e.gapMs!))),
                  ),
                  GridColumn(label: 'Values', width: 280, cell: (_, e) => Text(e.summary)),
                  GridColumn(
                    label: 'Raw',
                    width: 260,
                    fill: true,
                    cell: (ctx, e) => Text(toHexCompact(e.bytes), style: monoStyle(ctx, size: 11.5, color: ctx.tokens.dim)),
                  ),
                ],
              ),
      ),
    );
  }

  String _label() => deviceLabel(AppScope.read(context).book, widget.device);

  Future<void> _save(BuildContext context, List<RxEntry> entries) async {
    final d = widget.device;
    final book = AppScope.read(context).book;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final csv = RxCsv.document(entries, mac: d.mac, name: d.name, tag: book.tagOf(d.mac));
      final name = RxCsv.fileName(label: _label(), mac: d.mac, time: DateTime.now());
      final dir = await rxLogsDir();
      if (Platform.isWindows) {
        final loc = await getSaveLocation(
          suggestedName: name,
          initialDirectory: dir.path,
          acceptedTypeGroups: const [XTypeGroup(label: 'CSV', extensions: ['csv'])],
        );
        if (loc == null) return;
        final path = loc.path.toLowerCase().endsWith('.csv') ? loc.path : '${loc.path}.csv';
        await File(path).writeAsString(csv);
        _savedNotice(messenger, path, entries.length);
      } else {
        final file = File(p.join(dir.path, name));
        await file.writeAsString(csv);
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/csv')], subject: name));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Log not saved: ${e.runtimeType}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startRecording(BuildContext context) async {
    final c = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final dir = await rxLogsDir();
      final file = File(p.join(dir.path, RxCsv.fileName(label: _label(), mac: widget.device.mac, time: DateTime.now())));
      await c.registry.startRecording(widget.device, file);
      messenger.showSnackBar(SnackBar(content: Text('Recording to ${p.basename(file.path)}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Recording did not start: ${e.runtimeType}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopRecording(BuildContext context) async {
    final c = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final rows = c.registry.recorder(widget.device.mac)?.rows ?? 0;
    setState(() => _busy = true);
    try {
      final file = await c.registry.stopRecording(widget.device.mac);
      if (file == null) return;
      if (Platform.isWindows) {
        _savedNotice(messenger, file.path, rows);
      } else {
        await SharePlus.instance.share(
            ShareParams(files: [XFile(file.path, mimeType: 'text/csv')], subject: p.basename(file.path)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _savedNotice(ScaffoldMessengerState messenger, String path, int rows) {
    messenger.showSnackBar(SnackBar(
      content: Text('Saved ${formatCount(rows)} packets · ${p.basename(path)}'),
      action: SnackBarAction(
        label: 'Open folder',
        onPressed: () => Process.start('explorer.exe', ['/select,$path']),
      ),
    ));
  }
}

/// Hex without separators, for a dense column.
String toHexCompact(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
