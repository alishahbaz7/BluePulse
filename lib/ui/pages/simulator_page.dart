import 'dart:async';

import 'package:eye_protocol/eye_protocol.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../simulator/sim_model.dart';
import '../../simulator/sim_service.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/rx_log_card.dart' show toHexCompact;

/// This device transmits as an EYE SENSOR, EYE BEACON or iBeacon at a chosen interval, with values
/// that change by themselves — to check what a receiver (BluePulse on another device, a tracker)
/// really gets, and when.
class SimulatorPage extends StatefulWidget {
  const SimulatorPage({super.key});

  @override
  State<SimulatorPage> createState() => _SimulatorPageState();
}

class _SimulatorPageState extends State<SimulatorPage> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    final sim = AppScope.read(context).simulator;
    if (sim.capabilities == null) unawaited(sim.refreshCapabilities());
    // The running time and expected count tick while transmitting.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && AppScope.read(context).simulator.running) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).simulator;
    final s = sim.settings;
    final caps = sim.capabilities;
    final t = context.tokens;
    final now = DateTime.now();
    final payload = sim.payload ?? sim.build();
    final (findAs, findTip) = _findAs(payload, s);

    final (stateText, stateTone) = switch (sim.state) {
      SimState.transmitting => ('Transmitting', Tone.ok),
      SimState.starting => ('Starting', Tone.accent),
      SimState.failed => ('Failed', Tone.bad),
      SimState.stopped => ('Stopped', Tone.neutral),
    };
    final bursts = caps != null && caps.supported && !caps.exactInterval;

    // The ID a receiver lists this device by is what people read off this page: it gets a whole line
    // where five tiles would cut it short.
    final receiver =
        StatTile(label: 'Receiver', value: findAs ?? '—', tone: findAs == null ? Tone.warn : Tone.neutral, tip: findTip);
    return ListView(padding: const EdgeInsets.all(16), children: [
      LayoutBuilder(builder: (context, c) {
        final together = c.maxWidth >= 1040;
        return Column(children: [
          TileRow(minWidth: 150, tiles: [
            StatTile(label: 'State', value: stateText, tone: stateTone),
            StatTile(
              label: 'Interval',
              value: formatInterval(s.intervalMs),
              tip: bursts ? 'A short burst every interval: Windows sets its own advertising rate' : 'Kept by the radio',
            ),
            StatTile(
              label: 'Running',
              value: sim.running && sim.startedAt != null ? formatDuration(now.difference(sim.startedAt!)) : '—',
              secondary: sim.running ? '${formatCount(bursts ? sim.bursts : sim.expectedEvents(now))} sent' : null,
              tip: bursts ? 'Bursts sent' : 'Advertisements expected on air at this interval',
            ),
            StatTile(
              label: 'Changes',
              value: formatCount(sim.changes),
              secondary: _changeLabel(s),
              tip: 'Times the values changed and went on air',
            ),
            if (together) receiver,
          ]),
          if (!together) ...[const SizedBox(height: 10), SizedBox(width: double.infinity, child: receiver)],
        ]);
      }),
      if (caps != null && !caps.supported) ...[
        const SizedBox(height: 12),
        Notice(caps.reason ?? 'This device cannot transmit.', tone: Tone.warn),
      ],
      if (sim.error != null) ...[
        const SizedBox(height: 12),
        Notice(sim.error!, tone: Tone.bad),
      ],
      if (bursts) ...[
        const SizedBox(height: 12),
        const Notice(
          'Windows: one short burst every interval, each from a new random address; no name, and no scan response.',
          tone: Tone.warn,
        ),
      ],
      if (findAs == null) ...[
        const SizedBox(height: 12),
        const Notice(
          'Nothing in these packets tells this device apart, and its address is random: turn the BluePulse tag on '
          'to find it on a receiver.',
          tone: Tone.warn,
        ),
      ],
      const SizedBox(height: 14),
      PanelCard(
        title: 'Transmitter',
        actions: [
          if (sim.running)
            OutlinedButton.icon(
              onPressed: sim.stop,
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Stop'),
            )
          else
            FilledButton.icon(
              onPressed: caps == null || caps.supported ? sim.start : null,
              icon: const Icon(Icons.cell_tower, size: 18),
              label: const Text('Start transmitting'),
            ),
        ],
        child: _TransmitterForm(sim: sim, nameAllowed: caps?.name ?? true, powerAllowed: caps?.txPower ?? true),
      ),
      const SizedBox(height: 14),
      PanelCard(
        title: 'Values',
        tip: 'Auto: the value changes by itself around the one set here',
        child: _ValuesForm(sim: sim),
      ),
      const SizedBox(height: 14),
      PanelCard(
        title: 'On air',
        tip: 'The packets as transmitted, decoded back by the same decoder that reads real devices',
        child: _OnAir(payload: payload, settings: s, nameOnAir: sim.nameOnAir, t: t),
      ),
    ]);
  }

  /// What to look for on a receiver: the simulator ID, the name, or the beacon ID — or null when
  /// nothing in the packets tells this device apart. With the tip that explains it.
  static (String?, String) _findAs(SimPayload p, SimSettings s) {
    if (p.simulatorId != null) {
      return (
        simulatorKey(p.simulatorId!),
        'BluePulse on the receiving phone or PC lists this device under this ID, in place of a MAC; '
            'search the Devices page for SIM. Other receivers see a random address that changes'
      );
    }
    final name = p.adv.name ?? p.scanResponse?.name;
    if (name != null) return (name, 'The advertised name: search for it on the receiver. The address is random');
    final id = simBeaconId(s);
    if (id != null) {
      return (
        id.isEddystone ? id.instanceHex : '${id.major} · ${id.minor}',
        'The beacon ID (${id.kindLabel}): search for it on the receiver. The address is random'
      );
    }
    return (null, 'Nothing identifies this device: its address is random and it sends no name or ID');
  }

  static String _changeLabel(SimSettings s) => switch (s.changeEverySec) {
        < 0 => 'fixed',
        0 => 'every ${formatInterval(s.intervalMs)}',
        final n => 'every ${formatInterval(n * 1000)}',
      };
}

