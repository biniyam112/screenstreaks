import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../models/models.dart';

/// Pushes this-week progress + streak to the Android home-screen widget
/// (see android WeekWidgetProvider). No-op on other platforms.
class HomeWidgetService {
  HomeWidgetService._();

  static const _androidName = 'WeekWidgetProvider';
  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S']; // weekday 1..7

  static Future<void> update(Profile me) async {
    if (!Platform.isAndroid) return;
    try {
      final today = dateOnly(DateTime.now());
      final days =
          List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));

      await HomeWidget.saveWidgetData<int>('streak', me.currentStreak);
      for (var i = 0; i < 7; i++) {
        final status = me.statusOn(days[i]);
        final code = switch (status) {
          DayStatus.met => 'met',
          DayStatus.missed => 'missed',
          DayStatus.none => 'none',
        };
        await HomeWidget.saveWidgetData<String>('day$i', code);
        await HomeWidget.saveWidgetData<String>(
            'letter$i', _labels[days[i].weekday - 1]);
      }
      await HomeWidget.updateWidget(androidName: _androidName);
    } catch (_) {
      // A missing widget or platform-channel hiccup must never break the app.
    }
  }
}
