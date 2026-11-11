import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../app/controller.dart';
import '../app/paths.dart';
import '../core/error_log.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/common.dart';

bool get _windows => !kIsWeb && Platform.isWindows;
bool get _android => !kIsWeb && Platform.isAndroid;

/// Settings → Files: the one folder where BluePulse saves everything on this device, to open or
/// change, and the error log.
class FilesCard extends StatefulWidget {
  const FilesCard({super.key});

  @override
  State<FilesCard> createState() => _FilesCardState();
}

class _FilesCardState extends State<FilesCard> {
  bool _busy = false;

  /// Asks where; null when the person cancels. A null [Directory] inside means the default folder.
  Future<(Directory?,)?> _ask() async {
    if (_android) {
      // Android lets an app write its own files into the shared Documents and Download folders only.
      final docs = await androidFolder('Documents');
      final download = await androidFolder('Download');
      if (!mounted) return null;
      return showDialog<(Directory?,)>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Save BluePulse files in'),
          children: [
            for (final (dir, isDefault) in [(docs, true), (download, false)])
              if (dir != null)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop((isDefault ? null : dir,)),
                  child: Text('${folderLabel(dir.path)}${isDefault ? '  (default)' : ''}'),
                ),
          ],
        ),
      );
    }
    final picked = await getDirectoryPath(
      confirmButtonText: 'Use this folder',
      initialDirectory: appHomeNow?.parent.path,
    );
    return picked == null ? null : (Directory(bluePulseFolderIn(picked)),);
  }

  Future<void> _change({bool toDefault = false}) async {
    final c = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final (Directory? to,)? choice = toDefault ? (null,) : await _ask();
    if (choice == null || !mounted) return;
    final to = choice.$1;
    final target = to ?? await defaultAppHome();
    final current = appHomeNow;
    if (current == null || p.equals(target.path, current.path) || !mounted) return;

    final files = savedFiles(current);
    var bytes = 0;
    for (final f in files) {
      try {
        bytes += f.lengthSync();
      } catch (_) {}
    }
    final move = await _confirm(folderLabel(target.path), files.length, bytes);
    if (move == null) return;

    setState(() => _busy = true);
    try {
      final r = await c.changeFilesFolder(to, moveFiles: move);
      messenger.showSnackBar(SnackBar(
        content: Text('Files now go to ${folderLabel(target.path)}'
            '${move ? ' · ${r.moved} moved${r.stayed > 0 ? ', ${r.stayed} stayed (see the error log)' : ''}' : ''}'),
      ));
    } catch (e) {
      errorLog.warn('files', 'The files folder was not changed', error: e);
      messenger.showSnackBar(SnackBar(content: Text('Not changed: ${e is FileSystemException ? e.message : e}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Use [label]? With the files already saved moving along (on by default); null on Cancel.
  Future<bool?> _confirm(String label, int count, int bytes) {
    var move = true;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) {
          final t = context.tokens;
          return AlertDialog(
            backgroundColor: t.panel,
            title: Text('Save files here?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: t.text)),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText(label, style: monoStyle(context, size: 13.5, color: t.text)),
              if (count > 0) ...[
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: move,
                  onChanged: (v) => set(() => move = v),
                  title: Text(
                    'Move the $count file${count == 1 ? '' : 's'} already saved (${formatBytes(bytes)})',
                    style: TextStyle(fontSize: 13.5, color: t.text),
                  ),
                ),
              ],
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(context).pop(count > 0 && move), child: const Text('Use this folder')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final t = context.tokens;
    final label = appHomeLabel();
    final busy = c.filesFolderBusy;
    if (label == null) return const SizedBox.shrink(); // the web build saves nothing

    return PanelCard(
      title: 'Files',
      actions: [
        if (_windows)
          OutlinedButton.icon(
            onPressed: () => Process.start('explorer.exe', [appHomeNow!.path]),
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Open folder'),
          ),
        Tooltip(
          message: busy ?? 'Save sessions, logs and the error log in another folder',
          child: OutlinedButton.icon(
            onPressed: _busy || busy != null ? null : _change,
            icon: const Icon(Icons.drive_file_move_outline, size: 18),
            label: const Text('Change…'),
          ),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText(label, style: monoStyle(context, size: 13.5, color: t.text)),
        const SizedBox(height: 4),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
          Text(
            appHomeIsDefault ? 'Default folder · sessions, logs and the error log' : 'Chosen folder · sessions, logs and the error log',
            style: TextStyle(fontSize: 12.5, color: t.dim),
          ),
          if (!appHomeIsDefault)
            TextButton(
              onPressed: _busy || busy != null ? null : () => _change(toDefault: true),
              child: const Text('Use the default'),
            ),
        ]),
        if (_busy) ...[const SizedBox(height: 8), const LinearProgressIndicator()],
        const SizedBox(height: 8),
        Divider(height: 1, color: t.line),
        const SizedBox(height: 6),
        ListenableBuilder(
          listenable: errorLog,
          builder: (context, _) {
            final n = errorLog.problems;
            return Row(children: [
              Icon(n == 0 ? Icons.check_circle_outline : Icons.report_outlined, size: 18, color: n == 0 ? t.ok : t.warn),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  n == 0 ? 'Error log · nothing went wrong this run' : 'Error log · $n problem${n == 1 ? '' : 's'} this run',
                  style: TextStyle(fontSize: 13.5, color: t.text),
                ),
              ),
              TextButton(onPressed: () => showErrorLog(context), child: const Text('View log')),
            ]);
          },
        ),
      ]),
    );
  }
}

/// What happened this run, newest first, in words — and the file (every run) to open or share.
Future<void> showErrorLog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ErrorLogDialog());

class _ErrorLogDialog extends StatelessWidget {
  const _ErrorLogDialog();

  Future<void> _openFile(BuildContext context, File file) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await errorLog.flush();
      if (_windows) {
        await Process.start('notepad.exe', [file.path]);
      } else {
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/plain')], subject: p.basename(file.path)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('The log could not be opened: ${e.runtimeType}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final entries = errorLog.recent.reversed.toList();
    final file = errorLog.file;
    Color tone(LogLevel l) => switch (l) {
          LogLevel.error => t.bad,
          LogLevel.warning => t.warn,
          LogLevel.info => t.dim,
        };
    return AlertDialog(
      backgroundColor: t.panel,
      title: Text('Error log', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: t.text)),
      content: SizedBox(
        width: 620,
        child: entries.isEmpty
            ? Text('Nothing has gone wrong this run.', style: TextStyle(color: t.dim))
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 440),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => Divider(height: 14, color: t.line),
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        '${formatClock(e.time)} · ${e.source}${e.repeats > 0 ? ' · ${e.repeats + 1} times' : ''}',
                        style: TextStyle(fontSize: 12, color: t.dim, fontFeatures: tabular),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(e.message, style: TextStyle(fontSize: 13.5, color: tone(e.level))),
                    ]);
                  },
                ),
              ),
      ),
      actions: [
        if (file != null)
          TextButton(
            onPressed: () => _openFile(context, file),
            child: Text(_windows ? 'Open file' : 'Share file'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
