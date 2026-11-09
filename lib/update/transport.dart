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
    } on HandshakeException {
      throw UpdateException('Secure connection to ${url.host} failed');
    } on TimeoutException {
      throw UpdateException('${url.host} did not answer in time');
    } on HttpException {
      throw UpdateException('${url.host} closed the connection');
    }
  }

  String _status(HttpClientResponse r, Uri url) =>
      r.statusCode == 404 ? 'Not found on ${url.host} (HTTP 404)' : 'HTTP ${r.statusCode} from ${url.host}';

  @override
  Future<String> getText(Uri url) async {
    final client = _client();
    try {
      final r = await _get(client, url);
      if (r.statusCode != 200) {
        await r.drain<void>();
        throw UpdateException(_status(r, url));
      }
      return await r.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw UpdateException('${url.host} stopped sending');
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
        await r.drain<void>();
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
    } on TimeoutException {
      throw UpdateException('${url.host} stopped sending');
    } on SocketException {
      throw UpdateException('Connection to ${url.host} was lost');
    } finally {
      await out?.close();
      client.close(force: true);
    }
  }
}
