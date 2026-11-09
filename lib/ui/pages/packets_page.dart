import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/registry.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/device_name.dart';
import '../widgets/inspector.dart';
import 'live_state.dart';

class PacketsPage extends StatefulWidget {
  const PacketsPage({super.key});

  @override
  State<PacketsPage> createState() => _PacketsPageState();
}

class _PacketsPageState extends State<PacketsPage> {
  List<PacketEntry>? _frozen;
  int? _selected;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final live = c.registry.packets.toList().reversed.toList();
    final empty = liveEmptyState(context, hasRows: live.isNotEmpty);
    if (empty != null) return empty;

    final source = _frozen ?? live;
    final q = _query.trim().toLowerCase();
    final rows = q.isEmpty
        ? source
        : source
            .where((p) => p.mac.toLowerCase().contains(q) || (p.data.name ?? '').toLowerCase().contains(q))
            .toList();
    final selected = _selected == null ? null : source.where((p) => p.seq == _selected).firstOrNull;

    final grid = PanelCard(
      title: 'Packets',
      count: rows.length == source.length ? '${source.length}' : '${rows.length} of ${source.length}',
      tip: 'The last 500 packets, newest first',
      padding: EdgeInsets.zero,
      expand: true,
      child: DataGrid<PacketEntry>(
        rows: rows,
        selected: (p) => p.seq == _selected,
        onTap: (p) => setState(() => _selected = p.seq),
        columns: [
          GridColumn(label: 'Time', width: 112, cell: (ctx, p) => Text(formatClockMs(p.time), style: monoStyle(ctx, size: 12))),
          GridColumn(label: 'MAC', width: 150, cell: (ctx, p) => Text(p.mac, style: monoStyle(ctx, size: 12))),
          GridColumn(
            label: 'Name',
            width: 150,
            cell: (_, p) {
              final d = c.registry.device(p.mac);
              return Text(d == null ? (p.data.name ?? '—') : deviceLabel(c.book, d));
            },
          ),
          GridColumn(label: 'Kind', width: 120, cell: (_, p) => Text(p.kind)),
          GridColumn(label: 'RSSI', width: 64, numeric: true, cell: (_, p) => Text(p.rssi?.toString() ?? '—')),
          GridColumn(label: 'Carries', width: 260, fill: true, cell: (_, p) => Text(p.summary)),
        ],
      ),
    );

    final inspector = PanelCard(
      title: 'Bytes',
      tip: 'Every byte named — as received when the scanner provides raw bytes, otherwise rebuilt from the parsed fields',
      expand: true,
      child: selected == null
          ? const EmptyState(text: 'No packet selected.')
          : SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${selected.mac} · ${formatClockMs(selected.time)} · ${selected.rssi ?? '—'} dBm',
                    style: monoStyle(context, size: 12.5, color: context.tokens.dim)),
                const SizedBox(height: 10),
                PacketInspector(packet: selected.annotated),
              ]),
            ),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 260,
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'MAC or name'),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => setState(() => _frozen = _frozen == null ? live : null),
            icon: Icon(_frozen == null ? Icons.pause : Icons.play_arrow, size: 18),
            label: Text(_frozen == null ? 'Pause' : 'Resume'),
          ),
          if (_frozen != null) const Pill('Paused', tone: Tone.warn),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            if (box.maxWidth < 1000) {
              return Column(children: [
                Expanded(flex: 3, child: grid),
                if (selected != null) ...[const SizedBox(height: 12), Expanded(flex: 4, child: inspector)],
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 5, child: grid),
              const SizedBox(width: 14),
              Expanded(flex: 4, child: inspector),
            ]);
          }),
        ),
      ]),
    );
  }
}
