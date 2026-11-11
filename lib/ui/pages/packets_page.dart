import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/registry.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/device_card.dart' show isPhone;
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
    final phone = isPhone(context);
    String nameOf(PacketEntry p) {
      final d = c.registry.device(p.mac);
      return d == null ? (p.data.name ?? '—') : deviceLabel(c.book, d);
    }

    final grid = PanelCard(
      title: 'Packets',
      count: rows.length == source.length ? '${source.length}' : '${rows.length} of ${source.length}',
      tip: 'The last 500 packets, newest first',
      padding: EdgeInsets.zero,
      expand: true,
      child: phone
          ? ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => Divider(height: 1, thickness: 1, color: context.tokens.line),
              itemBuilder: (_, i) => _PacketTile(
                packet: rows[i],
                name: nameOf(rows[i]),
                stripe: i.isOdd,
                selected: rows[i].seq == _selected,
                onTap: () => setState(() => _selected = rows[i].seq),
              ),
            )
          : DataGrid<PacketEntry>(
        rows: rows,
        selected: (p) => p.seq == _selected,
        onTap: (p) => setState(() => _selected = p.seq),
        columns: [
          GridColumn(label: 'Time', width: 112, cell: (ctx, p) => Text(formatClockMs(p.time), style: monoStyle(ctx, size: 12))),
          GridColumn(label: 'MAC', width: 150, cell: (ctx, p) => Text(p.mac, style: monoStyle(ctx, size: 12))),
          GridColumn(label: 'Name', width: 150, cell: (_, p) => Text(nameOf(p))),
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
      padding: EdgeInsets.all(phone ? 12 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SearchButton(query: _query, hint: 'MAC or name', onChanged: (q) => setState(() => _query = q)),
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

/// One packet as a phone lists it: who sent it and how strong, when and from which address, and what
/// it carried — in place of a table too wide for the screen.
class _PacketTile extends StatelessWidget {
  const _PacketTile({required this.packet, required this.name, required this.selected, required this.onTap, this.stripe = false});

  final PacketEntry packet;
  final bool stripe;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = packet;
    return Material(
      color: selected ? Color.alphaBlend(t.accentSoft, t.panel) : (stripe ? rowStripe(t) : t.panel),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: t.text)),
              ),
              Text(p.rssi == null ? '—' : '${p.rssi} dBm',
                  style: TextStyle(fontSize: 13.5, color: t.text, fontFeatures: tabular)),
            ]),
            const SizedBox(height: 3),
            Text('${formatClockMs(p.time)}  ·  ${p.mac}', style: monoStyle(context, size: 12, color: t.dim)),
            const SizedBox(height: 4),
            // Android does not say whether a packet was the advertisement or the scan response.
            Text(p.scanResponse == null ? p.summary : '${p.kind} · ${p.summary}',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: t.dim)),
          ]),
        ),
      ),
    );
  }
}
