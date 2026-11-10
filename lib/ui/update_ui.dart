import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../update/manifest.dart';
import '../update/update_config.dart';
import '../update/update_service.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Opens the update dialog; it follows the service through download, install and restart.
Future<void> showUpdateDialog(BuildContext context) async {
  final c = AppScope.read(context);
  final u = c.updates;
  await showDialog<void>(
    context: context,
    barrierDismissible: !u.required && !u.busy,
    builder: (_) => const _UpdateDialog(),
  );
  // Closed with the update still on offer: *Later*, or the dialog dismissed.
  if (u.stage == UpdateStage.available) {
    c.usage.record('update_postponed', {'version': u.manifest?.version.toString()});
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final u = AppScope.of(context).updates;
    final m = u.manifest;
    final next = m?.version.toString() ?? '—';
    final close = OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'));

    final (String title, Widget body, List<Widget> actions) = switch (u.stage) {
      UpdateStage.checking => ('Checking for updates', const LinearProgressIndicator(), <Widget>[]),
      UpdateStage.upToDate => ('Up to date', _line(context, 'Version ${u.current} is the latest.'), [close]),
      UpdateStage.available => (
          'Update available',
          _available(context, u),
          [
            if (!u.required)
              OutlinedButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: const Text('Later')),
            FilledButton(
              onPressed: u.downloadAndInstall,
              child: Text(u.canInstallHere ? 'Update ›' : 'Open download page'),
            ),
          ],
        ),
      UpdateStage.downloading => (
          'Downloading $next',
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LinearProgressIndicator(value: u.progress, minHeight: 6),
            const SizedBox(height: 8),
            Text(
              '${formatBytes(u.received)} of ${formatBytes(u.total)}'
              '${u.progress == null ? '' : ' · ${(u.progress! * 100).round()} %'}',
              style: TextStyle(fontSize: 13, color: t.dim, fontFeatures: tabular),
            ),
          ]),
          [OutlinedButton(onPressed: u.cancel, child: const Text('Cancel'))],
        ),
      UpdateStage.installing => ('Installing $next', const LinearProgressIndicator(minHeight: 6), <Widget>[]),
      UpdateStage.ready when u.platform == UpdatePlatform.android => (
          'Install $next',
          _line(context, 'The Android installer is open.'),
          [close, FilledButton(onPressed: u.finish, child: const Text('Open installer again'))],
        ),
      UpdateStage.ready => (
          'Restart to finish',
          _line(context, 'Version $next is installed${u.launcherUpdated ? ', and the launcher was updated' : ''}.'),
          [
            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Later')),
            FilledButton(onPressed: u.finish, child: const Text('Restart now')),
          ],
        ),
      UpdateStage.failed => (
          'Update failed',
          Notice(u.error ?? 'Unknown error', tone: Tone.bad),
          [
            close,
            FilledButton(
              onPressed: u.manifest == null ? u.check : u.downloadAndInstall,
              child: const Text('Retry'),
            ),
          ],
        ),
      UpdateStage.disabled || UpdateStage.idle => ('Updates', _line(context, 'Updates are not available in this build.'), [close]),
    };

    return AlertDialog(
      backgroundColor: t.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: t.frame)),
      title: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: t.text)),
      content: SizedBox(width: 480, child: body),
      actions: actions,
    );
  }

  Widget _line(BuildContext context, String text) =>
      Text(text, style: TextStyle(fontSize: 13.5, color: context.tokens.dim));

  Widget _available(BuildContext context, UpdateService u) {
    final t = context.tokens;
    final m = u.manifest!;
    final a = u.asset;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 130, child: Text(k.toUpperCase(), style: labelStyle(context))),
            Expanded(child: Text(v, style: TextStyle(fontSize: 13.5, color: t.text, fontFeatures: tabular))),
          ]),
        );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Version ${m.version} is available. This copy is ${u.current}.',
          style: TextStyle(fontSize: 13.5, color: t.dim)),
      const SizedBox(height: 12),
      row('Version', '${m.version}'),
      row('Installed', '${u.current}'),
      if (m.published != null) row('Published', formatDateTime(m.published!).substring(0, 10)),
      row('Download', a == null ? '—' : formatBytes(a.size)),
      if (u.required) ...[
        const SizedBox(height: 10),
        Notice('Version ${u.current} must be updated to keep working.', tone: Tone.warn),
      ],
      if (!u.canInstallHere && u.platform == UpdatePlatform.windows) ...[
        const SizedBox(height: 10),
        const Notice('This copy was not started from the launcher, so it cannot update itself.', tone: Tone.warn),
      ],
      if (m.notes.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text("WHAT'S NEW", style: labelStyle(context)),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: t.panel2,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: SingleChildScrollView(
            child: SelectableText(m.notes, style: TextStyle(fontSize: 13, color: t.text, height: 1.4)),
          ),
        ),
      ],
    ]);
  }
}

