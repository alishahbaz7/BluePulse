import 'dart:convert';
import 'dart:math';

import 'usage_config.dart';

/// A random 128-bit identifier as 32 lower-case hex digits.
String newUsageId([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

bool isUsageId(String? id) => id != null && RegExp(r'^[0-9a-f]{32}$').hasMatch(id);

String? _clip(String? s, int max) {
  final v = s?.trim();
  if (v == null || v.isEmpty) return null;
  return v.length <= max ? v : v.substring(0, max);
}

/// Who and what this copy is. Sent with every report; the server keeps the latest.
class InstallInfo {
  const InstallInfo({
    required this.id,
    required this.app,
    required this.platform,
    required this.appVersion,
    required this.build,
    this.name = '',
    this.login,
    this.computer,
    this.os,
    this.device,
    this.launcher,
    this.timeZone,
  });

  /// Created at the first start and kept in the app's settings, so it survives updates.
  final String id;

  /// Which application this is (`BluePulse`): one usage server serves every app, so the user list
  /// can be read per app.
  final String app;

  /// As the person typed it at the first start (Settings → Usage reporting changes it).
  final String name;

  /// Windows sign-in (`DOMAIN\user` on a domain PC) and computer name; null on a phone.
  final String? login;
  final String? computer;

  /// `windows`, `android`.
  final String platform;
  final String? os;

  /// Phone maker and model; null on Windows.
  final String? device;
  final String appVersion;

  /// `release`, `profile` or `debug`.
  final String build;

  /// Windows: started through the launcher install, so it can update itself.
  final bool? launcher;
  final String? timeZone;

  InstallInfo withName(String name) => InstallInfo(
        id: id,
        app: app,
        name: name,
        login: login,
        computer: computer,
        platform: platform,
        os: os,
        device: device,
        appVersion: appVersion,
        build: build,
        launcher: launcher,
        timeZone: timeZone,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'app': app,
        'name': _clip(name, 120),
        'login': _clip(login, 120),
        'computer': _clip(computer, 120),
        'platform': platform,
        'os': _clip(os, 120),
        'device': _clip(device, 120),
        'appVersion': appVersion,
        'build': build,
        'launcher': launcher,
        'timeZone': _clip(timeZone, 60),
      };
}

/// One start of the app, measured while it runs. Each report carries the latest snapshot; the
/// server keeps the newest one per [id].
class SessionRecord {
  SessionRecord({
    required this.id,
    required this.startedAt,
    required this.appVersion,
    DateTime? lastActiveAt,
    this.endedAt,
    this.open = Duration.zero,
    Map<String, int>? pages,
    this.errors = 0,
    this.metrics = const {},
  })  : lastActiveAt = lastActiveAt ?? startedAt,
        pages = pages ?? {};

  final String id;
  final DateTime startedAt;
  final String appVersion;

  /// The last moment the app was known to be running.
  DateTime lastActiveAt;

  /// Set when the app was closed normally; null when it was killed or is still open.
  DateTime? endedAt;

  /// Time on screen (not minimised, not in the background).
  Duration open;

  /// Times each page was opened, by page name.
  final Map<String, int> pages;

  /// App errors this session (all of them, though only the first few are reported in full).
  int errors;

  /// The app's own counters (see `UsageMetrics`), under its own names.
  Map<String, Object?> metrics;

  Map<String, Object?> toJson() => {
        'id': id,
        'appVersion': appVersion,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'lastActiveAt': lastActiveAt.toUtc().toIso8601String(),
        'endedAt': endedAt?.toUtc().toIso8601String(),
        'openSeconds': open.inSeconds,
        'pages': Map.of(pages),
        'errors': errors,
        'metrics': Map.of(metrics),
      };
}

/// Something that happened, reported once (the server ignores an [id] it already has).
class UsageEvent {
  const UsageEvent({required this.id, required this.sessionId, required this.at, required this.kind, this.data = const {}});

  final String id;
  final String sessionId;
  final DateTime at;

  /// `first_start`, `version_changed`, `update_offered`, `update_postponed`, `update_started`,
  /// `update_installed`, `update_failed`, `update_check_failed`, `error`.
  final String kind;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'at': at.toUtc().toIso8601String(),
        'kind': kind,
        'data': data,
      };
}

/// Reports not yet sent, kept on the device: session snapshots by id (the newest replaces the
/// older) and events in order. Bounded, oldest first out, so a copy offline for months cannot
/// grow without limit.
class Outbox {
  Outbox({Map<String, Map<String, Object?>>? sessions, List<Map<String, Object?>>? events})
      : sessions = sessions ?? {},
        events = events ?? [];

  /// In the order they were last changed, oldest first.
  final Map<String, Map<String, Object?>> sessions;
  final List<Map<String, Object?>> events;

  bool get isEmpty => sessions.isEmpty && events.isEmpty;

  void putSession(SessionRecord s) {
    sessions.remove(s.id); // re-inserted at the end: most recently changed last
    sessions[s.id] = s.toJson();
    while (sessions.length > UsageConfig.maxQueuedSessions) {
      sessions.remove(sessions.keys.first);
    }
  }

  void addEvent(UsageEvent e) {
    events.add(e.toJson());
    if (events.length > UsageConfig.maxQueuedEvents) {
      events.removeRange(0, events.length - UsageConfig.maxQueuedEvents);
    }
  }

  /// After a send: drops what went out, except a session that changed while it was on its way.
  void acknowledge(Map<String, Map<String, Object?>> sentSessions, List<Map<String, Object?>> sentEvents) {
    for (final e in sentSessions.entries) {
      final now = sessions[e.key];
      if (now != null && jsonEncode(now) == jsonEncode(e.value)) sessions.remove(e.key);
    }
    final ids = {for (final e in sentEvents) e['id']};
    events.removeWhere((e) => ids.contains(e['id']));
  }

  String encode() => jsonEncode({'sessions': sessions.values.toList(), 'events': events});

  /// Reads what [encode] wrote; anything unreadable is dropped rather than blocking the queue.
  static Outbox decode(String? text) {
    final box = Outbox();
    if (text == null || text.isEmpty) return box;
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return box;
      for (final s in (json['sessions'] as List? ?? const [])) {
        if (s is Map<String, dynamic> && s['id'] is String) box.sessions[s['id'] as String] = s;
      }
      for (final e in (json['events'] as List? ?? const [])) {
        if (e is Map<String, dynamic> && e['id'] is String && e['kind'] is String) box.events.add(e);
      }
    } on FormatException {
      // A damaged queue is discarded; the next report starts a fresh one.
    }
    return box;
  }
}
