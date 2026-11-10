// Checks that the usage server is set up, without storing anything on it.
//
//   dart run tool/usage_check.dart [--url <report address>] [--key <publishable key>]
//
// The address and key default to lib/usage/usage_config.dart. The check sends a report with no
// install ID, which a correctly set-up server must refuse with "install.id is missing…": that
// refusal proves the address, the key and backend/supabase/usage.sql are all in place, and nothing
// is written. Exit code 0 when ready, 1 when not, 64 when there is nothing to check.
import 'dart:io';

import 'package:bluepulse/usage/usage_config.dart';
import 'package:bluepulse/usage/usage_transport.dart';

/// What a failed check means, in words someone setting up the server can act on.
String diagnose(String message) {
  if (message.contains('HTTP 401') || message.contains('HTTP 403')) {
    return 'The key was refused. Copy the publishable key (or the legacy anon key) from Supabase → '
        'Project Settings → API keys.';
  }
  if (message.contains('HTTP 404')) {
    return 'The address answers, but usage_report is not there. Run backend/supabase/usage.sql in the '
        'SQL Editor, and check the address ends in /rest/v1/rpc/usage_report.';
  }
  if (message.startsWith('No connection') || message.contains('did not answer')) {
    return 'The server could not be reached. Check the project URL, the network, and whether the '
        'free project is paused (Supabase → the project → Restore).';
  }
  return 'Unexpected answer.';
}

Future<void> main(List<String> argv) async {
  String? opt(String name) {
    final i = argv.indexOf('--$name');
    return i >= 0 && i + 1 < argv.length ? argv[i + 1] : null;
  }

  final url = opt('url') ?? UsageConfig.url;
  final key = opt('key') ?? UsageConfig.key;
  final uri = Uri.tryParse(url);
  if (url.isEmpty || uri == null || !uri.hasScheme || uri.host.isEmpty) {
    stderr.writeln('No usage address: set the defaults in lib/usage/usage_config.dart, or pass --url and --key.');
    exit(64);
  }
  stdout.writeln('Checking $url');
  final t = HttpUsageTransport(url: uri, key: key, userAgent: 'BluePulse-usage-check');
  try {
    await t.send({'install': <String, Object?>{}, 'sessions': <Object?>[], 'events': <Object?>[]});
    stdout.writeln('NOT READY: the server accepted a report with no install ID, so this is not the '
        'usage_report function from backend/supabase/usage.sql.');
    exit(1);
  } on UsageSendException catch (e) {
    if (e.rejected && e.message.contains('install.id')) {
      stdout.writeln('READY: ${uri.host} answers, the key is accepted and usage_report is installed. '
          'Nothing was stored.');
      exit(0);
    }
    stdout.writeln('NOT READY: ${e.message}\n${diagnose(e.message)}');
    exit(1);
  }
}
