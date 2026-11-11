import 'dart:convert';

import 'semver.dart';

enum UpdatePlatform { windows, android }

/// One downloadable file of a release.
class UpdateAsset {
  const UpdateAsset({required this.url, required this.file, required this.sha256, this.size});

  final Uri url;
  final String file;

  /// Lower-case hex SHA-256 of the file.
  final String sha256;
  final int? size;
}

/// `latest.json`, attached to every release:
///
/// ```json
/// {
///   "app": "BluePulse",
///   "version": "9.1.0",
///   "published": "2026-11-20T10:00:00Z",
///   "notes": "What changed and why",
///   "minimumVersion": "9.0.2",
///   "assets": {
///     "windows": {"file": "BluePulse-v9.1.0.zip", "url": "https://…", "sha256": "…", "size": 123},
///     "android": {"file": "BluePulse-v9.1.0.apk", "url": "https://…", "sha256": "…", "size": 456}
///   }
/// }
/// ```
///
/// `url` may be relative; it resolves against the manifest's own address. `minimumVersion` is
/// optional: a running version below it must update (used only for a critical fix).
class UpdateManifest {
  UpdateManifest({
    required this.app,
    required this.version,
    required this.notes,
    required this.assets,
    this.published,
    this.minimumVersion,
  });

  final String app;
  final SemVer version;
  final String notes;
  final DateTime? published;
  final SemVer? minimumVersion;
  final Map<UpdatePlatform, UpdateAsset> assets;

  /// Parses and validates; throws [FormatException] naming what is wrong.
  factory UpdateManifest.parse(String text, {required Uri base, required String expectedApp}) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const FormatException('latest.json is not valid JSON');
    }
    if (json is! Map<String, dynamic>) throw const FormatException('latest.json is not an object');

    // A value of the wrong type (a version written as a number) is a mistake in the file, said as one —
    // never a crash halfway through a check.
    String? str(Object? v) => v is String ? v : null;

    final app = json['app'];
    if (app != expectedApp) throw FormatException('latest.json is for "$app", not $expectedApp');
    final version = SemVer.tryParse(str(json['version']));
    if (version == null) throw FormatException('latest.json has no valid version: ${json['version']}');
    final minimum = json['minimumVersion'];
    final minVersion = minimum == null ? null : SemVer.tryParse(str(minimum));
    if (minimum != null && minVersion == null) {
      throw FormatException('latest.json has an invalid minimumVersion: $minimum');
    }

    final assets = <UpdatePlatform, UpdateAsset>{};
    final rawAssets = json['assets'];
    if (rawAssets is Map<String, dynamic>) {
      for (final p in UpdatePlatform.values) {
        final a = rawAssets[p.name];
        if (a is! Map<String, dynamic>) continue;
        final file = a['file'];
        final sha = str(a['sha256'])?.toLowerCase();
        if (file is! String || file.isEmpty || file.contains('/') || file.contains(r'\')) {
          throw FormatException('latest.json: ${p.name} asset has no valid file name');
        }
        if (sha == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
          throw FormatException('latest.json: ${p.name} asset has no valid sha256');
        }
        final url = a['url'] is String ? base.resolve(a['url'] as String) : base.resolve(file);
        if (url.scheme != 'https' && url.scheme != 'http') {
          throw FormatException('latest.json: ${p.name} asset URL is not http(s)');
        }
        final size = a['size'];
        assets[p] = UpdateAsset(url: url, file: file, sha256: sha, size: size is num ? size.toInt() : null);
      }
    }

    return UpdateManifest(
      app: app as String,
      version: version,
      notes: str(json['notes'])?.trim() ?? '',
      published: DateTime.tryParse(str(json['published']) ?? ''),
      minimumVersion: minVersion,
      assets: assets,
    );
  }

  bool isNewerThan(SemVer current) => version > current;

  /// True when [current] is below the release's minimum supported version.
  bool requires(SemVer current) => minimumVersion != null && current < minimumVersion!;
}
