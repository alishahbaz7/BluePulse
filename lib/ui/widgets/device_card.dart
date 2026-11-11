import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/settings.dart';
import '../../core/device.dart';
import '../format.dart';
import '../theme.dart';
import 'common.dart';
import 'data_grid.dart' show rowStripe;
import 'device_name.dart';
import 'sensor_icons.dart';
import 'device_pills.dart';

/// Below this width the app is laid out for a phone (the shell's drawer, cards in place of tables).
const phoneWidth = 640.0;

/// A phone in either orientation — its shorter side is under 600 dp, as Android tells phones from
/// tablets — or any window narrower than [phoneWidth]. A phone turned sideways is ~985 dp wide and
/// used to get the desktop rail and tables; it keeps the phone layout, with cards two to a row.
bool isPhone(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width < phoneWidth || size.shortestSide < 600;
}

/// Cards side by side on a phone turned sideways.
int cardColumns(BuildContext context) => MediaQuery.sizeOf(context).width >= 700 ? 2 : 1;

/// One group of cards in [CardRows.sections], under its own heading when it has a [title].
class CardSection {
  const CardSection({this.title, this.icon, required this.count, required this.card});

  final String? title;
  final IconData? icon;
  final int count;

  /// The card for [index] within the section; [stripe] is true on every other row.
  final Widget Function(int index, bool stripe) card;
}

/// Items as cards, [cardColumns] to a row, rows of equal height — in one run, or in sections each
/// under a heading (the pinned devices, then the rest).
class CardRows extends StatelessWidget {
  CardRows({super.key, required int count, required Widget Function(int index, bool stripe) card, this.shrinkWrap = false})
      : sections = [CardSection(count: count, card: card)];

  const CardRows.sections({super.key, required this.sections, this.shrinkWrap = false});

  final List<CardSection> sections;

  /// Inside another scroll view (the Overview), not filling the space it is given.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final columns = cardColumns(context);
    final t = context.tokens;
    final line = t.line;

    Widget row(CardSection s, int r) {
      if (columns == 1) return s.card(r, r.isOdd);
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var c = 0; c < columns; c++) ...[
            if (c > 0) VerticalDivider(width: 1, thickness: 1, color: line),
            Expanded(child: r * columns + c < s.count ? s.card(r * columns + c, r.isOdd) : const SizedBox()),
          ],
        ]),
      );
    }

    Widget heading(CardSection s) => Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 7),
          decoration: BoxDecoration(
            color: t.panel2,
            border: Border(bottom: BorderSide(color: t.frame, width: 2)),
          ),
          child: Row(children: [
            if (s.icon != null) ...[Icon(s.icon, size: 16, color: t.accent), const SizedBox(width: 8)],
            Text(s.title!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(width: 8),
            Text('${s.count}', style: TextStyle(fontSize: 13, color: t.dim, fontFeatures: tabular)),
          ]),
        );

    // Headings and rows in one list; a divider between rows of the same section.
    final items = <Widget>[];
    for (final s in sections.where((s) => s.count > 0)) {
      if (s.title != null) items.add(heading(s));
      final rows = (s.count + columns - 1) ~/ columns;
      for (var r = 0; r < rows; r++) {
        items.add(r == 0
            ? row(s, r)
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Divider(height: 1, thickness: 1, color: line),
                row(s, r),
              ]));
      }
    }

    if (shrinkWrap) return Column(children: items);
    return ListView.builder(itemCount: items.length, itemBuilder: (_, i) => items[i]);
  }
}

/// A device as a phone shows it, in place of a table row: name and model, then the MAC and when it
/// was last heard, then what it reports — every figure readable without scrolling sideways.
class DeviceCard extends StatelessWidget {
  const DeviceCard({super.key, required this.device, required this.now, this.onTap, this.focus = false, this.stripe = false});

  /// Every other row tinted, as in the tables.
  final bool stripe;

  final EyeDevice device;
  final DateTime now;
  final VoidCallback? onTap;

  /// Shows the focus box (the Devices page).
  final bool focus;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final t = context.tokens;
    final d = device;
    final book = c.book;
    final r = c.registry;
    final notSeen = d.isNotSeen(now, c.settings.notSeenMinSeconds);
    final pinned = book.pinned(d.mac);
    final tel = d.teltonika;
    final distance = r.distanceOf(d);
    final small = TextStyle(fontSize: 13, color: notSeen ? t.muted : t.dim, fontFeatures: tabular);

