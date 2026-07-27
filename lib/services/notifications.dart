import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'prefs.dart';
import '../theme.dart';

/// Local "you're approaching your limit" notifications.
class Notifications {
  Notifications._();

  static FlutterLocalNotificationsPlugin? _plugin;

  static FlutterLocalNotificationsPlugin get _instance {
    _plugin ??= FlutterLocalNotificationsPlugin();
    return _plugin!;
  }

  static const _channelId = 'screen_time_alerts';
  static const _channelName = 'Screen time alerts';

  static const _idHalf = 1;
  static const _idHourLeft = 2;
  static const _idLimit = 3;

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _instance.initialize(
      settings: const InitializationSettings(android: android),
    );

    // Pre-create the channel so importance is respected on Android 8+.
    final android8 = _instance.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android8?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Alerts as you approach your daily screen-time limit',
        importance: Importance.high,
      ),
    );
  }

  /// Ask for POST_NOTIFICATIONS (Android 13+). Safe to call repeatedly.
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    final android = _instance.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  static Future<void> _show(int id, String title, String body) async {
    await _instance.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  /// Core rule engine — shared by the foreground refresh and the background
  /// WorkManager task. Fires each threshold alert at most once per day.
  ///
  ///  - Half of the limit reached
  ///  - One hour of headroom left (only meaningful when the goal is > 1h)
  ///  - Limit reached
  static Future<void> evaluate({
    required int usedMinutes,
    required int goalMinutes,
  }) async {
    if (!await Prefs.notificationsEnabled()) return;
    if (goalMinutes <= 0) return;

    final flags = await Prefs.firedFlags();
    final half = goalMinutes ~/ 2;
    final hourLeftAt = goalMinutes - 60;

    if (usedMinutes >= goalMinutes && !flags.limit) {
      await _show(
        _idLimit,
        "⏰ Limit reached!",
        "You've hit your ${formatDuration(goalMinutes)} screen-time goal for today.",
      );
      await Prefs.markFired(limit: true);
    } else if (goalMinutes > 60 &&
        usedMinutes >= hourLeftAt &&
        !flags.hourLeft) {
      await _show(
        _idHourLeft,
        "🦉 1 hour to go",
        "Just ${formatDuration(goalMinutes - usedMinutes)} of screen time left before your limit.",
      );
      await Prefs.markFired(hourLeft: true);
    } else if (usedMinutes >= half && !flags.half) {
      await _show(
        _idHalf,
        "👀 Halfway there",
        "You've used half of your ${formatDuration(goalMinutes)} screen-time goal.",
      );
      await Prefs.markFired(half: true);
    }
  }
}
