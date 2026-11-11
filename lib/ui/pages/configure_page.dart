import 'dart:async';

import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../config/config_session.dart';
import '../../core/device.dart';
import '../format.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/device_card.dart';
import '../widgets/device_name.dart';
import '../widgets/sensor_icons.dart';
import '../widgets/data_grid.dart';
import '../widgets/device_table.dart';

/// Configure an EYE SENSOR or EYE BEACON over Bluetooth: choose it, unlock it with its PIN, change
/// any of its settings, save — each change is read back from the device before it counts.
class ConfigurePage extends StatefulWidget {
  const ConfigurePage({super.key, this.mac});

  /// The device to configure; null to choose one.
  final String? mac;

  @override
  State<ConfigurePage> createState() => _ConfigurePageState();
}

class _ConfigurePageState extends State<ConfigurePage> {
  late String? _mac = _configurable(widget.mac) ? widget.mac : null;
  ConfigSession? _session;
  final _pin = TextEditingController(text: '123456');

  /// The scan pauses while a device is connected — a phone's one radio scanning without pause left
  /// the connection no air (the sensor dropped it: supervision timeout, logcat 11-11-2026) — and
  /// starts again when configuring ends.
  AppController? _controller;
  bool _scanPaused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = AppScope.read(context);
  }

  void _resumeScan() {
    if (!_scanPaused) return;
    _scanPaused = false;
    unawaited(_controller?.resumeScan());
  }

  static bool _configurable(String? mac) => mac != null && mac.isNotEmpty && !mac.startsWith('SIM-');

  @override
  void didUpdateWidget(ConfigurePage old) {
    super.didUpdateWidget(old);
    if (widget.mac != old.mac && _configurable(widget.mac)) _choose(widget.mac!);
  }

  void _choose(String? mac) {
    unawaited(_session?.close());
    _session?.dispose();
    _resumeScan();
    setState(() {
      _session = null;
      _mac = mac;
    });
  }

  Future<void> _connect() async {
    final c = AppScope.read(context);
    final pin = _pin.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The PIN is six digits')));
      return;
    }
    _session?.dispose();
    final s = ConfigSession(link: c.gattLink, mac: _mac!);
    setState(() => _session = s);
    if (c.scanning) {
      _scanPaused = true;
      await c.pauseScan();
    }
    await s.open(pin);
    if (s.state == ConfigState.failed) _resumeScan();
  }

  @override
  void dispose() {
    unawaited(_session?.close());
    _session?.dispose();
    _resumeScan();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final phone = isPhone(context);
    if (_mac == null) return _Chooser(onChoose: _choose);
    final d = c.registry.device(_mac!);
    final s = _session;
    return ListenableBuilder(
      listenable: s ?? ValueNotifier(0),
      builder: (context, _) {
        final body = <Widget>[
          _Header(device: d, mac: _mac!, session: s, onBack: () => _choose(null), onDisconnect: () => _choose(_mac)),
          const SizedBox(height: 12),
          if (s == null || s.state == ConfigState.idle || s.state == ConfigState.failed)
            _Unlock(pin: _pin, session: s, onConnect: _connect)
          else if (!s.connected)
            _Progress(session: s)
          else
            ..._settings(context, s, phone),
        ];
        return Column(children: [
          Expanded(child: ListView(padding: EdgeInsets.all(phone ? 12 : 16), children: body)),
          if (s != null && s.connected) _SaveBar(session: s),
        ]);
      },
    );
  }

  List<Widget> _settings(BuildContext context, ConfigSession s, bool phone) {
    final groups = [
      _Group('Reporting', Icons.speed, 'How often the device advertises, and how strongly', [
        EyeSetting.interval,
        EyeSetting.repeats,
        EyeSetting.subInterval,
        EyeSetting.txPower,
      ], extra: _Delivery(session: s)),
      _Group('Identity', Icons.badge_outlined, 'Its name and what it advertises', [
        EyeSetting.name,
        EyeSetting.protocolType,
        EyeSetting.iBeaconId,
        EyeSetting.eddystoneId,
      ]),
      _Group('Sensors', Icons.sensors, 'Which measurements it sends', [EyeSetting.sensors]),
      _Group('Movement', Icons.directions_run, 'How long movement must last to start or end a movement event', [
        EyeSetting.movementStart,
        EyeSetting.movementStop,
      ]),
      _Group('Power', Icons.battery_charging_full_outlined, 'Hibernation and the advertising burst after a wake-up', [
        EyeSetting.hibernate,
        EyeSetting.wakeUpAdvertising,
      ]),
      _Group('Advanced', Icons.tune, 'Signal reference for distance estimates', [EyeSetting.rssiCalibration]),
    ];
    final panels = [
      for (final g in groups)
        if (g.settings.any((e) => !s.unsupported.contains(e)))
          PanelCard(
            title: g.title,
            tip: g.tip,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final e in g.settings)
                if (!s.unsupported.contains(e)) _Field(session: s, setting: e),
              ?g.extra,
            ]),
          ),
    ];
    return [
      if (s.saveErrors.isNotEmpty) ...[
        Notice(
          'Not saved: ${s.saveErrors.entries.map((e) => '${e.key.label} (${e.value})').join('; ')}',
          tone: Tone.bad,
        ),
        const SizedBox(height: 12),
      ],
      if (s.state == ConfigState.saved) ...[
        Notice('Saved to the device and read back: ${s.savedSettings.map((e) => e.label).join(', ')}', tone: Tone.ok),
        const SizedBox(height: 12),
      ],
      LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 900) {
          return Column(children: [for (final p in panels) Padding(padding: const EdgeInsets.only(bottom: 12), child: p)]);
        }
        final left = [for (var i = 0; i < panels.length; i += 2) panels[i]];
        final right = [for (var i = 1; i < panels.length; i += 2) panels[i]];
        Widget col(List<Widget> ps) =>
            Column(children: [for (final p in ps) Padding(padding: const EdgeInsets.only(bottom: 12), child: p)]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: col(left)),
          const SizedBox(width: 12),
          Expanded(child: col(right)),
        ]);
      }),
    ];
  }
}

