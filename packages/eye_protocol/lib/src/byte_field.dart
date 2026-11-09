/// A labelled run of bytes, used by the packet inspector to name every byte.
class ByteField {
  const ByteField(this.offset, this.length, this.label, this.value);

  final int offset;
  final int length;
  final String label;
  final String value;

  int get end => offset + length;

  ByteField shift(int by) => ByteField(offset + by, length, label, value);

  @override
  String toString() => '[$offset+$length] $label = $value';
}
