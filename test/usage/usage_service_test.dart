import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bluepulse/update/installer.dart' show UpdateException;
import 'package:bluepulse/update/manifest.dart';
import 'package:bluepulse/update/semver.dart';
import 'package:bluepulse/update/transport.dart';
import 'package:bluepulse/update/update_service.dart';
import 'package:bluepulse/usage/usage_config.dart';
import 'package:bluepulse/usage/usage_device.dart';
import 'package:bluepulse/usage/usage_model.dart';
import 'package:bluepulse/usage/usage_service.dart';
import 'package:bluepulse/usage/usage_store.dart';
import 'package:bluepulse/usage/usage_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import '../update/update_fixtures.dart' show TestHost;

/// Records every report; fails while [failWith] is set (with anything at all), and holds each send
/// until [hold] completes while it is set — a server that does not answer.
class FakeUsageTransport implements UsageTransport {
  final reports = <Map<String, Object?>>[];
  Object? failWith;
  Completer<void>? hold;

  /// Sends tried, whatever became of them.
  int calls = 0;

  @override
  Future<Object?> send(Map<String, Object?> report) async {
    calls++;
    // Round-trip through JSON, as the wire does, so the test sees exactly what the server would.
    final copy = jsonDecode(jsonEncode(report)) as Map<String, Object?>;
    if (hold != null) await hold!.future;
    if (failWith != null) throw failWith!;
    reports.add(copy);
    return {'ok': true};
  }

  List<Map<String, Object?>> get events => [for (final r in reports) ...(r['events']! as List).cast()];
  List<String> get kinds => [for (final e in events) e['kind']! as String];
}

/// The simplest app counters: how often and how long they were measured.
class CountingMetrics implements UsageMetrics {
  int ticks = 0;
  Duration total = Duration.zero;

  @override
  void measure(Duration elapsed) {
    ticks++;
    total += elapsed;
  }

  @override
  Map<String, Object?> toJson() => {'ticks': ticks, 'seconds': total.inSeconds};
}

const facts = DeviceFacts(platform: 'windows', os: 'Windows 11 Pro (build 26300)', login: 'MMI\\shahbaz', computer: 'GT2575');

class Rig {
  Rig({MemoryUsageStore? store}) : store = store ?? MemoryUsageStore();

  final MemoryUsageStore store;
  final transport = FakeUsageTransport();
  var now = DateTime.utc(2026, 11, 9, 10);
  final counters = CountingMetrics();

  late final service = UsageService(
    store: store,
    transport: transport,
    endpoint: Uri.parse('https://example.supabase.co/rest/v1/rpc/usage_report'),
    clock: () => now,
    random: Random(7),
  )..metrics = counters;

  Future<void> start({String version = '1.0.0'}) async {
    await service.start(app: 'BluePulse', appVersion: version, build: 'release', facts: facts, listenToLifecycle: false, timers: false);
    await pump();
  }

  void advance(Duration d) => now = now.add(d);
}

