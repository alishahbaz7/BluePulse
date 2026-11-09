import 'dart:math';

import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';

class ChartPoint {
  const ChartPoint(this.time, this.value);
  final DateTime time;
  final double value;
}

class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.color,
    required this.points,
    this.width = 1.6,
    this.dots = false,
    this.unit = '',
    this.decimals = 0,
  });

  final String label;
  final Color color;
  final List<ChartPoint> points;
  final double width;
  final bool dots;
  final String unit;
  final int decimals;
}

/// A horizontal band behind the lines (proximity zones).
class ChartBand {
  const ChartBand(this.from, this.to, this.color, this.label);
  final double from;
  final double to;
  final Color color;
  final String label;
}

/// Time-series chart, hand-drawn: fixed height, fixed text size, and the full time window on the
/// axis even when only part of it has data. Lines break across gaps longer than [maxGap].
class TimeChart extends StatelessWidget {
  const TimeChart({
    super.key,
    required this.series,
    required this.end,
    this.window = const Duration(minutes: 10),
    this.height = 170,
    this.yMin,
    this.yMax,
    this.maxGap = const Duration(seconds: 30),
    this.bands = const [],
    this.minSpan = 0,
  });

  final List<ChartSeries> series;
  final DateTime end;
  final Duration window;
  final double height;
  final double? yMin;
  final double? yMax;
  final Duration maxGap;
  final List<ChartBand> bands;

  /// Smallest Y range shown, so a nearly flat series is not magnified into noise.
  final double minSpan;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 16, runSpacing: 4, children: [
        for (final s in series)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 14, height: 3, color: s.color),
            const SizedBox(width: 6),
            Text(s.label, style: TextStyle(fontSize: 12, color: t.dim)),
            if (s.points.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                '${s.points.last.value.toStringAsFixed(s.decimals)}${s.unit}',
                style: TextStyle(fontSize: 12, color: t.text, fontWeight: FontWeight.w600, fontFeatures: tabular),
              ),
            ],
          ]),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _TimeChartPainter(
            series: series,
            end: end,
            window: window,
            yMin: yMin,
            yMax: yMax,
            maxGap: maxGap,
            bands: bands,
            minSpan: minSpan,
            tokens: t,
          ),
        ),
      ),
    ]);
  }
}

class _TimeChartPainter extends CustomPainter {
  _TimeChartPainter({
    required this.series,
    required this.end,
    required this.window,
    required this.yMin,
    required this.yMax,
    required this.maxGap,
    required this.bands,
    required this.tokens,
    this.minSpan = 0,
  });

  final double minSpan;
  final List<ChartSeries> series;
  final DateTime end;
  final Duration window;
  final double? yMin;
  final double? yMax;
  final Duration maxGap;
  final List<ChartBand> bands;
  final AppTokens tokens;

  static const _left = 46.0;
  static const _bottom = 20.0;
  static const _top = 6.0;
  static const _right = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final start = end.subtract(window);
    final plot = Rect.fromLTRB(_left, _top, size.width - _right, size.height - _bottom);
    if (plot.width <= 10 || plot.height <= 10) return;

    // Y range from what is visible, unless fixed.
    var lo = double.infinity, hi = -double.infinity;
    for (final s in series) {
      for (final p in s.points) {
        if (p.time.isBefore(start)) continue;
        lo = min(lo, p.value);
        hi = max(hi, p.value);
      }
    }
    if (lo == double.infinity) {
      lo = yMin ?? 0;
      hi = yMax ?? 1;
    }
    lo = yMin ?? lo;
    hi = yMax ?? hi;
    final span = max(minSpan, 1e-9);
    if (hi - lo < span) {
      final mid = (hi + lo) / 2;
      lo = yMin ?? mid - span / 2;
      hi = yMax ?? lo + span;
      if (hi - lo < 1e-9) hi = lo + 1;
    }
    final ticks = _niceTicks(lo, hi, 4);
    lo = min(lo, ticks.first);
    hi = max(hi, ticks.last);

    double x(DateTime t) => plot.left + plot.width * (t.difference(start).inMilliseconds / window.inMilliseconds);
    double y(double v) => plot.bottom - plot.height * ((v - lo) / (hi - lo));

    final textStyle = TextStyle(fontSize: 11.5, color: tokens.muted, fontFeatures: tabular);

    // Bands.
    for (final b in bands) {
      final top = y(min(hi, max(b.from, b.to)));
      final bottom = y(max(lo, min(b.from, b.to)));
      if (bottom <= top) continue;
      canvas.drawRect(Rect.fromLTRB(plot.left, top, plot.right, bottom), Paint()..color = b.color);
    }

