import 'dart:math' as math;

import 'models.dart';

/// The lowest group limit that clears every member's personal limit.
/// A group limit must sit at or above this — it's a shared floor, not a target.
int minGroupLimit(List<Profile> members) {
  if (members.isEmpty) return 0;
  return members.map((m) => m.dailyLimitMinutes).reduce(math.max);
}

/// True only when we can *prove* this day was under [limit].
///
/// Meeting a personal limit that's already at-or-below the group's is proof.
/// Otherwise we need the raw minutes, which iOS doesn't provide — and an
/// unprovable day counts against the group rather than being assumed good.
bool _provablyUnder(DailyRecord r, int limit) {
  if (r.limitMet && r.limitMinutes <= limit) return true;
  final used = r.usedMinutes;
  return used != null && used <= limit;
}

bool _allUnderOn(List<Profile> members, DateTime day, int limit,
    Set<DateTime> recovered) {
  final d = dateOnly(day);
  // A day the group spent its pass on counts as held.
  if (recovered.contains(d)) return true;
  for (final m in members) {
    final record = m.byDay[d];
    if (record == null) return false;
    if (!_provablyUnder(record, limit)) return false;
  }
  return true;
}

/// Consecutive days where *every* member stayed under [limit].
/// One miss breaks it for everyone.
///
/// Today is skipped if nobody has logged it yet, so an unfinished day doesn't
/// visually break the streak — same rule as [Profile.currentStreak].
int groupStreak(List<Profile> members, int limit,
    {Set<DateTime> recovered = const {}}) {
  if (members.isEmpty || limit <= 0) return 0;

  final today = dateOnly(DateTime.now());
  var cursor = today;
  if (!members.any((m) => m.byDay[today] != null)) {
    cursor = today.subtract(const Duration(days: 1));
  }

  var streak = 0;
  while (_allUnderOn(members, cursor, limit, recovered)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Who broke the streak most recently — useful for "Leo went over yesterday".
List<Profile> membersOverOn(List<Profile> members, DateTime day, int limit) {
  final d = dateOnly(day);
  return members.where((m) {
    final record = m.byDay[d];
    return record == null || !_provablyUnder(record, limit);
  }).toList();
}
