import 'dart:typed_data';

import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/inspector.dart';

enum _Kind { auto, packet, avlValue, ble, eyeBlock }

/// Examples from the BTSID1 wiki page (PDF, oldid 117310) and PLAN.md §9.
const _examples = <(String, String)>[
  (
    'Lost beacon record · wiki',
    '000000000000004b8e010000018368952793000f0e54fc209ab05800b300b40e00002a4f0001000000000000000000012a4f001e'
        '011c0001a40110eb47706aa38255aa96f21a154e2d00550d01000e020bd6010000823f',
  ),
  (
    'Visible list, 3 beacons · wiki',
    '00000000000000898e0100000183a1c8fbe3000f0e310b209ab02600e900760d00002a4c0001000000000000000000012a4c005c'
        '011c0001c00110eb577075868d55aa96021b20313800550d01000e020c1c1c0001b60110ef3f3f74868d55aa9aeae91e31380055'
        '0d01000e020bae200001a50114faffffff34b6f6aa38255aa9ef619154d0e200050d01000e020ad20100008811',
  ),
  ('AVL 385, 2 iBeacons · wiki', '11216B817F8A274D4FBDB62D33E1842F8DF8014D022BBF21A579723675064DC396A7C3520129F61900000000BF'),
  ('BTSID1 scan response', '0C094944315F41424344454647 06FF9A08018063'),
  ('EYE SENSOR block · provisional layout', '01BF08B42D800CF6005A64'),
];

class DecodePage extends StatefulWidget {
  const DecodePage({super.key, this.initialHex});

  final String? initialHex;

  @override
  State<DecodePage> createState() => _DecodePageState();
}

