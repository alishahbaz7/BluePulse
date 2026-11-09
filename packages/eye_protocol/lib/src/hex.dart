import 'dart:typed_data';

final _separators = RegExp(r'[\s,:;\-_]+');
final _hexOnly = RegExp(r'^[0-9a-fA-F]*$');

/// Parses hex text into bytes.
///
/// Accepts the shapes people paste: `0A FF 9A 08`, `0a:ff:9a:08`, `0x0A 0xFF`, one long run, or
/// several lines. Throws [FormatException] on anything else.
Uint8List parseHex(String text) {
  final buf = StringBuffer();
  for (final token in text.trim().split(_separators)) {
    if (token.isEmpty) continue;
    var t = token;
    if (t.length > 2 && (t.startsWith('0x') || t.startsWith('0X'))) t = t.substring(2);
    buf.write(t);
  }
  final s = buf.toString();
  if (!_hexOnly.hasMatch(s)) {
    final bad = s.split('').firstWhere((c) => !_hexOnly.hasMatch(c));
    throw FormatException('Not hexadecimal: "$bad"', text);
  }
  if (s.length.isOdd) {
    throw FormatException('Odd number of hex digits (${s.length})', text);
  }
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return out;
}

/// Formats bytes as hex: `toHex([0x9a, 0x08])` → `9A08`, with [separator] between bytes.
String toHex(List<int> bytes, {String separator = '', bool upper = true}) {
  final parts = bytes.map((b) => b.toRadixString(16).padLeft(2, '0'));
  final s = parts.join(separator);
  return upper ? s.toUpperCase() : s;
}

/// `0x089A`-style label for a number, padded to [digits] hex digits.
String hexLabel(int value, {int digits = 2}) =>
    '0x${value.toRadixString(16).padLeft(digits, '0').toUpperCase()}';

/// Formats a 6-byte address as `AA:BB:CC:DD:EE:FF`.
String formatMac(List<int> bytes) => toHex(bytes, separator: ':');
