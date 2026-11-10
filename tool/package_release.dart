// Packages a release: the Windows zip (launcher + version folder), the Android APK, and latest.json
// with SHA-256 checksums and the release notes from CHANGELOG.md.
//
//   dart run tool/package_release.dart [--build] [--minimum 1.0.2]
//
//   --repo owner/repo     releases repository (default: UpdateConfig.repo, alishahbaz7/BluePulse)
//   --build               run `flutter build windows` / `flutter build apk` first
//   --windows-build DIR   Flutter Windows output (default build/windows/x64/runner/Release)
//   --android-apk FILE    Flutter APK (default build/app/outputs/flutter-apk/app-release.apk)
//   --launcher FILE       launcher exe (default build/launcher/BluePulse.exe; built if missing)
//   --minimum X.Y.Z       versions below this must update (critical fixes only)
//   --out DIR             output folder (default dist)
//
// Output, all named for the version (BluePulse-v1.0.0):
//   dist/BluePulse-v1.0.0.zip   → BluePulse/BluePulse.exe (launcher)
//                                             BluePulse/versions/BluePulse-v1.0.0/…
//   dist/BluePulse-v1.0.0.apk
//   dist/latest.json
//   dist/notes.md
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bluepulse/update/update_config.dart';
import 'package:bluepulse/usage/usage_config.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

// Names come from the app's own release channel definition, so the tool and the app cannot disagree.
const appName = UpdateConfig.appName;
const launcherExe = UpdateConfig.launcherExe;
const installFolder = UpdateConfig.appName;
const flutterExe = 'bluepulse.exe';

String releaseName(String version) => '$appName-v$version';

/// `1.0.0` from `version: 1.0.0+1`.
String readVersion(String pubspec) {
  final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)', multiLine: true).firstMatch(pubspec);
  if (m == null) throw const FormatException('pubspec.yaml has no version');
  return m.group(1)!;
}

/// The body of `## <version>` in the changelog, up to the next `## `.
String changelogSection(String changelog, String version) {
  final lines = const LineSplitter().convert(changelog);
  final start = lines.indexWhere((l) => l.trim() == '## $version');
  if (start < 0) throw FormatException('CHANGELOG.md has no section "## $version"');
  final body = <String>[];
  for (final l in lines.skip(start + 1)) {
    if (l.startsWith('## ')) break;
    body.add(l);
  }
  return body.join('\n').trim();
}

String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

/// The Microsoft C++ runtime a Flutter Windows app links against. Bundled beside the program so a
/// fresh, locked-down PC runs BluePulse with nothing installed.
const vcRuntime = ['msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'];

/// The x64 runtime files from the newest Visual Studio redist folder, else System32; empty if neither
/// has all three.
List<File> findVcRuntime() {
  final vswhere = File(p.join(Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)',
      'Microsoft Visual Studio', 'Installer', 'vswhere.exe'));
  if (vswhere.existsSync()) {
    final r = Process.runSync(vswhere.path, ['-latest', '-products', '*', '-property', 'installationPath']);
    final redist = Directory(p.join((r.stdout as String).trim(), 'VC', 'Redist', 'MSVC'));
    if (redist.existsSync()) {
      final versions = redist.listSync().whereType<Directory>().toList()..sort((a, b) => b.path.compareTo(a.path));
      for (final v in versions) {
        final x64 = Directory(p.join(v.path, 'x64'));
        if (!x64.existsSync()) continue;
        for (final crt in x64.listSync().whereType<Directory>().where((d) => RegExp(r'Microsoft\.VC\d+\.CRT$').hasMatch(d.path))) {
          final files = [for (final n in vcRuntime) File(p.join(crt.path, n))];
          if (files.every((f) => f.existsSync())) return files;
        }
      }
    }
  }
  final system32 = p.join(Platform.environment['SystemRoot'] ?? r'C:\Windows', 'System32');
  final files = [for (final n in vcRuntime) File(p.join(system32, n))];
  return files.every((f) => f.existsSync()) ? files : const [];
}