class _Group {
  const _Group(this.title, this.icon, this.tip, this.settings, {this.extra});
  final String title;
  final IconData icon;
  final String tip;
  final List<EyeSetting> settings;
  final Widget? extra;
}

/// The EYE devices in range, strongest first, to pick one.
class _Chooser extends StatelessWidget {
  const _Chooser({required this.onChoose});
  final void Function(String mac) onChoose;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final now = DateTime.now();
    final devices = c.registry.devices.where((d) => d.model.isEye && !d.isSimulated).toList();
    final tiles = showTiles(context);
    // The same order as the Devices tiles (As found by default); the table sorts by its headers.
    if (tiles) sortDevices(devices, c.settings.deviceSort, (d) => deviceLabel(c.book, d));
    if (devices.isEmpty) {
      return EmptyState(
        icon: Icons.tune_outlined,
        text: c.scanning ? 'No EYE devices in range yet.' : 'Start a scan to find the device to configure.',
        action: c.scanning ? null : c.startScan,
        actionLabel: 'Start scan',
      );
    }
    return Padding(
      padding: EdgeInsets.all(isPhone(context) ? 12 : 16),
      child: PanelCard(
        title: 'Choose a device',
        tip: 'Configuring connects to the device; it keeps advertising meanwhile',
        padding: EdgeInsets.zero,
        expand: true,
        actions: [
          if (tiles)
            DeviceSortMenu(value: c.settings.deviceSort, onChanged: (v) => c.settings.update((s) => s.deviceSort = v)),
          if (!isPhone(context)) const DeviceViewToggle(),
        ],
        // Tiles or the Devices page's table, as chosen with the switch.
        child: tiles
            ? CardRows(
                count: devices.length,
                card: (i, stripe) => DeviceCard(device: devices[i], now: now, stripe: stripe, onTap: () => onChoose(devices[i].mac)),
              )
            : DataGrid<EyeDevice>(
                rows: devices,
                columns: deviceColumns(context, rows: devices, now: now, pin: false),
                onTap: (d) => onChoose(d.mac),
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.device, required this.mac, required this.session, required this.onBack, required this.onDisconnect});

  final EyeDevice? device;
  final String mac;
  final ConfigSession? session;
  final VoidCallback onBack;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = AppScope.of(context);
    final s = session;
    final info = s?.info;
    final live = s?.live;
    final name = (s?.original[EyeSetting.name] as String?) ?? (device == null ? mac : deviceLabel(c.book, device!));
    return PanelCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(onPressed: onBack, tooltip: 'Choose another device', icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.text)),
              Text(mac, style: monoStyle(context, color: t.dim)),
            ]),
          ),
          if (s != null && s.connected) ...[
            const Pill('Connected', tone: Tone.ok),
            const SizedBox(width: 6),
            PopupMenuButton<EyeCommand>(
              tooltip: 'Device commands',
              icon: const Icon(Icons.more_vert),
              onSelected: (cmd) => _command(context, s, cmd),
              itemBuilder: (_) => const [
                PopupMenuItem(value: EyeCommand.reset, child: Text('Restart the device')),
                PopupMenuItem(value: EyeCommand.restoreDefaults, child: Text('Restore factory settings')),
              ],
            ),
            IconButton(onPressed: onDisconnect, tooltip: 'Disconnect', icon: const Icon(Icons.link_off)),
          ],
        ]),
        if (info != null && (info.model != null || info.firmware != null)) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 24, runSpacing: 10, children: [
            if (info.model != null) Fact('Model', info.model!),
            if (info.firmware != null) Fact('Firmware', info.firmware!),
            if (info.hardware != null) Fact('Hardware', info.hardware!),
            if (s!.failedAttempts != null && s.failedAttempts! > 0) Fact('Wrong PINs so far', '${s.failedAttempts}'),
          ]),
        ],
        if (live != null) ...[
          const SizedBox(height: 10),
          HoldTip(
            message: 'Read from the device while connected, every few seconds',
            child: Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const FreshDot(live: true),
              if (live.temperatureC != null)
                ValueChip(icon: Icon(Icons.thermostat, size: 16, color: t.warn), value: live.temperatureC!.toStringAsFixed(1), unit: '°C', tip: 'Temperature'),
              if (live.humidity != null)
                ValueChip(icon: Icon(Icons.water_drop, size: 16, color: t.accent), value: '${live.humidity}', unit: '%', tip: 'Humidity'),
              if (live.moving != null)
                ValueChip(
                  icon: Icon(live.moving! ? Icons.directions_run : Icons.accessibility_new, size: 16, color: live.moving! ? t.accent : t.dim),
                  value: '${live.movementCount ?? '—'}',
                  tip: live.moving! ? 'Moving' : 'Still',
                ),
              if (live.batteryMv != null)
                ValueChip(
                  icon: Icon(batteryIcon(live.batteryMv, low: live.lowBattery), size: 16, color: live.lowBattery ? t.warn : t.ok),
                  value: (live.batteryMv! / 1000).toStringAsFixed(2),
                  unit: ' V',
                  tip: 'Battery',
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  Future<void> _command(BuildContext context, ConfigSession s, EyeCommand cmd) async {
    final restore = cmd == EyeCommand.restoreDefaults;
    final ok = await confirmDestructive(
      context,
      title: restore ? 'Restore factory settings?' : 'Restart the device?',
      sentence: restore
          ? 'Every setting returns to its factory value — interval, name, IDs and the PIN included. The connection ends.'
          : 'The device restarts with its saved settings. The connection ends.',
      action: restore ? 'Restore' : 'Restart',
    );
    if (!ok) return;
    try {
      await s.command(cmd);
      if (cmd == EyeCommand.restoreDefaults) await s.command(EyeCommand.writeToFlash);
      await s.command(EyeCommand.reset);
    } catch (_) {
      // The device restarts and drops the link: the session reports it.
    }
  }
}

class _Unlock extends StatelessWidget {
  const _Unlock({required this.pin, required this.session, required this.onConnect});

  final TextEditingController pin;
  final ConfigSession? session;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final s = session;
    return PanelCard(
      title: 'Connect',
      tip: "The device's 6-digit PIN; 123456 unless it was changed. Each wrong PIN counts against a lock-out. "
          'Scanning pauses while connected and starts again afterwards',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (s?.error != null) ...[
          Notice(s!.error!, tone: Tone.bad),
          const SizedBox(height: 12),
        ],
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 160,
            child: TextField(
              controller: pin,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: false,
              style: monoStyle(context, size: 16),
              decoration: const InputDecoration(labelText: 'PIN', counterText: '', prefixIcon: Icon(Icons.lock_outline, size: 18)),
              onSubmitted: (_) => onConnect(),
            ),
          ),
          FilledButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.bluetooth_connected, size: 18),
            label: Text(s?.wrongPin == true ? 'Try again' : 'Connect'),
          ),
        ]),
      ]),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.session});
  final ConfigSession session;

  @override
  Widget build(BuildContext context) {
    final step = switch (session.state) {
      ConfigState.connecting => 'Connecting…',
      ConfigState.unlocking => 'Unlocking with the PIN…',
      ConfigState.reading => 'Reading the settings…',
      _ => '',
    };
    return PanelCard(
      child: Row(children: [
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 14),
        Text(step, style: TextStyle(fontSize: 14, color: context.tokens.text)),
      ]),
    );
  }
}

