/// Where usage reports go. Everything about the usage channel is spelled here, once.
///
/// The app sends one JSON document — `{install, sessions, events}` — by HTTPS POST to [url]. With
/// Supabase that is the `usage_report` function (`backend/supabase/usage.sql`); any server that
/// accepts the same JSON can replace it without touching the app beyond this URL.
abstract final class UsageConfig {
  /// Full address the reports are posted to: the BluePulse Supabase project (Mumbai), function
  /// `usage_report`. Every build carries it, as `UpdateConfig.repo` is carried;
  /// `--dart-define=USAGE_URL=…` points a build at another server. Empty means no reports.
  static const url = String.fromEnvironment(
    'USAGE_URL',
    defaultValue: 'https://zjudpkovgkavarcjxmmp.supabase.co/rest/v1/rpc/usage_report',
  );

  /// The project's *publishable* key, sent as `apikey`. Public by design — it ships inside the app
  /// and the source — and the server lets it write reports, never read them (checked against the
  /// live project: the `usage` schema is not served). Same override rule as [url].
  static const key = String.fromEnvironment('USAGE_KEY', defaultValue: 'sb_publishable_s5NBH9RdIC7-avJsjHc8jQ_TNFWjhw9');

  /// A development run reports only when it is pointed at a server on purpose, so the user list
  /// holds people, not the developer's every restart.
  static const passedAtBuild = bool.hasEnvironment('USAGE_URL');

  static bool get configured {
    final u = Uri.tryParse(url);
    return u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.isNotEmpty;
  }

  /// How often the open session is measured and saved on this device.
  static const tick = Duration(minutes: 1);

  /// How often reports are sent while the app is open (also at start, on close and on a name change).
  static const sendEvery = Duration(minutes: 5);

  /// While sends fail the gap doubles — 10, 20, then every 30 minutes at most — so a server that is
  /// down or a computer that is offline costs a few quick attempts an hour, not one every 5 minutes.
  static const retryAtMost = Duration(minutes: 30);

  /// The longest one send may take while the app runs, whatever the network does; then it has
  /// failed and the report waits for the next try. (Closing waits 3 seconds at most.)
  static const sendTimeout = Duration(seconds: 30);

  /// Events kept while offline; the oldest go first beyond this.
  static const maxQueuedEvents = 500;

  /// Sessions kept while offline; the oldest go first beyond this.
  static const maxQueuedSessions = 100;

  /// Events in one request, so a long offline spell goes out in several.
  static const maxEventsPerSend = 200;

  /// App errors reported per session, so a fault in a loop cannot flood the record.
  static const maxErrorsPerSession = 10;
}
