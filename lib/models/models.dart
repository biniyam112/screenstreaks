import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Estimated share of people (0–1) who stay under a given daily limit.
///
/// Placeholder cohort model until the backend serves real numbers: modelled as
/// a logistic around a ~3h/day typical usage, so a stricter limit is rarer.
/// Deterministic, so the "X% stay under this" copy is stable between rebuilds.
double communityUnderRate(int limitMinutes) {
  final rate = 1 / (1 + math.exp(-(limitMinutes - 180) / 55));
  return rate.clamp(0.02, 0.98);
}

/// One item in the social feed — a milestone a user (you or a friend) reached,
/// with its celebrate-reaction count and whether you've celebrated it.
class FeedItem {
  FeedItem({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.kind,
    required this.milestone,
    required this.createdAt,
    required this.celebrateCount,
    required this.iCelebrated,
    required this.commentCount,
    this.friendId,
    this.friendName,
    this.viewerIsOwner = false,
    this.viewerIsParticipant = false,
  });

  final String id;
  final String userId;
  final String displayName;
  final String kind; // 'streak' | 'friend_streak'
  final int milestone;
  final DateTime createdAt;
  final int celebrateCount;
  final bool iCelebrated;
  final int commentCount;

  // friend_streak only:
  final String? friendId;
  final String? friendName;
  final bool viewerIsOwner; // the event belongs to me
  final bool viewerIsParticipant; // I'm one of the two people in it

  bool get isFriendStreak => kind == 'friend_streak';

  String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get friendInitials => _initialsOf(friendName ?? '');

  String get initials => _initialsOf(displayName);

  FeedItem copyWith({int? celebrateCount, bool? iCelebrated, int? commentCount}) => FeedItem(
    id: id,
    userId: userId,
    displayName: displayName,
    kind: kind,
    milestone: milestone,
    createdAt: createdAt,
    celebrateCount: celebrateCount ?? this.celebrateCount,
    iCelebrated: iCelebrated ?? this.iCelebrated,
    commentCount: commentCount ?? this.commentCount,
    friendId: friendId,
    friendName: friendName,
    viewerIsOwner: viewerIsOwner,
    viewerIsParticipant: viewerIsParticipant,
  );