class _DecodePageState extends State<DecodePage> {
  late final _ctl = TextEditingController(text: widget.initialHex ?? '');
  _Kind _kind = _Kind.auto;
  int _avlId = BeaconAvlId.eyeVisibleOrNear;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _load(String hex) {
    final pretty = toHex(parseHex(hex), separator: ' ');
    setState(() {
      _ctl.text = pretty;
      _kind = _Kind.auto;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final input = PanelCard(
      title: 'Hex',
      tip: 'A whole tracker packet, its data field, one AVL value, a BLE advertising packet or a Teltonika block',
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Examples',
          onSelected: _load,
          itemBuilder: (_) => [for (final (label, hex) in _examples) PopupMenuItem(value: hex, child: Text(label))],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.library_books_outlined, size: 17, color: t.accent),
              const SizedBox(width: 6),
              Text('Examples', style: TextStyle(fontSize: 13, color: t.accent)),
              Icon(Icons.arrow_drop_down, size: 18, color: t.accent),
            ]),
          ),
        ),
        TextButton(onPressed: () => setState(_ctl.clear), child: const Text('Clear')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _ctl,
          minLines: 3,
          maxLines: 8,
          onChanged: (_) => setState(() {}),
          style: monoStyle(context, size: 13),
          decoration: const InputDecoration(hintText: '00 00 00 00 00 00 00 4B 8E 01 …'),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<_Kind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Kind.auto, label: Text('Auto')),
              ButtonSegment(value: _Kind.packet, label: Text('Tracker packet')),
              ButtonSegment(value: _Kind.avlValue, label: Text('AVL value')),
              ButtonSegment(value: _Kind.ble, label: Text('BLE packet')),
              ButtonSegment(value: _Kind.eyeBlock, label: Text('Teltonika block')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          if (_kind == _Kind.avlValue)
            DropdownButton<int>(
              value: _avlId,
              dropdownColor: t.panel,
              style: TextStyle(fontSize: 13, color: t.text),
              underline: const SizedBox.shrink(),
              items: [
                for (final id in BeaconAvlId.all)
                  DropdownMenuItem(value: id, child: Text('AVL $id · ${BeaconAvlId.name(id)}')),
              ],
              onChanged: (v) => setState(() => _avlId = v ?? _avlId),
            ),
        ]),
      ]),
    );

    return ListView(padding: const EdgeInsets.all(16), children: [
      input,
      const SizedBox(height: 14),
      ..._output(context),
    ]);
  }

  List<Widget> _output(BuildContext context) {
    final text = _ctl.text.trim();
    if (text.isEmpty) return const [];
    final Uint8List bytes;
    try {
      bytes = parseHex(text);
    } on FormatException catch (e) {
      return [Notice(e.message, tone: Tone.bad)];
    }
    if (bytes.isEmpty) return const [];

    var kind = _kind;
    var avlId = _avlId;
    if (kind == _Kind.auto) {
      final found = _detect(bytes);
      if (found == null) {
        return [const Notice('Not recognised as a tracker packet, AVL value, BLE packet or Teltonika block.', tone: Tone.warn)];
      }
      (kind, avlId) = found;
    }

    return switch (kind) {
      _Kind.packet => _packetView(context, decodeAvlPacket(bytes)),
      _Kind.avlValue => [_beaconListCard(context, avlId, decodeBeaconAvl(avlId, bytes)!, auto: _kind == _Kind.auto)],
      _Kind.ble => _bleView(context, bytes),
      _Kind.eyeBlock => _eyeBlockView(context, bytes),
      _Kind.auto => const [],
    };
  }

  /// Picks the most likely reading of the bytes.
  (_Kind, int)? _detect(Uint8List b) {
    if (looksLikeAvlPacket(b)) return (_Kind.packet, 0);
    if (b[0] == 0x01) {
      final list = decodeEyeBeaconList(b);
      if (list.error == null && list.beacons.isNotEmpty && list.beacons.every((x) => x.id != null || x.rssi != null)) {
        return (_Kind.avlValue, BeaconAvlId.eyeVisibleOrNear);
      }
    }
    final hi = b[0] >> 4, lo = b[0] & 0x0F;
    if (b.length > 2 && (b[1] == 0x21 || b[1] == 0x01) && hi >= 1 && hi <= lo) {
      final v = decodeAvl385(b);
      if (v.error == null && v.beacons.isNotEmpty) return (_Kind.avlValue, BeaconAvlId.beacon);
    }
    final ad = parseAdStructures(b);
    if (ad.error == null && ad.structures.isNotEmpty && ad.structures.every((s) => s.data.isNotEmpty)) {
      return (_Kind.ble, 0);
    }
    if (b.length >= 2 && decodeTeltonika(b).ok) return (_Kind.eyeBlock, 0);
    return null;
  }

  List<Widget> _packetView(BuildContext context, AvlPacket p) {
    final t = context.tokens;
    return [
      TileRow(minWidth: 170, tiles: [
        StatTile(label: 'Codec', value: p.codecName),
        StatTile(label: 'Records', value: '${p.recordCount ?? '—'}'),
        StatTile(label: 'Data length', value: p.dataLength == null ? '—' : '${p.dataLength}', secondary: p.dataLength == null ? null : 'bytes'),
        StatTile(
          label: 'CRC',
          value: p.crcField == null ? '—' : (p.crcOk ? 'OK' : 'Mismatch'),
          secondary: p.crcField == null ? null : hexLabel(p.crcField!, digits: 4),
          tone: p.crcField == null ? Tone.neutral : (p.crcOk ? Tone.ok : Tone.bad),
          tip: 'CRC-16/IBM over the data field',
        ),
      ]),
      for (final problem in p.problems) ...[const SizedBox(height: 10), Notice(problem, tone: Tone.bad)],
      for (var i = 0; i < p.records.length; i++) ...[
        const SizedBox(height: 14),
        _recordCard(context, i, p.records[i], t),
        for (final io in p.records[i].io)
          if (decodeBeaconAvl(io.id, io.value) case final v?) ...[
            const SizedBox(height: 14),
            _beaconListCard(context, io.id, v),
          ],
      ],
    ];
  }

  Widget _recordCard(BuildContext context, int i, AvlRecord r, AppTokens t) => PanelCard(
        title: 'Record ${i + 1}',
        count: formatDateTime(r.timestamp, utc: true),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 28, runSpacing: 12, children: [
            Fact('Latitude', r.latitude.toStringAsFixed(7)),
            Fact('Longitude', r.longitude.toStringAsFixed(7)),
            Fact('Altitude', '${r.altitude} m'),
            Fact('Angle', '${r.angle}°'),
            Fact('Satellites', '${r.satellites}'),
            Fact('Speed', '${r.speed} km/h'),
            Fact('Priority', '${r.priority}'),
            Fact('Event IO', r.eventIoId == 0 ? '—' : '${r.eventIoId}${_ioName(r.eventIoId)}'),
          ]),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(border: Border.all(color: t.line), borderRadius: BorderRadius.circular(6)),
            clipBehavior: Clip.antiAlias,
            child: DataGrid<IoElement>(
              rows: r.io,
              shrinkWrap: true,
              columns: [
                GridColumn(label: 'IO ID', width: 80, numeric: true, cell: (_, e) => Text('${e.id}')),
                GridColumn(label: 'Name', width: 220, cell: (_, e) => Text(BeaconAvlId.name(e.id) ?? '—')),
                GridColumn(label: 'Size', width: 70, numeric: true, cell: (_, e) => Text('${e.size}')),
                GridColumn(
                  label: 'Value',
                  width: 260,
                  fill: true,
                  cell: (ctx, e) => Text(toHex(e.value, separator: ' '), style: monoStyle(ctx, size: 12)),
                ),
                GridColumn(
                  label: 'Unsigned',
                  width: 140,
                  numeric: true,
                  cell: (_, e) => Text(e.variableLength ? '—' : e.unsigned.toString()),
                ),
              ],
            ),
          ),
        ]),
      );

  String _ioName(int id) {
    final n = BeaconAvlId.name(id);
    return n == null ? '' : ' · $n';
  }

  Widget _beaconListCard(BuildContext context, int avlId, BeaconListValue v, {bool auto = false}) {
    final t = context.tokens;
    final title = auto && avlId != BeaconAvlId.beacon
        ? 'AVL 10828 / 10829 / 10831 · EYE beacons'
        : 'AVL $avlId · ${BeaconAvlId.name(avlId)}';
    final rows = [for (var i = 0; i < v.beacons.length; i++) (i + 1, v.beacons[i])];
    return PanelCard(
      title: title,
      count: '${v.beacons.length} beacon${v.beacons.length == 1 ? '' : 's'}'
          '${v.part != null ? ' · part ${v.part} of ${v.totalParts}' : ''}',
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (v.error != null) Padding(padding: const EdgeInsets.all(12), child: Notice(v.error!, tone: Tone.bad)),
        if (v.tail.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text('Unread: ${toHex(v.tail, separator: ' ')}', style: monoStyle(context, size: 12, color: t.dim)),
          ),
        DataGrid<(int, TrackerBeacon)>(
          rows: rows,
          shrinkWrap: true,
          columns: [
            GridColumn(label: '#', width: 50, numeric: true, cell: (_, r) => Text('${r.$1}')),
            GridColumn(label: 'Kind', width: 110, cell: (_, r) => Text(r.$2.id?.kindLabel ?? '—')),
            GridColumn(
              label: 'ID',
              width: 340,
              fill: true,
              cell: (ctx, r) => Text(
                r.$2.id?.display ?? (r.$2.idBytes == null ? '—' : toHex(r.$2.idBytes!)),
                style: monoStyle(ctx, size: 12),
              ),
            ),
            GridColumn(label: 'RSSI', width: 80, numeric: true, cell: (_, r) => Text(r.$2.rssi == null ? '—' : '${r.$2.rssi} dBm')),
            GridColumn(
              label: 'Battery',
              width: 96,
              numeric: true,
              cell: (_, r) => Text(r.$2.batteryMv == null ? '—' : '${r.$2.batteryMv} mV'),
            ),
            GridColumn(
              label: 'Low battery',
              width: 104,
              cell: (_, r) => switch (r.$2.lowBattery) {
                true => const Pill('Low', tone: Tone.warn),
                false => const Text('No'),
                null => const Text('—'),
              },
            ),
            GridColumn(label: 'MAC', width: 150, cell: (ctx, r) => Text(r.$2.macText ?? '—', style: monoStyle(ctx, size: 12))),
          ],
        ),
      ]),
    );
  }

  List<Widget> _bleView(BuildContext context, Uint8List bytes) {
    final d = decodeAdvertisement(AdvertisementData.parse(bytes));
    final tel = d.teltonika;
    return [
      PanelCard(
        title: 'Advertisement',
        child: Wrap(spacing: 28, runSpacing: 12, children: [
          Fact('Name', d.name ?? '—'),
          Fact('Beacon', d.beaconId?.kindLabel ?? '—'),
          if (d.beaconId != null) Fact('ID', d.beaconId!.display, mono: true),
          if (d.txPower1m != null) Fact('TX power at 1 m', '${d.txPower1m} dBm'),
          if (tel != null) ..._teltonikaFacts(tel),
        ]),
      ),
      if (tel != null && !tel.ok) ...[const SizedBox(height: 10), Notice(tel.error!, tone: Tone.bad)],
      const SizedBox(height: 14),
      PanelCard(title: 'Bytes', child: PacketInspector(packet: annotateRaw(bytes))),
    ];
  }

  List<Widget> _eyeBlockView(BuildContext context, Uint8List bytes) {
    final tel = decodeTeltonika(bytes);
    return [
      PanelCard(
        title: 'Teltonika block',
        tip: 'Company 0x089A payload: version, flags, values in flag order',
        child: Wrap(spacing: 28, runSpacing: 12, children: _teltonikaFacts(tel)),
      ),
      if (!tel.ok) ...[const SizedBox(height: 10), Notice(tel.error!, tone: Tone.bad)],
      const SizedBox(height: 14),
      PanelCard(title: 'Bytes', child: PacketInspector(packet: AnnotatedPacket(bytes, tel.fields))),
    ];
  }

  List<Widget> _teltonikaFacts(TeltonikaData t) => [
        Fact('Flags', t.flags == null ? '—' : hexLabel(t.flags!)),
        if (t.temperatureC != null) Fact('Temperature', '${t.temperatureC!.toStringAsFixed(2)} °C'),
        if (t.humidity != null) Fact('Humidity', '${t.humidity} %'),
        if (t.magnetDetected != null) Fact('Magnet', t.magnetDetected! ? 'Detected' : 'None'),
        if (t.moving != null) Fact('Movement', '${t.moving! ? 'Moving' : 'Still'} · count ${t.movementCount}'),
        if (t.pitch != null) Fact('Pitch · Roll', '${t.pitch}° · ${t.roll}°'),
        Fact('Low battery', t.lowBattery ? 'Yes' : 'No'),
        Fact('Battery', t.batteryMv == null ? '—' : '${t.batteryMv} mV'),
      ];
}