/// A label and its control, as on the Settings page.
class _Row extends StatelessWidget {
  const _Row(this.label, this.control, {this.tip = ''});

  final String label;
  final Widget control;
  final String tip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(builder: (context, c) {
        final label0 = HoldTip(message: tip, child: Text(label, style: TextStyle(fontSize: 13.5, color: t.text)));
        if (c.maxWidth < 520) {
          return SizedBox(
            width: c.maxWidth,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              label0,
              const SizedBox(height: 6),
              control,
            ]),
          );
        }
        return Row(children: [
          SizedBox(width: 170, child: label0),
          Flexible(child: Align(alignment: Alignment.centerLeft, child: control)),
        ]);
      }),
    );
  }
}

class _TransmitterForm extends StatelessWidget {
  const _TransmitterForm({required this.sim, required this.nameAllowed, required this.powerAllowed});

  final SimulatorService sim;
  final bool nameAllowed;
  final bool powerAllowed;

  @override
  Widget build(BuildContext context) {
    final s = sim.settings;
    return Column(children: [
      _Row(
        'Simulate',
        SegmentedButton<SimProfile>(
          showSelectedIcon: false,
          segments: [for (final p in SimProfile.values) ButtonSegment(value: p, label: Text(p.label))],
          selected: {s.profile},
          onSelectionChanged: (v) => sim.update((x) {
            // Follow the profile's usual name unless the user typed their own.
            if (x.name == x.profile.defaultName) x.name = v.first.defaultName;
            x.profile = v.first;
          }),
        ),
      ),
      if (s.profile == SimProfile.eyeSensor)
        _Row(
          'Packet',
          DropdownButton<SensorPacket>(
            value: s.sensorPacket,
            items: [for (final p in SensorPacket.values) DropdownMenuItem(value: p, child: Text(p.label))],
            onChanged: (v) => v == null ? null : sim.update((x) => x.sensorPacket = v),
          ),
          tip: "The EYE SENSOR's protocol type: with a beacon frame, the sensor data goes in the scan response",
        ),
      if (s.profile == SimProfile.eyeBeacon)
        _Row(
          'Frame',
          SegmentedButton<BeaconFrame>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: BeaconFrame.eddystone, label: Text('Eddystone')),
              ButtonSegment(value: BeaconFrame.iBeacon, label: Text('iBeacon')),
            ],
            selected: {s.beaconFrame},
            onSelectionChanged: (v) => sim.update((x) => x.beaconFrame = v.first),
          ),
        ),
      _Row(
        'Name',
        SizedBox(
          width: 220,
          child: _TextField(
            key: ValueKey('name-${s.profile.name}'),
            value: s.name,
            enabled: nameAllowed,
            maxLength: 20,
            hint: nameAllowed ? 'none' : 'not sent from Windows',
            onSubmitted: (v) => sim.update((x) => x.name = v.trim()),
          ),
        ),
        tip: nameAllowed
            ? "Android advertises the phone's Bluetooth name, so it is renamed to this while transmitting "
                'and given its old name back on Stop'
            : 'Windows does not let apps advertise a name. BluePulse receivers list this device by the ID '
                'its tag carries instead',
      ),
      _Row(
        'Interval',
        DropdownButton<int>(
          value: simIntervals.contains(s.intervalMs) ? s.intervalMs : 2000,
          items: [for (final ms in simIntervals) DropdownMenuItem(value: ms, child: Text(formatInterval(ms)))],
          onChanged: (v) => v == null ? null : sim.update((x) => x.intervalMs = v),
        ),
        tip: 'How often an advertisement goes on air. EYE SENSOR default 5 s, EYE BEACON 1 s',
      ),
      if (powerAllowed)
        _Row(
          'Transmit power',
          SegmentedButton<SimTxPower>(
            showSelectedIcon: false,
            segments: [for (final p in SimTxPower.values) ButtonSegment(value: p, label: Text(p.label))],
            selected: {s.txPower},
            onSelectionChanged: (v) => sim.update((x) => x.txPower = v.first),
          ),
          tip: 'Ultra low −21 dBm, low −15, medium −7, high +1; Windows takes it as a preference',
        ),
      _Row(
        'BluePulse tag',
        Switch(value: s.simTag, onChanged: (v) => sim.update((x) => x.simTag = v)),
        tip: 'Ten extra bytes (company 0xFFFF, kept for tests) wherever a packet has room. BluePulse receivers use '
            'them to list this as one device, SIM-…, although its address keeps changing. Off: only what a real '
            'device sends',
      ),
      _Row(
        'Values change',
        DropdownButton<int>(
          value: s.changeEverySec,
          items: [
            for (final v in simChangeChoices)
              DropdownMenuItem(
                value: v,
                child: Text(switch (v) {
                  0 => 'With every advertisement',
                  < 0 => 'Never',
                  _ => 'Every ${formatInterval(v * 1000)}',
                }),
              ),
          ],
          onChanged: (v) => v == null ? null : sim.update((x) => x.changeEverySec = v),
        ),
      ),
    ]);
  }
}

