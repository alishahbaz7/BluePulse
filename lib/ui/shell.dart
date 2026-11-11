import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/settings.dart';
import '../scanner/scanner.dart';
import '../update/update_service.dart';
import '../version.dart';
import 'nav.dart';
import 'pages/configure_page.dart';
import 'pages/decode_page.dart';
import 'pages/device_detail_page.dart';
import 'pages/devices_page.dart';
import 'pages/overview_page.dart';
import 'pages/packets_page.dart';
import 'pages/proximity_page.dart';
import 'pages/sessions_page.dart';
import 'pages/simulator_page.dart';
import 'pages/settings_page.dart';
import 'theme.dart';
import 'update_ui.dart';
import 'usage_ui.dart';
import 'widgets/common.dart';
import 'widgets/device_card.dart' show isPhone;

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
        PageId.simulator => const SimulatorPage(),
        PageId.sessions => const SessionsPage(),
        PageId.configure => ConfigurePage(mac: _mac),
      };

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    return Navigation(
      go: _go,
      child: LayoutBuilder(builder: (context, box) {
        final phone = isPhone(context);
        final forcedRail = box.maxWidth < 1000;
        final folded = !phone && (forcedRail || c.settings.railFolded);
        final item = navItem(_page);
        final page = KeyedSubtree(key: ValueKey(_page), child: _body());

        if (phone) {
          return Scaffold(
            key: _scaffold,
            drawer: Drawer(
              width: 260,
              // The menu's own colour behind the status bar, and its content below it and above the
              // gesture bar — without SafeArea the brand sat under the phone's notification bar.
              backgroundColor: context.tokens.panel,
              child: SafeArea(
                right: false,
                child: _Sidebar(
                  current: _page,
                  folded: false,
                  onSelect: (id) {
                    Navigator.of(context).pop();
                    _go(id);
                  },
                ),
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
                      needsRadio: item.live && radioProblem,
                      onTap: () => onSelect(item.id),
                    ),
                ],
              ]),
            ),
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
              // The name, then simply which version this is — and DEV on a development copy.
              Row(children: [
                Flexible(
                  child: Tooltip(
                    message: '$protocolSource\n${kDebugMode ? 'Development build' : 'Release build'}',
                    child: Text('Version $version',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: t.dim, fontFeatures: tabular)),
                  ),
                ),
                if (kDebugMode) ...[
                  const SizedBox(width: 6),
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
  const _RailItem({required this.item, required this.folded, required this.active, required this.needsRadio, required this.onTap});

  final NavItem item;
  final bool folded;
  final bool active;

  /// The page shows live data and Bluetooth is off or not allowed: a crossed-out Bluetooth mark,
  /// explained when hovered or held.
  final bool needsRadio;
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
                if (item.soon)
                  const Tooltip(message: 'Not built yet', child: Pill('Soon', tone: Tone.warn, small: true))
                else if (needsRadio)
                  Tooltip(
                    message: 'Turn Bluetooth on and allow BluePulse to use it to see this page live',
                    child: Icon(Icons.bluetooth_disabled, size: 16, color: t.warn),
                  ),
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.item, required this.phone, required this.onMenu});

  final NavItem item;
  final bool phone;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = AppScope.of(context);

    // One icon says what the radio is doing; the page says how many devices, once.
    final chips = <Widget>[
      if (item.live) ...[
        if (c.isDemo) _radioChip(context, c),
        // A phone's bar has no room for it; the Devices page says how many are in focus.
        if (c.book.focus.isNotEmpty && !phone)
          StatusChip(
            text: 'Pinned · ${c.book.focus.length}',
            tone: Tone.accent,
            detail: 'Pinned devices stay on top and refresh fastest',
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
            child: Text(item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: t.text)),
          ),
        ),
        ...chips.expand((w) => [w, const SizedBox(width: 8)]),
        if (!phone || !item.live) ...[const UpdateChip(), const SizedBox(width: 4)],
        // On a phone the scanning pages need the room (Clear, the scan button); Settings has the theme too.
        if (!phone || !item.live) _ThemeButton(settings: c.settings),
        if ((item.id == PageId.overview || item.id == PageId.devices) && c.registry.totalPackets > 0) ...[
          const SizedBox(width: 4),
          _ClearButton(phone: phone),
        ],
        if (item.live) ...[const SizedBox(width: 6), _ScanButton(controller: c)],
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

/// Empties the device list — on the Overview and Devices pages, where a busy place fills it.
class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.phone});

  final bool phone;

  Future<void> _clear(BuildContext context) async {
    final c = AppScope.read(context);
    final ok = await confirmDestructive(
      context,
      title: 'Clear the list?',
      sentence: 'Every device and packet heard so far is removed from the screen. Devices still in range come '
          'back as they are heard; the saved session is kept.',
      action: 'Clear',
    );
    if (ok) c.clearDevices();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (phone) {
      return IconButton(
        onPressed: () => _clear(context),
        tooltip: 'Clear the list',
        icon: Icon(Icons.delete_sweep_outlined, size: 20, color: t.dim),
      );
    }
    return HoldTip(
      message: 'Removes every device and packet from the screen; devices still in range come back as they are '
          'heard. The saved session is kept',
      child: OutlinedButton.icon(
        onPressed: () => _clear(context),
        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
        label: const Text('Clear'),
      ),
    );
  }
}

/// One button for the radio and the scan: it glows while scanning (tap to stop), shows plain while
/// Bluetooth is on but idle (tap to scan), and is grey while Bluetooth is off or not permitted — a tap
/// then turns it on or asks for the permission.
class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = controller;
    final radio = c.isDemo ? RadioState.on : c.status.radio;
    final (icon, look, tip, VoidCallback? tap) = switch (radio) {
      RadioState.on when c.scanning => (Icons.bluetooth_searching, _Look.glow, 'Scanning · tap to stop', c.stopScan),
      RadioState.on => (Icons.bluetooth, _Look.plain, 'Bluetooth on · tap to scan', c.startScan),
      RadioState.off => (Icons.bluetooth_disabled, _Look.grey, 'Bluetooth is off · tap to turn it on', c.scanner.enableRadio),
      RadioState.unauthorized =>
        (Icons.bluetooth_disabled, _Look.grey, 'BluePulse may not use Bluetooth · tap to allow it', c.scanner.requestPermission),
      RadioState.unsupported => (Icons.bluetooth_disabled, _Look.grey, c.status.error ?? 'No Bluetooth adapter', null),
      RadioState.unknown => (Icons.bluetooth, _Look.grey, 'Bluetooth …', c.startScan),
    };
    final (fill, border, color, glow) = switch (look) {
      _Look.glow => (t.accent, t.accent, Colors.white, true),
      _Look.plain => (Colors.transparent, t.text.withValues(alpha: 0.75), t.text, false),
      _Look.grey => (Colors.transparent, t.line, t.muted, false),
    };
    return Tooltip(
      message: tip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: tap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: Border.all(color: border, width: 1.5),
              boxShadow: glow ? [BoxShadow(color: t.accent.withValues(alpha: 0.6), blurRadius: 16, spreadRadius: 1)] : null,
            ),
            child: Icon(icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }
}

enum _Look { glow, plain, grey }

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
