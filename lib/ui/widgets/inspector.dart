import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'common.dart';

/// Every byte of a packet, with the field it belongs to. Pointing at a byte or a field row
/// highlights both.
class PacketInspector extends StatefulWidget {
  const PacketInspector({super.key, required this.packet, this.title});

  final AnnotatedPacket packet;
  final String? title;

  @override
  State<PacketInspector> createState() => _PacketInspectorState();
}

class _PacketInspectorState extends State<PacketInspector> {
  int? _field;

  @override
  void didUpdateWidget(covariant PacketInspector old) {
    super.didUpdateWidget(old);
    if (_field != null && _field! >= widget.packet.fields.length) _field = null;
  }

  int? _fieldIndexAt(int byte) {
    final f = widget.packet.fields;
    for (var i = 0; i < f.length; i++) {
      if (byte >= f[i].offset && byte < f[i].end) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = widget.packet;
    final hex = toHex(p.bytes, separator: ' ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        if (widget.title != null) Text(widget.title!.toUpperCase(), style: labelStyle(context)),
        const SizedBox(width: 8),
        Text('${p.bytes.length} bytes', style: TextStyle(fontSize: 12, color: t.muted)),
        const Spacer(),
        TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: hex)),
          icon: const Icon(Icons.copy_outlined, size: 16),
          label: const Text('Copy hex'),
        ),
      ]),
      const SizedBox(height: 6),
      if (p.error != null) ...[Notice(p.error!, tone: Tone.bad), const SizedBox(height: 8)],
      Wrap(spacing: 3, runSpacing: 3, children: [
        for (var i = 0; i < p.bytes.length; i++) _byte(context, i),
      ]),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(border: Border.all(color: t.line), borderRadius: BorderRadius.circular(6)),
        child: Column(children: [
          for (var i = 0; i < p.fields.length; i++) _fieldRow(context, i),
        ]),
      ),
    ]);
  }

  Color _tint(BuildContext context, int fieldIndex) {
    final t = context.tokens;
    final f = widget.packet.fields[fieldIndex];
    if (f.label == 'Length' || f.label == 'AD type') return t.muted.withValues(alpha: 0.18);
    if (f.label == 'Unparsed') return t.bad.withValues(alpha: 0.18);
    return fieldIndex.isEven ? t.accent.withValues(alpha: 0.13) : t.ok.withValues(alpha: 0.13);
  }

  Widget _byte(BuildContext context, int i) {
    final t = context.tokens;
    final fi = _fieldIndexAt(i);
    final on = fi != null && fi == _field;
    return MouseRegion(
      onEnter: (_) => setState(() => _field = fi),
      child: GestureDetector(
        onTap: () => setState(() => _field = fi),
        child: Container(
          width: 26,
          padding: const EdgeInsets.symmetric(vertical: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? t.accent : (fi == null ? null : _tint(context, fi)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            toHex([widget.packet.bytes[i]]),
            style: monoStyle(context, size: 12.5, color: on ? t.bg : t.text),
          ),
        ),
      ),
    );
  }

  Widget _fieldRow(BuildContext context, int i) {
    final t = context.tokens;
    final f = widget.packet.fields[i];
    final on = i == _field;
    return MouseRegion(
      onEnter: (_) => setState(() => _field = i),
      child: Container(
        color: on ? t.accentSoft : (i.isOdd ? t.text.withValues(alpha: 0.025) : null),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 64,
            child: Text(
              f.length == 1 ? '${f.offset}' : '${f.offset}–${f.end - 1}',
              style: monoStyle(context, size: 12, color: t.dim),
            ),
          ),
          Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 3, right: 8), color: _tint(context, i)),
          SizedBox(width: 150, child: Text(f.label, style: TextStyle(fontSize: 13, color: t.text))),
          Expanded(child: SelectableText(f.value, style: monoStyle(context, size: 12.5, color: t.dim))),
        ]),
      ),
    );
  }
}
