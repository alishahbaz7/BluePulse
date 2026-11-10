import 'package:flutter/material.dart';

import '../../core/device_book.dart';
import '../theme.dart';

/// Lets the person order the device page's charts, show or hide each, and make each half or full
/// width. Saved at once, per device kind, on this computer or phone.
Future<void> showArrangeCharts(BuildContext context,
        {required DeviceBook book, required String kind, required Set<String> available}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ArrangeDialog(book: book, kind: kind, available: available),
    );

class _ArrangeDialog extends StatefulWidget {
  const _ArrangeDialog({required this.book, required this.kind, required this.available});

  final DeviceBook book;
  final String kind;
  final Set<String> available;

  @override
  State<_ArrangeDialog> createState() => _ArrangeDialogState();
}

class _ArrangeDialogState extends State<_ArrangeDialog> {
  late List<ChartSlot> _slots = widget.book.chartLayout(widget.kind);

  void _set(List<ChartSlot> slots) {
    setState(() => _slots = slots);
    widget.book.setChartLayout(widget.kind, slots);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      backgroundColor: t.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: t.frame)),
      title: Text('Arrange charts', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: t.text)),
      content: SizedBox(
        width: 480,
        height: (_slots.length * 64.0).clamp(120, 460),
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          itemCount: _slots.length,
          onReorderItem: (from, to) {
            final s = [..._slots];
            final item = s.removeAt(from);
            s.insert(to, item);
            _set(s);
          },
          itemBuilder: (context, i) {
            final slot = _slots[i];
            final hasData = widget.available.contains(slot.id);
            return Container(
              key: ValueKey(slot.id),
              height: 60,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: t.panel2,
                border: Border.all(color: t.line),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                ReorderableDragStartListener(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.drag_indicator, size: 20, color: t.dim),
                  ),
                ),
                Expanded(
                  child: Opacity(
                    opacity: slot.visible ? 1 : 0.5,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ChartSlot.title(slot.id), style: TextStyle(fontSize: 13.5, color: t.text)),
                      if (!hasData) Text('No data on this device', style: TextStyle(fontSize: 11.5, color: t.muted)),
                    ]),
                  ),
                ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Half')),
                    ButtonSegment(value: true, label: Text('Full')),
                  ],
                  selected: {slot.full},
                  onSelectionChanged: (v) => _set([
                    for (final s in _slots) s.id == slot.id ? s.copyWith(full: v.first) : s,
                  ]),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: slot.visible ? 'Shown' : 'Hidden',
                  child: Switch(
                    value: slot.visible,
                    onChanged: (v) => _set([
                      for (final s in _slots) s.id == slot.id ? s.copyWith(visible: v) : s,
                    ]),
                  ),
                ),
                const SizedBox(width: 6),
              ]),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.book.resetChartLayout(widget.kind);
            setState(() => _slots = widget.book.chartLayout(widget.kind));
          },
          child: const Text('Reset'),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}