class _ValuesForm extends StatelessWidget {
  const _ValuesForm({required this.sim});

  final SimulatorService sim;

  @override
  Widget build(BuildContext context) {
    final s = sim.settings;
    final rows = <Widget>[];

    Widget number(String key, num value, void Function(SimSettings, String) apply, {double width = 96}) => SizedBox(
          width: width,
          child: _TextField(
            key: ValueKey(key),
            value: value is double ? value.toStringAsFixed(2) : '$value',
            numeric: true,
            onSubmitted: (v) => sim.update((x) => apply(x, v)),
          ),
        );
    Widget auto(bool value, void Function(SimSettings, bool) apply) => Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(value: value, onChanged: (v) => sim.update((x) => apply(x, v))),
          const SizedBox(width: 4),
          const Text('Auto'),
        ]);
    Widget send(bool value, void Function(SimSettings, bool) apply) =>
        Checkbox(value: value, onChanged: (v) => sim.update((x) => apply(x, v ?? false)));
    Widget line(List<Widget> parts) => Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: parts);

    final battery = _Row(
      'Battery (mV)',
      line([
        if (s.profile != SimProfile.iBeacon) send(s.sendBattery, (x, v) => x.sendBattery = v),
        number('battery', s.batteryMv, (x, v) => x.batteryMv = int.tryParse(v)?.clamp(2000, 4550) ?? x.batteryMv),
        auto(s.autoBattery, (x, v) => x.autoBattery = v),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(value: s.lowBattery, onChanged: (v) => sim.update((x) => x.lowBattery = v ?? false)),
          const Text('Low battery'),
        ]),
      ]),
      tip: 'Sent in 10 mV steps, 2000–4550 mV. Auto sags slowly; at 2600 mV or less the low-battery flag is set',
    );

    switch (s.profile) {
      case SimProfile.eyeSensor:
        rows.addAll([
          _Row(
            'Temperature (°C)',
            line([
              send(s.sendTemperature, (x, v) => x.sendTemperature = v),
              number('temp', s.temperatureC, (x, v) => x.temperatureC = double.tryParse(v)?.clamp(-40, 125).toDouble() ?? x.temperatureC),
              auto(s.autoTemperature, (x, v) => x.autoTemperature = v),
            ]),
          ),
          _Row(
            'Humidity (%)',
            line([
              send(s.sendHumidity, (x, v) => x.sendHumidity = v),
              number('hum', s.humidity, (x, v) => x.humidity = int.tryParse(v)?.clamp(0, 100) ?? x.humidity),
              auto(s.autoHumidity, (x, v) => x.autoHumidity = v),
            ]),
          ),
          _Row(
            'Movement',
            line([
              send(s.sendMovement, (x, v) => x.sendMovement = v),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Checkbox(
                  value: s.moving,
                  onChanged: s.autoMovement ? null : (v) => sim.update((x) => x.moving = v ?? false),
                ),
                const Text('Moving'),
              ]),
              number('count', s.movementCount, (x, v) => x.movementCount = int.tryParse(v)?.clamp(0, 32767) ?? x.movementCount),
              auto(s.autoMovement, (x, v) => x.autoMovement = v),
              HoldTip(
                message: 'The movement count goes up by one with every change, so a receiver can count the updates it missed',
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(value: s.countPackets, onChanged: (v) => sim.update((x) => x.countPackets = v ?? false)),
                  const Text('Count updates'),
                ]),
              ),
            ]),
          ),
          _Row(
            'Pitch / roll (°)',
            line([
              send(s.sendAngles, (x, v) => x.sendAngles = v),
              number('pitch', s.pitch, (x, v) => x.pitch = int.tryParse(v)?.clamp(-90, 90) ?? x.pitch, width: 72),
              number('roll', s.roll, (x, v) => x.roll = int.tryParse(v)?.clamp(-180, 180) ?? x.roll, width: 72),
              auto(s.autoAngles, (x, v) => x.autoAngles = v),
            ]),
          ),
          _Row(
            'Magnet',
            line([
              send(s.sendMagnet, (x, v) => x.sendMagnet = v),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Checkbox(
                  value: s.magnetDetected,
                  onChanged: s.autoMagnet ? null : (v) => sim.update((x) => x.magnetDetected = v ?? false),
                ),
                const Text('Detected'),
              ]),
              auto(s.autoMagnet, (x, v) => x.autoMagnet = v),
            ]),
          ),
          battery,
        ]);
        if (s.sensorPacket != SensorPacket.sensorOnly) rows.addAll(_beaconIds(s));
      case SimProfile.eyeBeacon:
        rows.addAll([..._beaconIds(s), battery]);
      case SimProfile.iBeacon:
        rows.addAll(_iBeaconIds(s));
    }
    return Column(children: rows);
  }

  List<Widget> _beaconIds(SimSettings s) {
    final eddystone = s.profile == SimProfile.eyeBeacon
        ? s.beaconFrame == BeaconFrame.eddystone
        : s.sensorPacket == SensorPacket.eddystoneAndSensor;
    if (!eddystone) return _iBeaconIds(s);
    return [
      _Row(
        'Namespace',
        SizedBox(
          width: 260,
          child: _TextField(
            key: const ValueKey('ns'),
            value: s.namespaceHex,
            mono: true,
            maxLength: 20,
            onSubmitted: (v) => sim.update((x) => x.namespaceHex = v.toUpperCase()),
          ),
        ),
        tip: 'Eddystone-UID namespace, 10 bytes in hex',
      ),
      _Row(
        'Instance',
        SizedBox(
          width: 160,
          child: _TextField(
            key: const ValueKey('inst'),
            value: s.instanceHex,
            mono: true,
            maxLength: 12,
            onSubmitted: (v) => sim.update((x) => x.instanceHex = v.toUpperCase()),
          ),
        ),
        tip: 'Eddystone-UID instance, 6 bytes in hex; a new random one is made for each install',
      ),
    ];
  }

  List<Widget> _iBeaconIds(SimSettings s) => [
        _Row(
          'UUID',
          SizedBox(
            width: 320,
            child: _TextField(
              key: const ValueKey('uuid'),
              value: s.iBeaconUuidHex,
              mono: true,
              maxLength: 36,
              onSubmitted: (v) => sim.update((x) => x.iBeaconUuidHex = v.replaceAll('-', '').toUpperCase()),
            ),
          ),
          tip: 'iBeacon proximity UUID, 16 bytes in hex',
        ),
        _Row(
          'Major / minor',
          Wrap(spacing: 12, children: [
            SizedBox(
              width: 96,
              child: _TextField(
                key: const ValueKey('major'),
                value: '${s.major}',
                numeric: true,
                onSubmitted: (v) => sim.update((x) => x.major = int.tryParse(v)?.clamp(0, 65535) ?? x.major),
              ),
            ),
            SizedBox(
              width: 96,
              child: _TextField(
                key: const ValueKey('minor'),
                value: '${s.minor}',
                numeric: true,
                onSubmitted: (v) => sim.update((x) => x.minor = int.tryParse(v)?.clamp(0, 65535) ?? x.minor),
              ),
            ),
          ]),
        ),
      ];
}

