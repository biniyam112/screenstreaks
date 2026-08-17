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
  static const _kGroupLimit = 'group_limit_minutes';

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

  /// Shared group limit in minutes. Null until the group sets one.
  static Future<int?> groupLimitMinutes() async =>
      (await SharedPreferences.getInstance()).getInt(_kGroupLimit);

  static Future<void> setGroupLimitMinutes(int m) async =>
      (await SharedPreferences.getInstance()).setInt(_kGroupLimit, m);

  /// Per-group limit in minutes. Null until that group sets one.
  static Future<int?> groupLimit(String groupId) async =>
      (await SharedPreferences.getInstance()).getInt('group_limit_$groupId');

  static Future<void> setGroupLimit(String groupId, int m) async =>
      (await SharedPreferences.getInstance()).setInt('group_limit_$groupId', m);

  /// Which group the home-screen widget shows.
  static Future<String?> widgetGroupId() async =>
      (await SharedPreferences.getInstance()).getString('widget_group');

  static Future<void> setWidgetGroupId(String id) async =>
      (await SharedPreferences.getInstance()).setString('widget_group', id);

  /// True once the user has turned on Screen Time tracking. Survives app
  /// installs, unlike the app-group selection, so we can tell "declined"
  /// apart from "wiped by a reinstall".
  /// Group passes we've already told the user about, as 'groupId:day'.
  static Future<Set<String>> announcedPasses() async =>
      ((await SharedPreferences.getInstance())
              .getStringList('announced_passes') ??
          const [])
          .toSet();

  static Future<void> setAnnouncedPasses(Set<String> keys) async =>
      (await SharedPreferences.getInstance())
          // Keep it bounded — old entries can't be re-announced anyway.
          .setStringList('announced_passes', keys.toList().take(200).toList());

  /// Which account the running monitor belongs to. Counting against one
  /// person's limit and apps means nothing for anyone else.
  static Future<String?> monitorOwner() async =>
      (await SharedPreferences.getInstance()).getString('monitor_owner');

  static Future<void> setMonitorOwner(String? id) async {
    final p = await SharedPreferences.getInstance();
    if (id == null) {
      await p.remove('monitor_owner');
    } else {
      await p.setString('monitor_owner', id);
    }
  }

  /// A limit change waiting for midnight. Changing the limit mid-day would
  /// reset the threshold count, so today keeps the old one.
  static Future<int?> pendingGoal() async =>
      (await SharedPreferences.getInstance()).getInt('pending_goal');

  static Future<void> setPendingGoal(int? v) async {
    final p = await SharedPreferences.getInstance();
    if (v == null) {
      await p.remove('pending_goal');
      await p.remove('pending_goal_set_on');
    } else {
      await p.setInt('pending_goal', v);
      // The day it was queued — it applies once a midnight has passed.
      final now = DateTime.now();
      await p.setString('pending_goal_set_on',
          DateTime(now.year, now.month, now.day).toIso8601String());
    }
  }

  /// The day a pending limit was queued on, or null if none is waiting.
  static Future<DateTime?> pendingGoalSetOn() async {
    final raw =
        (await SharedPreferences.getInstance()).getString('pending_goal_set_on');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<bool> trackingEnabled() async =>
      (await SharedPreferences.getInstance()).getBool('tracking_enabled') ?? false;

  static Future<void> setTrackingEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool('tracking_enabled', v);

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
