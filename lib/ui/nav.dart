import 'package:flutter/material.dart';

/// Every page the app has.
enum PageId { overview, devices, deviceDetail, packets, proximity, decode, sessions, configure, settings }

/// One navigation definition feeds the sidebar, the top bar title and tip, and the tests.
class NavItem {
  const NavItem({
    required this.id,
    required this.module,
    required this.title,
    required this.tip,
    required this.icon,
    this.soon = false,
    this.inRail = true,
    this.live = false,
    this.railParent,
  });

  final PageId id;
  final String module;
  final String title;

  /// The page description, shown as a hold-tip on the title — never printed.
  final String tip;
  final IconData icon;

  /// Listed to show the shape of the app; not built yet.
  final bool soon;
  final bool inRail;

  /// Needs the scanner: shows the Bluetooth / scan chips and the *BT* pill.
  final bool live;

  /// Highlighted in the rail when this page (not in the rail itself) is open.
  final PageId? railParent;
}

const navItems = <NavItem>[
  NavItem(
    id: PageId.overview,
    module: 'Live',
    title: 'Overview',
    tip: 'Devices in range right now, what needs attention, and readings per minute',
    icon: Icons.space_dashboard_outlined,
    live: true,
  ),
  NavItem(
    id: PageId.devices,
    module: 'Live',
    title: 'Devices',
    tip: 'Every EYE device heard this session, with its latest values',
    icon: Icons.sensors_outlined,
    live: true,
  ),
  NavItem(
    id: PageId.deviceDetail,
    module: 'Live',
    title: 'Device',
    tip: "One device's signal, battery and sensor values over this session",
    icon: Icons.sensors_outlined,
    live: true,
    inRail: false,
    railParent: PageId.devices,
  ),
  NavItem(
    id: PageId.packets,
    module: 'Live',
    title: 'Packets',
    tip: 'Each packet as it arrives, with every byte named',
    icon: Icons.receipt_long_outlined,
    live: true,
  ),
  NavItem(
    id: PageId.proximity,
    module: 'Live',
    title: 'Proximity',
    tip: 'How a Teltonika tracker would sort these beacons into Near, Away and Lost',
    icon: Icons.radar_outlined,
    live: true,
  ),
  NavItem(
    id: PageId.decode,
    module: 'Tracker',
    title: 'Decode',
    tip: 'A tracker packet, AVL value or BLE packet decoded from its hex',
    icon: Icons.data_object_outlined,
  ),
  NavItem(
    id: PageId.sessions,
    module: 'Data',
    title: 'Sessions',
    tip: 'Recorded scan sessions, exported as CSV and replayed',
    icon: Icons.history_outlined,
    soon: true,
  ),
  NavItem(
    id: PageId.configure,
    module: 'Device',
    title: 'Configure',
    tip: "A device's settings changed over Bluetooth — PIN, name, TX power, interval, IDs",
    icon: Icons.tune_outlined,
    soon: true,
  ),
  NavItem(
    id: PageId.settings,
    module: 'App',
    title: 'Settings',
    tip: 'Theme, scanning source, signal smoothing and the distance model',
    icon: Icons.settings_outlined,
  ),
];

NavItem navItem(PageId id) => navItems.firstWhere((n) => n.id == id);

/// Modules in rail order, each with its rail items.
List<(String, List<NavItem>)> get navModules {
  final out = <(String, List<NavItem>)>[];
  for (final item in navItems.where((n) => n.inRail)) {
    if (out.isEmpty || out.last.$1 != item.module) {
      out.add((item.module, [item]));
    } else {
      out.last.$2.add(item);
    }
  }
  return out;
}

/// Every pill string the rail can show, and what it means. Keep in step with the rail.
const pillLegend = <String, String>{
  'Soon': 'Not built yet',
  'BT': 'Needs Bluetooth on and permitted',
};
