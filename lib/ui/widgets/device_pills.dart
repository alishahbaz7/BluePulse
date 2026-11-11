import 'package:flutter/material.dart';

import '../../core/device.dart';
import '../../core/signal.dart';
import 'common.dart';

/// EYE BEACON, EYE SENSOR, … as a coloured pill.
class ModelPill extends StatelessWidget {
  const ModelPill(this.model, {super.key});
  final DeviceModel model;

  @override
  Widget build(BuildContext context) => Pill(
        model.label,
        tone: switch (model) {
          DeviceModel.eyeBeacon => Tone.accent,
          DeviceModel.eyeSensor => Tone.ok,
          DeviceModel.eyeDevice => Tone.neutral,
          DeviceModel.otherBeacon => Tone.muted,
        },
      );
}

/// Near, Away or Lost as a coloured pill.
/// Re-exported for pages that show a proximity state.
class ProximityPill extends StatelessWidget {
  const ProximityPill(this.p, {super.key});
  final Proximity p;

  @override
  Widget build(BuildContext context) => Pill(
        p.label,
        tone: switch (p) {
          Proximity.near => Tone.ok,
          Proximity.away => Tone.warn,
          Proximity.lost => Tone.muted,
        },
      );
}
