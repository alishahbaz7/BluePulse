import 'dart:io';

import 'package:bluepulse/core/error_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bluepulse_errors_'));
  tearDown(() => dir.deleteSync(recursive: true));

  List<String> lines(ErrorLog log) => log.file!.readAsLinesSync();

  test('one plain line per event, in words; what came before the file opened is kept', () async {
    final log = ErrorLog();
    log.warn('settings', 'Settings could not be read', error: const FileSystemException('locked'));
    await log.open(dir, header: 'BluePulse 1.0.1 · release · windows');
    log.warn('update', 'Update check failed', error: 'No connection to github.com');
    log.info('update', 'Version 1.0.2 is available');
    await log.flush();

    final text = lines(log).where((l) => l.isNotEmpty).toList();
    expect(text.first, startsWith('==== BluePulse 1.0.1 · release · windows · started '));
    expect(text[1], matches(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}  WARNING  settings   Settings could not be read: '));
    expect(text[2], endsWith('WARNING  update     Update check failed: No connection to github.com'));
    expect(text[3], endsWith('INFO     update     Version 1.0.2 is available'));
    expect(log.problems, 2, reason: 'information is not a problem');
    expect(log.file!.path, endsWith(ErrorLog.fileName));
  });

  test('an error nobody handled carries where it happened', () async {
    final log = ErrorLog();
    await log.open(dir, header: 'test');
    try {
      throw StateError('broken');
    } catch (e, stack) {
      log.error('app', e, stack: stack, context: 'while building DevicesPage');
    }
    await log.flush();
    final text = lines(log);
    final i = text.indexWhere((l) => l.contains('ERROR    app        while building DevicesPage: StateError: Bad state: broken'));
    expect(i, isNonNegative);
    expect(text[i + 1], startsWith('    #0'), reason: 'the top of the stack, indented under the line');
  });

  test('the same event again is counted, not written again', () async {
    final log = ErrorLog();
    await log.open(dir, header: 'test');
    for (var i = 0; i < 50; i++) {
      log.warn('scanner', 'Bluetooth state could not be read');
    }
    log.warn('scanner', 'Scan did not start');
    await log.flush();
    final text = lines(log);
    expect(text.where((l) => l.contains('Bluetooth state could not be read')), hasLength(1));
    expect(text, contains('    … 49 more times'));
    expect(text.last, endsWith('Scan did not start'));
    expect(log.problems, 51);
    expect(log.recent.first.repeats, 0, reason: 'written out, so not counted twice');
  });

  test('two files at most: past the limit the log moves to .1.log and starts again', () async {
    final log = ErrorLog(maxBytes: 400);
    await log.open(dir, header: 'test');
    for (var i = 0; i < 20; i++) {
      log.warn('log', 'Log rows not written, attempt $i');
    }
    await log.flush();
    final older = File('${dir.path}/BluePulse_errors.1.log');
    expect(older.existsSync(), isTrue);
    expect(log.file!.lengthSync(), lessThan(400));
    expect(older.lengthSync(), lessThan(800));
    expect(lines(log).last, endsWith('attempt 19'), reason: 'the newest always in the current file');
  });

  test('a folder it cannot write to costs nothing: the events stay in memory', () async {
    final log = ErrorLog();
    final blocked = File('${dir.path}/not-a-folder')..writeAsStringSync('x');
    await log.open(Directory(blocked.path), header: 'test');
    log.warn('files', 'Something');
    await expectLater(log.flush(), completes);
    expect(log.file, isNull);
    expect(log.recent.single.message, 'Something');
  });
}