/// Top-bar chip while an update is on offer or in progress; opens the dialog.
class UpdateChip extends StatelessWidget {
  const UpdateChip({super.key});

  @override
  Widget build(BuildContext context) {
    final u = AppScope.of(context).updates;
    final next = u.manifest?.version.toString() ?? '';
    final (String? text, Tone tone) = switch (u.stage) {
      UpdateStage.available => ('Update $next', Tone.accent),
      UpdateStage.downloading => ('Updating · ${u.progress == null ? '…' : '${(u.progress! * 100).round()} %'}', Tone.accent),
      UpdateStage.installing => ('Installing $next', Tone.accent),
      UpdateStage.ready => (u.platform == UpdatePlatform.android ? 'Install $next' : 'Restart to update', Tone.ok),
      UpdateStage.failed when u.updateAvailable => ('Update failed', Tone.bad),
      _ => (null, Tone.muted),
    };
    if (text == null) return const SizedBox.shrink();
    return StatusChip(text: text, tone: tone, glow: true, onTap: () => showUpdateDialog(context));
  }
}

/// Settings → Updates.
class UpdatesCard extends StatelessWidget {
  const UpdatesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final u = AppScope.of(context).updates;
    final channel = UpdateConfig.manifestOverride.isNotEmpty
        ? Uri.parse(UpdateConfig.manifestOverride).host
        : (UpdateConfig.repo.isEmpty ? 'Not set' : UpdateConfig.repo);

    final status = switch (u.stage) {
      UpdateStage.disabled => Notice(u.disabledReason ?? 'Updates are not available in this build.', tone: Tone.warn),
      UpdateStage.upToDate => const Notice('Up to date.', tone: Tone.ok),
      UpdateStage.failed => Notice(u.error ?? 'Check failed', tone: Tone.bad),
      UpdateStage.available when !u.canInstallHere && u.platform == UpdatePlatform.windows =>
        const Notice('Not started from the launcher; updating opens the download page.', tone: Tone.warn),
      _ => null,
    };

    return PanelCard(
      title: 'Updates',
      tip: 'Checks the public releases repository each time the app starts',
      actions: [
        OutlinedButton.icon(
          onPressed: u.stage == UpdateStage.disabled || u.busy ? null : u.check,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Check now'),
        ),
        if (u.updateAvailable)
          FilledButton(onPressed: () => showUpdateDialog(context), child: Text('Update to ${u.manifest!.version}')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 28, runSpacing: 12, children: [
          Fact('Installed', u.current?.toString() ?? '—'),
          Fact('Latest', u.manifest?.version.toString() ?? '—'),
          Fact('Last checked', u.lastChecked == null ? '—' : formatClock(u.lastChecked!)),
          Fact('Channel', channel, mono: channel.contains('/')),
        ]),
        if (status != null) ...[const SizedBox(height: 12), status],
      ]),
    );
  }
}
