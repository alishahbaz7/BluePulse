import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// Icons for what a device reports, so a card is read at a glance instead of label by label: signal
/// bars, battery level, temperature, humidity, movement, magnet. Each carries its meaning as a
/// hold-tip.

/// Four bars for a signal strength, filled and coloured by how strong it is.
class SignalBars extends StatelessWidget {
  const SignalBars(this.rssi, {super.key, this.size = 16});

  final int? rssi;
  final double size;

  /// 4 at -60 dBm or stronger, then one fewer every 10 dB; 0 when unknown.
  static int barsFor(int? rssi) => switch (rssi) {
        null => 0,
        >= -60 => 4,
        >= -70 => 3,
        >= -80 => 2,
        >= -90 => 1,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bars = barsFor(rssi);
    final on = switch (bars) { >= 3 => t.ok, 2 => t.warn, _ => t.bad };
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BarsPainter(bars, on, t.line)),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.bars, this.on, this.off);
  final int bars;
  final Color on;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 4;
    for (var i = 0; i < 4; i++) {
      final h = size.height * (i + 1) / 4;
      final r = RRect.fromLTRBR(i * w + w * 0.15, size.height - h, (i + 1) * w - w * 0.15, size.height, const Radius.circular(1));
      canvas.drawRRect(r, Paint()..color = i < bars ? on : off);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.bars != bars || old.on != on || old.off != off;
}

/// A horseshoe magnet: red tips when a magnet is detected, grey when not.
class MagnetIcon extends StatelessWidget {
  const MagnetIcon({super.key, required this.detected, this.size = 16});

  final bool detected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MagnetPainter(detected ? t.bad : t.muted, detected ? t.text : t.muted)),
    );
  }
}

class _MagnetPainter extends CustomPainter {
  _MagnetPainter(this.tips, this.body);
  final Color tips;
  final Color body;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.22;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = body;
    final r = (s - stroke) / 2;
    final c = Offset(s / 2, s * 0.62 - stroke / 2);
    // The U: a half circle at the bottom and two legs up.
    canvas.drawArc(Rect.fromCircle(center: c, radius: r - stroke / 2), 0, math.pi, false, paint);
    final leftX = c.dx - (r - stroke / 2);
    final rightX = c.dx + (r - stroke / 2);
    canvas.drawLine(Offset(leftX, c.dy), Offset(leftX, s * 0.28), paint);
    canvas.drawLine(Offset(rightX, c.dy), Offset(rightX, s * 0.28), paint);
    final tip = paint..color = tips;
    canvas.drawLine(Offset(leftX, s * 0.28), Offset(leftX, s * 0.05), tip);
    canvas.drawLine(Offset(rightX, s * 0.28), Offset(rightX, s * 0.05), tip);
  }

  @override
  bool shouldRepaint(_MagnetPainter old) => old.tips != tips || old.body != body;
}

/// The battery icon for a voltage (EYE devices run on a 3 V cell): full down to one bar, and the
/// alert icon when the device set its low-battery flag.
IconData batteryIcon(int? mv, {bool low = false}) {
  if (low) return Icons.battery_alert;
  return switch (mv) {
    null => Icons.battery_unknown,
    >= 2950 => Icons.battery_full,
    >= 2850 => Icons.battery_5_bar,
    >= 2750 => Icons.battery_4_bar,
    >= 2650 => Icons.battery_3_bar,
    >= 2550 => Icons.battery_2_bar,
    _ => Icons.battery_1_bar,
  };
}

/// An icon and its value — no label; the label is the hold-tip.
class ValueChip extends StatelessWidget {
  const ValueChip({super.key, required this.icon, required this.value, required this.tip, this.unit, this.color});

  final Widget icon;
  final String value;
  final String? unit;
  final String tip;

  /// The value's colour (a warning), when not the text colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return HoldTip(
      message: tip,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        icon,
        const SizedBox(width: 4),
        Text.rich(TextSpan(children: [
          TextSpan(
            text: value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color ?? t.text, fontFeatures: tabular),
          ),
          if (unit != null) TextSpan(text: unit, style: TextStyle(fontSize: 12.5, color: t.dim, fontFeatures: tabular)),
        ])),
      ]),
    );
  }
}

/// A dot for how fresh a device's data is: green while it is heard, grey once it has gone quiet.
class FreshDot extends StatelessWidget {
  const FreshDot({super.key, required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = live ? t.ok : t.muted;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: live ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 4)] : null,
      ),
    );
  }
}