/// Lets fire-and-forget sends finish.
Future<void> pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('outbox', () {
    SessionRecord session(String id, {int minutes = 0}) =>
        SessionRecord(id: id, startedAt: DateTime.utc(2026), appVersion: '1.0.0')..open = Duration(minutes: minutes);

    test('keeps one snapshot per session, the latest', () {
      final box = Outbox();
      final s = session('a' * 32);
      box.putSession(s);
      s.open = const Duration(minutes: 5);
      box.putSession(s);
      expect(box.sessions, hasLength(1));
      expect(box.sessions['a' * 32]!['openSeconds'], 300);
    });

    test('is bounded, dropping the oldest first', () {
      final box = Outbox();
      for (var i = 0; i < UsageConfig.maxQueuedEvents + 20; i++) {
        box.addEvent(UsageEvent(id: i.toRadixString(16).padLeft(32, '0'), sessionId: 's', at: DateTime.utc(2026), kind: 'error'));
      }
      expect(box.events, hasLength(UsageConfig.maxQueuedEvents));
      expect(box.events.first['id'], 20.toRadixString(16).padLeft(32, '0'));
      for (var i = 0; i < UsageConfig.maxQueuedSessions + 3; i++) {
        box.putSession(session(i.toRadixString(16).padLeft(32, '0')));
      }
      expect(box.sessions, hasLength(UsageConfig.maxQueuedSessions));
      expect(box.sessions.keys.first, 3.toRadixString(16).padLeft(32, '0'));
    });

    test('a session that changed while it was being sent stays queued', () {
      final box = Outbox();
      final s = session('a' * 32);
      box.putSession(s);
      final sent = Map.of(box.sessions);
      s.open = const Duration(minutes: 1);
      box.putSession(s);
      box.acknowledge(sent, const []);
      expect(box.sessions, contains('a' * 32));
      box.acknowledge(Map.of(box.sessions), const []);
      expect(box.isEmpty, isTrue);
    });

    test('survives being written and read back; damage is discarded, not fatal', () {
      final box = Outbox()
        ..putSession(session('a' * 32, minutes: 3))
        ..addEvent(UsageEvent(id: 'b' * 32, sessionId: 'a' * 32, at: DateTime.utc(2026), kind: 'first_start'));
      final back = Outbox.decode(box.encode());
      expect(back.sessions['a' * 32]!['openSeconds'], 180);
      expect(back.events.single['kind'], 'first_start');
      expect(Outbox.decode('{not json').isEmpty, isTrue);
      expect(Outbox.decode('[1,2]').isEmpty, isTrue);
      expect(Outbox.decode('{"sessions":[{"x":1}],"events":[{"id":"e"}]}').isEmpty, isTrue);
    });
  });

  group('device facts', () {
    test('Windows 11 is named 11, though Windows calls itself 10', () {
      expect(windowsName('"Windows 10 Pro" 10.0 (Build 26300)'), 'Windows 11 Pro (build 26300)');
      expect(windowsName('"Windows 10 Enterprise" 10.0 (Build 19045)'), 'Windows 10 Enterprise (build 19045)');
      expect(windowsName('something else'), 'Windows');
    });

    test('ids are 32 hex digits and do not repeat', () {
      final r = Random(1);
      final ids = {for (var i = 0; i < 1000; i++) newUsageId(r)};
      expect(ids, hasLength(1000));
      expect(ids.every(isUsageId), isTrue);
      expect(isUsageId('XYZ'), isFalse);
    });
  });

  group('service', () {
    test('first start: a new install ID, the session and first_start go out at once', () async {
      final rig = Rig();
      await rig.start();
      final s = rig.service;
      expect(isUsageId(rig.store.read('installId')), isTrue);
      expect(s.needsName, isTrue);
      final report = rig.transport.reports.single;
      final install = report['install']! as Map;
      expect(install['id'], rig.store.read('installId'));
      expect(install['app'], 'BluePulse', reason: 'one usage server serves every app');
      expect(install['login'], 'MMI\\shahbaz');
      expect(install['computer'], 'GT2575');
      expect(install['appVersion'], '1.0.0');
      expect(install['name'], isNull, reason: 'not asked yet');
      expect((report['sessions']! as List).single['id'], s.session!.id);
      expect(rig.transport.kinds, ['first_start']);
      expect(s.lastSent, rig.now);
      expect(s.error, isNull);
      expect(s.waiting, 0);
    });

    test('the next start keeps the install ID and records an update that arrived', () async {
      final first = Rig();
      await first.start();
      final id = first.store.read('installId');
      first.service.dispose();

      final second = Rig(store: first.store);
      await second.start(version: '1.1.0');
      expect(second.service.install!.id, id);
      expect(second.transport.kinds, ['version_changed']);
      expect(second.transport.events.single['data'], {'from': '1.0.0', 'to': '1.1.0'});

      final third = Rig(store: first.store);
      await third.start(version: '1.1.0');
      expect(third.transport.kinds, isEmpty, reason: 'same version, nothing to say');
    });

    test('the name is asked once and sent, and nothing else is asked', () async {
      final rig = Rig();
      await rig.start();
      await rig.service.setName('  Shahbaz Khan ');
      await pump();
      expect(rig.service.needsName, isFalse);
      final install = rig.transport.reports.last['install']! as Map;
      expect(install['name'], 'Shahbaz Khan');
      expect(install.containsKey('team'), isFalse);

      final again = Rig(store: rig.store);
      await again.start();
      expect(again.service.needsName, isFalse);
      expect(again.service.install!.name, 'Shahbaz Khan');
    });

    test("measures time on screen and passes each tick to the app's own counters", () async {
      final rig = Rig();
      await rig.start();
      for (var i = 0; i < 3; i++) {
        rig.advance(const Duration(minutes: 1));
        rig.service.tick();
      }
      final session = rig.service.session!;
      expect(session.open, const Duration(minutes: 3));
      expect(session.metrics, {'ticks': 3, 'seconds': 180});
      expect(session.lastActiveAt, rig.now);
      await rig.service.flush();
      final sent = (rig.transport.reports.last['sessions']! as List).single as Map;
      expect(sent['metrics'], {'ticks': 3, 'seconds': 180});
      expect(sent.containsKey('liveSeconds'), isFalse, reason: "an app's counters travel only inside metrics");
    });

    test('a long gap between ticks (the computer asleep) counts as one tick at most', () async {
      final rig = Rig();
      await rig.start();
      rig.advance(const Duration(hours: 3));
      rig.service.tick();
      expect(rig.service.session!.open, UsageConfig.tick);
    });

    test('page opens are counted per page', () async {
      final rig = Rig();
      await rig.start();
      rig.service
        ..pageOpened('overview')
        ..pageOpened('decode')
        ..pageOpened('overview');
      expect(rig.service.session!.pages, {'overview': 2, 'decode': 1});
    });

    test('offline: reports wait on the device and go out with the next send', () async {
      final rig = Rig();
      rig.transport.failWith = UsageSendException('No connection to example.supabase.co');
      await rig.start();
      final s = rig.service;
      expect(s.error, 'No connection to example.supabase.co');
      expect(s.lastSent, isNull);
      s.record('update_offered', {'version': '1.1.0'});
      expect(s.waiting, 2);
      expect(Outbox.decode(rig.store.read('outbox')).events, hasLength(2), reason: 'saved, so a restart keeps them');

      rig.transport.failWith = null;
      await s.flush();
      expect(rig.transport.kinds, ['first_start', 'update_offered']);
      expect(s.waiting, 0);
      expect(s.error, isNull);
    });

    test('starts made offline are reported at the next start that reaches the server', () async {
      final first = Rig();
      first.transport.failWith = UsageSendException('No connection');
      await first.start();
      final offlineSession = first.service.session!.id;
      first.service.dispose();

      final second = Rig(store: first.store);
      await second.start();
      final sent = (second.transport.reports.single['sessions']! as List).map((s) => (s as Map)['id']).toSet();
      expect(sent, {offlineSession, second.service.session!.id});
    });

    test('a report the server refuses outright is dropped, so it cannot block the queue', () async {
      final rig = Rig();
      rig.transport.failWith = UsageSendException('HTTP 400 from example.supabase.co', rejected: true);
      await rig.start();
      expect(rig.service.waiting, 0);
      expect(rig.service.error, contains('dropped'));
    });

    test('the name never waits for the server: saved at once, sent when the server answers', () async {
      final rig = Rig();
      final hold = rig.transport.hold = Completer<void>();
      await rig.start();
      expect(rig.service.sending, isTrue, reason: 'the first report is still on its way');

      await rig.service.setName('Shahbaz').timeout(const Duration(seconds: 1));
      expect(rig.service.needsName, isFalse, reason: 'the welcome closes at once');
      expect(rig.store.read('name'), 'Shahbaz');

      hold.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((rig.transport.reports.last['install']! as Map)['name'], 'Shahbaz',
          reason: 'sent again once the first send was through');
    });

    test('a send that hangs gives up, keeps its reports and lets the next one through', () async {
      final rig = Rig();
      await rig.start();
      rig.service.record('export_done');
      final hold = rig.transport.hold = Completer<void>();
      await rig.service.flush(timeout: const Duration(milliseconds: 50));
      expect(rig.service.sending, isFalse, reason: 'never stuck: the next try is not blocked');
      expect(rig.service.error, contains('in time'));
      expect(rig.service.waiting, 1, reason: 'still on this device');
      expect(rig.service.failures, 1);
      hold.complete();
    });

    test('anything unexpected is caught: reports kept, nothing thrown into the app', () async {
      final rig = Rig();
      rig.transport.failWith = StateError('something nobody planned for');
      await rig.start();
      rig.service.record('export_done');
      await expectLater(rig.service.flush(), completes);
      expect(rig.service.error, contains('StateError'));
      expect(rig.service.waiting, 2);
      rig.transport.failWith = null;
      await rig.service.flush();
      expect(rig.transport.kinds, ['first_start', 'export_done']);
    });

    test('a server that is down is asked less and less often, and normally again once it answers', () async {
      final rig = Rig();
      rig.transport.failWith = UsageSendException('No connection');
      await rig.start();
      expect(rig.service.retryEvery, const Duration(minutes: 10));

      Future<int> tickAfter(int minutes) async {
        rig.advance(Duration(minutes: minutes));
        rig.service.tick();
        await pump();
        return rig.transport.calls;
      }

      expect(await tickAfter(6), 1, reason: 'not yet: 10 minutes after one failure');
      expect(await tickAfter(5), 2);
      expect(rig.service.retryEvery, const Duration(minutes: 20));
      expect(await tickAfter(21), 3);
      expect(rig.service.retryEvery, const Duration(minutes: 30), reason: 'at most every 30 minutes');
      expect(await tickAfter(31), 4);
      expect(rig.service.retryEvery, const Duration(minutes: 30));

      rig.transport.failWith = null;
      expect(await tickAfter(31), 5);
      expect(rig.service.failures, 0);
      expect(rig.service.retryEvery, UsageConfig.sendEvery);
      expect(rig.service.waiting, 0);
    });

    test('a long offline spell goes out in batches', () async {
      final rig = Rig();
      rig.transport.failWith = UsageSendException('No connection');
      await rig.start();
      for (var i = 0; i < UsageConfig.maxEventsPerSend + 50; i++) {
        rig.service.record('error', {'message': '$i'});
      }
      rig.transport.failWith = null;
      await rig.service.flush();
      expect(rig.transport.reports, hasLength(2));
      expect((rig.transport.reports.first['events']! as List), hasLength(UsageConfig.maxEventsPerSend));
      expect(rig.service.waiting, 0);
    });

    test('errors: all counted, the first few reported in full', () async {
      final rig = Rig();
      await rig.start();
      for (var i = 0; i < UsageConfig.maxErrorsPerSession + 5; i++) {
        rig.service.recordError(StateError('boom $i'), StackTrace.current);
      }
      await rig.service.flush();
      final errors = rig.transport.events.where((e) => e['kind'] == 'error').toList();
      expect(errors, hasLength(UsageConfig.maxErrorsPerSession));
      expect((errors.first['data']! as Map)['message'], 'StateError: Bad state: boom 0');
      expect((errors.first['data']! as Map)['stack'], isNotEmpty);
      expect(rig.service.session!.errors, UsageConfig.maxErrorsPerSession + 5);
    });

    test('closing ends the session and sends it', () async {
      final rig = Rig();
      await rig.start();
      rig.advance(const Duration(minutes: 1));
      await rig.service.end();
      final last = (rig.transport.reports.last['sessions']! as List).single as Map;
      expect(last['endedAt'], rig.now.toIso8601String());
      expect(last['openSeconds'], 60);
    });

    test('update offers, postponements and failed checks are recorded', () async {
      final rig = Rig();
      await rig.start();
      final ok = _ManifestTransport('{"app":"BluePulse","version":"1.1.0","notes":"","assets":{}}');
      final updates = UpdateService(
        current: SemVer.parse('1.0.0'),
        host: TestHost(null, platform: UpdatePlatform.android),
        transport: ok,
        manifestUrl: Uri.parse('https://example.com/latest.json'),
      );
      rig.service.watchUpdates(updates);
      await updates.check();
      ok.fail = true;
      final failing = UpdateService(
        current: SemVer.parse('1.0.0'),
        host: TestHost(null, platform: UpdatePlatform.android),
        transport: ok,
        manifestUrl: Uri.parse('https://example.com/latest.json'),
      );
      rig.service.watchUpdates(failing);
      await failing.check();
      await rig.service.flush();
      expect(rig.transport.kinds, containsAllInOrder(['update_offered', 'update_check_failed']));
      final offered = rig.transport.events.firstWhere((e) => e['kind'] == 'update_offered');
      expect(offered['data'], {'version': '1.1.0', 'required': false});
    });

    test('a disabled service does nothing and asks nothing', () async {
      final s = UsageService.disabled(disabledReason: 'Usage reporting is not set in this build');
      await s.start(app: 'BluePulse', appVersion: '1.0.0', build: 'release', facts: facts, listenToLifecycle: false, timers: false);
      s
        ..tick()
        ..pageOpened('overview')
        ..record('first_start')
        ..recordError(StateError('x'), null);
      await s.flush();
      expect(s.needsName, isFalse);
      expect(s.install, isNull);
      expect(s.waiting, 0);
    });
  });
}

class _ManifestTransport implements UpdateTransport {
  _ManifestTransport(this.text);

  final String text;
  bool fail = false;

  @override
  Future<String> getText(Uri url) async {
    if (fail) throw UpdateException('No connection to ${url.host}');
    return text;
  }

  @override
  Future<String> download(Uri url, File into, {void Function(int, int?)? onProgress, bool Function()? cancelled}) =>
      throw UnimplementedError();
}
