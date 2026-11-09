import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bluepulse/update/installer.dart';
import 'package:bluepulse/update/manifest.dart';
import 'package:bluepulse/update/update_host.dart';
import 'package:path/path.dart' as p;

/// A temp folder, removed at the end of the test.
Directory tempDir(String prefix) => Directory.systemTemp.createTempSync('eye-$prefix-');

/// A Flutter Windows build folder with stand-in files.
Directory fakeFlutterBuild(Directory parent, String version) {
  final d = Directory(p.join(parent.path, 'build-$version'))..createSync(recursive: true);
  File(p.join(d.path, 'bluepulse.exe')).writeAsStringSync('app $version');
  File(p.join(d.path, 'flutter_windows.dll')).writeAsStringSync('engine');
  File(p.join(d.path, 'data', 'flutter_assets', 'AssetManifest.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync('{}');
  return d;
}

/// An install root with the given complete versions (and their stand-in programs).
InstallLayout fakeInstall(Directory parent, List<String> versions, {String? current, String launcher = 'launcher v1'}) {
  final root = Directory(p.join(parent.path, 'BluePulse'))..createSync(recursive: true);
  File(p.join(root.path, 'BluePulse.exe')).writeAsStringSync(launcher);
  for (final v in versions) {
    final dir = Directory(p.join(root.path, 'versions', 'BluePulse-v$v'))..createSync(recursive: true);
    File(p.join(dir.path, 'BluePulse-v$v.exe')).writeAsStringSync('app $v');
  }
  return InstallLayout(root,
      current: current == null ? null : Directory(p.join(root.path, 'versions', 'BluePulse-v$current')));
}

/// A zip with arbitrary entries.
List<int> zipOf(Map<String, String> entries) {
  final a = Archive();
  entries.forEach((name, content) => a.add(ArchiveFile.bytes(name, utf8.encode(content))));
  return ZipEncoder().encodeBytes(a);
}

/// Windows host over a temp install; records what the app asked of the platform.
class TestHost implements UpdateHost {
  TestHost(this.layout, {this.platform = UpdatePlatform.windows});

  @override
  final UpdatePlatform platform;
  @override
  final InstallLayout? layout;

  bool restarted = false;
  File? installerOpened;
  Uri? opened;

  @override
  Future<Directory> stagingDir() async => layout?.stagingDir ?? Directory(p.join(Directory.systemTemp.path, 'eye-apk'));
  @override
  Future<InstallResult> install(File zip, String version) async => installFromZip(zip.path, layout!.root.path, version);
  @override
  Future<void> restart() async => restarted = true;
  @override
  Future<void> openInstaller(File apk) async => installerOpened = apk;
  @override
  Future<void> openUrl(Uri url) async => opened = url;
  @override
  Future<List<String>> cleanup() async => layout == null ? const [] : cleanupVersions(layout!);
}
