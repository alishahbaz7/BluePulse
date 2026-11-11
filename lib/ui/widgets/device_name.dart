import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/device.dart';
import '../../core/device_book.dart';
import '../theme.dart';

/// The name people see: their own tag when set, otherwise the advertised name, otherwise the MAC.
String deviceLabel(DeviceBook book, EyeDevice d) => book.tagOf(d.mac) ?? d.name ?? d.mac;

/// A device's tag in bold with its advertised name after it, or just the advertised name.
class DeviceName extends StatelessWidget {
  const DeviceName(this.device, {super.key, this.size = 13, this.bold = false});

  final EyeDevice device;
  final double size;

  /// The advertised name in semi-bold too (a phone's device card), not only the person's own.
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tag = AppScope.of(context).book.tagOf(device.mac);
    final name = device.name ?? device.mac;
    if (tag == null) {
      return Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.w600 : null, color: bold ? t.text : null));
    }
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: tag, style: TextStyle(fontWeight: FontWeight.w600, color: t.text)),
        TextSpan(text: '  $name', style: TextStyle(color: t.muted, fontSize: size - 1)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: size),
    );
  }
}

/// Lets the person give a device their own name, kept on this computer.
Future<void> showRenameDialog(BuildContext context, EyeDevice device) async {
  final book = AppScope.read(context).book;
  await showDialog<void>(context: context, builder: (_) => _RenameDialog(book: book, device: device));
}

/// Owns its text controller, so it is released only once the dialog has finished closing.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.book, required this.device});

  final DeviceBook book;
  final EyeDevice device;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final String? _current = widget.book.tagOf(widget.device.mac);
  late final _ctl = TextEditingController(text: _current ?? '');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _save() {
    widget.book.setTag(widget.device.mac, _ctl.text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = widget.device;
    return AlertDialog(
      backgroundColor: t.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: t.frame)),
      title: Text('Name this device', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: t.text)),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${d.name ?? 'Unnamed'} · ${d.mac}', style: monoStyle(context, size: 12.5, color: t.dim)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctl,
            autofocus: true,
            maxLength: DeviceBook.maxTagLength,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(hintText: 'Cold room 2'),
            onSubmitted: (_) => _save(),
          ),
        ]),
      ),
      actions: [
        if (_current != null)
          TextButton(
            onPressed: () {
              widget.book.setTag(d.mac, null);
              Navigator.of(context).pop();
            },
            child: const Text('Remove name'),
          ),
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
