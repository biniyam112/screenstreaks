import 'package:flutter/foundation.dart';
import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../data/repository.dart';
import '../models/group.dart';
import '../models/group_streak.dart';
import '../models/models.dart';
import 'avatar_cache.dart';
import 'prefs.dart';

/// Writes the home-screen widget's payload. Lives outside any screen so
/// opening the app anywhere refreshes it — the groups tab used to be the
/// only thing that did, leaving limits stale until someone visited it.
class WidgetPush {
  WidgetPush._();

  /// [me] lets a caller pass the profile it already loaded. Fetching again
  /// can return a cached copy that's missing today's record, which is how
  /// the widget ended up showing a streak the app didn't.
  static Future<void> push(Repository repo, {Profile? meProfile}) async {
    try {
      final groups = await repo.groups();
      if (groups.isEmpty) {
        debugPrint('WIDGET PUSH: no groups');
        return;
      }

      // Fall back to the first group rather than doing nothing — an unpinned
      // widget was silently keeping whatever payload it last received.
      final id = await Prefs.widgetGroupId() ?? groups.first.id;
      Group? g;
      for (final x in groups) {
        if (x.id == id) g = x;
      }
      if (g == null) return;

      // Members can include people we aren't connected to, so fetch anyone
      // missing rather than relying on the friends list.
      final me = meProfile ?? await repo.me();
      final friends = await repo.friends();
      final people = {me.id: me, for (final f in friends) f.id: f};
      for (final memberId in g.memberIds) {
        if (people.containsKey(memberId)) continue;
        try {
          people[memberId] = await repo.friend(memberId);
        } catch (_) {
          // Unreadable — leave them out rather than failing the push.
        }
      }

      final members = [
        for (final memberId in g.memberIds)
          if (people[memberId] != null) people[memberId]!,
      ]..sort((a, b) => b.currentStreak.compareTo(a.currentStreak));

      final limit = g.limitMinutes;
      final recovered = (await repo.groupRecoveredDays())[g.id] ?? const {};
      final photos = await AvatarCache.cache(members.take(6).toList());

      await HomeWidget.setAppGroupId('group.com.screenstreaks.screenstreaks');
      await HomeWidget.saveWidgetData<String>(
        'leaderboard',
        jsonEncode(members
            .take(6)
            .map((p) => {
                  'name': p.shortLabel,
                  'streak': p.currentStreak,
                  'isMe': p.id == me.id,
                  'limit': p.dailyLimitMinutes,
                  'photo': photos[p.id],
                })
            .toList()),
      );
      await HomeWidget.saveWidgetData<String>(
        'group',
        jsonEncode({
          'name': g.name,
          'streak': limit == null
              ? 0
              : groupStreak(members, limit, recovered: recovered),
          'limit': limit ?? 0,
          'members': members.length,
        }),
      );
      await HomeWidget.updateWidget(iOSName: 'StreaksWidget');
    } catch (e) {
      // The widget keeps its last payload; never break a screen load — but
      // a silent failure here means it shows stale data forever.
      debugPrint('WIDGET PUSH FAILED: ' + e.toString());
    }
  }
}
