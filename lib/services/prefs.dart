import 'package:shared_preferences/shared_preferences.dart';

/// Thin persistence layer over SharedPreferences.
///
/// Every method reads a fresh instance so it works identically from the UI
/// isolate and the WorkManager background isolate.
class Prefs {
  Prefs._();

  static const _kOnboarded = 'onboarded';
  static const _kGoalMinutes = 'goal_minutes';
  static const _kNotifEnabled = 'notif_enabled';

  // Per-day guard so each threshold alert fires at most once.
  static const _kNotifDate = 'notif_date';
  static const _kFiredHalf = 'fired_half';
  static const _kFiredHourLeft = 'fired_hour_left';
  static const _kFiredLimit = 'fired_limit';

  static Future<bool> isOnboarded() async =>
      (await SharedPreferences.getInstance()).getBool(_kOnboarded) ?? false;

  static Future<void> setOnboarded(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kOnboarded, v);

  /// Daily screen-time limit goal in minutes (default 2h).
  static Future<int> goalMinutes() async =>
      (await SharedPreferences.getInstance()).getInt(_kGoalMinutes) ?? 120;

  static Future<void> setGoalMinutes(int m) async =>
      (await SharedPreferences.getInstance()).setInt(_kGoalMinutes, m);

  static Future<bool> notificationsEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_kNotifEnabled) ?? true;

  static Future<void> setNotificationsEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kNotifEnabled, v);

  /// Returns which threshold alerts have already fired today, resetting the
  /// guard when the day rolls over.
  static Future<({bool half, bool hourLeft, bool limit})> firedFlags() async {
    final p = await SharedPreferences.getInstance();
    final today = _todayKey();
    if (p.getString(_kNotifDate) != today) {
      await p.setString(_kNotifDate, today);
      await p.setBool(_kFiredHalf, false);
      await p.setBool(_kFiredHourLeft, false);
      await p.setBool(_kFiredLimit, false);
    }
    return (
      half: p.getBool(_kFiredHalf) ?? false,
      hourLeft: p.getBool(_kFiredHourLeft) ?? false,
      limit: p.getBool(_kFiredLimit) ?? false,
    );
  }

  static Future<void> markFired({bool? half, bool? hourLeft, bool? limit}) async {
    final p = await SharedPreferences.getInstance();
    if (half != null) await p.setBool(_kFiredHalf, half);
    if (hourLeft != null) await p.setBool(_kFiredHourLeft, hourLeft);
    if (limit != null) await p.setBool(_kFiredLimit, limit);
  }

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }
}