  factory FeedItem.fromJson(Map<String, dynamic> j) {
    final owner = j['viewer_is_owner'] as bool? ?? false;
    final friend = j['viewer_is_friend'] as bool? ?? false;
    return FeedItem(
      id: j['id'] as String,
      userId: j['user_id'] as String,
      displayName: j['display_name'] as String? ?? 'Friend',
      kind: j['kind'] as String? ?? 'streak',
      milestone: (j['milestone'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(j['created_at'] as String),
      celebrateCount: (j['celebrate_count'] as num?)?.toInt() ?? 0,
      iCelebrated: j['i_celebrated'] as bool? ?? false,
      commentCount: (j['comment_count'] as num?)?.toInt() ?? 0,
      friendId: j['friend_id'] as String?,
      friendName: j['friend_name'] as String?,
      viewerIsOwner: owner,
      viewerIsParticipant: owner || friend,
    );
  }
}

/// A comment on a feed event.
class FeedComment {
  FeedComment({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String displayName;
  final String body;
  final DateTime createdAt;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory FeedComment.fromJson(Map<String, dynamic> j) => FeedComment(
    id: j['id'] as String,
    userId: j['user_id'] as String,
    displayName: j['display_name'] as String? ?? 'Friend',
    body: j['body'] as String? ?? '',
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

/// A single day's outcome against the user's limit — the core signal the whole
/// app is built on. On Android this is derived from real usage; on iOS from a
/// Screen Time threshold or a manual check-in.
enum DayStatus { met, missed, none }

/// Normalise a DateTime to midnight (date only).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// One day's record.
class DailyRecord {
  DailyRecord({
    required this.day,
    required this.limitMet,
    required this.limitMinutes,
    this.usedMinutes,
    this.source = 'auto',
  });

  final DateTime day;
  final bool limitMet;
  final int limitMinutes;

  /// Optional — present on Android, null on iOS (privacy sandbox).
  final int? usedMinutes;
  final String source; // 'auto' | 'manual'

  DayStatus get status => limitMet ? DayStatus.met : DayStatus.missed;

  Map<String, dynamic> toJson() => {
    'day': day.toIso8601String(),
    'limitMet': limitMet,
    'limitMinutes': limitMinutes,
    'usedMinutes': usedMinutes,
    'source': source,
  };

  factory DailyRecord.fromJson(Map<String, dynamic> j) => DailyRecord(
    day: DateTime.parse(j['day'] as String),
    limitMet: j['limitMet'] as bool,
    limitMinutes: j['limitMinutes'] as int,
    usedMinutes: j['usedMinutes'] as int?,
    source: j['source'] as String? ?? 'auto',
  );
}

/// A user — used for both "me" and friends.
class Profile {
  Profile({
    required this.id,
    required this.displayName,
    required this.shareCode,
    required this.dailyLimitMinutes,
    required this.records,
    this.avatarColor,
    this.isMe = false,
  });

  final String id;
  final String displayName;
  final String shareCode;
  final int dailyLimitMinutes;

  /// History, most-recent last. Keyed access via [byDay].
  final List<DailyRecord> records;
  final Color? avatarColor;
  final bool isMe;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Profile copyWith({String? displayName, int? dailyLimitMinutes, List<DailyRecord>? records}) =>
      Profile(
        id: id,
        displayName: displayName ?? this.displayName,
        shareCode: shareCode,
        dailyLimitMinutes: dailyLimitMinutes ?? this.dailyLimitMinutes,
        records: records ?? this.records,
        avatarColor: avatarColor,
        isMe: isMe,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'shareCode': shareCode,
    'dailyLimitMinutes': dailyLimitMinutes,
    'avatarColor': avatarColor?.toARGB32(),
    'isMe': isMe,
    'records': records.map((r) => r.toJson()).toList(),
  };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    displayName: j['displayName'] as String,
    shareCode: j['shareCode'] as String,
    dailyLimitMinutes: j['dailyLimitMinutes'] as int,
    avatarColor: j['avatarColor'] != null ? Color(j['avatarColor'] as int) : null,
    isMe: j['isMe'] as bool? ?? false,
    records: (j['records'] as List)
        .map((e) => DailyRecord.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Map<DateTime, DailyRecord> get byDay => {for (final r in records) dateOnly(r.day): r};

  DayStatus statusOn(DateTime day) => byDay[dateOnly(day)]?.status ?? DayStatus.none;

  /// Consecutive met-days ending today (or yesterday if today isn't logged yet,
  /// so an unfinished day doesn't visually break the streak).
  int get currentStreak {
    final map = byDay;
    final today = dateOnly(DateTime.now());
    var cursor = today;
    if (map[today] == null) {
      cursor = today.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (map[cursor]?.limitMet == true) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Longest met-streak anywhere in the history.
  int get longestStreak {
    final sorted = records.map((r) => dateOnly(r.day)).toList()..sort();
    final map = byDay;
    var best = 0, run = 0;
    DateTime? prev;
    for (final day in sorted) {
      if (map[day]?.limitMet != true) {
        run = 0;
        prev = day;
        continue;
      }
      if (prev != null && day.difference(prev).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      prev = day;
    }
    return best;
  }

  int get totalMet => records.where((r) => r.limitMet).length;
  int get totalLogged => records.length;

  /// Success rate over the last [days] days (0–1).
  double successRate([int days = 30]) {
    final since = dateOnly(DateTime.now()).subtract(Duration(days: days - 1));
    final window = records.where((r) => !dateOnly(r.day).isBefore(since)).toList();
    if (window.isEmpty) return 0;
    return window.where((r) => r.limitMet).length / window.length;
  }

  /// Weekday the user most reliably meets their limit (1=Mon … 7=Sun), or null.
  int? get bestWeekday {
    final metByWd = <int, int>{};
    final totalByWd = <int, int>{};
    for (final r in records) {
      final wd = r.day.weekday;
      totalByWd[wd] = (totalByWd[wd] ?? 0) + 1;
      if (r.limitMet) metByWd[wd] = (metByWd[wd] ?? 0) + 1;
    }
    int? best;
    double bestRate = -1;
    totalByWd.forEach((wd, total) {
      final rate = (metByWd[wd] ?? 0) / total;
      if (rate > bestRate) {
        bestRate = rate;
        best = wd;
      }
    });
    return best;
  }
}
