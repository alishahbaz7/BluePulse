import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/settings.dart';
import '../scanner/scanner.dart';
import '../update/update_service.dart';
import '../version.dart';
import 'nav.dart';
import 'pages/decode_page.dart';
import 'pages/device_detail_page.dart';
import 'pages/devices_page.dart';
import 'pages/overview_page.dart';
import 'pages/packets_page.dart';
import 'pages/proximity_page.dart';
import 'pages/sessions_page.dart';
import 'pages/settings_page.dart';
import 'theme.dart';
import 'update_ui.dart';
import 'usage_ui.dart';
import 'widgets/common.dart';

/// Lets pages move between pages (open a device, go back to the list).
class Navigation extends InheritedWidget {
  const Navigation({super.key, required this.go, required super.child});

  final void Function(PageId page, {String? mac}) go;

  static Navigation of(BuildContext context) => context.getInheritedWidgetOfExactType<Navigation>()!;

  @override
  bool updateShouldNotify(Navigation old) => false;
}

/// Sidebar workbench: rail on the left (folds to icons), top bar, page.
class Shell extends StatefulWidget {
  const Shell({super.key, this.initialPage, this.initialMac, this.initialHex});

  final PageId? initialPage;
  final String? initialMac;
  final String? initialHex;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late PageId _page = widget.initialPage != null && !navItem(widget.initialPage!).soon
      ? widget.initialPage!
      : PageId.overview;
  late String? _mac = widget.initialMac;
  final _scaffold = GlobalKey<ScaffoldState>();
  UpdateService? _updates;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = AppScope.read(context);
    if (!_started) {
      _started = true;
      c.usage.pageOpened(_page.name);
      // The first start asks who is using the app before anything else is offered.
      if (c.usage.needsName) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await showIdentityDialog(context, required: true);
          _onUpdates();
        });
      }
    }
    final u = c.updates;
    if (!identical(u, _updates)) {
      _updates?.removeListener(_onUpdates);
      _updates = u..addListener(_onUpdates);
      _onUpdates();
    }
  }

  @override
  void dispose() {
    _updates?.removeListener(_onUpdates);
    super.dispose();
  }

  /// A newer release found at start is offered once per run; after that the top-bar chip carries it.
  void _onUpdates() {
    final u = _updates;
    if (u == null || u.promptShown || u.stage != UpdateStage.available) return;
    if (mounted && AppScope.read(context).usage.needsName) return; // offered once the name is given
    u.promptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showUpdateDialog(context);
    });
  }

  void _go(PageId page, {String? mac}) {
    if (navItem(page).soon) return;
    if (page != _page) AppScope.read(context).usage.pageOpened(page.name);
    setState(() {
      _page = page;
      if (mac != null) _mac = mac;
    });
  }

  Widget _body() => switch (_page) {
        PageId.overview => const OverviewPage(),
        PageId.devices => const DevicesPage(),
        PageId.deviceDetail => DeviceDetailPage(mac: _mac ?? ''),
        PageId.packets => const PacketsPage(),
        PageId.proximity => const ProximityPage(),
        PageId.decode => DecodePage(initialHex: widget.initialHex),
        PageId.settings => const SettingsPage(),
        PageId.sessions => const SessionsPage(),
        PageId.configure => const SizedBox.shrink(),
      };

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    return Navigation(
      go: _go,
      child: LayoutBuilder(builder: (context, box) {
        final phone = box.maxWidth < 640;
        final forcedRail = box.maxWidth < 1000;
        final folded = !phone && (forcedRail || c.settings.railFolded);
        final item = navItem(_page);
        final page = KeyedSubtree(key: ValueKey(_page), child: _body());

        if (phone) {
          return Scaffold(
            key: _scaffold,
            drawer: Drawer(
              width: 260,
              child: _Sidebar(
                current: _page,
                folded: false,
                onSelect: (id) {
                  Navigator.of(context).pop();
                  _go(id);
                },
              ),
            ),
            body: SafeArea(
              child: Column(children: [
                _TopBar(item: item, phone: true, onMenu: () => _scaffold.currentState?.openDrawer()),
                Expanded(child: page),
              ]),
            ),
          );
        }

        return Scaffold(
          body: Row(children: [
            _Sidebar(current: _page, folded: folded, onSelect: _go),
            Expanded(
              child: Column(children: [
                _TopBar(
                  item: item,
                  phone: false,
                  onMenu: forcedRail
                      ? null
                      : () => c.settings.update((s) => s.railFolded = !s.railFolded),
                ),
                Expanded(child: page),
              ]),
            ),
          ]),
        );
      }),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, required this.folded, required this.onSelect});

  final PageId current;
  final bool folded;
  final void Function(PageId) onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = AppScope.of(context);
    final radioProblem = !c.isDemo && c.status.radio != RadioState.on;
    final railCurrent = navItem(current).railParent ?? current;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: folded ? 58 : 240,
      decoration: BoxDecoration(color: t.panel, border: Border(right: BorderSide(color: t.line))),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: folded ? 58 : 240,
          maxWidth: folded ? 58 : 240,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Brand(folded: folded),
            Expanded(
              child: ListView(padding: const EdgeInsets.only(bottom: 8), children: [
                for (final (module, items) in navModules) ...[
                  if (!folded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Text(module.toUpperCase(), style: labelStyle(context).copyWith(color: t.muted)),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                      child: Divider(height: 1, color: t.line),
                    ),
                  for (final item in items)
                    _RailItem(
                      item: item,
                      folded: folded,
                      active: item.id == railCurrent,
                      pill: item.soon ? 'Soon' : (item.live && radioProblem ? 'BT' : null),
                      onTap: () => onSelect(item.id),
                    ),
                ],
              ]),
            ),
            if (!folded) const _Legend(),
          ]),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.folded});

  final bool folded;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final version = AppScope.of(context).version;
    final mark = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(7)),
      child: Icon(Icons.bluetooth_searching, size: 18, color: t.accent),
    );
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: folded ? 14 : 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Row(children: [
        Tooltip(message: 'BluePulse $version', child: mark),
        if (!folded) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: 'Blue', style: TextStyle(color: t.text)),
                TextSpan(text: 'Pulse', style: TextStyle(color: t.accent)),
              ]), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Row(children: [
                Flexible(
                  child: Text('Bluetooth workbench',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: t.dim)),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: '$protocolSource\n${kDebugMode ? 'Debug build' : 'Release build'}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(border: Border.all(color: t.frame), borderRadius: BorderRadius.circular(4)),
                    child: Text(version, style: monoStyle(context, size: 10.5, color: t.dim)),
                  ),
                ),
                if (kDebugMode) ...[
                  const SizedBox(width: 4),
                  const Pill('DEV', tone: Tone.warn, small: true),
                ],
              ]),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.item, required this.folded, required this.active, required this.pill, required this.onTap});

  final NavItem item;
  final bool folded;
  final bool active;
  final String? pill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = active ? t.accent : (item.soon ? t.muted : t.dim);
    final tile = Opacity(
      opacity: item.soon ? 0.5 : 1,
      child: Container(
        height: 38,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: active ? t.accentSoft : null,
          borderRadius: BorderRadius.circular(6),
          border: active ? Border(left: BorderSide(color: t.accent, width: 2)) : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: item.soon ? null : onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: folded ? 11 : 10),
            child: Row(children: [
              Icon(item.icon, size: 18, color: color),
              if (!folded) ...[
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: active ? t.text : t.dim,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (pill != null) Pill(pill!, tone: Tone.warn, small: true),
              ],
            ]),
          ),
        ),
      ),
    );
    final semantics = Semantics(selected: active, button: true, label: item.title, child: tile);
    return folded ? Tooltip(message: '${item.module} · ${item.title}', child: semantics) : semantics;
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final e in pillLegend.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Pill(e.key, tone: Tone.warn, small: true),
              const SizedBox(width: 8),
              Expanded(child: Text(e.value, style: TextStyle(fontSize: 11.5, color: t.dim))),
            ]),
          ),
      ]),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.item, required this.phone, required this.onMenu});

  final NavItem item;
  final bool phone;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = AppScope.of(context);
    final s = c.status;
    final count = c.registry.devices.length;

    final chips = <Widget>[
      if (item.live) ...[
        _radioChip(context, c),
        if (!phone)
          StatusChip(
            text: s.scanning ? 'Scanning · $count' : 'Stopped',
            tone: s.scanning ? Tone.ok : Tone.muted,
            glow: s.scanning,
            detail: s.scanning ? '$count devices this session' : null,
          ),
        if (c.book.focus.isNotEmpty)
          StatusChip(
            text: 'Focus · ${c.book.focus.length}',
            tone: Tone.accent,
            detail: 'Devices in focus refresh fastest',
            onTap: () => Navigation.of(context).go(PageId.devices),
          ),
      ],
    ];

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: t.bg, border: Border(bottom: BorderSide(color: t.line))),
      child: Row(children: [
        if (onMenu != null)
          IconButton(
            onPressed: onMenu,
            icon: Icon(Icons.menu, color: t.dim, size: 20),
            tooltip: phone ? 'Menu' : 'Fold the sidebar',
          )
        else
          const SizedBox(width: 8),
        const SizedBox(width: 4),
        Expanded(
          child: HoldTip(
            message: item.tip,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: t.text)),
              Text(item.module,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: t.dim)),
            ]),
          ),
        ),
        ...chips.expand((w) => [w, const SizedBox(width: 8)]),
        if (!phone || !item.live) ...[const UpdateChip(), const SizedBox(width: 4)],
        _ThemeButton(settings: c.settings),
        if (item.live) ...[
          const SizedBox(width: 6),
          if (phone)
            IconButton.filled(
              onPressed: c.toggleScan,
              tooltip: c.scanning ? 'Stop scan' : 'Start scan',
              icon: Icon(c.scanning ? Icons.stop : Icons.play_arrow, size: 20),
            )
          else
            FilledButton.icon(
              onPressed: c.toggleScan,
              icon: Icon(c.scanning ? Icons.stop : Icons.play_arrow, size: 18),
              label: Text(c.scanning ? 'Stop scan' : 'Start scan'),
            ),
        ],
        const SizedBox(width: 6),
      ]),
    );
  }

  Widget _radioChip(BuildContext context, AppController c) {
    if (c.isDemo) {
      return StatusChip(
        text: 'Demo data',
        tone: Tone.warn,
        detail: 'Simulated devices',
        onTap: () => Navigation.of(context).go(PageId.settings),
      );
    }
    return switch (c.status.radio) {
      RadioState.on => const StatusChip(text: 'Bluetooth on', tone: Tone.ok, glow: true),
      RadioState.off => StatusChip(text: 'Bluetooth off', tone: Tone.bad, onTap: c.scanner.enableRadio),
      RadioState.unauthorized => StatusChip(text: 'No permission', tone: Tone.warn, onTap: c.scanner.requestPermission),
      RadioState.unsupported => StatusChip(
          text: 'No adapter',
          tone: Tone.bad,
          detail: c.status.error,
          onTap: () => Navigation.of(context).go(PageId.settings),
        ),
      RadioState.unknown => const StatusChip(text: 'Bluetooth …', tone: Tone.muted),
    };
  }
}

class _ThemeButton extends StatelessWidget {
  const _ThemeButton({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (icon, label, next) = switch (settings.themeChoice) {
      ThemeChoice.auto => (Icons.brightness_auto_outlined, 'Auto', ThemeChoice.light),
      ThemeChoice.light => (Icons.light_mode_outlined, 'Light', ThemeChoice.dark),
      ThemeChoice.dark => (Icons.dark_mode_outlined, 'Dark', ThemeChoice.auto),
    };
    return IconButton(
      onPressed: () => settings.update((s) => s.themeChoice = next),
      tooltip: 'Theme: $label',
      icon: Icon(icon, size: 19, color: t.dim),
    );
  }
}