/// The packets on air, decoded back.
class _OnAir extends StatelessWidget {
  const _OnAir({required this.payload, required this.settings, required this.nameOnAir, required this.t});

  final SimPayload payload;
  final SimSettings settings;
  final String? nameOnAir;
  final AppTokens t;

  @override
  Widget build(BuildContext context) {
    final merged = payload.scanResponse == null ? payload.adv : payload.adv.merge(payload.scanResponse!);
    final d = decodeAdvertisement(merged);
    final tel = d.teltonika;
    final facts = <(String, String)>[
      if (d.name != null) ('Name', nameOnAir ?? d.name!),
      if (d.beaconId != null) (d.beaconId!.kindLabel, d.beaconId!.display),
      if (tel?.temperatureC != null) ('Temperature', '${tel!.temperatureC!.toStringAsFixed(2)} °C'),
      if (tel?.humidity != null) ('Humidity', '${tel!.humidity} %'),
      if (tel?.movementCount != null) ('Movement', '${tel!.moving! ? 'moving' : 'still'} · ${tel.movementCount}'),
      if (tel?.pitch != null) ('Pitch / roll', '${tel!.pitch}° / ${tel.roll}°'),
      if (tel != null && tel.magnetPresent) ('Magnet', tel.magnetDetected == true ? 'detected' : 'not detected'),
      if (tel?.batteryMv != null) ('Battery', '${tel!.batteryMv} mV${tel.lowBattery ? ' · low' : ''}'),
      if (d.simulatorId != null) ('Simulator tag', simulatorKey(d.simulatorId!)),
    ];
    Widget packet(String label, AdvertisementData data) {
      final bytes = data.toBytes();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label · ${bytes.length} / ${SimPayload.maxBytes} bytes',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: t.dim)),
          const SizedBox(height: 4),
          SelectableText(toHexCompact(bytes), style: monoStyle(context, size: 12)),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 28, runSpacing: 10, children: [for (final (k, v) in facts) Fact(k, v)]),
      if (payload.problem != null) ...[const SizedBox(height: 10), Notice(payload.problem!, tone: Tone.bad)],
      packet('Advertisement', payload.adv),
      if (payload.scanResponse != null) packet('Scan response', payload.scanResponse!),
    ]);
  }
}

/// A text field that applies its value on Enter or when it loses focus, and follows outside changes
/// while it is not being edited.
class _TextField extends StatefulWidget {
  const _TextField({
    super.key,
    required this.value,
    required this.onSubmitted,
    this.numeric = false,
    this.mono = false,
    this.enabled = true,
    this.maxLength,
    this.hint,
  });

  final String value;
  final void Function(String) onSubmitted;
  final bool numeric;
  final bool mono;
  final bool enabled;
  final int? maxLength;
  final String? hint;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _controller.text != widget.value) widget.onSubmitted(_controller.text);
    });
  }

  @override
  void didUpdateWidget(_TextField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.enabled,
        maxLength: widget.maxLength,
        keyboardType: widget.numeric ? const TextInputType.numberWithOptions(signed: true, decimal: true) : null,
        style: widget.mono ? monoStyle(context, size: 13) : null,
        decoration: InputDecoration(isDense: true, counterText: '', hintText: widget.hint),
        onSubmitted: widget.onSubmitted,
      );
}
