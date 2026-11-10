import 'package:flutter/material.dart';

import '../app/controller.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// The first-start question: asked gently, as a welcome — the app is getting to know its user.
const welcomeTitle = 'Hi! May I have your name, please?';

/// Asks for the person's name. At the first start it must be answered ([required]); from Settings
/// it can be cancelled.
Future<void> showIdentityDialog(BuildContext context, {bool required = false}) => showDialog<void>(
      context: context,
      barrierDismissible: !required,
      builder: (_) => _IdentityDialog(required: required),
    );

class _IdentityDialog extends StatefulWidget {
  const _IdentityDialog({required this.required});

  final bool required;

  @override
  State<_IdentityDialog> createState() => _IdentityDialogState();
}

class _IdentityDialogState extends State<_IdentityDialog> {
  late final TextEditingController _name;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final i = AppScope.read(context).usage.install;
    _name = TextEditingController(text: i?.name ?? '')..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    await AppScope.read(context).usage.setName(_name.text);
    if (mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PopScope(
      canPop: !widget.required,
      child: AlertDialog(
        backgroundColor: t.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: t.frame)),
        title: Text(widget.required ? welcomeTitle : 'Your name',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: t.text)),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Friendly, and still honest: the name is shared, and Settings shows exactly what is.
            Text(
              "We'll use it to greet you and to make BluePulse better for you. "
              'Settings → Usage reporting shows what is shared.',
              style: TextStyle(fontSize: 13.5, color: t.dim, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(labelText: 'Name', counterText: ''),
            ),
          ]),
        ),
        actions: [
          if (!widget.required)
            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: _valid && !_saving ? _save : null,
            child: Text(widget.required ? 'Continue' : 'Save'),
          ),
        ],
      ),
    );
  }
}

/// The person's name once given, for greeting them; null before that and where reporting is off.
String? greetingName(BuildContext context) {
  final name = AppScope.of(context).usage.install?.name.trim() ?? '';
  return name.isEmpty ? null : name;
}

/// "Hello, Name" at the top of the home page.
class Greeting extends StatelessWidget {
  const Greeting(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          'Hello, $name',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: context.tokens.text),
        ),
      );
}

/// Settings → Usage reporting.
class UsageCard extends StatelessWidget {
  const UsageCard({super.key});

  @override
  Widget build(BuildContext context) {
    final u = AppScope.of(context).usage;
    final i = u.install;
    String or(String? v) => v == null || v.trim().isEmpty ? '—' : v;

    final status = !u.enabled
        ? Notice(u.disabledReason ?? 'Usage reporting is not set in this build.', tone: Tone.warn)
        : (u.error != null ? Notice('Not sent: ${u.error}', tone: Tone.warn) : null);

    // Today's sends by the clock alone, as Updates → Last checked; older ones with the date.
    String sent(DateTime t) {
      final now = DateTime.now();
      final l = t.toLocal();
      return l.year == now.year && l.month == now.month && l.day == now.day ? formatClock(t) : formatDateTime(t);
    }

    return PanelCard(
      title: 'Usage reporting',
      tip: 'Reported: your name, this device, the app version, each start with its time open, '
          'scanning and pages used, updates and app errors. Never beacon addresses, packets or location',
      actions: [
        OutlinedButton.icon(
          onPressed: u.enabled && i != null ? () => showIdentityDialog(context) : null,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit name'),
        ),
        OutlinedButton.icon(
          onPressed: u.enabled && !u.sending ? u.flush : null,
          icon: const Icon(Icons.upload_outlined, size: 18),
          label: const Text('Send now'),
        ),
      ],
      // Switched off, there is nothing to show but why.
      child: !u.enabled
          ? status!
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 28, runSpacing: 12, children: [
                Fact('Name', or(i?.name)),
                Fact('Install ID', or(i?.id), mono: i != null),
                Fact('Reporting to', or(u.endpoint?.host), mono: u.endpoint != null),
                Fact('Last sent', u.sending ? 'Sending…' : (u.lastSent == null ? '—' : sent(u.lastSent!))),
                Fact('Waiting', '${u.waiting}'),
              ]),
              if (status != null) ...[const SizedBox(height: 12), status],
            ]),
    );
  }
}
