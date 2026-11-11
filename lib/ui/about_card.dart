import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../update/manifest.dart' show UpdatePlatform;
import '../update/update_service.dart';
import 'format.dart';
import 'theme.dart';
import 'update_ui.dart';
import 'usage_ui.dart';
import 'widgets/common.dart';

/// Settings → About: the version and whether it is the latest, Check for updates, and the name this
/// copy greets and reports as. The latest version, last check, platform, build and install ID are one
/// tap away under Details, for support.
class AboutCard extends StatelessWidget {
  const AboutCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final t = context.tokens;
    final u = c.updates;
    final usage = c.usage;
    final kind = kDebugMode ? 'Debug' : (kProfileMode ? 'Profile' : 'Release');

    final (IconData icon, Color color, String line) = switch (u.stage) {
      _ when u.busy => (Icons.sync, t.dim, 'Checking for updates…'),
      UpdateStage.disabled => (
        Icons.info_outline,
        t.muted,
        u.disabledReason ?? 'Updates are not available in this build',
      ),
      UpdateStage.upToDate => (
        Icons.check_circle,
        t.ok,
        'Up to date${u.lastChecked == null ? '' : ' · checked ${formatClock(u.lastChecked!)}'}',
      ),
      UpdateStage.failed => (Icons.error_outline, t.warn, 'Could not check for updates'),
      _ when u.updateAvailable => (Icons.system_update, t.accent, 'Version ${u.manifest!.version} is available'),
      _ => (Icons.info_outline, t.muted, 'Not checked yet'),
    };

    return PanelCard(
      title: 'About',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.bluetooth_searching, color: t.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BluePulse',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: t.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Version ${c.version}${kind == 'Release' ? '' : ' · $kind'}',
                      style: TextStyle(fontSize: 13.5, color: t.dim, fontFeatures: tabular),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          HoldTip(
            message: u.stage == UpdateStage.failed ? (u.error ?? '') : '',
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(line, style: TextStyle(fontSize: 13.5, color: t.text)),
                ),
              ],
            ),
          ),
          if (u.updateAvailable && !u.canInstallHere && u.platform == UpdatePlatform.windows) ...[
            const SizedBox(height: 8),
            Text(
              'Not started from the launcher: updating opens the download page.',
              style: TextStyle(fontSize: 12.5, color: t.dim),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (u.updateAvailable)
                FilledButton.icon(
                  onPressed: () => showUpdateDialog(context),
                  icon: const Icon(Icons.download, size: 18),
                  label: Text('Update to ${u.manifest!.version}'),
                ),
              OutlinedButton.icon(
                onPressed: u.stage == UpdateStage.disabled || u.busy ? null : u.check,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Check for updates'),
              ),
            ],
          ),
          if (usage.enabled && usage.install != null) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: t.line),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Fact('Your name', usage.install!.name.isEmpty ? '—' : usage.install!.name)),
                TextButton(onPressed: () => showIdentityDialog(context), child: const Text('Edit name')),
              ],
            ),
          ],
          const SizedBox(height: 6),
          // Its own Material: the card paints a background the tile's ink would otherwise hide behind.
          Material(
            type: MaterialType.transparency,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: Text('Details', style: TextStyle(fontSize: 13.5, color: t.dim)),
                children: [_Details(kind: kind)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// For support: which version is the latest, when it was checked, the platform and build, and the
/// install ID that names this copy in the usage reports.
class _Details extends StatelessWidget {
  const _Details({required this.kind});

  /// Release, Profile or Debug.
  final String kind;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final u = c.updates;
    final id = c.usage.enabled ? c.usage.install?.id : null;
    return Wrap(
      spacing: 28,
      runSpacing: 12,
      children: [
        Fact('Latest', u.manifest?.version.toString() ?? '—'),
        Fact('Last checked', u.lastChecked == null ? '—' : formatClock(u.lastChecked!)),
        Fact('Platform', kIsWeb ? 'Web' : defaultTargetPlatform.name),
        Fact('Build', kind),
        if (id != null) Fact('Install ID', id, mono: true),
      ],
    );
  }
}