/// The zip that both installs fresh (unzip, pin the launcher) and updates (the app takes the
/// version folder and, if changed, the launcher). [runtime] files go beside the program unless the
/// build already has them.
List<int> buildWindowsZip({
  required Directory flutterBuild,
  required File launcher,
  required String version,
  List<File> runtime = const [],
}) {
  final name = releaseName(version);
  final exe = File(p.join(flutterBuild.path, flutterExe));
  if (!exe.existsSync()) throw FileSystemException('Windows build not found', exe.path);
  final archive = Archive();
  archive.add(ArchiveFile.bytes('$installFolder/$launcherExe', launcher.readAsBytesSync()));
  archive.add(ArchiveFile.string('$installFolder/README.txt', _readme(version)));
  final added = <String>{};
  for (final f in flutterBuild.listSync(recursive: true).whereType<File>()) {
    var rel = p.relative(f.path, from: flutterBuild.path).replaceAll(r'\', '/');
    if (rel == flutterExe) rel = '$name.exe'; // the program carries the release name
    archive.add(ArchiveFile.bytes('$installFolder/versions/$name/$rel', f.readAsBytesSync()));
    added.add(rel.toLowerCase());
  }
  for (final f in runtime) {
    final n = p.basename(f.path);
    if (added.add(n.toLowerCase())) {
      archive.add(ArchiveFile.bytes('$installFolder/versions/$name/$n', f.readAsBytesSync()));
    }
  }
  return ZipEncoder().encodeBytes(archive);
}

String _readme(String version) => '''
BluePulse $version

Start BluePulse.exe — pin that one to the taskbar or Start.
It starts the newest version in the "versions" folder. When a new release is published the app
offers it on start; updating downloads it into "versions" and restarts.

Hold Shift while starting BluePulse.exe to choose an installed version.
Settings live in your Windows profile, so they carry over between versions.
''';

Map<String, Object?> asset(String file, List<int> bytes, String? repo, String version) => {
      'file': file,
      'url': repo == null ? file : 'https://github.com/$repo/releases/download/v$version/$file',
      'sha256': sha256Of(bytes),
      'size': bytes.length,
    };

String buildManifest({
  required String version,
  required String notes,
  required Map<String, Map<String, Object?>> assets,
  String? minimum,
  DateTime? published,
}) =>
    const JsonEncoder.withIndent('  ').convert({
      'app': appName,
      'version': version,
      'published': (published ?? DateTime.now()).toUtc().toIso8601String(),
      'notes': notes,
      'minimumVersion': ?minimum,
      'assets': assets,
    });

Future<int> _run(String exe, List<String> args) async {
  stdout.writeln('> $exe ${args.join(' ')}');
  final pr = await Process.start(exe, args, runInShell: true, mode: ProcessStartMode.inheritStdio);
  return pr.exitCode;
}

Future<void> main(List<String> argv) async {
  String? opt(String name) {
    final i = argv.indexOf('--$name');
    return i >= 0 && i + 1 < argv.length ? argv[i + 1] : null;
  }

  final String repo = opt('repo') ?? UpdateConfig.repo;
  final minimum = opt('minimum');
  final out = Directory(opt('out') ?? 'dist');
  final winBuild = Directory(opt('windows-build') ?? p.join('build', 'windows', 'x64', 'runner', 'Release'));
  final apk = File(opt('android-apk') ?? p.join('build', 'app', 'outputs', 'flutter-apk', 'app-release.apk'));
  final launcher = File(opt('launcher') ?? p.join('build', 'launcher', launcherExe));

  if (!RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(repo)) {
    stderr.writeln('--repo must be owner/repo');
    exit(64);
  }
  final version = readVersion(File('pubspec.yaml').readAsStringSync());
  final notes = changelogSection(File('CHANGELOG.md').readAsStringSync(), version);
  final name = releaseName(version);
  stdout.writeln('Packaging $name for github.com/$repo');
  // A copy released without the usage channel can never be monitored or controlled afterwards.
  stdout.writeln(UsageConfig.configured
      ? '  Usage reports go to ${Uri.parse(UsageConfig.url).host}'
      : '  WARNING: usage reporting is not set (lib/usage/usage_config.dart): copies of this release '
          'cannot be monitored or controlled, ever');

  if (argv.contains('--build')) {
    final define = repo == UpdateConfig.repo ? <String>[] : ['--dart-define=UPDATE_REPO=$repo'];
    if (await _run('flutter', ['build', 'windows', '--release', ...define]) != 0) {
      stderr.writeln('Windows build failed (needs Visual Studio "Desktop development with C++" and Developer Mode)');
    }
    if (!File(p.join('android', 'key.properties')).existsSync()) {
      stderr.writeln('Android skipped: android/key.properties (release signing key) is missing; '
          'a debug-signed APK must never be published');
    } else if (await _run('flutter', ['build', 'apk', '--release', ...define]) != 0) {
      stderr.writeln('Android build failed (needs the Android SDK)');
    }
  }
  if (!launcher.existsSync()) {
    await _run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', p.join('launcher', 'build.ps1')]);
  }

  out.createSync(recursive: true);
  final assets = <String, Map<String, Object?>>{};

  if (File(p.join(winBuild.path, flutterExe)).existsSync()) {
    final runtime = findVcRuntime();
    if (runtime.isEmpty) {
      stderr.writeln('  C++ runtime (${vcRuntime.join(', ')}) not found: PCs without it would not start the app');
      exit(1);
    }
    final zip = buildWindowsZip(flutterBuild: winBuild, launcher: launcher, version: version, runtime: runtime);
    File(p.join(out.path, '$name.zip')).writeAsBytesSync(zip);
    stdout.writeln('  C++ runtime bundled from ${p.dirname(runtime.first.path)}');
    assets['windows'] = asset('$name.zip', zip, repo, version);
    stdout.writeln('  $name.zip  ${(zip.length / 1048576).toStringAsFixed(1)} MB');
  } else {
    stdout.writeln('  Windows build missing at ${winBuild.path} — skipped');
  }

  if (apk.existsSync() && !File(p.join('android', 'key.properties')).existsSync()) {
    stdout.writeln('  Android APK skipped — no release signing key (android/key.properties)');
  } else if (apk.existsSync()) {
    final bytes = apk.readAsBytesSync();
    File(p.join(out.path, '$name.apk')).writeAsBytesSync(bytes);
    assets['android'] = asset('$name.apk', bytes, repo, version);
    stdout.writeln('  $name.apk  ${(bytes.length / 1048576).toStringAsFixed(1)} MB');
  } else {
    stdout.writeln('  Android APK missing at ${apk.path} — skipped');
  }

  if (assets.isEmpty) {
    stderr.writeln('Nothing to release.');
    exit(1);
  }

  File(p.join(out.path, 'latest.json')).writeAsStringSync(
      buildManifest(version: version, notes: notes, assets: assets, minimum: minimum));
  File(p.join(out.path, 'notes.md')).writeAsStringSync(notes);
  stdout.writeln('  latest.json, notes.md');

  final files = [
    for (final a in assets.values) p.join(out.path, a['file']! as String),
    p.join(out.path, 'latest.json'),
  ];
  stdout.writeln('\nPublish (needs the GitHub CLI, signed in):');
  stdout.writeln('  gh release create v$version ${files.join(' ')} '
      '--repo $repo --title "BluePulse $version" --notes-file ${p.join(out.path, 'notes.md')}');
}
