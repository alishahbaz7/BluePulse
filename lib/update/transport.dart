import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'installer.dart' show UpdateException;

/// Fetches the manifest and downloads release files.
abstract class UpdateTransport {
  Future<String> getText(Uri url);

  /// Streams [url] into [into] and returns the file's SHA-256 (lower-case hex), computed while it
  /// downloads. [onProgress] gets bytes received and the total when the server says it.
  Future<String> download(
    Uri url,
    File into, {
    void Function(int received, int? total)? onProgress,
    bool Function()? cancelled,
  });
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// `dart:io` HttpClient: follows GitHub's redirects to its file host, times out instead of hanging,
/// and identifies itself by app name and version only.
class HttpUpdateTransport implements UpdateTransport {
  HttpUpdateTransport({required this.userAgent});

  final String userAgent;

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 15)
    ..userAgent = userAgent;

  Future<HttpClientResponse> _get(HttpClient client, Uri url) async {
    try {
      final req = await client.getUrl(url);
      req.followRedirects = true;
      req.maxRedirects = 8;
      return await req.close().timeout(const Duration(seconds: 20));
    } on SocketException {
      throw UpdateException('No connection to ${url.host}');
    } on TlsException {
      throw UpdateException('Secure connection to ${url.host} failed');
    } on TimeoutException {
      throw UpdateException('${url.host} did not answer in time');
    } on HttpException {
      throw UpdateException('${url.host} closed the connection');
    }
  }

  String _status(HttpClientResponse r, Uri url) =>
      r.statusCode == 404 ? 'Not found on ${url.host} (HTTP 404)' : 'HTTP ${r.statusCode} from ${url.host}';

  /// Anything else the network or the server does, in words — so every failure reaches the service
  /// as an [UpdateException] and the app carries on with the version it has.
  static String _failure(Uri url, Object e) => switch (e) {
        SocketException() || HttpException() => 'Connection to ${url.host} was lost',
        TlsException() => 'Secure connection to ${url.host} failed',
        _ => 'Could not read from ${url.host} (${e.runtimeType})',
      };

  static Future<void> _discard(HttpClientResponse r) async {
    try {
      await r.drain<void>();
    } catch (_) {
      // The status says enough.
    }
  }

  @override
  Future<String> getText(Uri url) async {
    final client = _client();
    try {
      final r = await _get(client, url);
      if (r.statusCode != 200) {
        await _discard(r);
        throw UpdateException(_status(r, url));
      }
      return await r.transform(const Utf8Decoder(allowMalformed: true)).join().timeout(const Duration(seconds: 20));
    } on UpdateException {
      rethrow;
    } on TimeoutException {
      throw UpdateException('${url.host} stopped sending');
    } catch (e) {
      throw UpdateException(_failure(url, e));
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<String> download(
    Uri url,
    File into, {
    void Function(int received, int? total)? onProgress,
    bool Function()? cancelled,
  }) async {
    final client = _client();
    IOSink? out;
    try {
      final r = await _get(client, url);
      if (r.statusCode != 200) {
        await _discard(r);
        throw UpdateException(_status(r, url));
      }
      final total = r.contentLength >= 0 ? r.contentLength : null;
      into.parent.createSync(recursive: true);
      out = into.openWrite();
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      var received = 0;
      await for (final chunk in r.timeout(const Duration(seconds: 30))) {
        if (cancelled?.call() ?? false) throw UpdateException('Download cancelled');
        out.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      hasher.close();
      await out.flush();
      await out.close();
      out = null;
      if (total != null && received != total) {
        throw UpdateException('Download ended early (${received ~/ 1024} of ${total ~/ 1024} KB)');
      }
      return digest.value.toString();
    } on UpdateException {
      rethrow;
    } on FileSystemException {
      rethrow; // the service names the file it could not write
    } on TimeoutException {
      throw UpdateException('${url.host} stopped sending');
    } catch (e) {
      // A connection dropped mid-file is an HttpException, not a SocketException.
      throw UpdateException(_failure(url, e));
    } finally {
      try {
        await out?.close();
      } catch (_) {
        // The download failed already; the partial file is removed by the service.
      }
      client.close(force: true);
    }
  }
}
