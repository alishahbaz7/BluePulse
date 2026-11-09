import 'dart:math';

/// Exponential RSSI smoothing that mirrors the tracker's *averaging timeout*: the smoothed value is
/// ~95 % of the way to a new level once [timeoutSeconds] have passed (time constant = timeout / 3).
class RssiSmoother {
  RssiSmoother(this.timeoutSeconds);

  int timeoutSeconds;
  double? value;
  DateTime? _at;

  double add(int rssi, DateTime at) {
    final prev = value;
    final last = _at;
    _at = at;
    if (prev == null || last == null || timeoutSeconds <= 0) return value = rssi.toDouble();
    final dt = at.difference(last).inMilliseconds / 1000.0;
    if (dt <= 0) return prev;
    final tau = timeoutSeconds / 3.0;
    final alpha = 1 - exp(-dt / tau);
    return value = prev + (rssi - prev) * alpha;
  }
}

enum Proximity { near, away, lost }

extension ProximityLabel on Proximity {
  String get label => switch (this) {
        Proximity.near => 'Near',
        Proximity.away => 'Away',
        Proximity.lost => 'Lost',
      };
}

/// Sorts a smoothed RSSI into the tracker's zones; a device not seen is Lost.
Proximity classifyProximity(double? smoothed, {required int nearDbm, required int awayDbm, bool notSeen = false}) {
  if (notSeen || smoothed == null) return Proximity.lost;
  if (smoothed >= nearDbm) return Proximity.near;
  if (smoothed >= awayDbm) return Proximity.away;
  return Proximity.lost;
}

/// Log-distance estimate in metres: `10 ^ ((txPower1m − rssi) / (10 · n))`.
double? estimateDistance(double? rssi, int? txPower1m, double n) {
  if (rssi == null || txPower1m == null || n <= 0) return null;
  return pow(10, (txPower1m - rssi) / (10 * n)).toDouble();
}

/// Median of a list of ints, or null when empty.
int? median(List<int> values) {
  if (values.isEmpty) return null;
  final s = [...values]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : ((s[m - 1] + s[m]) / 2).round();
}