    // Horizontal grid + labels.
    final grid = Paint()
      ..color = tokens.line
      ..strokeWidth = 1;
    for (final v in ticks) {
      final yy = y(v);
      if (yy < plot.top - 0.5 || yy > plot.bottom + 0.5) continue;
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), grid);
      _text(canvas, _fmt(v, ticks), Offset(plot.left - 6, yy), textStyle, alignRight: true);
    }

    // Time axis: the whole window.
    final step = _timeStep(window);
    var tick = DateTime.fromMillisecondsSinceEpoch(
        (start.millisecondsSinceEpoch ~/ step.inMilliseconds + 1) * step.inMilliseconds);
    while (!tick.isAfter(end)) {
      final xx = x(tick);
      canvas.drawLine(Offset(xx, plot.bottom), Offset(xx, plot.bottom + 4), grid);
      _text(canvas, formatHm(tick), Offset(xx, plot.bottom + 12), textStyle, center: true);
      tick = tick.add(step);
    }
    canvas.drawLine(Offset(plot.left, plot.bottom), Offset(plot.right, plot.bottom), grid);

    // Lines.
    canvas.save();
    canvas.clipRect(plot.inflate(2));
    for (final s in series) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      DateTime? prev;
      for (final p in s.points) {
        if (p.time.isBefore(start.subtract(maxGap))) continue;
        final o = Offset(x(p.time), y(p.value));
        if (prev == null || p.time.difference(prev) > maxGap) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
        prev = p.time;
        if (s.dots) canvas.drawCircle(o, 1.8, Paint()..color = s.color);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  String _fmt(double v, List<double> ticks) {
    final step = ticks.length > 1 ? (ticks[1] - ticks[0]).abs() : 1.0;
    final decimals = step >= 1 ? 0 : (step >= 0.1 ? 1 : 2);
    return v.toStringAsFixed(decimals);
  }

  void _text(Canvas canvas, String s, Offset at, TextStyle style, {bool alignRight = false, bool center = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    var dx = at.dx;
    if (alignRight) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  static List<double> _niceTicks(double lo, double hi, int count) {
    final span = hi - lo;
    final raw = span / count;
    final mag = pow(10, (log(raw) / ln10).floor()).toDouble();
    final norm = raw / mag;
    final step = (norm < 1.5 ? 1 : norm < 3 ? 2 : norm < 7 ? 5 : 10) * mag;
    final first = (lo / step).floor() * step;
    final last = (hi / step).ceil() * step;
    return [for (var v = first; v <= last + step / 2; v += step) v];
  }

  static Duration _timeStep(Duration window) {
    final m = window.inMinutes;
    if (m <= 3) return const Duration(seconds: 30);
    if (m <= 6) return const Duration(minutes: 1);
    if (m <= 15) return const Duration(minutes: 2);
    if (m <= 35) return const Duration(minutes: 5);
    if (m <= 70) return const Duration(minutes: 10);
    return const Duration(minutes: 30);
  }

  @override
  bool shouldRepaint(covariant _TimeChartPainter old) => true;
}

/// Bars per bucket (readings per minute), the current bucket drawn lighter.
class BucketChart extends StatelessWidget {
  const BucketChart({super.key, required this.values, required this.end, this.height = 150});

  final List<int> values;
  final DateTime end;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _BucketPainter(values, end, context.tokens)),
      );
}

class _BucketPainter extends CustomPainter {
  _BucketPainter(this.values, this.end, this.tokens);

  final List<int> values;
  final DateTime end;
  final AppTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0, bottom = 20.0, top = 6.0;
    final plot = Rect.fromLTRB(left, top, size.width - 6, size.height - bottom);
    if (values.isEmpty || plot.width < 20) return;
    final maxV = max(1, values.reduce(max));
    final ticks = _TimeChartPainter._niceTicks(0, maxV.toDouble(), 3);
    final hi = ticks.last;
    final style = TextStyle(fontSize: 11.5, color: tokens.muted, fontFeatures: tabular);
    final grid = Paint()..color = tokens.line;
    for (final v in ticks) {
      final y = plot.bottom - plot.height * (v / hi);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final tp = TextPainter(text: TextSpan(text: v.round().toString(), style: style), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(plot.left - 6 - tp.width, y - tp.height / 2));
    }
    final slot = plot.width / values.length;
    final barW = max(2.0, slot * 0.68);
    for (var i = 0; i < values.length; i++) {
      final h = plot.height * (values[i] / hi);
      final current = i == values.length - 1;
      final paint = Paint()..color = current ? tokens.accent.withValues(alpha: 0.4) : tokens.accent;
      final x = plot.left + slot * i + (slot - barW) / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(x, plot.bottom - h, barW, h),
            topLeft: const Radius.circular(2), topRight: const Radius.circular(2)),
        paint,
      );
    }
    // Labels: every 5th minute.
    final firstMinute = end.subtract(Duration(minutes: values.length - 1));
    for (var i = 0; i < values.length; i++) {
      final t = firstMinute.add(Duration(minutes: i));
      if (t.minute % 5 != 0) continue;
      final tp = TextPainter(text: TextSpan(text: formatHm(t), style: style), textDirection: TextDirection.ltr)
        ..layout();
      final cx = plot.left + slot * i + slot / 2;
      tp.paint(canvas, Offset(cx - tp.width / 2, plot.bottom + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _BucketPainter old) => true;
}
