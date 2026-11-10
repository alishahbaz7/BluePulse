import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A folder for files people keep: `Documents\BluePulse\<name>` on Windows, where they can find them;
/// the app's own documents folder on Android (shared from there through the share sheet).
Future<Directory> appFilesDir(String name) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(Platform.isWindows ? p.join(docs.path, 'BluePulse', name) : p.join(docs.path, name));
  await dir.create(recursive: true);
  return dir;
}
