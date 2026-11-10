import 'dart:convert';
import 'dart:io';

import 'package:bluepulse/usage/usage_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// The HTTP layer against a real local server, answering as Supabase's REST endpoint does.
void main() {
  late HttpServer server;
  late List<HttpRequest> seen;
  late List<String> bodies;
  var status = 200;
  var answer = '{"ok": true}';

  setUp(() async {
    seen = [];
    bodies = [];
    status = 200;
    answer = '{"ok": true}';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      seen.add(req);
      bodies.add(await utf8.decoder.bind(req).join());
      req.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(answer);
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Uri url() => Uri.parse('http://127.0.0.1:${server.port}/rest/v1/rpc/usage_report');

  test('posts the report as JSON with the publishable key in apikey only', () async {
    final t = HttpUsageTransport(url: url(), key: 'sb_publishable_abc123', userAgent: 'BluePulse/1.0.0');
    final result = await t.send({'install': {'id': 'a' * 32}, 'sessions': [], 'events': []});
    expect(result, {'ok': true});
    final req = seen.single;
    expect(req.method, 'POST');
    expect(req.uri.path, '/rest/v1/rpc/usage_report');
    expect(req.headers.contentType?.mimeType, 'application/json');
    expect(req.headers.value('apikey'), 'sb_publishable_abc123');
    expect(req.headers.value(HttpHeaders.authorizationHeader), isNull, reason: 'a publishable key is not a JWT');
    expect(req.headers.value(HttpHeaders.userAgentHeader), 'BluePulse/1.0.0');
    expect(jsonDecode(bodies.single), {'install': {'id': 'a' * 32}, 'sessions': [], 'events': []});
  });

  test('a legacy anon key (a JWT) also goes in Authorization', () async {
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.c2lnbmF0dXJl';
    await HttpUsageTransport(url: url(), key: jwt, userAgent: 'x').send({});
    expect(seen.single.headers.value(HttpHeaders.authorizationHeader), 'Bearer $jwt');
    expect(seen.single.headers.value('apikey'), jwt);
  });

  test('a refused report is marked rejected and says why, without the request', () async {
    status = 400;
    answer = '{"code":"22023","message":"install.id is missing or not 32 hex digits"}';
    final t = HttpUsageTransport(url: url(), key: 'sb_publishable_secretish', userAgent: 'x');
    await expectLater(
      t.send({}),
      throwsA(isA<UsageSendException>()
          .having((e) => e.rejected, 'rejected', isTrue)
          .having((e) => e.message, 'message', 'HTTP 400 from 127.0.0.1: install.id is missing or not 32 hex digits')
          .having((e) => e.message, 'message', isNot(contains('secretish')))),
    );
  });

  test('a missing function or a bad key is kept for later, not dropped', () async {
    final t = HttpUsageTransport(url: url(), key: 'k', userAgent: 'x');
    for (final code in [401, 404, 500, 503]) {
      status = code;
      answer = '{"message":"nope"}';
      await expectLater(t.send({}), throwsA(isA<UsageSendException>().having((e) => e.rejected, 'rejected', isFalse)));
    }
  });

  test('no server: a short message, kept for later', () async {
    final port = server.port;
    await server.close(force: true);
    final t = HttpUsageTransport(url: Uri.parse('http://127.0.0.1:$port/x'), key: '', userAgent: 'x');
    await expectLater(
      t.send({}),
      throwsA(isA<UsageSendException>()
          .having((e) => e.message, 'message', 'No connection to 127.0.0.1')
          .having((e) => e.rejected, 'rejected', isFalse)),
    );
  });
}