/// One setting: label, its control, the device's value beside it when changed, and why it cannot be
/// saved when it cannot.
class _Field extends StatefulWidget {
  const _Field({required this.session, required this.setting});
  final ConfigSession session;
  final EyeSetting setting;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final _text = TextEditingController(text: _shown(widget.session.edited[widget.setting]));

  String _shown(Object? v) => widget.setting.show(v) == '—' ? '' : widget.setting.show(v);

  @override
  void didUpdateWidget(_Field old) {
    super.didUpdateWidget(old);
    // Follow a discard or a save; never overwrite what is being typed.
    final want = _shown(widget.session.edited[widget.setting]);
    final typed = _parse(_text.text);
    if (typed == null || !_equal(typed, widget.session.edited[widget.setting])) {
      if (_text.text != want && FocusScope.of(context).focusedChild == null) _text.text = want;
    }
  }

  static bool _equal(Object? a, Object? b) => a is List<int> && b is List<int> ? a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x) : a == b;

  Object? _parse(String v) => switch (widget.setting.kind) {
        EyeValueKind.text => v,
        EyeValueKind.bytes => hexOrNull(v),
        _ => int.tryParse(v.trim()),
      };

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = widget.session;
    final e = widget.setting;
    final value = s.edited[e];
    final was = s.original[e];
    final changed = !_equal(value, was);
    final problem = changed && value != null ? e.problem(value) : null;
    final bits = value is int ? value : 0;

    final Widget control = switch (e) {
      EyeSetting.txPower => DropdownButton<int>(
          value: EyeSetting.txPowers.contains(value) ? value as int : null,
          items: [for (final p in EyeSetting.txPowers) DropdownMenuItem(value: p, child: Text('${p > 0 ? '+' : ''}$p dBm'))],
          onChanged: (v) => v == null ? null : s.edit(e, v),
        ),
      EyeSetting.protocolType => DropdownButton<int>(
          value: value as int?,
          items: [
            for (var p = 0; p <= (hasSensorSwitches(s.info.firmware ?? '') ? 2 : 4); p++)
              DropdownMenuItem(value: p, child: Text(protocolTypeLabel(p))),
          ],
          onChanged: (v) => v == null ? null : s.edit(e, v),
        ),
      EyeSetting.hibernate => Switch(value: value == 1, onChanged: (v) => s.edit(e, v ? 1 : 0)),
      EyeSetting.sensors => Wrap(spacing: 8, runSpacing: 4, children: [
          for (final (bit, label, icon) in [
            (0, 'Temperature', Icons.thermostat),
            (1, 'Humidity', Icons.water_drop),
            (2, 'Magnet', Icons.circle_outlined),
            (3, 'Movement', Icons.directions_run),
          ])
            FilterChip(
              avatar: Icon(icon, size: 16),
              label: Text(label),
              selected: (bits >> bit) & 1 == 1,
              onSelected: (on) => s.edit(e, on ? bits | (1 << bit) : bits & ~(1 << bit)),
            ),
        ]),
      _ => SizedBox(
          width: switch (e.kind) { EyeValueKind.bytes => 340, EyeValueKind.text => 220, _ => 120 },
          child: TextField(
            controller: _text,
            keyboardType: e.kind == EyeValueKind.text || e.kind == EyeValueKind.bytes ? null : const TextInputType.numberWithOptions(signed: true),
            maxLength: e.kind == EyeValueKind.text ? e.max : (e.kind == EyeValueKind.bytes ? e.max * 2 + 8 : 6),
            style: e.kind == EyeValueKind.bytes ? monoStyle(context, size: 13) : null,
            decoration: InputDecoration(isDense: true, counterText: '', suffixText: e.unit),
            onChanged: (v) {
              final parsed = _parse(v);
              if (parsed != null) s.edit(e, parsed);
            },
          ),
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(builder: (context, box) {
        final label = Row(mainAxisSize: MainAxisSize.min, children: [
          if (changed) ...[Icon(Icons.edit, size: 14, color: t.accent), const SizedBox(width: 6)],
          Flexible(child: Text(e.label, style: TextStyle(fontSize: 13.5, color: changed ? t.accent : t.text))),
        ]);
        final note = [
          if (changed && was != null) 'was ${e == EyeSetting.protocolType ? protocolTypeLabel(was as int) : e.show(was)}${e.unit == null || was is List ? '' : ' ${e.unit}'}',
          ?problem,
        ].join(' · ');
        final noteText = note.isEmpty ? null : Text(note, style: TextStyle(fontSize: 12, color: problem != null ? t.bad : t.dim));
        if (box.maxWidth < 520) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            label,
            const SizedBox(height: 4),
            control,
            ?noteText,
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(width: 180, child: label),
          Flexible(child: Align(alignment: Alignment.centerLeft, child: control)),
          if (noteText != null) ...[const SizedBox(width: 10), Flexible(child: noteText)],
        ]);
      }),
    );
  }
}

