import 'dart:io';
import 'package:usage_stats/usage_stats.dart';

/// Reads real device screen-time via Android's UsageStatsManager.
///
/// Only Android exposes this data to third-party apps; on other platforms the
/// methods degrade gracefully (permission reads as false, usage as 0).
class UsageService {
  UsageService._();

  static bool get isSupported => Platform.isAndroid;

  /// Whether the user has granted the special "usage access" permission.
  static Future<bool> hasPermission() async {
    if (!isSupported) return false;
    try {
      return await UsageStats.checkUsagePermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "Usage access" settings screen so the user can grant it.
  static Future<void> requestPermission() async {
    if (!isSupported) return;
    await UsageStats.grantUsagePermission();
  }

  /// Total foreground screen time since local midnight, in whole minutes.
  ///
  /// We sum each app's foreground time over today's window — the standard way
  /// to approximate "screen time" from UsageStatsManager.
  static Future<int> todayMinutes() async {
    if (!isSupported) return 0;
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final stats = await UsageStats.queryUsageStats(midnight, now);

      var totalMs = 0;
      for (final info in stats) {
        totalMs += int.tryParse(info.totalTimeInForeground ?? '0') ?? 0;
      }
      return (totalMs / 60000).round();
    } catch (_) {
      return 0;
    }
  }
}
