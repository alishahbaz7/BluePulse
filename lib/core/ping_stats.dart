import 'dart:math' as math;

/// Ping figures for a time window. A ping is one advertising event (an advertisement plus its scan
/// response, repeats folded), so gaps match the beacon's advertising interval.
class PingStats {
  const PingStats({
    required this.pings,
    this.avg,
    this.min,
    this.max,
    this.last,
    this.jitter,
    this.expected,
    this.receivedPercent,
  });

  final int pings;
  final Duration? avg;
  final Duration? min;
  final Duration? max;

  /// The gap before the most recent ping.
  final Duration? last;

  /// Standard deviation of the gaps: how regular the pings are.
  final Duration? jitter;

  /// The advertising interval as estimated from all gaps seen (see [estimateInterval]).
  final Duration? expected;

  /// Pings heard against pings the estimated interval implies over the window, 0–100.
  final double? receivedPercent;

  static const empty = PingStats(pings: 0);

  /// [times]: every ping time known for the device, oldest first. [allGapsMs]: the device's recent
  /// gaps, for the interval estimate.
  static PingStats compute({
    required Iterable<DateTime> times,
    required List<int> allGapsMs,
    required DateTime now,
    required Duration window,
    required DateTime firstSeen,
  }) {
    final start = now.subtract(window);
    final inWindow = times.where((t) => !t.isBefore(start) && !t.isAfter(now)).toList();
    if (inWindow.isEmpty) return PingStats(pings: 0, expected: estimateInterval(allGapsMs));

    final gaps = <int>[
      for (var i = 1; i < inWindow.length; i++) inWindow[i].difference(inWindow[i - 1]).inMilliseconds,
    ];
    final expected = estimateInterval(allGapsMs);
    double? received;
    if (expected != null && expected.inMilliseconds > 0) {
      final spanStart = firstSeen.isAfter(start) ? firstSeen : start;
      final span = now.difference(spanStart).inMilliseconds;
      final due = span / expected.inMilliseconds;
      if (due >= 1) received = (inWindow.length / due * 100).clamp(0, 100).toDouble();
    }
    if (gaps.isEmpty) return PingStats(pings: inWindow.length, expected: expected, receivedPercent: received);

    final mean = gaps.reduce((a, b) => a + b) / gaps.length;
    final variance = gaps.map((g) => (g - mean) * (g - mean)).reduce((a, b) => a + b) / gaps.length;
    return PingStats(
      pings: inWindow.length,
      avg: Duration(milliseconds: mean.round()),
      min: Duration(milliseconds: gaps.reduce(math.min)),
      max: Duration(milliseconds: gaps.reduce(math.max)),
      last: Duration(milliseconds: gaps.last),
      jitter: Duration(milliseconds: math.sqrt(variance).round()),
      expected: expected,
      receivedPercent: received,
    );
  }

  /// The advertising interval: the 10th-percentile gap. Missed pings only ever make gaps longer
  /// (whole multiples of the interval), so the short end of the gaps is the interval itself. Needs
  /// five gaps or more.
  static Duration? estimateInterval(List<int> gapsMs) {
    final g = gapsMs.where((x) => x > 0).toList()..sort();
    if (g.length < 5) return null;
    return Duration(milliseconds: g[(g.length * 0.1).floor()]);
  }
}
