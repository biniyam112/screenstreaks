import 'dart:io';

import 'package:flutter/services.dart';

/// iOS Screen Time (Family Controls) bridge. All calls are no-ops off iOS.
class ScreenTime {
  ScreenTime._();

  static const _channel = MethodChannel('screenstreaks/screentime');

  static bool get supported => Platform.isIOS;

  static Future<bool> requestAuthorization() async {
    if (!supported) return false;
    try {
      await _channel.invokeMethod('authorize');
      return true;
    } on PlatformException {
      return false;
    }
  }

  /// Opens Apple's picker so the user chooses which apps count.
  /// Opens Apple's picker. Returns the number of individual apps chosen —
  /// categories alone don't reliably trigger thresholds, so a zero here
  /// means tracking won't work and the caller should say so.
  static Future<int> pickApps() async {
    if (!supported) return 0;
    try {
      final result = await _channel.invokeMethod('pickApps');
      final match = RegExp(r'^(\d+) apps').firstMatch('$result');
      return int.tryParse(match?.group(1) ?? '') ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  static Future<bool> hasSelection() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod('hasSelection') as bool? ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Minutes the current monitor is watching for, or 0 if not monitoring.
  static Future<int> activeLimit() async {
    if (!supported) return 0;
    try {
      return await _channel.invokeMethod('activeLimit') as int? ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  static Future<bool> startMonitoring(int limitMinutes) async {
    if (!supported) return false;
    try {
      await _channel.invokeMethod('startProbe', limitMinutes);
      return true;
    } on PlatformException {
      return false;
    }
  }

  /// Days the monitor extension has recorded but Dart hasn't consumed.
  /// Keys are 'yyyy-MM-dd'; values are true when the day stayed under.
  static Future<Map<String, bool>> pendingOutcomes() async {
    if (!supported) return const {};
    try {
      final raw = await _channel.invokeMethod('readPending');
      if (raw is! Map) return const {};
      return raw.map((k, v) => MapEntry('$k', v == true));
    } on PlatformException {
      return const {};
    }
  }

  static Future<void> clearPending(List<String> days) async {
    if (!supported || days.isEmpty) return;
    try {
      await _channel.invokeMethod('clearPending', days);
    } on PlatformException {
      // Next launch will retry — checkIn overwrites by day, so that's harmless.
    }
  }

  /// 'yyyy-MM-dd' → DateTime, or null if malformed.
  static DateTime? parseDay(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  /// Days monitoring only partly covered — recorded, but not judged.
  static Future<List<String>> partialDays() async {
    if (!supported) return const [];
    try {
      final raw = await _channel.invokeMethod('readPartials');
      return (raw as List?)?.map((e) => '$e').toList() ?? const [];
    } on PlatformException {
      return const [];
    }
  }

  static Future<void> clearPartials(List<String> days) async {
    if (!supported || days.isEmpty) return;
    try {
      await _channel.invokeMethod('clearPartials', days);
    } on PlatformException {
      // Retried next launch; writes are idempotent.
    }
  }

  /// Stop watching. The active limit drops to 0, so the indicator goes red.
  static Future<void> stopMonitoring() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('stop');
    } on PlatformException {
      // Already stopped, or the extension isn't registered.
    }
  }

  /// When the monitor extension last woke, or null if it never has.
  /// A live monitor that hasn't fired in days is broken, not quiet.
  static Future<DateTime?> lastCallback() async {
    if (!supported) return null;
    try {
      final secs = await _channel.invokeMethod('lastCallback');
      final v = (secs as num?)?.toDouble() ?? 0;
      if (v <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch((v * 1000).round());
    } on PlatformException {
      return null;
    }
  }

  /// True when monitoring claims to be running but nothing has come back for
  /// [days]. The interval callbacks alone should fire daily, so silence that
  /// long means the registration has gone stale.
  static Future<bool> looksStale({int days = 2}) async {
    if (!supported) return false;
    if (await activeLimit() <= 0) return false;
    final last = await lastCallback();
    if (last == null) return false;
    return DateTime.now().difference(last).inDays >= days;
  }

  /// When the current monitoring interval was registered.
  static Future<DateTime?> monitoringSince() async {
    if (!supported) return null;
    try {
      final secs = await _channel.invokeMethod('monitoringSince');
      final v = (secs as num?)?.toDouble() ?? 0;
      if (v <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch((v * 1000).round());
    } on PlatformException {
      return null;
    }
  }

  /// Shared container path. Widgets can't fetch URLs, so avatars are
  /// downloaded here and read from disk by the extension.
  static Future<String?> appGroupPath() async {
    if (!supported) return null;
    try {
      final path = await _channel.invokeMethod('appGroupPath') as String?;
      return (path == null || path.isEmpty) ? null : path;
    } on PlatformException {
      return null;
    }
  }

  /// Where today stands against the limit. iOS won't give us minutes, but
  /// it does tell us when the warning and the threshold were crossed.
  static Future<({int state, DateTime? warnedAt, DateTime? overAt})>
      dayState() async {
    if (!supported) return (state: 0, warnedAt: null, overAt: null);
    try {
      final raw = await _channel.invokeMethod('dayState');
      if (raw is! Map) return (state: 0, warnedAt: null, overAt: null);
      DateTime? at(String key) {
        final v = (raw[key] as num?)?.toDouble() ?? 0;
        if (v <= 0) return null;
        return DateTime.fromMillisecondsSinceEpoch((v * 1000).round());
      }

      return (
        state: (raw['state'] as num?)?.toInt() ?? 0,
        warnedAt: at('warnedAt'),
        overAt: at('overAt'),
      );
    } on PlatformException {
      return (state: 0, warnedAt: null, overAt: null);
    }
  }

  /// Ask iOS for notification permission directly. The Screen Time extension
  /// posts through UNUserNotificationCenter and inherits this.
  static Future<bool> authorizeNotifications() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod('authorizeNotifications') as bool? ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Write a line into the probe log from Dart.
  static Future<void> log(String message) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('appendLog', message);
    } on PlatformException {
      // Logging must never throw.
    }
  }

  /// Day key to the time its threshold fired, for spotting overnight misses.
  static Future<Map<String, DateTime>> overTimes() async {
    if (!supported) return const {};
    try {
      final raw = await _channel.invokeMethod('overTimes');
      if (raw is! Map) return const {};
      return {
        for (final e in raw.entries)
          '${e.key}': DateTime.fromMillisecondsSinceEpoch(
              (((e.value as num).toDouble()) * 1000).round()),
      };
    } on PlatformException {
      return const {};
    }
  }

  /// A threshold crossed between 2 and 5am is a screen left on, not use.
  static bool looksLikeSleep(DateTime at) => at.hour >= 2 && at.hour < 5;

  /// The 'yyyy-MM-dd' key the extension stores a day under.
  /// The 'yyyy-MM-dd' key the extension stores a day under.
  static String dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return y + '-' + m + '-' + day;
  }

  /// Days the overnight watcher flagged — an hour of use between 2 and 5am.
  static Future<List<String>> sleepFlags() async {
    if (!supported) return const [];
    try {
      final raw = await _channel.invokeMethod('sleepFlags');
      return (raw as List?)?.map((e) => '$e').toList() ?? const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Lines the monitor extension has written, newest first.
  static Future<List<String>> readLog() async {
    if (!supported) return const [];
    try {
      final raw = await _channel.invokeMethod('readLog');
      return (raw as List?)?.map((e) => '$e').toList() ?? const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Queue a limit for the extension to apply at the next midnight.
  static Future<void> setPendingLimit(int? minutes) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('setPendingLimit', minutes ?? 0);
    } on PlatformException {
      // The app applies it on next load as a fallback.
    }
  }

  /// How many apps and categories are being watched. Shown to friends so a
  /// selection of one app is visible rather than hidden.
  static Future<({int apps, int categories})> selectionCount() async {
    if (!supported) return (apps: 0, categories: 0);
    try {
      final raw = await _channel.invokeMethod('selectionCount');
      if (raw is! Map) return (apps: 0, categories: 0);
      return (
        apps: (raw['apps'] as num?)?.toInt() ?? 0,
        categories: (raw['categories'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException {
      return (apps: 0, categories: 0);
    }
  }
}
