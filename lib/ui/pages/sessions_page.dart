import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/controller.dart';
import '../../core/session_store.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../../core/error_log.dart';

/// Every live scan saved from Start scan to Stop scan, one CSV each: listed here to open, export or
/// delete.
class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  List<SessionInfo> _sessions = const [];
  int _loaded = -1;
  bool _busy = false;

  bool get _windows => !kIsWeb && Platform.isWindows;

  Future<void> _load(AppController c) async {
    final store = c.sessions;
    final revision = c.sessionsRevision;
    _loaded = revision;
    final list = store == null ? const <SessionInfo>[] : await store.list();
    if (mounted && revision == c.sessionsRevision) setState(() => _sessions = list);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    if (c.sessions == null) {
      return const EmptyState(icon: Icons.history_outlined, text: 'Sessions are recorded by the Windows and Android apps.');
    }
    if (_loaded != c.sessionsRevision) _load(c);

    final now = DateTime.now();
    final recording = c.recording;
    // The session being recorded shows its live figures; the rest come from their files.
    final rows = [
      for (final s in _sessions)
        if (recording != null && s.csv.path == recording.csv.path) recording.info else s,
    ];
    final totalBytes = rows.fold<int>(0, (n, s) => n + s.bytes);
    final narrow = MediaQuery.sizeOf(context).width < 720;
    final recordOff = !c.settings.recordSessions;

    final String recordingValue;
    final Tone recordingTone;
    if (recording != null) {
      recordingValue = formatDuration(now.difference(recording.started));
      recordingTone = Tone.bad;
    } else if (recordOff) {
      recordingValue = 'Off';
      recordingTone = Tone.warn;
    } else if (c.scanning && c.isDemo) {
      recordingValue = 'Demo data';
      recordingTone = Tone.muted;
    } else {
      recordingValue = 'Waiting';
      recordingTone = Tone.neutral;
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      TileRow(tiles: [
        StatTile(label: 'Sessions', value: formatCount(rows.length)),
        StatTile(label: 'On disk', value: formatBytes(totalBytes), tip: c.sessions!.dir.path),
        StatTile(
          label: 'Recording',
          value: recordingValue,
          secondary: recording == null ? null : '${formatCount(recording.packets)} packets',
          tone: recordingTone,
          tip: 'Each live scan is saved from Start scan to Stop scan; demo data is not recorded',
        ),
      ]),
      if (recordOff) ...[
        const SizedBox(height: 12),
        Notice(
          'Scans are not being recorded.',
          action: TextButton(
            onPressed: () => c.settings.update((s) => s.recordSessions = true),
            child: const Text('Record every scan'),
          ),
        ),
      ],
      if (c.sessionProblem != null) ...[
        const SizedBox(height: 12),
        Notice(c.sessionProblem!, tone: Tone.bad),
      ],
      const SizedBox(height: 14),
      PanelCard(
        title: 'Sessions',
        count: '${rows.length}',
        padding: EdgeInsets.zero,
        actions: [
          if (_windows)
            OutlinedButton.icon(
              onPressed: () => Process.start('explorer.exe', [c.sessions!.dir.path]),
              icon: const Icon(Icons.folder_open_outlined, size: 17),
              label: const Text('Open folder'),
            ),
        ],
        child: rows.isEmpty
            ? const SizedBox(height: 160, child: EmptyState(text: 'No sessions yet.'))
            : DataGrid<SessionInfo>(
                rows: rows,
                shrinkWrap: true,
                initialSort: 0,
                initialAscending: false,
                onTap: (s) => _rowMenu(context, c, s),
                columns: [
                  GridColumn(
                    label: 'Started',
                    width: 168,
                    sortValue: (s) => s.started,
                    cell: (ctx, s) => Text(formatDateTime(s.started), style: monoStyle(ctx, size: 12.5)),
                  ),
                  GridColumn(
                    label: 'Duration',
                    width: 110,
                    numeric: true,
                    sortValue: (s) => s.duration,
                    cell: (_, s) => Text(formatDuration(s.duration)),
                  ),
                  GridColumn(
                    label: 'Devices',
                    width: 80,
                    numeric: true,
                    sortValue: (s) => s.devices,
                    cell: (_, s) => Text(s.devices == null ? '—' : formatCount(s.devices!)),
                  ),
                  GridColumn(
                    label: 'Packets',
                    width: 96,
                    numeric: true,
                    sortValue: (s) => s.packets,
                    cell: (_, s) => Text(s.packets == null ? '—' : formatCount(s.packets!)),
                  ),
                  GridColumn(
                    label: 'Size',
                    width: 84,
                    numeric: true,
                    sortValue: (s) => s.bytes,
                    cell: (_, s) => Text(formatBytes(s.bytes)),
                  ),
                  GridColumn(
                    label: 'State',
                    width: 118,
                    tip: 'Interrupted: the app closed while recording; everything up to then is kept',
                    cell: (_, s) => _isRecording(c, s)
                        ? const Pill('Recording', tone: Tone.bad, small: true)
                        : s.ended == null
                            ? const Pill('Interrupted', tone: Tone.warn, small: true)
                            : const Pill('Saved', tone: Tone.ok, small: true),
                  ),
                  // On a phone a row opens its actions instead: no sideways scrolling to reach them.
                  if (!narrow) ...[
                    GridColumn(
                      label: 'File',
                      width: 220,
                      fill: true,
                      cell: (ctx, s) =>
                          Text(s.name, overflow: TextOverflow.ellipsis, style: monoStyle(ctx, size: 12, color: ctx.tokens.dim)),
                    ),
                    GridColumn(
                      label: '',
                      width: _windows ? 148 : 108,
                      cell: (ctx, s) => _actions(ctx, c, s),
                    ),
                  ],
                ],
              ),
      ),
    ]);
  }

  bool _isRecording(AppController c, SessionInfo s) => c.recording?.csv.path == s.csv.path;

  /// A row's actions as a sheet: Open (Windows), Save a copy or Share, Delete.
  Future<void> _rowMenu(BuildContext context, AppController c, SessionInfo s) async {
    final t = context.tokens;
    final live = _isRecording(c, s);
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true, // as tall as its rows, not capped at part of the screen
      backgroundColor: t.panel,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(formatDateTime(s.started), style: monoStyle(ctx, size: 13)),
            subtitle: Text([
              formatDuration(s.duration),
              if (s.packets != null) '${formatCount(s.packets!)} packets',
              formatBytes(s.bytes),
              if (live) 'recording',
            ].join(' · ')),
          ),
          const Divider(height: 1),
          if (_windows)
            ListTile(
              enabled: !live,
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open'),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
          ListTile(
            enabled: !live,
            leading: Icon(_windows ? Icons.save_alt : Icons.share_outlined),
            title: Text(_windows ? 'Save a copy' : 'Share'),
            onTap: () => Navigator.pop(ctx, 'export'),
          ),
          ListTile(
            enabled: !live,
            leading: Icon(Icons.delete_outline, color: live ? null : t.bad),
            title: Text('Delete', style: TextStyle(color: live ? null : t.bad)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'open':
        await Process.start('explorer.exe', [s.csv.path]);
      case 'export':
        await _export(context, s);
      case 'delete':
        await _delete(context, c, s);
    }
  }

  Widget _actions(BuildContext context, AppController c, SessionInfo s) {
    final t = context.tokens;
    final live = _isRecording(c, s);
    final enabled = !live && !_busy;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (_windows)
        IconButton(
          tooltip: live ? 'Recording' : 'Open',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: enabled ? () => Process.start('explorer.exe', [s.csv.path]) : null,
          icon: const Icon(Icons.open_in_new),
        ),
      IconButton(
        tooltip: live ? 'Recording' : (_windows ? 'Save a copy' : 'Share'),
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        onPressed: enabled ? () => _export(context, s) : null,
        icon: Icon(_windows ? Icons.save_alt : Icons.share_outlined),
      ),
      IconButton(
        tooltip: live ? 'Recording' : 'Delete',
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        color: t.bad,
        onPressed: enabled ? () => _delete(context, c, s) : null,
        icon: const Icon(Icons.delete_outline),
      ),
    ]);
  }

  Future<void> _export(BuildContext context, SessionInfo s) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (_windows) {
        final loc = await getSaveLocation(
          suggestedName: s.name,
          acceptedTypeGroups: const [XTypeGroup(label: 'CSV', extensions: ['csv'])],
        );
        if (loc == null) return;
        final path = loc.path.toLowerCase().endsWith('.csv') ? loc.path : '${loc.path}.csv';
        await s.csv.copy(path);
        messenger.showSnackBar(SnackBar(
          content: Text('Saved ${s.name}'),
          action: SnackBarAction(label: 'Open folder', onPressed: () => Process.start('explorer.exe', ['/select,$path'])),
        ));
      } else {
        await SharePlus.instance.share(ShareParams(files: [XFile(s.csv.path, mimeType: 'text/csv')], subject: s.name));
      }
    } catch (e) {
      errorLog.warn('files', 'Session not saved or shared', error: e);
      messenger.showSnackBar(SnackBar(content: Text('Not saved: ${e is FileSystemException ? e.message : e.runtimeType}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(BuildContext context, AppController c, SessionInfo s) async {
    final ok = await confirmDestructive(
      context,
      title: 'Delete?',
      sentence: 'Delete the session started ${formatDateTime(s.started)}'
          '${s.packets == null ? '' : ' (${formatCount(s.packets!)} packets)'}? This cannot be undone.',
      action: 'Delete',
    );
    if (!ok) return;
    await c.deleteSession(s);
  }
}
