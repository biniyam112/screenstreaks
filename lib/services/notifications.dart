import 'dart:io';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'screen_time.dart';
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
    // zonedSchedule needs the local zone set up before it can be used.
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Ask separately via requestPermission so the prompt appears when the
    // user turns alerts on, rather than at launch.
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _instance.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
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

  /// Post a one-off notification — used for group events the app spots
  /// when it loads rather than anything iOS tells us directly.
  static Future<void> post(int id, String title, String body) =>
      _show(id, title, body);

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

  /// Reminds someone to open the app when yesterday's result is still stuck
  /// on their phone. Background sync usually handles this, but iOS only
  /// schedules it for people who open the app often — which isn't the people
  /// who need it.
  static const _nudgeId = 9200;

  static Future<void> scheduleUnsyncedNudge() async {
    await _instance.cancel(id: _nudgeId);
    final pending = await ScreenTime.pendingOutcomes();
    if (pending.isEmpty) return;

    // Late morning, so it lands after they've woken but before the day runs on.
    final now = DateTime.now();
    var when = DateTime(now.year, now.month, now.day, 11);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));

    try {
      await _instance.zonedSchedule(
        id: _nudgeId,
        title: 'Your streak is waiting',
        body: "Open Undr so yesterday's result reaches your group.",
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(),
          android: AndroidNotificationDetails(_channelId, _channelName),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      // Scheduling is best effort.
    }
  }
}