/// What the reporting settings give a receiver: one reading every interval, and with repeats several
/// chances at it.
class _Delivery extends StatelessWidget {
  const _Delivery({required this.session});
  final ConfigSession session;

  @override
  Widget build(BuildContext context) {
    final interval = session.edited[EyeSetting.interval] as int?;
    final repeats = session.edited[EyeSetting.repeats] as int? ?? 1;
    if (interval == null) return const SizedBox.shrink();
    final chances = interval > 2000 ? repeats : 1;
    final share = deliveredShare(intervalMs: interval, repeats: repeats, heard: 0.45);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: HoldTip(
        message: 'A phone in a busy room hears about 45 % of single packets (benchmark, 10-11-2026). Repeats '
            'only count above 2000 ms',
        child: Wrap(spacing: 24, runSpacing: 8, children: [
          Fact('A reading every', formatInterval(interval)),
          Fact('Chances per reading', '$chances'),
          Fact('Expected on time', '≈ ${(share * 100).round()} %'),
        ]),
      ),
    );
  }
}

/// Changes waiting to be saved: how many, Discard, Save.
class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.session});
  final ConfigSession session;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = session;
    final n = s.changes.length;
    final blocked = s.problems.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(color: t.panel, border: Border(top: BorderSide(color: t.line))),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: Text(
              s.state == ConfigState.saving
                  ? 'Saving…'
                  : n == 0
                      ? 'No changes'
                      : '$n change${n == 1 ? '' : 's'}${blocked ? ' · fix the marked values' : ''}',
              style: TextStyle(fontSize: 13.5, color: blocked ? t.bad : t.text),
            ),
          ),
          TextButton(onPressed: n == 0 || s.busy ? null : s.discard, child: const Text('Discard')),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: n == 0 || blocked || s.busy ? null : s.save,
            icon: s.state == ConfigState.saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save'),
          ),
        ]),
      ),
    );
  }
}

/// The device page's way in.
void openConfigure(BuildContext context, EyeDevice d) => Navigation.of(context).go(PageId.configure, mac: d.mac);
