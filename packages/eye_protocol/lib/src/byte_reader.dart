import 'dart:typed_data';

/// A read ran past the end of the input.
class TruncatedException implements Exception {
  TruncatedException(this.what, this.offset, this.needed, this.available);

  final String what;
  final int offset;
  final int needed;
  final int available;

  @override
  String toString() =>
      '$what: needs $needed byte${needed == 1 ? '' : 's'} at offset $offset, $available left';
}

/// Big-endian reader with bounds checks.
///
/// Uses only 32-bit `ByteData` accessors and composes 64-bit values arithmetically, so it also
/// runs when the app is compiled to JavaScript (where 64-bit `ByteData` getters do not exist).
class ByteReader {
  ByteReader(this.bytes, [this.pos = 0]) : _data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData _data;
  int pos;

  int get remaining => bytes.length - pos;
  bool has(int n) => remaining >= n;

  void _need(int n, String what) {
    if (remaining < n) throw TruncatedException(what, pos, n, remaining < 0 ? 0 : remaining);
  }

  int u8([String what = 'Byte']) {
    _need(1, what);
    return bytes[pos++];
  }

  int i8([String what = 'Byte']) {
    _need(1, what);
    return _data.getInt8(pos++);
  }

  int u16([String what = 'Value']) {
    _need(2, what);
    final v = _data.getUint16(pos, Endian.big);
    pos += 2;
    return v;
  }

  int i16([String what = 'Value']) {
    _need(2, what);
    final v = _data.getInt16(pos, Endian.big);
    pos += 2;
    return v;
  }

  int u32([String what = 'Value']) {
    _need(4, what);
    final v = _data.getUint32(pos, Endian.big);
    pos += 4;
    return v;
  }

  int i32([String what = 'Value']) {
    _need(4, what);
    final v = _data.getInt32(pos, Endian.big);
    pos += 4;
    return v;
  }

  /// Unsigned 64-bit; exact up to 2^53 on the web, which covers millisecond timestamps.
  int u64([String what = 'Value']) {
    _need(8, what);
    final hi = _data.getUint32(pos, Endian.big);
    final lo = _data.getUint32(pos + 4, Endian.big);
    pos += 8;
    return hi * 4294967296 + lo;
  }

  /// A copy of the next [n] bytes.
  Uint8List take(int n, [String what = 'Data']) {
    _need(n, what);
    final out = Uint8List.fromList(bytes.sublist(pos, pos + n));
    pos += n;
    return out;
  }

  /// A copy of everything left.
  Uint8List rest() {
    final out = Uint8List.fromList(bytes.sublist(pos));
    pos = bytes.length;
    return out;
  }
}
