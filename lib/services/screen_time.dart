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
  static Future<bool> pickApps() async {
    if (!supported) return false;
    try {
      await _channel.invokeMethod('pickApps');
      return true;
    } on PlatformException {
      return false;
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
}
