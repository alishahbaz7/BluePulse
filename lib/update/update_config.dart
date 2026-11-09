/// Where releases live and what they are called. Everything about the release channel is spelled
/// here, once.
///
/// Releases are published to a **public** GitHub repository that holds only release files (the
/// source can stay private), so the app needs no token. Each release carries `latest.json`, read
/// through GitHub's `releases/latest/download/` redirect — not the REST API, so no hourly limit.
abstract final class UpdateConfig {
  /// The release name prefix: `BluePulse-v1.2.0` for the zip, its version folder, the
  /// program inside it and the APK.
  static const appName = 'BluePulse';

  /// The stable launcher at the install root — the one program people pin; it never carries a version.
  static const launcherExe = 'BluePulse.exe';

  /// Version folders sit under this, beside the launcher.
  static const versionsDir = 'versions';

  /// `owner/repo` of the public releases repository. Set at build time with
  /// `--dart-define=UPDATE_REPO=owner/repo`, or change the default here once the repo exists.
  static const repo = String.fromEnvironment('UPDATE_REPO');

  /// Test and staging override: a full URL to a `latest.json` (e.g. on a local server).
  static const manifestOverride = String.fromEnvironment('UPDATE_MANIFEST_URL');

  static bool get configured => manifestOverride.isNotEmpty || RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(repo);

  static Uri get manifestUrl => manifestOverride.isNotEmpty
      ? Uri.parse(manifestOverride)
      : Uri.parse('https://github.com/$repo/releases/latest/download/latest.json');

  static Uri get releasesPage => manifestOverride.isNotEmpty
      ? Uri.parse(manifestOverride).resolve('.')
      : Uri.parse('https://github.com/$repo/releases/latest');

  static String releaseName(String version) => '$appName-v$version';
}
