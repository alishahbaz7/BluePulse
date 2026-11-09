/// `major.minor.patch`, compared numerically. A build suffix (`+3`) and a leading `v` are ignored.
class SemVer implements Comparable<SemVer> {
  const SemVer(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final _pattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$');

  static SemVer? tryParse(String? text) {
    final m = _pattern.firstMatch(text?.trim() ?? '');
    if (m == null) return null;
    return SemVer(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  static SemVer parse(String text) =>
      tryParse(text) ?? (throw FormatException('Not a version (expected 1.2.3)', text));

  @override
  int compareTo(SemVer o) {
    if (major != o.major) return major.compareTo(o.major);
    if (minor != o.minor) return minor.compareTo(o.minor);
    return patch.compareTo(o.patch);
  }

  bool operator >(SemVer o) => compareTo(o) > 0;
  bool operator <(SemVer o) => compareTo(o) < 0;
  bool operator >=(SemVer o) => compareTo(o) >= 0;

  @override
  bool operator ==(Object other) => other is SemVer && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
