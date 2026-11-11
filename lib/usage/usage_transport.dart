import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A report that did not reach the server.
class UsageSendException implements Exception {
  UsageSendException(this.message, {this.rejected = false});

  final String message;

  /// The server refused the report itself (HTTP 400 / 422): sending it again cannot succeed, so it
  /// is dropped rather than blocking every report after it.
  final bool rejected;

  @override
  String toString() => message;
}

/// Sends one usage report.
abstract class UsageTransport {
  /// Posts [report]; returns the server's answer (decoded JSON, or null) or throws
  /// [UsageSendException].
  Future<Object?> send(Map<String, Object?> report);
}

/// HTTPS POST of the report as JSON. The key goes in `apikey` (Supabase's gateway reads it there);
/// a legacy JWT-style key also goes in `Authorization`, as Supabase's own clients send it.
class HttpUsageTransport implements UsageTransport {
  HttpUsageTransport({required this.url, required this.key, required this.userAgent});

  final Uri url;
  final String key;
  final String userAgent;

  static bool _isJwt(String key) => RegExp(r'^eyJ[\w-]*\.[\w-]+\.[\w-]+$').hasMatch(key);

  @override
  Future<Object?> send(Map<String, Object?> report) async {
    final List<int> body;
    try {
      body = utf8.encode(jsonEncode(report));
    } catch (e) {
      // Sending it again cannot help: drop it rather than let it block every report after it.
      throw UsageSendException('The report could not be written (${e.runtimeType})', rejected: true);
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 15)
      ..userAgent = userAgent;
    try {
      final req = await client.postUrl(url);
      req.headers.contentType = ContentType.json;
      if (key.isNotEmpty) {
        req.headers.set('apikey', key);
        if (_isJwt(key)) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      }
      req.contentLength = body.length;
      req.add(body);
      final r = await req.close().timeout(const Duration(seconds: 20));
      // A proxy or Wi-Fi sign-in page may answer with anything; never fail on its characters.
      final text = await r.transform(const Utf8Decoder(allowMalformed: true)).join().timeout(const Duration(seconds: 20));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        try {
          return text.isEmpty ? null : jsonDecode(text);
        } on FormatException {
          return null;
        }
      }
      throw UsageSendException(
        'HTTP ${r.statusCode} from ${url.host}${_reason(text)}',
        rejected: r.statusCode == 400 || r.statusCode == 422,
      );
    } on UsageSendException {
      rethrow;
    } on SocketException {
      throw UsageSendException('No connection to ${url.host}');
    } on TlsException {
      throw UsageSendException('Secure connection to ${url.host} failed');
    } on TimeoutException {
      throw UsageSendException('${url.host} did not answer in time');
    } on HttpException {
      throw UsageSendException('${url.host} closed the connection');
    } catch (e) {
      // Whatever else the network does: kept, and tried again later.
      throw UsageSendException('Not sent to ${url.host} (${e.runtimeType})');
    } finally {
      client.close(force: true);
    }
  }

  /// The server's own short reason (PostgREST sends `{"message": …}`), never the request.
  static String _reason(String body) {
    try {
      final json = jsonDecode(body);
      final m = json is Map ? json['message'] : null;
      if (m is String && m.isNotEmpty) return ': ${m.length > 120 ? '${m.substring(0, 120)}…' : m}';
    } on FormatException {
      // Not JSON: say nothing more than the status.
    }
    return '';
  }
}
