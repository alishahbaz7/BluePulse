/// Durations read like speech: "34 s", "6 min", "5 min 41 s", "1 h 2 min".
String formatDuration(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '$s s';
  final m = s ~/ 60;
  final rs = s % 60;
  if (m < 60) return rs == 0 ? '$m min' : '$m min $rs s';
  final h = m ~/ 60;
  final rm = m % 60;
  return rm == 0 ? '$h h' : '$h h $rm min';
}

/// "4 s ago", "2 min ago".
String formatAgo(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inMilliseconds < 1500) return 'now';
  return '${formatDuration(d)} ago';
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 24-hour local clock: "14:05:09".
String formatClock(DateTime t) {
  final l = t.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
}

/// "14:05:09.123".
String formatClockMs(DateTime t) =>
    '${formatClock(t)}.${t.toLocal().millisecond.toString().padLeft(3, '0')}';

/// "14:05".
String formatHm(DateTime t) {
  final l = t.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

/// DD-MM-YYYY HH:MM:SS, the house date order.
String formatDateTime(DateTime t, {bool utc = false}) {
  final l = utc ? t.toUtc() : t.toLocal();
  return '${_two(l.day)}-${_two(l.month)}-${l.year} ${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}'
      '${utc ? ' UTC' : ''}';
}

/// "5 s", "2.5 s", "800 ms".
String formatInterval(int? ms) {
  if (ms == null) return '—';
  if (ms < 1000) return '$ms ms';
  final s = ms / 1000;
  return s == s.roundToDouble() ? '${s.round()} s' : '${s.toStringAsFixed(1)} s';
}

/// A gap between pings: "850 ms", "4.98 s", "1 min 5 s".
String formatGap(Duration? d) {
  if (d == null) return '—';
  final ms = d.inMilliseconds;
  if (ms < 1000) return '$ms ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(2)} s';
  return formatDuration(d);
}

String formatDistance(double? m) {
  if (m == null) return '—';
  if (m < 10) return '≈ ${m.toStringAsFixed(1)} m';
  return '≈ ${m.round()} m';
}

/// "820 KB", "23.4 MB".
String formatBytes(int? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatCount(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
