import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// One column of a [DataGrid].
class GridColumn<T> {
  const GridColumn({
    required this.label,
    required this.cell,
    this.width = 110,
    this.fill = false,
    this.numeric = false,
    this.sortValue,
    this.tip = '',
  });

  final String label;
  final Widget Function(BuildContext context, T row) cell;

  /// Compact columns keep this width; the [fill] column takes what is left.
  final double width;
  final bool fill;

  /// Right-aligned, tabular figures.
  final bool numeric;

  /// Present → the header sorts by it. Nulls sit last in either direction.
  final Object? Function(T row)? sortValue;
  final String tip;
}

/// The house data grid: a header band that stays put, rows a shade apart, compact columns that fit
/// their content and one column taking the rest, sortable headers.
class DataGrid<T> extends StatefulWidget {
  const DataGrid({
    super.key,
    required this.rows,
    required this.columns,
    this.onTap,
    this.selected,
    this.initialSort,
    this.initialAscending = true,
    this.rowHeight = 34,
    this.shrinkWrap = false,
    this.dimmed,
    this.pinned,
  });

  final List<T> rows;
  final List<GridColumn<T>> columns;
  final void Function(T row)? onTap;
  final bool Function(T row)? selected;

  /// Rows drawn faded (devices out of focus).
  final bool Function(T row)? dimmed;

  /// Rows that stay at the top whatever the sort, in the sort's order among themselves.
  final bool Function(T row)? pinned;
  final int? initialSort;
  final bool initialAscending;
  final double rowHeight;

  /// Size to the rows (inside a scrolling page) instead of filling and scrolling.
  final bool shrinkWrap;

  @override
  State<DataGrid<T>> createState() => _DataGridState<T>();
}

class _DataGridState<T> extends State<DataGrid<T>> {
  late int? _sort = widget.initialSort;
  late bool _asc = widget.initialAscending;
  final _h = ScrollController();
  final _v = ScrollController();

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    super.dispose();
  }

  int _compare(Object? a, Object? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final x = a is bool ? (a ? 1 : 0) : a;
    final y = b is bool ? (b ? 1 : 0) : b;
    final c = (x is Comparable && y is Comparable) ? Comparable.compare(x, y) : x.toString().compareTo(y.toString());
    return _asc ? c : -c;
  }

  List<T> _sorted() {
    final rows = _sortedByColumn();
    final p = widget.pinned;
    if (p == null) return rows;
    return [...rows.where(p), ...rows.where((r) => !p(r))];
  }

  List<T> _sortedByColumn() {
    final s = _sort;
    if (s == null || widget.columns[s].sortValue == null) return widget.rows;
    final key = widget.columns[s].sortValue!;
    final rows = [...widget.rows];
    // Nulls last regardless of direction.
    rows.sort((a, b) {
      final ka = key(a), kb = key(b);
      if (ka == null && kb != null) return 1;
      if (kb == null && ka != null) return -1;
      return _compare(ka, kb);
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (context, c) {
      final fixed = widget.columns.fold<double>(0, (s, col) => s + col.width);
      final extra = max(0.0, c.maxWidth - fixed);
      final fillIndex = max(0, widget.columns.indexWhere((col) => col.fill));
      final widths = [
        for (var i = 0; i < widget.columns.length; i++) widget.columns[i].width + (i == fillIndex ? extra : 0),
      ];
      final total = widths.fold<double>(0, (s, w) => s + w);
      final rows = _sorted();

      final header = Container(
        height: 36,
        decoration: BoxDecoration(
          color: t.panel2,
          border: Border(bottom: BorderSide(color: t.frame, width: 2)),
        ),
        child: Row(children: [
          for (var i = 0; i < widget.columns.length; i++) _headerCell(context, i, widths[i]),
        ]),
      );

      final pinnedCount = widget.pinned == null ? 0 : rows.where(widget.pinned!).length;

      Widget rowAt(int i) {
        final row = rows[i];
        final selected = widget.selected?.call(row) ?? false;
        final stripe = i.isOdd ? rowStripe(t) : t.panel;
        // The last pinned row closes the pinned section with a line, when more rows follow.
        final lastPinned = pinnedCount > 0 && i == pinnedCount - 1 && rows.length > pinnedCount;
        final cell = Material(
          color: selected ? Color.alphaBlend(t.accentSoft, t.panel) : stripe,
          child: InkWell(
            onTap: widget.onTap == null ? null : () => widget.onTap!(row),
            hoverColor: t.text.withValues(alpha: 0.04),
            child: SizedBox(
              height: widget.rowHeight,
              child: Opacity(
                opacity: (widget.dimmed?.call(row) ?? false) ? 0.42 : 1,
                child: Row(children: [
                for (var j = 0; j < widget.columns.length; j++)
                  SizedBox(
                    width: widths[j],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Align(
                        alignment: widget.columns[j].numeric ? Alignment.centerRight : Alignment.centerLeft,
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            fontSize: 13,
                            color: t.text,
                            fontFeatures: widget.columns[j].numeric ? tabular : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          child: widget.columns[j].cell(context, row),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
        if (!lastPinned) return cell;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.accent, width: 2))),
          child: cell,
        );
      }

      final body = widget.shrinkWrap
          ? Column(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < rows.length; i++) rowAt(i)])
          : Scrollbar(
              controller: _v,
              child: ListView.builder(
                controller: _v,
                itemCount: rows.length,
                itemExtent: widget.rowHeight,
                itemBuilder: (_, i) => rowAt(i),
              ),
            );

      final grid = SizedBox(
        width: total,
        child: Column(
          mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header, if (widget.shrinkWrap) body else Expanded(child: body)],
        ),
      );

      return Scrollbar(
        controller: _h,
        notificationPredicate: (n) => n.depth == 0 && n.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(controller: _h, scrollDirection: Axis.horizontal, child: grid),
      );
    });
  }

  Widget _headerCell(BuildContext context, int i, double width) {
    final t = context.tokens;
    final col = widget.columns[i];
    final sortable = col.sortValue != null;
    final active = _sort == i;
    final label = Row(
      mainAxisAlignment: col.numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            col.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.text),
          ),
        ),
        if (active) Icon(_asc ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 18, color: t.accent),
      ],
    );
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: sortable
            ? () => setState(() {
                  if (_sort == i) {
                    _asc = !_asc;
                  } else {
                    _sort = i;
                    _asc = !col.numeric;
                  }
                })
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Align(
            alignment: col.numeric ? Alignment.centerRight : Alignment.centerLeft,
            child: HoldTip(message: col.tip, child: label),
          ),
        ),
      ),
    );
  }
}

/// The tint of every other row, in tables and lists: plain enough to read through, clear enough to
/// follow a row across.
Color rowStripe(AppTokens t) => Color.alphaBlend(t.text.withValues(alpha: 0.055), t.panel);