    final chips = <Widget>[
      ValueChip(
        icon: SignalBars(d.rssi),
        value: d.rssi?.toString() ?? '—',
        unit: ' dBm',
        tip: 'Signal of the last packet',
      ),
      if (distance != null)
        ValueChip(
          icon: Icon(Icons.straighten, size: 16, color: t.dim),
          value: formatDistance(distance).replaceAll(' m', ''),
          unit: ' m',
          tip: 'Estimated distance, from the signal and the power the device advertises',
        ),
      if (tel?.temperatureC != null)
        ValueChip(
          icon: Icon(Icons.thermostat, size: 16, color: t.warn),
          value: tel!.temperatureC!.toStringAsFixed(1),
          unit: '°C',
          tip: 'Temperature',
        ),
      if (tel?.humidity != null)
        ValueChip(
          icon: Icon(Icons.water_drop, size: 16, color: t.accent),
          value: '${tel!.humidity}',
          unit: '%',
          tip: 'Humidity',
        ),
      if (tel?.moving != null)
        ValueChip(
          icon: Icon(tel!.moving! ? Icons.directions_run : Icons.accessibility_new,
              size: 16, color: tel.moving! ? t.accent : t.dim),
          value: '${tel.movementCount ?? '—'}',
          tip: '${tel.moving! ? 'Moving' : 'Still'} · movements counted',
        ),
      if (tel != null && tel.magnetPresent)
        ValueChip(
          icon: MagnetIcon(detected: tel.magnetDetected ?? false),
          value: tel.magnetDetected == true ? 'On' : 'Off',
          tip: tel.magnetDetected == true ? 'Magnet detected' : 'No magnet',
          color: tel.magnetDetected == true ? null : t.dim,
        ),
      if (d.batteryMv != null || d.lowBattery)
        ValueChip(
          icon: Icon(batteryIcon(d.batteryMv, low: d.lowBattery), size: 16, color: d.lowBattery ? t.warn : t.ok),
          value: d.batteryMv == null ? 'Low' : (d.batteryMv! / 1000).toStringAsFixed(2),
          unit: d.batteryMv == null ? null : ' V',
          tip: d.lowBattery ? 'Battery low (the device says so)' : 'Battery',
          color: d.lowBattery ? t.warn : null,
        ),
    ];

    return Material(
      color: pinned && focus ? Color.alphaBlend(t.accentSoft, t.panel) : (stripe ? rowStripe(t) : t.panel),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(focus ? 4 : 14, 12, 10, 12),
          // Out of range: greyed, in the same place, the last values still readable.
          child: Opacity(
            opacity: notSeen ? greyedOut : 1,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (focus) PinButton(mac: d.mac),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: DeviceName(d, size: 15, bold: true)),
                  const SizedBox(width: 8),
                  ModelPill(d.model),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(
                    child: Text(d.mac,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: monoStyle(context, size: 12.5, color: t.dim)),
                  ),
                  HoldTip(
                    message: notSeen ? 'Not heard for a while: the values are the last ones received' : 'Last heard',
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      FreshDot(live: !notSeen),
                      const SizedBox(width: 6),
                      Text(notSeen ? 'Lost · ${formatAgo(d.lastSeen, now)}' : formatAgo(d.lastSeen, now), style: small),
                    ]),
                  ),
                ]),
                const SizedBox(height: 9),
                Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: chips),
              ]),
            ),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Icon(Icons.chevron_right, size: 20, color: t.muted),
              ),
          ]),
          ),
        ),
      ),
    );
  }
}

/// How faded a device no longer heard is drawn, as a tile or a table row.
const greyedOut = 0.42;

extension DeviceSortLabel on DeviceSort {
  String get label => switch (this) {
        DeviceSort.found => 'As found',
        DeviceSort.name => 'Name',
        DeviceSort.signal => 'Strongest',
        DeviceSort.battery => 'Lowest battery',
        DeviceSort.lastSeen => 'Last heard',
      };
}

/// Orders [devices] in place.
void sortDevices(List<EyeDevice> devices, DeviceSort sort, String Function(EyeDevice) label) {
  int byName(EyeDevice a, EyeDevice b) => label(a).toLowerCase().compareTo(label(b).toLowerCase());
  int byFound(EyeDevice a, EyeDevice b) {
    final c = a.firstSeen.compareTo(b.firstSeen);
    return c != 0 ? c : a.mac.compareTo(b.mac);
  }

  devices.sort((a, b) => switch (sort) {
        // First heard first: a new device joins at the bottom and nothing moves.
        DeviceSort.found => byFound(a, b),
        DeviceSort.name => byName(a, b),
        DeviceSort.signal => (b.rssi ?? -999).compareTo(a.rssi ?? -999),
        DeviceSort.battery => (a.batteryMv ?? 99999).compareTo(b.batteryMv ?? 99999),
        DeviceSort.lastSeen => b.lastSeen.compareTo(a.lastSeen),
      });
}

/// The sort choice, for a card's header.
class DeviceSortMenu extends StatelessWidget {
  const DeviceSortMenu({super.key, required this.value, required this.onChanged});

  final DeviceSort value;
  final ValueChanged<DeviceSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PopupMenuButton<DeviceSort>(
      tooltip: 'Sort',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [for (final s in DeviceSort.values) PopupMenuItem(value: s, child: Text(s.label))],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.sort, size: 18, color: t.dim),
          const SizedBox(width: 6),
          Text(value.label, style: TextStyle(fontSize: 13.5, color: t.text)),
          Icon(Icons.arrow_drop_down, size: 20, color: t.dim),
        ]),
      ),
    );
  }
}

/// Pins a device to the top of the list; a pinned device also gets every packet and the fastest
/// refresh, and is what Log records.
class PinButton extends StatelessWidget {
  const PinButton({super.key, required this.mac});
  final String mac;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final book = AppScope.of(context).book;
    final pinned = book.pinned(mac);
    return IconButton(
      onPressed: () => book.toggleFocus(mac),
      tooltip: pinned ? 'Unpin' : 'Pin to the top',
      visualDensity: VisualDensity.compact,
      icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 20, color: pinned ? t.accent : t.muted),
    );
  }
}

